import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    /// Width of each lyric strip beside the notch, in points.
    @Published var wingWidth: Double { didSet { defaults.set(wingWidth, forKey: "wingWidth") } }
    @Published var showOnExternalDisplays: Bool { didSet { defaults.set(showOnExternalDisplays, forKey: "showOnExternalDisplays") } }
    @Published var convertToTraditional: Bool { didSet { defaults.set(convertToTraditional, forKey: "convertToTraditional") } }
    @Published var useNetEase: Bool { didSet { defaults.set(useNetEase, forKey: "useNetEase") } }
    /// Listen to Music's audio to line lyrics up automatically.
    @Published var autoSync: Bool { didSet { defaults.set(autoSync, forKey: "autoSync") } }

    init() {
        defaults.register(defaults: [
            "enabled": true,
            "fontSize": 13.0,
            "wingWidth": 250.0,
            "showOnExternalDisplays": true,
            "convertToTraditional": true,
            "useNetEase": true,
            "autoSync": true,
        ])
        // Timing is automatic now; drop the old manual offset.
        defaults.removeObject(forKey: "offsetMs")

        enabled = defaults.bool(forKey: "enabled")
        fontSize = defaults.double(forKey: "fontSize")
        wingWidth = defaults.double(forKey: "wingWidth")
        showOnExternalDisplays = defaults.bool(forKey: "showOnExternalDisplays")
        convertToTraditional = defaults.bool(forKey: "convertToTraditional")
        useNetEase = defaults.bool(forKey: "useNetEase")
        autoSync = defaults.bool(forKey: "autoSync")
    }

    var lyricsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Music/NotchLyrics", isDirectory: true)
    }

    var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchLyrics", isDirectory: true)
    }
}
