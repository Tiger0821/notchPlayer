import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: NowPlayingModel
    private let settings: AppSettings
    private let openSettings: () -> Void

    init(model: NowPlayingModel, settings: AppSettings, openSettings: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        self.openSettings = openSettings
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "quote.bubble", accessibilityDescription: "NotchLyrics")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if model.music.automationDenied {
            addItem(to: menu, "Allow NotchLyrics to Control Music…", #selector(openAutomationSettings))
            menu.addItem(.separator())
        }
        if let track = model.music.track {
            menu.addItem(disabledItem("\(track.title) — \(track.artist)"))
            menu.addItem(disabledItem(model.sourceDescription))
        } else {
            menu.addItem(disabledItem("Nothing playing in Music"))
        }
        menu.addItem(.separator())

        addItem(to: menu, "Show Lyrics in Notch", #selector(toggleEnabled)).state = settings.enabled ? .on : .off
        addItem(to: menu, "Reload Lyrics", #selector(reloadLyrics), key: "r")
        addItem(to: menu, "Open Lyrics Folder", #selector(openLyricsFolder))
        menu.addItem(.separator())
        addItem(to: menu, "Settings…", #selector(showSettings), key: ",")
        addItem(to: menu, "Quit NotchLyrics", #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleEnabled() { settings.enabled.toggle() }
    @objc private func reloadLyrics() { model.reload() }
    @objc private func showSettings() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openLyricsFolder() {
        try? FileManager.default.createDirectory(at: settings.lyricsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(settings.lyricsFolder)
    }

    @objc private func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
