import AppKit
import LyricsCore
import SwiftUI

/// A sprite being edited on a full 16 × 16 canvas. Saving trims it back down to the pixels actually drawn.
@MainActor
final class PixelEditorDocument: ObservableObject {
    static let size = PixelCanvas.size
    typealias Cell = PixelCanvas.Point

    enum Tool: String, CaseIterable, Identifiable {
        case pencil, eraser, fill, picker

        var id: Self { self }

        var label: String {
            switch self {
            case .pencil: "Pencil"
            case .eraser: "Eraser"
            case .fill: "Fill"
            case .picker: "Pick a color from the art"
            }
        }

        var symbol: String {
            switch self {
            case .pencil: "pencil"
            case .eraser: "eraser"
            case .fill: "drop.fill"
            case .picker: "eyedropper"
            }
        }
    }

    let id: String
    @Published var frames: [[UInt32]]
    @Published var currentFrame = 0
    @Published var name: String
    @Published var wordsText: String
    @Published var motion: PixelMotion
    @Published var framesPerSecond: Double
    @Published var tool: Tool = .pencil
    @Published var color: UInt32
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    /// The editor window's undo manager, shared with its text fields like any Mac document window.
    weak var undoManager: UndoManager?
    private var baseline: PixelSprite
    private var strokeStart: [[UInt32]]?
    private var lastCell: Cell?

    init(sprite: PixelSprite) {
        id = sprite.id
        name = sprite.name
        wordsText = sprite.words.joined(separator: ", ")
        motion = sprite.motion
        framesPerSecond = sprite.framesPerSecond
        frames = PixelCanvas.frames(for: sprite)
        color = sprite.frames.first?.first { $0 & 0xFF != 0 } ?? BuiltInPixelArt.palette[0].color
        baseline = sprite
        baseline = self.sprite
    }

    /// Replaces everything with `sprite` and treats that as the saved state.
    func load(_ sprite: PixelSprite) {
        name = sprite.name
        wordsText = sprite.words.joined(separator: ", ")
        motion = sprite.motion
        framesPerSecond = sprite.framesPerSecond
        frames = PixelCanvas.frames(for: sprite)
        currentFrame = 0
        undoManager?.removeAllActions(withTarget: self)
        refreshUndoState()
        baseline = self.sprite
    }

    // MARK: - The sprite

    var words: [String] {
        var seen = Set<String>()
        return wordsText.split(whereSeparator: { ",，、;；\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    var sprite: PixelSprite {
        PixelSprite(id: id, name: displayName, width: Self.size, height: Self.size, frames: frames,
                    framesPerSecond: framesPerSecond, words: words, motion: motion).trimmed()
    }

    var isEmpty: Bool {
        frames.allSatisfy { frame in frame.allSatisfy { $0 & 0xFF == 0 } }
    }

    var isDirty: Bool {
        sprite != baseline
    }

    func markSaved() {
        baseline = sprite
    }

    /// Colors already in the art, most used first.
    var usedColors: [UInt32] {
        var counts: [UInt32: Int] = [:]
        for frame in frames {
            for color in frame where color & 0xFF != 0 {
                counts[color, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
    }

    // MARK: - Drawing

    func beginStroke(at cell: Cell) {
        strokeStart = frames
        lastCell = nil
        switch tool {
        case .pencil, .eraser:
            paint(cell)
        case .fill:
            fill(from: cell)
        case .picker:
            let picked = frames[currentFrame][cell.y * Self.size + cell.x]
            if picked & 0xFF != 0 {
                color = picked
                tool = .pencil
            }
        }
    }

    /// `nil` while the pointer is outside the canvas, so re-entering doesn't draw a line across.
    func continueStroke(to cell: Cell?) {
        guard strokeStart != nil, tool == .pencil || tool == .eraser else { return }
        guard let cell else {
            lastCell = nil
            return
        }
        paint(cell)
    }

    func endStroke() {
        if let start = strokeStart, start != frames {
            registerUndo(restoring: start, frame: currentFrame, name: tool == .fill ? "Fill" : "Drawing")
        }
        strokeStart = nil
        lastCell = nil
    }

    func selectColor(_ color: UInt32) {
        self.color = color
        if tool == .eraser || tool == .picker { tool = .pencil }
    }

    /// Draws to `cell`, joining it to the previous cell so fast strokes don't leave holes.
    private func paint(_ cell: Cell) {
        let value: UInt32 = tool == .eraser ? 0 : color
        var frame = frames[currentFrame]
        for point in PixelCanvas.line(from: lastCell ?? cell, to: cell) {
            frame[point.y * Self.size + point.x] = value
        }
        lastCell = cell
        if frame != frames[currentFrame] { frames[currentFrame] = frame }
    }

    private func fill(from cell: Cell) {
        var frame = frames[currentFrame]
        PixelCanvas.fill(&frame, at: cell, with: color)
        if frame != frames[currentFrame] { frames[currentFrame] = frame }
    }

    // MARK: - Frames

    var canAddFrame: Bool { frames.count < PixelSprite.maxFrames }

    func addFrame() {
        guard canAddFrame else { return }
        let before = frames
        frames.insert(frames[currentFrame], at: currentFrame + 1)
        currentFrame += 1
        registerUndo(restoring: before, frame: currentFrame - 1, name: "Add Frame")
    }

    func deleteFrame() {
        guard frames.count > 1 else { return }
        let before = frames, index = currentFrame
        frames.remove(at: index)
        currentFrame = min(index, frames.count - 1)
        registerUndo(restoring: before, frame: index, name: "Delete Frame")
    }

    func flip() {
        let before = frames
        frames = frames.map(PixelCanvas.flipped)
        registerUndo(restoring: before, frame: currentFrame, name: "Flip")
    }

    func clearFrame() {
        let before = frames
        frames[currentFrame] = PixelCanvas.blankFrame()
        guard before != frames else { return }
        registerUndo(restoring: before, frame: currentFrame, name: "Clear")
    }

    // MARK: - Undo

    private func registerUndo(restoring previous: [[UInt32]], frame: Int, name: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                let current = document.frames, currentFrame = document.currentFrame
                document.frames = previous
                document.currentFrame = min(frame, previous.count - 1)
                // Registering while undoing records the redo.
                document.registerUndo(restoring: current, frame: currentFrame, name: name)
            }
        }
        undoManager.setActionName(name)
        refreshUndoState()
    }

    func refreshUndoState() {
        // The undo manager updates after the current event finishes.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.canUndo = self.undoManager?.canUndo ?? false
            self.canRedo = self.undoManager?.canRedo ?? false
        }
    }

    static func blank() -> PixelSprite {
        PixelSprite(id: PixelArtLibrary.newID(), name: "New Art", width: size, height: size,
                    frames: [PixelCanvas.blankFrame()], words: [], motion: .stay)
    }
}

extension PixelMotion {
    var label: String {
        switch self {
        case .stay: "Stay"
        case .bounce: "Bounce"
        case .beat: "Heartbeat"
        case .twinkle: "Twinkle"
        case .drive: "Drive away"
        case .fly: "Fly away"
        case .float: "Float up"
        case .fall: "Fall"
        }
    }
}

extension Color {
    init(pixel: UInt32) {
        self.init(.sRGB, red: Double((pixel >> 24) & 0xFF) / 255, green: Double((pixel >> 16) & 0xFF) / 255,
                  blue: Double((pixel >> 8) & 0xFF) / 255, opacity: Double(pixel & 0xFF) / 255)
    }

    /// 0xRRGGBBAA in sRGB.
    var pixel: UInt32 {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        func channel(_ value: CGFloat) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
        return channel(color.redComponent) << 24 | channel(color.greenComponent) << 16
            | channel(color.blueComponent) << 8 | channel(color.alphaComponent)
    }
}
