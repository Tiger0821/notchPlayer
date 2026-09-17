import AppKit
import LyricsCore
import SwiftUI

/// One lyric line whose words light up as they're sung. Long lines scroll to keep the sung position in view.
struct KaraokeLineView: View {
    let line: LyricLine
    let time: TimeInterval
    let fontSize: CGFloat
    let width: CGFloat
    /// Which edge the text hugs when it fits: the notch side.
    let alignment: Alignment
    /// Pixel art popping in after words of this line, keyed by word index.
    var art: [Int: PixelSprite] = [:]
    var whiteArt = false
    /// Which way sprites that leave head: +1 right, −1 left. Away from the notch.
    var artDirection: CGFloat = 1

    var body: some View {
        let widths = TextMeasurer.widths(of: line.words, fontSize: fontSize)
        let slots = artSlots()
        let slotWidths = line.words.indices.map { slots[$0]?.width ?? 0 }
        let total = widths.reduce(0, +) + slotWidths.reduce(0, +)
        let overflow = max(0, total - width + 2)
        // A sprite's gap counts as sung as soon as its word starts, so scrolling brings the sprite into view.
        let head = line.words.indices.reduce(0) { $0 + widths[$1] * line.words[$1].progress(at: time) + slotWidths[$1] }
        let scroll = overflow > 0 ? min(max(head - width * 0.65, 0), overflow) : 0
        let font = Font.system(size: fontSize, weight: .semibold)

        // The glow trails the word being sung and fades out over roughly the last 8 characters,
        // instead of switching off the moment a word ends.
        let characters = max(line.words.reduce(0) { $0 + $1.text.count }, 1)
        let glowSpan = max(widths.reduce(0, +) / CGFloat(characters) * 8, 1)
        var wordEnd: CGFloat = 0
        let ends = line.words.indices.map { index -> CGFloat in
            wordEnd += widths[index] + slotWidths[index]
            return wordEnd
        }

        HStack(spacing: 0) {
            ForEach(line.words.indices, id: \.self) { index in
                KaraokeWordView(text: line.words[index].text,
                                progress: line.words[index].progress(at: time),
                                glow: min(max(1 - (head - ends[index]) / glowSpan, 0), 1),
                                font: font)
                if let slot = slots[index] {
                    PixelArtSlotView(slot: slot, white: whiteArt, direction: artDirection)
                        // Leaving sprites pass over the words after them.
                        .zIndex(1)
                }
            }
        }
        .fixedSize()
        .offset(x: -scroll)
        .frame(width: width, alignment: overflow > 0 ? .leading : alignment)
        // The mask clips the sides like the strip does, but leaves room above and below for sprites to move.
        .mask {
            EdgeFade(leading: scroll > 0.5, trailing: scroll < overflow - 0.5)
                .padding(.vertical, -24)
        }
    }

    private func artSlots() -> [Int: PixelArtSlot] {
        guard !art.isEmpty else { return [:] }
        let pixelSize = SpriteMotion.pixelSize(fontSize: fontSize)
        var slots: [Int: PixelArtSlot] = [:]
        for (index, sprite) in art where line.words.indices.contains(index) {
            let word = line.words[index]
            let elapsed = time - word.start
            guard elapsed >= 0 else { continue }
            let pose = SpriteMotion.pose(for: sprite, elapsed: elapsed, direction: artDirection)
            // Words usually end with a space already; CJK characters and last words don't.
            let lead: CGFloat = word.text.last?.isWhitespace == true ? 0 : 3
            let trail: CGFloat = index == line.words.count - 1 ? 0 : 4
            let full = lead + CGFloat(sprite.width) * pixelSize + trail
            slots[index] = PixelArtSlot(sprite: sprite, pose: pose, lead: lead, pixelSize: pixelSize, width: full * pose.gap)
        }
        return slots
    }
}

struct PixelArtSlot {
    let sprite: PixelSprite
    let pose: SpritePose
    let lead: CGFloat
    let pixelSize: CGFloat
    /// The gap the sprite takes in the line right now.
    let width: CGFloat
}

/// The gap a sprite opens in a line, with the sprite drawn over it. The sprite never changes the line's height.
struct PixelArtSlotView: View {
    let slot: PixelArtSlot
    let white: Bool
    let direction: CGFloat

    var body: some View {
        let mirrored = SpriteMotion.isMirrored(slot.sprite, direction: direction)
        Color.clear
            .frame(width: slot.width, height: 1)
            .overlay(alignment: .leading) {
                PixelSpriteView(sprite: slot.sprite, frame: slot.pose.frame, white: white, pixelSize: slot.pixelSize)
                    .scaleEffect(x: mirrored ? -slot.pose.scale : slot.pose.scale, y: slot.pose.scale)
                    .opacity(slot.pose.opacity)
                    .offset(x: slot.lead + slot.pose.offset.width, y: slot.pose.offset.height)
                    .fixedSize()
            }
    }
}

struct KaraokeWordView: View {
    let text: String
    let progress: Double
    /// 1 on the word being sung, fading to 0 across the characters behind it.
    var glow: Double = 0
    let font: Font

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Color.white.opacity(0.4))
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(Color.white)
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle().frame(width: proxy.size.width * progress)
                        }
                    }
                    // The sung word glows, trailing off over the characters behind it.
                    .shadow(color: Color.white.opacity(0.85 * glow), radius: 4)
            }
    }
}

struct EdgeFade: View {
    let leading: Bool
    let trailing: Bool

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 16)
            Rectangle()
            LinearGradient(colors: [.black, trailing ? .clear : .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 16)
        }
    }
}

@MainActor
enum TextMeasurer {
    private static var cache: [String: [CGFloat]] = [:]

    static func widths(of words: [LyricWord], fontSize: CGFloat) -> [CGFloat] {
        let key = "\(fontSize)|" + words.map(\.text).joined(separator: "\u{1}")
        if let cached = cache[key] { return cached }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)]
        let result = words.map { ($0.text as NSString).size(withAttributes: attributes).width }
        if cache.count > 300 { cache.removeAll() }
        cache[key] = result
        return result
    }
}
