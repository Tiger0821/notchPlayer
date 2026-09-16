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
                if notification.object as? String == "openmenu" {
                    ControlsRowView.captureURL = self.settings.cacheFolder.appendingPathComponent("menu-window.png")
                    self.statusItem?.openMenuBriefly()
                } else if notification.object as? String == "menu" {
                    self.writeMenuSnapshot(to: self.settings.cacheFolder.appendingPathComponent("menu.png"))
                } else if let object = notification.object as? String, object.hasPrefix("settings-"), let tab = Int(object.dropFirst(9)) {
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

    /// Debug: renders the menu's playback controls in both appearances, since menus can't be captured while open.
    private func writeMenuSnapshot(to url: URL) {
        guard let statusItem else { return }
        var images: [(image: NSImage, backdrop: NSColor)] = []
        for (appearance, backdrop) in [(NSAppearance.Name.aqua, NSColor(white: 0.93, alpha: 1)),
                                       (NSAppearance.Name.darkAqua, NSColor(white: 0.16, alpha: 1))] {
            guard let controls = statusItem.controlsItem(isPlaying: music.isPlaying).view else { continue }
            controls.setFrameSize(NSSize(width: 320, height: controls.frame.height)) // a wider menu, to check centring
            let window = NSWindow(contentRect: controls.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView?.addSubview(controls)
            guard let content = window.contentView, let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { continue }
            content.cacheDisplay(in: content.bounds, to: rep)
            let image = NSImage(size: content.bounds.size)
            image.addRepresentation(rep)
            images.append((image, backdrop))
        }
        guard !images.isEmpty else { return }

        let size = NSSize(width: images[0].image.size.width, height: images.reduce(0) { $0 + $1.image.size.height })
        let sheet = NSImage(size: size)
        sheet.lockFocus()
        var y = size.height
        for (image, backdrop) in images {
            y -= image.size.height
            backdrop.setFill()
            NSRect(x: 0, y: y, width: size.width, height: image.size.height).fill()
            image.draw(at: NSPoint(x: 0, y: y), from: .zero, operation: .sourceOver, fraction: 1)
        }
        sheet.unlockFocus()
        guard let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    private func writeSnapshots() {
        for (index, window) in notchWindows.enumerated() {
            window.writeSnapshot(to: settings.cacheFolder.appendingPathComponent("snapshot-\(index).png"))
        }
    }
}
