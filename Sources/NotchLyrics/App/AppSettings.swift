import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    /// Positive values show lyrics earlier.
    @Published var offsetMs: Double { didSet { defaults.set(offsetMs, forKey: "offsetMs") } }
    /// Width of each lyric strip beside the notch, in points.
    @Published var wingWidth: Double { didSet { defaults.set(wingWidth, forKey: "wingWidth") } }
    @Published var showOnExternalDisplays: Bool { didSet { defaults.set(showOnExternalDisplays, forKey: "showOnExternalDisplays") } }
    @Published var convertToTraditional: Bool { didSet { defaults.set(convertToTraditional, forKey: "convertToTraditional") } }
    @Published var useNetEase: Bool { didSet { defaults.set(useNetEase, forKey: "useNetEase") } }

    init() {
        defaults.register(defaults: [
            "enabled": true,
            "fontSize": 13.0,
            "offsetMs": 0.0,
            "wingWidth": 250.0,
            "showOnExternalDisplays": true,
            "convertToTraditional": true,
            "useNetEase": true,
        ])
        enabled = defaults.bool(forKey: "enabled")
        fontSize = defaults.double(forKey: "fontSize")
        offsetMs = defaults.double(forKey: "offsetMs")
        wingWidth = defaults.double(forKey: "wingWidth")
        showOnExternalDisplays = defaults.bool(forKey: "showOnExternalDisplays")
        convertToTraditional = defaults.bool(forKey: "convertToTraditional")
        useNetEase = defaults.bool(forKey: "useNetEase")
    }

    var lyricsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/NotchLyrics", isDirectory: true)
    }

    var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchLyrics", isDirectory: true)
    }
}
