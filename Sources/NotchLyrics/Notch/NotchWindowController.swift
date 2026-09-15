import AppKit
import Combine
import QuartzCore
import SwiftUI

enum NotchLayout {
    /// Gap between lyric text and the notch.
    static let wingInnerPadding: CGFloat = 12
    static let wingOuterPadding: CGFloat = 14
    static let fakeNotchWidth: CGFloat = 180
}

struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchWidth: CGFloat
    var barHeight: CGFloat
    /// Absolute x of the notch centre, in global screen coordinates.
    var notchMidX: CGFloat
    var hasRealNotch: Bool

    init(screen: NSScreen) {
        let frame = screen.frame
        screenFrame = frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = frame.width - left.width - right.width
            barHeight = screen.safeAreaInsets.top
            notchMidX = frame.minX + left.width + notchWidth / 2
            hasRealNotch = true
        } else {
            notchWidth = NotchLayout.fakeNotchWidth
            let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
            barHeight = menuBarHeight >= 20 ? menuBarHeight : 25
            notchMidX = frame.midX
            hasRealNotch = false
        }
    }

    func clampedWing(_ wing: Double) -> CGFloat {
        min(CGFloat(wing), (screenFrame.width - notchWidth) / 2)
    }

    func width(wing: CGFloat) -> CGFloat {
        notchWidth + wing * 2
    }
}

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar and its status items; below pop-up menus.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        // Transient: hidden while Mission Control / App Exposé is showing (a stationary window would stay on top).
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
        // Purely visual: clicks always reach the menu bar underneath.
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchWindowController {
    private let panel = NotchPanel()
    private let geometry: NotchGeometry
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitors: [Any] = []
    private var hideWorkItem: DispatchWorkItem?
    private var pointerPollTimer: Timer?

    /// Music is playing and lyrics are enabled.
    private var wantsVisible = false
    /// The pointer went onto the lyrics, so the real menu bar shows until the pointer leaves the menu bar.
    private var hoverHidden = false
    private var isShown = false
    /// The revealed menu bar was clicked, so a menu is probably open below it.
    private var menuProbablyOpen = false
    private var leftMenuBarAt: CFTimeInterval?
    /// Longest wait for the click that closes a menu before covering the menu bar again.
    private static let openMenuGrace: CFTimeInterval = 3

    init(screen: NSScreen, model: NowPlayingModel, sync: AutoSyncController, settings: AppSettings) {
        self.settings = settings
        geometry = NotchGeometry(screen: screen)

        let root = NotchRootView(geometry: geometry, model: model, music: model.music, sync: sync, settings: settings)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        updateFrame()

        settings.$wingWidth
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFrame() }
            .store(in: &cancellables)

        Publishers.CombineLatest3(settings.$enabled, model.music.$track.map { $0 != nil }, model.music.$isPlaying)
            .map { enabled, hasTrack, playing in enabled && hasTrack && playing }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in
                self?.wantsVisible = visible
                self?.updatePointerPolling()
                self?.refresh()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: panel)
            .sink { [weak self] _ in
                guard let self else { return }
                Log.notch.info("occlusion: visible=\(self.panel.occlusionState.contains(.visible))")
            }
            .store(in: &cancellables)

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            Task { @MainActor in self?.pointerChanged(type) }
        }) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.pointerChanged(event.type)
            return event
        }) {
            eventMonitors.append(monitor)
        }
    }

    func close() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        pointerPollTimer?.invalidate()
        hideWorkItem?.cancel()
        cancellables.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    /// Renders the overlay's current content to a PNG. Needs no Screen Recording permission since it's our own view.
    func writeSnapshot(to url: URL) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        Log.notch.info("snapshot \(url.path, privacy: .public) shown=\(self.isShown) hoverHidden=\(self.hoverHidden) alpha=\(self.panel.alphaValue)")
    }

    private func updateFrame() {
        let width = geometry.width(wing: geometry.clampedWing(settings.wingWidth))
        let frame = NSRect(
            x: geometry.notchMidX - width / 2, y: geometry.screenFrame.maxY - geometry.barHeight,
            width: width, height: geometry.barHeight)
        panel.setFrame(frame, display: true)
        Log.notch.info("frame \(NSStringFromRect(frame), privacy: .public) notch=\(self.geometry.notchWidth)")
    }

    // MARK: - Hover to reveal the menu bar

    /// Entering this reveals the menu bar: the overlay itself, padded a little and past the top edge.
    private var overlayZone: NSRect {
        let frame = panel.frame
        return NSRect(x: frame.minX - 4, y: frame.minY, width: frame.width + 8, height: frame.height + 4)
    }

    /// This screen's whole menu bar; the lyrics return the moment the pointer leaves it.
    private var menuBarZone: NSRect {
        let screen = geometry.screenFrame
        return NSRect(x: screen.minX, y: screen.maxY - geometry.barHeight, width: screen.width, height: geometry.barHeight + 4)
    }

    private func pointerChanged(_ type: NSEvent.EventType) {
        guard wantsVisible || hoverHidden else { return }
        let location = NSEvent.mouseLocation
        let now = CACurrentMediaTime()
        let isClick = type == .leftMouseDown || type == .rightMouseDown

        if !hoverHidden {
            guard overlayZone.contains(location) else { return }
            hoverHidden = true
            menuProbablyOpen = isClick
            leftMenuBarAt = nil
            refresh()
            return
        }

        if menuBarZone.contains(location) {
            leftMenuBarAt = nil
            if isClick { menuProbablyOpen = true }
            return
        }

        if menuProbablyOpen {
            if isClick || type == .leftMouseUp {
                // This click picked a menu item or dismissed the menu.
                menuProbablyOpen = false
            } else {
                let left = leftMenuBarAt ?? now
                leftMenuBarAt = left
                guard now - left >= Self.openMenuGrace else { return }
                menuProbablyOpen = false
            }
        }

        hoverHidden = false
        leftMenuBarAt = nil
        refresh()
    }

    /// Mouse-moved events can be missed (e.g. while another app tracks a menu), and the open-menu grace needs a
    /// clock, so also check the pointer frequently while it matters.
    private func updatePointerPolling() {
        let needed = wantsVisible || hoverHidden
        if needed, pointerPollTimer == nil {
            pointerPollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pointerChanged(.mouseMoved) }
            }
        } else if !needed {
            pointerPollTimer?.invalidate()
            pointerPollTimer = nil
        }
    }

    // MARK: - Visibility

    private func refresh() {
        hideWorkItem?.cancel()
        updatePointerPolling()
        let visible = wantsVisible && !hoverHidden
        Log.notch.info("visible=\(visible) (playing=\(self.wantsVisible) hoverHidden=\(self.hoverHidden))")

        if visible {
            if !isShown {
                isShown = true
                panel.orderFrontRegardless()
            }
            animateAlpha(to: 1, duration: 0.1)
            return
        }
        guard isShown else { return }

        let hide = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.animateAlpha(to: 0, duration: self.hoverHidden ? 0.1 : 0.3) { [weak self] in
                guard let self, !(self.wantsVisible && !self.hoverHidden) else { return }
                self.isShown = false
                self.panel.orderOut(nil)
            }
        }
        hideWorkItem = hide
        if hoverHidden {
            hide.perform()
        } else {
            // Short grace period so track changes and brief pauses don't flicker the menu bar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: hide)
        }
    }

    private func animateAlpha(to alpha: CGFloat, duration: TimeInterval, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            panel.animator().alphaValue = alpha
        }, completionHandler: {
            Task { @MainActor in completion?() }
        })
    }
}
