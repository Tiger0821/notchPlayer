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
    /// How many lines the showing lyrics were matched to Music's own by, while its timing is being used.
    @Published private(set) var matchedLines: Int?

    let music: MusicController
    let settings: AppSettings
    /// Reads Music's own lyrics pane; runs while Apple Music is one of the sources, or while its timing is.
    let appleLyrics: MusicLyricsReader
    private let service: LyricsService
    /// What the ranked sources came back with, before Music's timing is put on it.
    private var fetched: Lyrics?
    private var searching = false
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

        // Music's pane is read rather than fetched, so the reader runs continuously while anything wants it.
        Publishers.Merge(
            settings.$disabledSources.removeDuplicates().map { _ in () },
            settings.$appleMusicTiming.removeDuplicates().map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.updateReader() }
        .store(in: &cancellables)

        // Music reaches a line, and what is on screen moves onto Apple's clock for it.
        Publishers.Merge(
            appleLyrics.$lyrics.map { _ in () },
            appleLyrics.$anchors.removeDuplicates().map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.publish() }
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
        case .idle: return ""
        case .loading: return "Searching lyrics…"
        case .notFound: return "No synced lyrics found"
        case .loaded(let lyrics):
            let timing = lyrics.timing == .word ? "word-synced" : "line-synced, estimated words"
            guard let matchedLines else { return "\(lyrics.source) · \(timing)" }
            return "\(lyrics.source) · \(timing) · timed by Music (\(matchedLines) lines)"
        }
    }

    /// What to tell the user when Music's pane is wanted but can't be read right now.
    var appleLyricsHint: String? {
        guard settings.appleMusicTiming || settings.isEnabled(.appleMusic) else { return nil }
        switch appleLyrics.status {
        case .needsPermission: return "Allow NotchLyrics in Privacy & Security › Accessibility."
        case .needsLyricsPane: return "Open the lyrics view in Music so its lyrics can be read."
        case .reading, .off: return nil
        }
    }

    func reload(ignoreCache: Bool = true) {
        loadTask?.cancel()
        loadTask = nil
        fetched = nil
        guard let track = music.track else {
            searching = false
            publish()
            return
        }
        let order = settings.fetchOrder
        searching = !order.isEmpty
        publish()
        guard searching else { return }

        let query = TrackQuery(title: track.title, artist: track.artist, album: track.album, duration: track.duration)
        let preferWordTiming = settings.preferWordTiming
        let traditional = settings.convertToTraditional

        loadTask = Task { [service] in
            let lyrics = await service.lyrics(
                for: query, order: order, preferWordTiming: preferWordTiming,
                convertToTraditional: traditional, ignoreCache: ignoreCache)
            guard !Task.isCancelled, self.music.track?.id == track.id else { return }
            Log.lyrics.info("lyrics: \(lyrics.map { "\($0.source) \($0.timing) \($0.lines.count) lines" } ?? "not found", privacy: .public)")
            self.fetched = lyrics
            self.searching = false
            self.publish()
        }
    }

    /// Settles what to show from the two things that arrive on their own schedule: the fetch, and whatever
    /// Music's pane has given up so far.
    private func publish() {
        guard music.track != nil else {
            lyricsState = .idle
            matchedLines = nil
            return
        }
        // Apple's own lines, when they're ranked above whatever came back.
        if let apple = appleLyrics.lyrics, appleBeats(fetched) {
            lyricsState = .loaded(apple)
            matchedLines = nil
            return
        }
        guard let fetched else {
            lyricsState = searching ? .loading : .notFound
            matchedLines = nil
            return
        }
        // The words are the fetched ones; only when each line starts comes from Music.
        if settings.appleMusicTiming, let retimed = TimingTransfer.apply(appleLyrics.anchors, to: fetched) {
            lyricsState = .loaded(retimed.lyrics)
            matchedLines = retimed.matchedLines
        } else {
            lyricsState = .loaded(fetched)
            matchedLines = nil
        }
    }

    private func updateReader() {
        if settings.appleMusicTiming || settings.isEnabled(.appleMusic) {
            // Asks whenever the permission is actually missing, and only once a launch.
            MusicLyricsReader.requestPermission()
            appleLyrics.start()
        } else {
            appleLyrics.stop()
        }
        publish()
    }

    /// Whether Music's own lyrics should win over `other`, by the user's ranking — and by their choice of
    /// word-by-word over line timing, which Apple never has.
    private func appleBeats(_ other: Lyrics?) -> Bool {
        guard settings.isEnabled(.appleMusic) else { return false }
        guard let other else { return true }
        if settings.preferWordTiming, other.timing == .word { return false }
        let ranks = settings.activeSources
        guard let apple = ranks.firstIndex(of: .appleMusic) else { return false }
        guard let rival = ranks.firstIndex(where: { $0.title == other.source }) else { return true }
        return apple < rival
    }
}
