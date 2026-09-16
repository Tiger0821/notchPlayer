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

    var body: some View {
        let widths = TextMeasurer.widths(of: line.words, fontSize: fontSize)
        let total = widths.reduce(0, +)
        let overflow = max(0, total - width + 2)
        let head = zip(line.words, widths).reduce(0) { $0 + $1.1 * $1.0.progress(at: time) }
        let scroll = overflow > 0 ? min(max(head - width * 0.65, 0), overflow) : 0
        let font = Font.system(size: fontSize, weight: .semibold)

        // The glow trails the word being sung and fades out over roughly the last 8 characters,
        // instead of switching off the moment a word ends.
        let characters = max(line.words.reduce(0) { $0 + $1.text.count }, 1)
        let glowSpan = max(total / CGFloat(characters) * 8, 1)
        var wordEnd: CGFloat = 0
        let ends = widths.map { width -> CGFloat in
            wordEnd += width
            return wordEnd
        }

        HStack(spacing: 0) {
            ForEach(line.words.indices, id: \.self) { index in
                KaraokeWordView(text: line.words[index].text,
                                progress: line.words[index].progress(at: time),
                                glow: min(max(1 - (head - ends[index]) / glowSpan, 0), 1),
                                font: font)
            }
        }
        .fixedSize()
        .offset(x: -scroll)
        .frame(width: width, alignment: overflow > 0 ? .leading : alignment)
        .clipped()
        .mask(EdgeFade(leading: scroll > 0.5, trailing: scroll < overflow - 0.5))
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
