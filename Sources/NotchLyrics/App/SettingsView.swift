import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show lyrics in the notch", isOn: $settings.enabled)
                Toggle("Draw a notch on displays without one", isOn: $settings.showOnExternalDisplays)
                LabeledContent("Font size") {
                    Slider(value: $settings.fontSize, in: 10...18, step: 1)
                    Text("\(Int(settings.fontSize)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                LabeledContent("Width beside notch") {
                    Slider(value: $settings.wingWidth, in: 140...420, step: 10)
                    Text("\(Int(settings.wingWidth)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }

            Section {
                LabeledContent("Lyrics timing") {
                    Slider(value: $settings.offsetMs, in: -3000...3000, step: 50)
                    Text(String(format: "%+.2fs", settings.offsetMs / 1000)).monospacedDigit().frame(width: 56, alignment: .trailing)
                    Button("Reset") { settings.offsetMs = 0 }
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Positive values show lyrics earlier.").foregroundStyle(.secondary)
            }

            Section("Lyrics sources") {
                Toggle("Use NetEase word-level lyrics (unofficial API)", isOn: $settings.useNetEase)
                Toggle("Convert Simplified Chinese to Traditional", isOn: $settings.convertToTraditional)
                LabeledContent("Local .lrc folder") {
                    Text(settings.lyricsFolder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Open") {
                        try? FileManager.default.createDirectory(at: settings.lyricsFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(settings.lyricsFolder)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 470)
    }
}

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 470),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "NotchLyrics Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
