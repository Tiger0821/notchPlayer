import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let music = MusicController()
    private lazy var model = NowPlayingModel(music: music, settings: settings)
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private var statusItem: StatusItemController?
    private var notchWindows: [NotchWindowController] = []
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: settings.lyricsFolder, withIntermediateDirectories: true)

        statusItem = StatusItemController(model: model, settings: settings) { [weak self] in
            self?.settingsWindow.show()
        }

        rebuildNotchWindows()
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildNotchWindows() }
            .store(in: &cancellables)
        settings.$showOnExternalDisplays
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildNotchWindows() }
            .store(in: &cancellables)

        // Debug: post "com.tigercho.NotchLyrics.snapshot" to dump each overlay to ~/Library/Caches/NotchLyrics/snapshot-N.png
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.tigercho.NotchLyrics.snapshot"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.writeSnapshots() }
            .store(in: &cancellables)

        music.start()
    }

    private func writeSnapshots() {
        for (index, window) in notchWindows.enumerated() {
            window.writeSnapshot(to: settings.cacheFolder.appendingPathComponent("snapshot-\(index).png"))
        }
    }

    /// One overlay per screen: the real notch on the built-in display, a drawn one elsewhere (if enabled).
    private func rebuildNotchWindows() {
        notchWindows.forEach { $0.close() }
        notchWindows = NSScreen.screens
            .filter { NotchGeometry(screen: $0).hasRealNotch || settings.showOnExternalDisplays }
            .map { screen in
                NotchWindowController(screen: screen, model: model, settings: settings) { [weak self] in
                    self?.settingsWindow.show()
                }
            }
    }
}
