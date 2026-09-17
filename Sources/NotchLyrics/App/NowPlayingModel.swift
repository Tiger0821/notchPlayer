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
        // Only a change asks for the permission: `dropFirst` leaves out the value each of these publishes on
        // subscribe, which is every launch.
        Publishers.Merge(
            settings.$disabledSources.removeDuplicates().dropFirst().map { _ in () },
            settings.$appleMusicTiming.removeDuplicates().dropFirst().map { _ in () }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.updateReader(askForPermission: true) }
        .store(in: &cancellables)

        updateReader(askForPermission: false)

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

    /// Every way taking timing from Music can be doing nothing, said out loud. Silence here used to look
    /// exactly like the lyrics being wrong.
    enum MusicTimingState: Equatable {
        case off
        case needsPermission
        case needsLyricsPane
        /// Music's lines are being read, but none of them has matched the lyrics on screen.
        case noMatch(readingLines: Int)
        /// Reading, matching, and moving the timing.
        case timing(matchedLines: Int)

        var title: String {
            switch self {
            case .off: "Not using Music's timing"
            case .needsPermission: "Music's lyrics can't be read"
            case .needsLyricsPane: "Music's lyrics pane isn't open"
            case .noMatch: "No lines matched yet"
            case .timing(let matched): "\(matched) \(matched == 1 ? "line" : "lines") matched"
            }
        }

        var detail: String {
            switch self {
            case .off: "The lyrics are shown with the timing they came with."
            case .needsPermission:
                "Allow NotchLyrics in Privacy & Security › Accessibility. If it is switched on there already, remove it with − and add this copy again: a tick belongs to the copy that asked for it, and an app signed differently is a different app to macOS."
            case .needsLyricsPane: "Open the lyrics view in Music, and play the song — a line's timing is read as Music reaches it."
            case .noMatch(let lines):
                "Music is showing \(lines) \(lines == 1 ? "line" : "lines"), but none of them is a line in the lyrics on screen yet. Timing moves once two of them match, so play a little further in."
            case .timing: "The lyrics on screen are on Music's own timing."
            }
        }
    }

    var musicTimingState: MusicTimingState {
        guard settings.appleMusicTiming else { return .off }
        switch appleLyrics.status {
        case .needsPermission: return .needsPermission
        case .off, .needsLyricsPane: return .needsLyricsPane
        case .reading(let lines):
            if let matchedLines { return .timing(matchedLines: matchedLines) }
            return .noMatch(readingLines: lines)
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

    /// - Parameter askForPermission: whether to put macOS's Accessibility prompt up if it is missing. Only a
    ///   deliberate change does — switching Music's timing on, or Apple Music into the list. Launching doesn't:
    ///   a permission someone has decided not to give shouldn't be asked for again every time the app starts,
    ///   and the Sync tab says what is missing for as long as it is.
    private func updateReader(askForPermission: Bool) {
        if settings.appleMusicTiming || settings.isEnabled(.appleMusic) {
            if askForPermission { MusicLyricsReader.requestPermission() }
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
        // By what the lyrics say they came from, not by the name the list shows: "NetEase" against
        // "NetEase Cloud Music" never matched, so nothing was ever found to rank Apple Music against and it
        // won every time, whatever the order said.
        guard let rival = ranks.firstIndex(where: { $0.kind?.sourceName == other.source }) else { return true }
        return apple < rival
    }
}
