import AppKit
import Combine

/// The ❝ menu bar item: now playing, playback controls, sync status and app actions.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: NowPlayingModel
    private let sync: AutoSyncController
    private let settings: AppSettings
    private let openSettings: () -> Void
    private var playButton: NSButton?
    private var playStateObserver: AnyCancellable?

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

    func menuDidClose(_ menu: NSMenu) {
        playStateObserver = nil
        playButton = nil
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
            menu.addItem(controlsItem(isPlaying: music.isPlaying))
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

    /// Previous / play-pause / next as three boxed buttons in a row, like a small remote.
    func controlsItem(isPlaying: Bool) -> NSMenuItem {
        let previous = controlButton("backward.fill", #selector(previousTrack), "Previous track")
        let play = controlButton(isPlaying ? "pause.fill" : "play.fill", #selector(playPause), isPlaying ? "Pause" : "Play")
        let next = controlButton("forward.fill", #selector(nextTrack), "Next track")
        playButton = play

        let container = ControlsRowView(buttons: [previous, play, next])

        // Keep the play/pause icon right while the menu stays open.
        playStateObserver = model.music.$isPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in
                self?.playButton?.image = Self.symbol(playing ? "pause.fill" : "play.fill")
            }

        let item = NSMenuItem()
        item.view = container
        return item
    }

    private func controlButton(_ symbol: String, _ action: Selector, _ label: String) -> NSButton {
        let button = ControlBoxButton(image: Self.symbol(symbol) ?? NSImage(), target: self, action: action)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
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

    /// Debug: opens the menu briefly so its live layout gets logged.
    func openMenuBriefly() {
        statusItem.button?.performClick(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.statusItem.menu?.cancelTracking()
        }
    }

    @objc private func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}

private extension NSFont {
    var bold: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}


/// A playback button drawn as a soft shaded box, so it reads the same in light and dark menus.
final class ControlBoxButton: NSButton {
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    init(image: NSImage, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.image = image
        self.target = target
        self.action = action
        isBordered = false
        imagePosition = .imageOnly
        contentTintColor = .labelColor
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        super.mouseDown(with: event)
        pressed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let opacity: CGFloat = pressed ? 0.22 : hovering ? 0.16 : 0.09
        NSColor.labelColor.withAlphaComponent(opacity).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        super.draw(dirtyRect)
    }
}


/// Lays the three playback buttons out with equal margins, re-centring whenever the menu changes width.
final class ControlsRowView: NSView {
    private let buttons: [NSButton]
    /// Line up with the menu's separator lines, which macOS insets by these amounts.
    private static let leadingInset: CGFloat = 30
    private static let trailingInset: CGFloat = 16
    private let spacing: CGFloat = 8
    private let buttonHeight: CGFloat = 28

    init(buttons: [NSButton]) {
        self.buttons = buttons
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 38))
        autoresizingMask = [.width]
        buttons.forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Debug: set before opening the menu to save a picture of the menu window for measuring.
    static var captureURL: URL?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // The menu's real window only exists once the menu is shown; re-run the centring then.
        needsLayout = true
        guard let url = Self.captureURL, window != nil else { return }
        Self.captureURL = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let content = self?.window?.contentView,
                  let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return }
            content.cacheDisplay(in: content.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            Log.notch.info("menu window captured \(NSStringFromRect(content.bounds), privacy: .public)")
        }
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layout()
    }

    override func layout() {
        super.layout()
        let width = max((bounds.width - Self.leadingInset - Self.trailingInset - spacing * 2) / 3, 1)
        let y = (bounds.height - buttonHeight) / 2
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: Self.leadingInset + (width + spacing) * CGFloat(index), y: y, width: width, height: buttonHeight)
        }
        Log.notch.info("controls row: view=\(self.bounds.width, privacy: .public) buttons \(Self.leadingInset, privacy: .public)–\(self.buttons.last?.frame.maxX ?? 0, privacy: .public)")
    }
}
