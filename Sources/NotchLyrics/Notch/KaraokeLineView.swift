import AppKit
import LyricsCore
import SwiftUI

/// One lyric line whose words light up as they're sung. Long lines scroll to keep the sung position in view.
struct KaraokeLineView: View {
    let line: LyricLine
    let time: TimeInterval
    let fontSize: CGFloat
    let width: CGFloat

    var body: some View {
        let widths = TextMeasurer.widths(of: line.words, fontSize: fontSize)
        let total = widths.reduce(0, +)
        let overflow = max(0, total - width + 2)
        let head = zip(line.words, widths).reduce(0) { $0 + $1.1 * $1.0.progress(at: time) }
        let scroll = overflow > 0 ? min(max(head - width * 0.65, 0), overflow) : 0
        let font = Font.system(size: fontSize, weight: .semibold)

        HStack(spacing: 0) {
            ForEach(line.words.indices, id: \.self) { index in
                KaraokeWordView(text: line.words[index].text, progress: line.words[index].progress(at: time), font: font)
            }
        }
        .fixedSize()
        .offset(x: -scroll)
        .frame(width: width, alignment: overflow > 0 ? .leading : .trailing)
        .clipped()
        .mask(EdgeFade(leading: scroll > 0.5, trailing: scroll < overflow - 0.5))
    }
}

struct KaraokeWordView: View {
    let text: String
    let progress: Double
    let font: Font

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Color.white.opacity(0.32))
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(Color.white)
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle().frame(width: proxy.size.width * progress)
                        }
                    }
                    // The word being sung right now glows.
                    .shadow(color: Color.white.opacity(progress > 0 && progress < 1 ? 0.8 : 0), radius: 4)
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
