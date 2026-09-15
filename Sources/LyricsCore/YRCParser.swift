import Foundation

/// Parses NetEase "YRC" word-level lyrics: `[lineStartMs,lineDurMs](wordStartMs,wordDurMs,0)word...`
public enum YRCParser {
    private static let header = try! NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#)
    private static let wordTag = try! NSRegularExpression(pattern: #"\((\d+),(\d+),-?\d+\)"#)

    public static func parse(_ raw: String, source: String) -> Lyrics? {
        var lines: [LyricLine] = []

        for rawLine in raw.components(separatedBy: .newlines) {
            let ns = rawLine as NSString
            guard let head = header.firstMatch(in: rawLine, range: NSRange(location: 0, length: ns.length)),
                  let lineStartMs = Double(ns.substring(with: head.range(at: 1))),
                  let lineDurationMs = Double(ns.substring(with: head.range(at: 2))) else { continue }

            let bodyStart = head.range.location + head.range.length
            let matches = wordTag.matches(in: rawLine, range: NSRange(location: bodyStart, length: ns.length - bodyStart))
            var words: [LyricWord] = []
            for (k, match) in matches.enumerated() {
                guard let startMs = Double(ns.substring(with: match.range(at: 1))),
                      let durationMs = Double(ns.substring(with: match.range(at: 2))) else { continue }
                let textStart = match.range.location + match.range.length
                let textEnd = k + 1 < matches.count ? matches[k + 1].range.location : ns.length
                let text = ns.substring(with: NSRange(location: textStart, length: textEnd - textStart))
                guard !text.isEmpty else { continue }
                words.append(LyricWord(text: text, start: startMs / 1000, end: (startMs + durationMs) / 1000))
            }
            guard !words.isEmpty else { continue }
            let start = lineStartMs / 1000
            lines.append(LyricLine(start: start, end: start + lineDurationMs / 1000, words: words))
        }

        lines.sort { $0.start < $1.start }
        lines = CreditFilter.apply(lines)
        guard lines.contains(where: { !$0.isBlank }) else { return nil }
        return Lyrics(lines: lines, timing: .word, source: source)
    }
}
