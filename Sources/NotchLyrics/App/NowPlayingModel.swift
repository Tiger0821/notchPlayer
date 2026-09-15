import Combine
import Foundation
import LyricsCore

@MainActor
final class NowPlayingModel: ObservableObject {
    enum LyricsState: Equatable {
        case idle
        case loading
        case loaded(Lyrics)
        case notFound
    }

    @Published private(set) var lyricsState: LyricsState = .idle

    let music: MusicController
    let settings: AppSettings
    private let service: LyricsService
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(music: MusicController, settings: AppSettings) {
        self.music = music
        self.settings = settings
        self.service = LyricsService(localFolder: settings.lyricsFolder, cacheDirectory: settings.cacheFolder)

        music.$track
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload(ignoreCache: false) }
            .store(in: &cancellables)

        Publishers.Merge(
            settings.$useNetEase.removeDuplicates().dropFirst().map { _ in () },
            settings.$convertToTraditional.removeDuplicates().dropFirst().map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.reload(ignoreCache: false) }
        .store(in: &cancellables)
    }

    var sourceDescription: String {
        switch lyricsState {
        case .idle: ""
        case .loading: "Searching lyrics…"
        case .notFound: "No synced lyrics found"
        case .loaded(let lyrics): "\(lyrics.source) · \(lyrics.timing == .word ? "word-synced" : "line-synced, estimated words")"
        }
    }

    func reload(ignoreCache: Bool = true) {
        loadTask?.cancel()
        guard let track = music.track else {
            lyricsState = .idle
            return
        }
        lyricsState = .loading
        let query = TrackQuery(title: track.title, artist: track.artist, album: track.album, duration: track.duration)
        let useNetEase = settings.useNetEase
        let traditional = settings.convertToTraditional

        loadTask = Task { [service] in
            let lyrics = await service.lyrics(
                for: query, useNetEase: useNetEase, convertToTraditional: traditional, ignoreCache: ignoreCache)
            guard !Task.isCancelled, self.music.track?.id == track.id else { return }
            Log.lyrics.info("lyrics: \(lyrics.map { "\($0.source) \($0.timing) \($0.lines.count) lines" } ?? "not found", privacy: .public)")
            self.lyricsState = lyrics.map { .loaded($0) } ?? .notFound
        }
    }
}
