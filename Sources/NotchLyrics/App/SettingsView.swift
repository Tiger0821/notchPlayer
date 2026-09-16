import AppKit
import LyricsCore
import SwiftUI

// MARK: - Window

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let model: NowPlayingModel
    private let sync: AutoSyncController
    private var window: NSWindow?

    init(settings: AppSettings, model: NowPlayingModel, sync: AutoSyncController) {
        self.settings = settings
        self.model = model
        self.sync = sync
    }

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Debug: opens the given tab and renders the whole window (toolbar included) to a PNG.
    func writeSnapshot(tab: Int, to url: URL) {
        show()
        guard let window, let tabs = window.contentViewController as? NSTabViewController,
              tabs.tabViewItems.indices.contains(tab) else { return }
        tabs.selectedTabViewItemIndex = tab
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let frameView = window.contentView?.superview,
                  let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab("General", "gearshape", height: 520, GeneralSettingsView(settings: settings)))
        tabs.addTabViewItem(tab("Lyrics", "text.quote", height: 490, LyricsSettingsView(settings: settings, model: model)))
        tabs.addTabViewItem(tab("Sync", "waveform", height: 400,
                                SyncSettingsView(settings: settings, sync: sync, latency: sync.latency, music: model.music)))
        tabs.addTabViewItem(tab("About", "info.circle", height: 300, AboutSettingsView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: SettingsTabViewController.width, height: 520))
        window.center()
        return window
    }

    private func tab<Content: View>(_ label: String, _ symbol: String, height: CGFloat, _ view: Content) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = []
        controller.title = label
        controller.preferredContentSize = NSSize(width: SettingsTabViewController.width, height: height)
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

/// Toolbar-style tabs that resize the window to each tab's content, like the system's own settings windows.
final class SettingsTabViewController: NSTabViewController {
    static let width: CGFloat = 540

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let window = view.window, let size = tabViewItem?.viewController?.preferredContentSize, size != .zero else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let target = NSRect(x: content.minX, y: content.maxY - size.height, width: size.width, height: size.height)
        window.setFrame(window.frameRect(forContentRect: target), display: true, animate: window.isVisible)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                NotchPreview(settings: settings)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }

            Section("Display") {
                Toggle("Show lyrics beside the notch", isOn: $settings.enabled)
                Toggle("Draw a notch on displays without one", isOn: $settings.showOnExternalDisplays)
            }

            Section("Size") {
                SliderRow(title: "Text size", value: $settings.fontSize, range: 10...18, step: 1,
                          smallSymbol: "textformat.size.smaller", largeSymbol: "textformat.size.larger")
                SliderRow(title: "Width beside the notch", value: $settings.wingWidth, range: 140...420, step: 10,
                          smallSymbol: "arrow.right.and.line.vertical.and.arrow.left",
                          largeSymbol: "arrow.left.and.line.vertical.and.arrow.right")
            }
        }
        .formStyle(.grouped)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let smallSymbol: String
    let largeSymbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step) {
                EmptyView()
            } minimumValueLabel: {
                Image(systemName: smallSymbol).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: largeSymbol).foregroundStyle(.secondary)
            }
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

/// A live, actual-size preview of the lyrics beside the notch, using made-up sample lines.
struct NotchPreview: View {
    @ObservedObject var settings: AppSettings

    private static let lineDuration = 3.4
    private static let sampleLines: [LyricLine] = {
        let texts = ["Neon rivers hum beneath the rain", "月光落在安靜的街角", "Hold on while the city sleeps"]
        return texts.enumerated().map { index, text in
            let start = Double(index) * lineDuration
            let end = start + lineDuration - 0.5
            return LyricLine(start: start, end: end, words: WordTiming.estimate(text: text, start: start, end: end))
        }
    }()

    private var screen: (width: CGFloat, notch: CGFloat) {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        guard let screen else { return (1512, 185) }
        let geometry = NotchGeometry(screen: screen)
        return (geometry.screenFrame.width, geometry.notchWidth)
    }

    var body: some View {
        let (screenWidth, notchWidth) = screen
        let wing = CGFloat(settings.wingWidth)
        let fontSize = CGFloat(settings.fontSize)

        VStack(alignment: .leading, spacing: 10) {
            // The bar is an overlay so its real (often wider-than-window) size never stretches the form; it's clipped instead.
            LinearGradient(colors: [Color(red: 0.23, green: 0.32, blue: 0.62), Color(red: 0.55, green: 0.33, blue: 0.58)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.18)).frame(height: 32)
            }
            .overlay(alignment: .top) {
                TimelineView(.animation) { context in
                    let cycle = Self.lineDuration * Double(Self.sampleLines.count)
                    let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle)
                    let index = min(Int(time / Self.lineDuration), Self.sampleLines.count - 1)

                    let line = Self.sampleLines[index]
                    let next = Self.sampleLines[(index + 1) % Self.sampleLines.count]
                    let onLeft = index.isMultiple(of: 2)
                    let textWidth = max(wing - NotchLayout.wingInnerPadding - NotchLayout.wingOuterPadding, 0)

                    HStack(spacing: 0) {
                        Group {
                            if onLeft {
                                KaraokeLineView(line: line, time: time, fontSize: fontSize, width: textWidth, alignment: .trailing)
                            } else {
                                KaraokeLineView(line: next, time: time, fontSize: fontSize, width: textWidth, alignment: .trailing)
                            }
                        }
                        .padding(.leading, NotchLayout.wingOuterPadding)
                        .padding(.trailing, NotchLayout.wingInnerPadding)
                        .frame(width: wing)

                        // A hint of the camera, so the notch position is readable in the preview.
                        Circle().fill(Color(white: 0.12)).frame(width: 7, height: 7).frame(width: notchWidth)

                        Group {
                            if onLeft {
                                KaraokeLineView(line: next, time: time, fontSize: fontSize, width: textWidth, alignment: .leading)
                            } else {
                                KaraokeLineView(line: line, time: time, fontSize: fontSize, width: textWidth, alignment: .leading)
                            }
                        }
                        .padding(.leading, NotchLayout.wingInnerPadding)
                        .padding(.trailing, NotchLayout.wingOuterPadding)
                        .frame(width: wing)
                    }
                    .frame(height: 32)
                    .frame(height: 32)
                    .background(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous).fill(.black))
                    .fixedSize()
                    .animation(.easeOut(duration: 0.45), value: index)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .environment(\.colorScheme, .dark)

            let covered = min((notchWidth + wing * 2) / screenWidth, 1)
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { proxy in
                    ZStack {
                        Capsule().fill(.quaternary)
                        Capsule().fill(.primary.opacity(0.75)).frame(width: proxy.size.width * covered)
                    }
                }
                .frame(height: 6)
                Text("Covers \(Int((covered * 100).rounded()))% of the menu bar while music plays. Move the pointer over the lyrics to use the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Lyrics

struct LyricsSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: NowPlayingModel

    var body: some View {
        Form {
            Section("Sources") {
                Toggle(isOn: $settings.useNetEase) {
                    Text("Word-by-word timing from NetEase")
                    Text("Unofficial service with the best coverage for Chinese songs. LRCLIB is always used.")
                }
                Toggle(isOn: $settings.convertToTraditional) {
                    Text("Show Chinese lyrics in Traditional characters")
                    Text("Japanese lyrics are left unchanged.")
                }
            }

            Section("Your lyrics files") {
                LabeledContent {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: settings.lyricsFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(settings.lyricsFolder)
                    }
                } label: {
                    Text("~/Music/NotchLyrics")
                    Text("Name files “Artist - Title.lrc”. They're used first when they have word timing.")
                }
            }

            Section("Now playing") {
                LabeledContent("Lyrics") {
                    Text(model.music.track == nil ? "Nothing playing" : model.sourceDescription)
                        .foregroundStyle(.secondary)
                }
                LabeledContent {
                    Button("Clear Cache") {
                        let cache = settings.cacheFolder
                        let files = (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)) ?? []
                        files.filter { $0.pathExtension == "json" }.forEach { try? FileManager.default.removeItem(at: $0) }
                        model.reload()
                    }
                } label: {
                    Text("Downloaded lyrics")
                    Text("Clear if a song keeps showing the wrong lyrics.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Sync

struct SyncSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var sync: AutoSyncController
    @ObservedObject var latency: OutputLatencyMonitor
    @ObservedObject var music: MusicController

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.autoSync) {
                    Text("Sync lyrics automatically")
                    Text("Listens to Music on this Mac and matches the sung words to the lyrics. Audio is never recorded or sent anywhere.")
                }
            }

            Section("Status") {
                LabeledContent("This song") {
                    Label(music.track == nil ? "Nothing playing" : sync.statusDescription, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                }
                if sync.status == .needsPermission {
                    LabeledContent {
                        Button("Open Privacy Settings…") { sync.openAudioPermissionSettings() }
                    } label: {
                        Text("Audio access is off")
                        Text("Allow NotchLyrics under Screen & System Audio Recording.")
                    }
                }
                LabeledContent("Output") {
                    Text(latency.deviceName.isEmpty
                         ? "—"
                         : "\(latency.deviceName) · \(Int((latency.latency * 1000).rounded())) ms delay compensated")
                        .foregroundStyle(.secondary)
                }
                LabeledContent {
                    Button("Re-sync") { sync.resync() }
                        .disabled(music.track == nil || !settings.autoSync)
                } label: {
                    Text("Re-sync this song")
                    Text("Forgets this song's measured timing and listens again.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusSymbol: String {
        switch sync.status {
        case .synced, .remembered: "checkmark.circle.fill"
        case .listening, .preparingModel: "waveform"
        case .needsPermission, .unavailable, .noMatch: "exclamationmark.triangle.fill"
        case .off, .waiting: "circle.dashed"
        }
    }

    private var statusColor: Color {
        switch sync.status {
        case .synced, .remembered: .green
        case .needsPermission, .unavailable, .noMatch: .orange
        default: .secondary
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "quote.bubble.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.23, green: 0.32, blue: 0.62), Color(red: 0.55, green: 0.33, blue: 0.58)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )
            Text("NotchLyrics").font(.title2.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Synced lyrics beside the notch for Apple Music.")
                .foregroundStyle(.secondary)
            Link("github.com/Tiger0821/notchPlayer", destination: URL(string: "https://github.com/Tiger0821/notchPlayer")!)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
