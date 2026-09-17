import Foundation
import LyricsCore

/// Everywhere lyrics can come from, in the one list the user ranks. Apple Music isn't a `LyricsSourceKind`
/// because it's read out of Music's own window rather than fetched.
enum LyricsSource: String, CaseIterable, Identifiable {
    case appleMusic
    case localFiles
    case netease
    case lrclib

    var id: String { rawValue }

    var kind: LyricsSourceKind? { LyricsSourceKind(rawValue: rawValue) }

    var title: String { kind?.title ?? MusicLyricsReader.sourceName }
}

/// Where a line's timing comes from. The fetched lyrics carry their own, which is right for a source that
/// times each word and wrong for most of the rest; the other two replace it, and can't both be on.
enum TimingSource: String, CaseIterable, Identifiable {
    case asFetched
    case musicLyrics
    case listening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .asFetched: "As fetched"
        case .musicLyrics: "Music's own lyrics"
        case .listening: "Listening"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    /// Width of each lyric strip beside the notch, in points.
    @Published var wingWidth: Double { didSet { defaults.set(wingWidth, forKey: "wingWidth") } }
    @Published var showOnExternalDisplays: Bool { didSet { defaults.set(showOnExternalDisplays, forKey: "showOnExternalDisplays") } }
    @Published var convertToTraditional: Bool { didSet { defaults.set(convertToTraditional, forKey: "convertToTraditional") } }
    /// Lyrics sources in the user's own order of preference; the first one with lyrics for the track wins.
    @Published var sourceOrder: [LyricsSource] {
        didSet { defaults.set(sourceOrder.map(\.rawValue), forKey: "sourceOrder") }
    }
    /// Sources the user has switched off; they stay in the list but are skipped.
    @Published var disabledSources: Set<String> {
        didSet { defaults.set(Array(disabledSources), forKey: "disabledSources") }
    }
    /// Take word-by-word lyrics from anywhere in the list before settling for line-timed ones.
    @Published var preferWordTiming: Bool { didSet { defaults.set(preferWordTiming, forKey: "preferWordTiming") } }
    /// Listen to Music's audio to line lyrics up automatically. Can't be on together with `appleMusicTiming`.
    @Published var autoSync: Bool {
        didSet {
            defaults.set(autoSync, forKey: "autoSync")
            if autoSync, appleMusicTiming { appleMusicTiming = false }
        }
    }
    /// Put the lyrics you have onto Music's own line changes, which is the timing Apple ships with the song.
    /// Can't be on together with `autoSync`.
    @Published var appleMusicTiming: Bool {
        didSet {
            defaults.set(appleMusicTiming, forKey: "appleMusicTiming")
            if appleMusicTiming, autoSync { autoSync = false }
        }
    }
    /// Little pixel pictures beside words like "love" or "car" as they're sung.
    @Published var pixelArtEnabled: Bool { didSet { defaults.set(pixelArtEnabled, forKey: "pixelArtEnabled") } }
    /// Draw the pixel art in white, like the lyrics, instead of in color.
    @Published var pixelArtWhite: Bool { didSet { defaults.set(pixelArtWhite, forKey: "pixelArtWhite") } }

    init() {
        // "appleMusicLyrics" used to mean the same switch, back when it replaced the lyrics rather than
        // retiming them. This has to run before the defaults are registered: once "appleMusicTiming" has a
        // registered default, reading it never comes back empty, and the old choice would never be carried over.
        if defaults.object(forKey: "appleMusicTiming") == nil, let old = defaults.object(forKey: "appleMusicLyrics") as? Bool {
            defaults.set(old, forKey: "appleMusicTiming")
        }
        defaults.register(defaults: [
            "enabled": true,
            "fontSize": 13.0,
            "wingWidth": 250.0,
            "showOnExternalDisplays": true,
            "convertToTraditional": true,
            "preferWordTiming": true,
            "autoSync": true,
            "appleMusicTiming": false,
            "pixelArtEnabled": true,
            "pixelArtWhite": false,
        ])
        // Timing is automatic now; drop the old manual offset.
        defaults.removeObject(forKey: "offsetMs")

        enabled = defaults.bool(forKey: "enabled")
        fontSize = defaults.double(forKey: "fontSize")
        wingWidth = defaults.double(forKey: "wingWidth")
        showOnExternalDisplays = defaults.bool(forKey: "showOnExternalDisplays")
        convertToTraditional = defaults.bool(forKey: "convertToTraditional")
        preferWordTiming = defaults.bool(forKey: "preferWordTiming")
        let stored = (defaults.array(forKey: "sourceOrder") as? [String] ?? []).compactMap(LyricsSource.init)
        // Anything new in a later version joins the end rather than going missing.
        sourceOrder = stored + LyricsSource.allCases.filter { !stored.contains($0) }
        var off = Set(defaults.array(forKey: "disabledSources") as? [String] ?? [])
        if defaults.object(forKey: "disabledSources") == nil {
            // Reading Music's window needs Accessibility, and nothing should put that prompt up on first
            // launch, so Apple Music is there to switch on rather than already on.
            off.insert(LyricsSource.appleMusic.rawValue)
            // Carry over the old NetEase switch the first time.
            if defaults.object(forKey: "useNetEase") as? Bool == false {
                off.insert(LyricsSource.netease.rawValue)
            }
        }
        disabledSources = off
        if defaults.bool(forKey: "autoSync"), defaults.bool(forKey: "appleMusicTiming") {
            // Saved while both could be on. Music's timing is off unless someone turned it on, so it wins.
            defaults.set(false, forKey: "autoSync")
        }
        autoSync = defaults.bool(forKey: "autoSync")
        appleMusicTiming = defaults.bool(forKey: "appleMusicTiming")
        pixelArtEnabled = defaults.bool(forKey: "pixelArtEnabled")
        pixelArtWhite = defaults.bool(forKey: "pixelArtWhite")
    }

    /// The enabled sources, in order.
    var activeSources: [LyricsSource] {
        sourceOrder.filter { !disabledSources.contains($0.rawValue) }
    }

    /// The sources that are actually fetched, in order. Apple Music isn't one: it's read from Music's window.
    var fetchOrder: [LyricsSourceKind] { activeSources.compactMap(\.kind) }

    func isEnabled(_ source: LyricsSource) -> Bool {
        !disabledSources.contains(source.rawValue)
    }

    func setEnabled(_ enabled: Bool, for source: LyricsSource) {
        if enabled { disabledSources.remove(source.rawValue) } else { disabledSources.insert(source.rawValue) }
    }

    func moveSources(from offsets: IndexSet, to destination: Int) {
        sourceOrder.move(fromOffsets: offsets, toOffset: destination)
    }

    /// The two timing switches as the one choice they really are. They keep each other off already; this is
    /// the same thing said once instead of twice.
    var timingSource: TimingSource {
        get {
            if appleMusicTiming { return .musicLyrics }
            if autoSync { return .listening }
            return .asFetched
        }
        set {
            switch newValue {
            case .asFetched:
                appleMusicTiming = false
                autoSync = false
            // Each of these turns the other off on its way in.
            case .musicLyrics: appleMusicTiming = true
            case .listening: autoSync = true
            }
        }
    }

    var lyricsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/NotchLyrics", isDirectory: true)
    }

    /// Where the user's pixel art lives.
    var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchLyrics", isDirectory: true)
    }

    var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchLyrics", isDirectory: true)
    }
}
