import AppKit
import Combine
import SwiftUI

enum NotchLayout {
    static let controlsHeight: CGFloat = 124
    static let expandedMinWidth: CGFloat = 440
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

    func width(wing: CGFloat, expanded: Bool) -> CGFloat {
        let collapsed = notchWidth + wing * 2
        return expanded ? min(max(collapsed, NotchLayout.expandedMinWidth), screenFrame.width) : collapsed
    }
}

@MainActor
final class NotchUIState: ObservableObject {
    @Published var geometry: NotchGeometry
    @Published var expanded = false

    init(geometry: NotchGeometry) {
        self.geometry = geometry
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
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        alphaValue = 0
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on an inactive app's panel hit SwiftUI buttons directly.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchWindowController {
    private let panel = NotchPanel()
    private let ui: NotchUIState
    private let model: NowPlayingModel
    private let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var hideWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?
    private var clickMonitor: Any?
    private var isShown = false

    init(screen: NSScreen, model: NowPlayingModel, settings: AppSettings, openSettings: @escaping () -> Void) {
        self.model = model
        self.settings = settings
        ui = NotchUIState(geometry: NotchGeometry(screen: screen))

        let root = NotchRootView(ui: ui, model: model, music: model.music, settings: settings, openSettings: openSettings)
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.setFrame(frame(expanded: false), display: false)

        ui.$expanded
            .removeDuplicates()
            .sink { [weak self] expanded in self?.expandedChanged(expanded) }
            .store(in: &cancellables)

        settings.$wingWidth
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFrame() }
            .store(in: &cancellables)

        // Visible only while music is playing (or while the controls are open).
        Publishers.CombineLatest4(settings.$enabled, model.music.$track.map { $0 != nil }, model.music.$isPlaying, ui.$expanded)
            .map { enabled, hasTrack, playing, expanded in enabled && hasTrack && (playing || expanded) }
            .removeDuplicates()
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &cancellables)

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.ui.expanded else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { self.ui.expanded = false }
            }
        }
    }

    func close() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        cancellables.removeAll()
        hideWorkItem?.cancel()
        panel.orderOut(nil)
        panel.close()
    }

    /// Renders the overlay's current content to a PNG. Needs no Screen Recording permission since it's our own view.
    func writeSnapshot(to url: URL) {
        guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        Log.notch.info("snapshot \(url.path, privacy: .public) shown=\(self.isShown) alpha=\(self.panel.alphaValue) onScreen=\(self.panel.isVisible)")
    }

    private func frame(expanded: Bool) -> NSRect {
        let geometry = ui.geometry
        let width = geometry.width(wing: geometry.clampedWing(settings.wingWidth), expanded: expanded)
        let height = geometry.barHeight + (expanded ? NotchLayout.controlsHeight : 0)
        return NSRect(x: geometry.notchMidX - width / 2, y: geometry.screenFrame.maxY - height, width: width, height: height)
    }

    private func updateFrame() {
        let target = frame(expanded: ui.expanded)
        panel.setFrame(target, display: true)
        Log.notch.info("frame target=\(NSStringFromRect(target), privacy: .public) actual=\(NSStringFromRect(self.panel.frame), privacy: .public) notch=\(self.ui.geometry.notchWidth)")
    }

    private func expandedChanged(_ expanded: Bool) {
        collapseWorkItem?.cancel()
        if expanded {
            panel.setFrame(frame(expanded: true), display: true)
        } else {
            // Let the collapse animation finish before shrinking the window.
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.ui.expanded else { return }
                self.panel.setFrame(self.frame(expanded: false), display: true)
            }
            collapseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
    }

    private func setVisible(_ visible: Bool) {
        Log.notch.info("visible=\(visible)")
        hideWorkItem?.cancel()
        if visible {
            guard !isShown else { return }
            isShown = true
            updateFrame()
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1
            }
        } else {
            // Short grace period so track changes and brief pauses don't flicker the menu bar.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isShown else { return }
                self.isShown = false
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    self.panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard let self, !self.isShown else { return }
                        self.panel.orderOut(nil)
                    }
                })
            }
            hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }
}
