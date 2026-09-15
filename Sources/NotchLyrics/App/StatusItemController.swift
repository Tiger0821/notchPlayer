import AppKit

/// The ❝ menu bar item: now playing, playback controls, sync status and app actions.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: NowPlayingModel
    private let sync: AutoSyncController
    private let settings: AppSettings
    private let openSettings: () -> Void

    init(model: NowPlayingModel, sync: AutoSyncController, settings: AppSettings, openSettings: @escaping () -> Void) {
        self.model = model
        self.sync = sync
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
        let music = model.music

        if music.automationDenied {
            addItem(to: menu, "Allow NotchLyrics to Control Music…", #selector(openAutomationSettings))
            menu.addItem(.separator())
        }

        if let track = music.track {
            let nowPlaying = NSMenuItem(title: track.title, action: nil, keyEquivalent: "")
            nowPlaying.isEnabled = false
            nowPlaying.attributedTitle = nowPlayingTitle(track)
            if let artwork = music.artwork {
                let image = NSImage(size: NSSize(width: 34, height: 34), flipped: false) { rect in
                    NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).addClip()
                    artwork.draw(in: rect)
                    return true
                }
                nowPlaying.image = image
            }
            menu.addItem(nowPlaying)

            menu.addItem(.separator())
            addItem(to: menu, music.isPlaying ? "Pause" : "Play", #selector(playPause), symbol: music.isPlaying ? "pause.fill" : "play.fill")
            addItem(to: menu, "Next Track", #selector(nextTrack), symbol: "forward.fill")
            addItem(to: menu, "Previous Track", #selector(previousTrack), symbol: "backward.fill")
            menu.addItem(.separator())

            menu.addItem(infoItem(model.sourceDescription, symbol: "text.quote"))
            if sync.status == .needsPermission {
                addItem(to: menu, "Allow Audio Access for Auto-Sync…", #selector(openAudioSettings), symbol: "exclamationmark.triangle")
            } else {
                menu.addItem(infoItem(sync.statusDescription, symbol: "waveform"))
            }
        } else {
            menu.addItem(infoItem("Nothing playing in Music", symbol: "music.note"))
        }
        menu.addItem(.separator())

        addItem(to: menu, "Show Lyrics in Notch", #selector(toggleEnabled)).state = settings.enabled ? .on : .off
        addItem(to: menu, "Reload Lyrics", #selector(reloadLyrics))
        if music.track != nil {
            addItem(to: menu, "Re-sync This Song", #selector(resync))
        }
        menu.addItem(.separator())
        addItem(to: menu, "Settings…", #selector(showSettings), key: ",")
        addItem(to: menu, "Quit NotchLyrics", #selector(quit), key: "q")
    }

    private func nowPlayingTitle(_ track: TrackInfo) -> NSAttributedString {
        let title = NSMutableAttributedString(
            string: track.title,
            attributes: [.font: NSFont.menuFont(ofSize: 13).bold, .foregroundColor: NSColor.labelColor])
        title.append(NSAttributedString(
            string: "\n\(track.artist)",
            attributes: [.font: NSFont.menuFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]))
        return title
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "", symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        menu.addItem(item)
        return item
    }

    private func infoItem(_ title: String, symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.isEnabled = false
        return item
    }

    @objc private func playPause() { model.music.playPause() }
    @objc private func nextTrack() { model.music.nextTrack() }
    @objc private func previousTrack() { model.music.previousTrack() }
    @objc private func toggleEnabled() { settings.enabled.toggle() }
    @objc private func reloadLyrics() { model.reload() }
    @objc private func resync() { sync.resync() }
    @objc private func showSettings() { openSettings() }
    @objc private func openAudioSettings() { sync.openAudioPermissionSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

private extension NSFont {
    var bold: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}
