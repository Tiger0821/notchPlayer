import AppKit
import LyricsCore
import SwiftUI
import UniformTypeIdentifiers

struct PixelArtSettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var library: PixelArtLibrary
    let editors: PixelEditorWindows

    @State private var confirmation: Confirmation?
    @State private var notice: Notice?

    /// Changes that throw away the user's drawing get a second question.
    enum Confirmation {
        case delete(PixelSprite)
        case reset(PixelSprite)

        var title: String {
            switch self {
            case .delete(let sprite): "Delete “\(sprite.name)”?"
            case .reset(let sprite): "Reset “\(sprite.name)” to the original?"
            }
        }

        var message: String {
            switch self {
            case .delete: "This art will be removed from the gallery. You can't undo this."
            case .reset: "Your changes to its pixels, words and motion will be lost."
            }
        }
    }

    struct Notice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    var body: some View {
        Form {
            Section {
                NotchPreview(settings: settings, pixelArt: library, samples: NotchPreview.pixelArtSamples)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }

            Section {
                Toggle(isOn: $settings.pixelArtEnabled) {
                    Text("Show pixel art in the lyrics")
                    Text("Words like “love”, “car” and “雨” get a little picture as they're sung, once per line.")
                }
                .onChange(of: settings.pixelArtEnabled) { Haptics.changed() }
                Picker("Style", selection: $settings.pixelArtWhite) {
                    Text("Color").tag(false)
                    Text("White").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.pixelArtWhite) { Haptics.changed() }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Click art to change its pixels, words or motion. Right-click for more.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 8)], spacing: 12) {
                        ForEach(library.sprites) { sprite in
                            PixelArtTile(sprite: sprite, enabled: library.isEnabled(sprite.id),
                                         edited: library.isChanged(sprite.id) || !library.isBuiltIn(sprite.id),
                                         white: settings.pixelArtWhite)
                                .onTapGesture { editors.open(sprite) }
                                .contextMenu { menu(for: sprite) }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Gallery")
                    Spacer()
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                HStack {
                    Button("New Art…") { editors.open(nil) }
                    Spacer()
                    Button("Import…", action: importFiles)
                    Button("Export All…") { export(library.sprites, name: "NotchLyrics Pixel Art") }
                }
            }
        }
        .formStyle(.grouped)
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message))
        }
        .alert(confirmation?.title ?? "", isPresented: Binding(
            get: { confirmation != nil },
            set: { if !$0 { confirmation = nil } }
        ), presenting: confirmation) { confirmation in
            switch confirmation {
            case .delete(let sprite):
                Button("Delete", role: .destructive) { library.delete(sprite.id) }
            case .reset(let sprite):
                Button("Reset", role: .destructive) { library.reset(sprite.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
    }

    private var summary: String {
        let off = library.sprites.filter { !library.isEnabled($0.id) }.count
        let count = "\(library.sprites.count) pieces of art"
        return off == 0 ? count : "\(count) · \(off) turned off"
    }

    @ViewBuilder
    private func menu(for sprite: PixelSprite) -> some View {
        Button("Edit…") { editors.open(sprite) }
        Button(library.isEnabled(sprite.id) ? "Turn Off" : "Turn On") {
            library.setEnabled(!library.isEnabled(sprite.id), id: sprite.id)
        }
        Button("Duplicate") {
            if let copy = library.duplicate(sprite.id) { editors.open(copy) }
        }
        Button("Export…") { export([sprite], name: sprite.name) }
        if library.isChanged(sprite.id) || !library.isBuiltIn(sprite.id) {
            Divider()
        }
        if library.isChanged(sprite.id) {
            Button("Reset to Original…") { confirmation = .reset(sprite) }
        }
        if !library.isBuiltIn(sprite.id) {
            Button("Delete…", role: .destructive) { confirmation = .delete(sprite) }
        }
    }

    private func importFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.message = "Choose pixel art exported from NotchLyrics."
        guard panel.runModal() == .OK else { return }

        var imported = 0
        var unreadable: [String] = []
        for url in panel.urls {
            do {
                imported += try library.importSprites(from: Data(contentsOf: url))
            } catch {
                unreadable.append(url.lastPathComponent)
            }
        }
        if unreadable.isEmpty {
            notice = Notice(title: imported == 1 ? "Imported 1 piece of art" : "Imported \(imported) pieces of art",
                            message: "Art that was already in the gallery was updated instead of added twice.")
        } else {
            notice = Notice(title: "Some files couldn't be imported",
                            message: "\(unreadable.joined(separator: ", ")) isn't NotchLyrics pixel art."
                                + (imported > 0 ? " \(imported) other pieces were imported." : ""))
        }
    }

    private func export(_ sprites: [PixelSprite], name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(name).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try library.exportData(for: sprites).write(to: url, options: .atomic)
        } catch {
            notice = Notice(title: "Couldn't export", message: error.localizedDescription)
        }
    }
}

struct PixelArtTile: View {
    let sprite: PixelSprite
    let enabled: Bool
    /// Drawn or changed by the user.
    let edited: Bool
    let white: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: sprite.frames.count < 2)) { context in
                PixelSpriteView(sprite: sprite, frame: sprite.frameIndex(at: context.date.timeIntervalSinceReferenceDate),
                                white: white, pixelSize: 2)
            }
            .frame(width: 58, height: 46)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(hovering ? 0.9 : 0), lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if !enabled {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(4)
                } else if edited {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6).padding(5)
                }
            }
            .opacity(enabled ? 1 : 0.4)

            Text(sprite.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(enabled ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(sprite.words.isEmpty ? sprite.name : sprite.words.joined(separator: ", "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sprite.name)\(enabled ? "" : ", turned off")")
        .accessibilityAddTraits(.isButton)
    }
}
