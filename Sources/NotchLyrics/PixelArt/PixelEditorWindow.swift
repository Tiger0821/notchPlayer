import AppKit
import LyricsCore
import SwiftUI

/// One editor window per sprite; opening a sprite that's already being edited brings its window forward.
@MainActor
final class PixelEditorWindows {
    private let library: PixelArtLibrary
    private let settings: AppSettings
    private var controllers: [String: PixelEditorWindowController] = [:]

    init(library: PixelArtLibrary, settings: AppSettings) {
        self.library = library
        self.settings = settings
    }

    /// Opens `sprite`, or a blank canvas for new art.
    func open(_ sprite: PixelSprite?) {
        let sprite = sprite ?? PixelEditorDocument.blank()
        if let controller = controllers[sprite.id] {
            controller.show()
            return
        }
        let controller = PixelEditorWindowController(sprite: sprite, library: library, settings: settings) { [weak self] in
            self?.controllers[sprite.id] = nil
        }
        controllers[sprite.id] = controller
        controller.show()
    }

    /// Debug: opens the editor for a sprite and renders the whole window to a PNG.
    func writeSnapshot(spriteID: String, to url: URL) {
        guard let sprite = library.sprite(id: spriteID) else { return }
        open(sprite)
        guard let window = controllers[spriteID]?.window else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let frameView = window.contentView?.superview,
                  let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

@MainActor
final class PixelEditorWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let document: PixelEditorDocument
    private let library: PixelArtLibrary
    private let onClose: () -> Void

    init(sprite: PixelSprite, library: PixelArtLibrary, settings: AppSettings, onClose: @escaping () -> Void) {
        document = PixelEditorDocument(sprite: sprite)
        self.library = library
        self.onClose = onClose
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()

        window.title = library.contains(sprite.id) ? "\(sprite.name) — Pixel Art" : "New Pixel Art"
        window.isReleasedWhenClosed = false
        window.delegate = self
        document.undoManager = window.undoManager

        let editor = PixelEditorView(
            document: document, library: library, settings: settings,
            save: { [weak self] in self?.save() },
            cancel: { [weak self] in self?.window.performClose(nil) },
            delete: { [weak self] in self?.delete() },
            reset: { [weak self] in self?.reset() })
        let hosting = NSHostingView(rootView: editor)
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func save() {
        guard !document.isEmpty else { return }
        library.save(document.sprite)
        document.markSaved()
        window.close()
    }

    private func delete() {
        let alert = NSAlert()
        alert.messageText = "Delete “\(document.displayName)”?"
        alert.informativeText = "This art will be removed from the gallery. You can't undo this."
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.library.delete(self.document.id)
            self.document.markSaved()
            self.window.close()
        }
    }

    private func reset() {
        guard let original = library.original(id: document.id) else { return }
        let alert = NSAlert()
        alert.messageText = "Reset “\(original.name)” to the original?"
        alert.informativeText = "Your changes to its pixels, words and motion will be lost."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.library.reset(original.id)
            self.document.load(original)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Empty art can't be saved, so there's nothing to ask about.
        guard document.isDirty, !document.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(document.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            library.save(document.sprite)
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

// MARK: - Editor

struct PixelEditorView: View {
    @ObservedObject var document: PixelEditorDocument
    @ObservedObject var library: PixelArtLibrary
    @ObservedObject var settings: AppSettings
    let save: () -> Void
    let cancel: () -> Void
    let delete: () -> Void
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    toolbar
                    PixelCanvasView(document: document)
                        .frame(width: 416, height: 416)
                    PixelFramesView(document: document)
                }
                .padding(20)

                Divider()

                Form {
                    Section("Preview") {
                        PixelEditorPreview(document: document, white: settings.pixelArtWhite)
                    }
                    details
                    colors
                }
                .formStyle(.grouped)
            }
            Divider()
            buttons
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Tool", selection: $document.tool) {
                ForEach(PixelEditorDocument.Tool.allCases) { tool in
                    Image(systemName: tool.symbol)
                        .help(tool.label)
                        .accessibilityLabel(tool.label)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            ControlGroup {
                Button { document.undoManager?.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .help("Undo")
                    .disabled(!document.canUndo)
                Button { document.undoManager?.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .help("Redo")
                    .disabled(!document.canRedo)
            }
            .fixedSize()

            Button { document.flip() } label: { Image(systemName: "flip.horizontal") }
                .help("Flip the art so it faces the other way")
            Button { document.clearFrame() } label: { Image(systemName: "trash") }
                .help(document.frames.count > 1 ? "Clear this frame" : "Clear the canvas")
        }
    }

    @ViewBuilder
    private var details: some View {
        Section {
            TextField("Name", text: $document.name)
            VStack(alignment: .leading, spacing: 6) {
                TextField("Words", text: $document.wordsText, prompt: Text("love, lover, 愛"), axis: .vertical)
                    .lineLimit(2...4)
                Text(document.words.isEmpty
                     ? "Add the words that should show this art. Separate them with commas."
                     : "English words also match their plurals, like car → cars. Chinese works in either script.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Motion", selection: $document.motion) {
                ForEach(PixelMotion.allCases, id: \.self) { motion in
                    Text(motion.label).tag(motion)
                }
            }
            if document.frames.count > 1 {
                LabeledContent("Animation speed") {
                    HStack {
                        Slider(value: $document.framesPerSecond, in: 1...12, step: 0.5)
                            .frame(width: 120)
                        Text("\(document.framesPerSecond, specifier: "%g") fps")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var colors: some View {
        Section("Color") {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(pixel: document.color))
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(.separator))
                Text(PixelSprite.hex(document.color))
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer()
                ColorPicker("Any color", selection: Binding(
                    get: { Color(pixel: document.color) },
                    set: { document.selectColor($0.pixel) }))
            }
            SwatchGrid(colors: BuiltInPixelArt.palette.map(\.color), document: document)
            let used = document.usedColors.filter { color in !BuiltInPixelArt.palette.contains { $0.color == color } }
            if !used.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Also in this art").font(.caption).foregroundStyle(.secondary)
                    SwatchGrid(colors: Array(used.prefix(18)), document: document)
                }
            }
        }
    }

    private var buttons: some View {
        HStack {
            if library.isBuiltIn(document.id) {
                Button("Reset to Original…", action: reset)
                    .disabled(!library.isChanged(document.id))
            } else if library.contains(document.id) {
                Button("Delete…", role: .destructive, action: delete)
            }
            Spacer()
            if document.isEmpty {
                Text("Draw something to save it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: save)
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(document.isEmpty)
        }
    }
}

private struct SwatchGrid: View {
    let colors: [UInt32]
    @ObservedObject var document: PixelEditorDocument

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 7), count: 9), alignment: .leading, spacing: 7) {
            ForEach(colors, id: \.self) { color in
                Button { document.selectColor(color) } label: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(pixel: color))
                        .frame(width: 22, height: 22)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(document.color == color ? Color.accentColor : Color.primary.opacity(0.15),
                                              lineWidth: document.color == color ? 2 : 1)
                        }
                }
                .buttonStyle(.plain)
                .help(PixelSprite.hex(color))
            }
        }
    }
}

// MARK: - Canvas

struct PixelCanvasView: View {
    @ObservedObject var document: PixelEditorDocument
    @State private var hovered: PixelEditorDocument.Cell?
    @State private var drawing = false

    var body: some View {
        GeometryReader { proxy in
            let count = PixelEditorDocument.size
            let cell = floor(min(proxy.size.width, proxy.size.height) / CGFloat(count))
            let side = cell * CGFloat(count)
            let pixels = document.frames[document.currentFrame]
            // A faint copy of the previous frame helps line animation frames up.
            let previous = document.currentFrame > 0 ? document.frames[document.currentFrame - 1] : nil

            Canvas { context, _ in
                context.fill(Path(CGRect(x: 0, y: 0, width: side, height: side)), with: .color(.black))
                for index in pixels.indices {
                    let rect = CGRect(x: CGFloat(index % count) * cell, y: CGFloat(index / count) * cell, width: cell, height: cell)
                    if pixels[index] & 0xFF != 0 {
                        context.fill(Path(rect), with: .color(Color(pixel: pixels[index])))
                    } else if let previous, previous[index] & 0xFF != 0 {
                        context.fill(Path(rect), with: .color(Color(pixel: previous[index]).opacity(0.18)))
                    }
                }

                var grid = Path()
                for line in 1..<count {
                    let position = CGFloat(line) * cell
                    grid.move(to: CGPoint(x: position, y: 0))
                    grid.addLine(to: CGPoint(x: position, y: side))
                    grid.move(to: CGPoint(x: 0, y: position))
                    grid.addLine(to: CGPoint(x: side, y: position))
                }
                context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)

                if let hovered {
                    let rect = CGRect(x: CGFloat(hovered.x) * cell, y: CGFloat(hovered.y) * cell, width: cell, height: cell)
                    context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.white.opacity(0.7)), lineWidth: 1)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let target = self.cell(at: value.location, size: cell)
                        hovered = target
                        if !drawing {
                            guard let target else { return }
                            drawing = true
                            document.beginStroke(at: target)
                        } else {
                            document.continueStroke(to: target)
                        }
                    }
                    .onEnded { _ in
                        if drawing { document.endStroke() }
                        drawing = false
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hovered = self.cell(at: location, size: cell)
                case .ended: hovered = nil
                }
            }
            .accessibilityLabel("Pixel canvas")
        }
    }

    private func cell(at point: CGPoint, size: CGFloat) -> PixelEditorDocument.Cell? {
        guard size > 0 else { return nil }
        let x = Int(floor(point.x / size)), y = Int(floor(point.y / size))
        let range = 0..<PixelEditorDocument.size
        return range.contains(x) && range.contains(y) ? PixelEditorDocument.Cell(x: x, y: y) : nil
    }
}

struct PixelFramesView: View {
    @ObservedObject var document: PixelEditorDocument

    var body: some View {
        let canvas = PixelSprite(id: "\(document.id)#canvas", name: "", width: PixelEditorDocument.size,
                                 height: PixelEditorDocument.size, frames: document.frames, words: [], motion: .stay)
        HStack(spacing: 10) {
            Text("Frames")
                .foregroundStyle(.secondary)
            ForEach(document.frames.indices, id: \.self) { index in
                Button { document.currentFrame = index } label: {
                    PixelSpriteView(sprite: canvas, frame: index, pixelSize: 2.5)
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(index == document.currentFrame ? Color.accentColor : .clear, lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .help("Frame \(index + 1)")
            }
            Button { document.addFrame() } label: { Image(systemName: "plus") }
                .help("Add a frame: copies this one, so you only redraw what moves")
                .disabled(!document.canAddFrame)
            Button { document.deleteFrame() } label: { Image(systemName: "minus") }
                .help("Delete this frame")
                .disabled(document.frames.count < 2)
        }
    }
}

/// The art beside a sample lyric at real size, doing its motion, plus a big view of its frames.
struct PixelEditorPreview: View {
    @ObservedObject var document: PixelEditorDocument
    let white: Bool

    var body: some View {
        // A separate id keeps the library's cached images of the saved version intact.
        var sprite = document.sprite
        sprite.id = "\(document.id)#preview"
        let (line, wordIndex) = Self.sampleLine(for: sprite)

        return TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.5)
            HStack(spacing: 14) {
                KaraokeLineView(line: line, time: time, fontSize: 13, width: 196, alignment: .leading,
                                art: document.isEmpty ? [:] : [wordIndex: sprite], whiteArt: white, artDirection: 1)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous).fill(.black))
                PixelSpriteView(sprite: sprite, frame: sprite.frameIndex(at: time), white: white, pixelSize: 3)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black))
            }
            .environment(\.colorScheme, .dark)
        }
    }

    /// "Singing about <first word> tonight", with the art placed where the real matcher would put it.
    private static func sampleLine(for sprite: PixelSprite) -> (LyricLine, Int) {
        let word = sprite.words.first ?? sprite.name.lowercased()
        let words = WordTiming.estimate(text: "Singing about \(word) tonight", start: 0.3, end: 2.8)
        let matcher = PixelArtMatcher(sprites: [(sprite.id, [word])], ignored: [])
        let index = matcher.matches(in: words).first?.wordIndex ?? min(2, words.count - 1)
        return (LyricLine(start: 0.3, end: 2.8, words: words), max(index, 0))
    }
}
