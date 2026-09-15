import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let music = MusicController()
    private lazy var model = NowPlayingModel(music: music, settings: settings)
    private lazy var sync = AutoSyncController(music: music, model: model, settings: settings)
    private lazy var settingsWindow = SettingsWindowController(settings: settings, model: model, sync: sync)
    private var statusItem: StatusItemController?
    private var notchWindows: [NotchWindowController] = []
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: settings.lyricsFolder, withIntermediateDirectories: true)

        statusItem = StatusItemController(model: model, sync: sync, settings: settings) { [weak self] in
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

        // Debug: post "com.tigercho.NotchLyrics.snapshot" to dump each overlay to ~/Library/Caches/NotchLyrics/snapshot-N.png.
        // With object "settings-N", opens Settings on tab N and saves settings-N.png instead.
        DistributedNotificationCenter.default()
            .publisher(for: Notification.Name("com.tigercho.NotchLyrics.snapshot"))
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                if let object = notification.object as? String, object.hasPrefix("settings-"), let tab = Int(object.dropFirst(9)) {
                    self.settingsWindow.writeSnapshot(tab: tab, to: self.settings.cacheFolder.appendingPathComponent("\(object).png"))
                } else {
                    self.writeSnapshots()
                }
            }
            .store(in: &cancellables)

        music.start()
        sync.start()
    }

    /// One overlay per screen: the real notch on the built-in display, a drawn one elsewhere (if enabled).
    private func rebuildNotchWindows() {
        notchWindows.forEach { $0.close() }
        notchWindows = NSScreen.screens
            .filter { NotchGeometry(screen: $0).hasRealNotch || settings.showOnExternalDisplays }
            .map { NotchWindowController(screen: $0, model: model, sync: sync, settings: settings) }
    }

    private func writeSnapshots() {
        for (index, window) in notchWindows.enumerated() {
            window.writeSnapshot(to: settings.cacheFolder.appendingPathComponent("snapshot-\(index).png"))
        }
    }
}
