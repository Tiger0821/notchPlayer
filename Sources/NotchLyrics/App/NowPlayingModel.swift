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
    /// Reads Music's own lyrics pane; runs only while that setting is on.
    let appleLyrics: MusicLyricsReader
    private let service: LyricsService
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(music: MusicController, settings: AppSettings) {
        self.music = music
        self.settings = settings
        self.service = LyricsService(localFolder: settings.lyricsFolder, cacheDirectory: settings.cacheFolder)
        self.appleLyrics = MusicLyricsReader(position: { [music] in music.position() })

        music.$track
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.appleLyrics.trackChanged()
                self?.reload(ignoreCache: false)
            }
            .store(in: &cancellables)

        // Music's pane is read rather than fetched, so the reader runs continuously while it is the choice.
        settings.$appleMusicLyrics
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] wanted in
                guard let self else { return }
                if wanted {
                    // Asks whenever the permission is actually missing, including at launch, and says
                    // nothing when it has already been granted.
                    MusicLyricsReader.requestPermission()
                    self.appleLyrics.start()
                } else {
                    self.appleLyrics.stop()
                }
                self.reload(ignoreCache: false)
            }
            .store(in: &cancellables)

        // Apple's pane usually becomes readable a moment after the song starts, so take it over whatever the
        // fetch found the moment it arrives.
        appleLyrics.$lyrics
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] lyrics in
                guard let self, self.settings.appleMusicLyrics else { return }
                self.lyricsState = .loaded(lyrics)
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            settings.$sourceOrder.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$disabledSources.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$preferWordTiming.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$convertToTraditional.removeDuplicates().dropFirst().map { _ in () }.eraseToAnyPublisher()
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

    /// What to tell the user when Music's own lyrics are the choice but can't be read right now.
    var appleLyricsHint: String? {
        guard settings.appleMusicLyrics else { return nil }
        switch appleLyrics.status {
        case .needsPermission: return "Allow NotchLyrics in Privacy & Security › Accessibility."
        case .needsLyricsPane: return "Open the lyrics view in Music so its lyrics can be read."
        case .reading, .off: return nil
        }
    }

    func reload(ignoreCache: Bool = true) {
        loadTask?.cancel()
        guard let track = music.track else {
            lyricsState = .idle
            return
        }
        // Music's pane is already showing this song; keep it rather than blanking to a spinner.
        if settings.appleMusicLyrics, let apple = appleLyrics.lyrics {
            lyricsState = .loaded(apple)
        } else {
            lyricsState = .loading
        }
        let query = TrackQuery(title: track.title, artist: track.artist, album: track.album, duration: track.duration)
        let order = settings.activeSources
        let preferWordTiming = settings.preferWordTiming
        let traditional = settings.convertToTraditional

        loadTask = Task { [service] in
            let lyrics = await service.lyrics(
                for: query, order: order, preferWordTiming: preferWordTiming,
                convertToTraditional: traditional, ignoreCache: ignoreCache)
            guard !Task.isCancelled, self.music.track?.id == track.id else { return }
            // Apple's own timing wins when it is there; the fetched lyrics are the fallback for songs Music
            // has no lyrics for, or while its pane isn't readable.
            if self.settings.appleMusicLyrics, let apple = self.appleLyrics.lyrics {
                self.lyricsState = .loaded(apple)
                return
            }
            Log.lyrics.info("lyrics: \(lyrics.map { "\($0.source) \($0.timing) \($0.lines.count) lines" } ?? "not found", privacy: .public)")
            self.lyricsState = lyrics.map { .loaded($0) } ?? .notFound
        }
    }
}
