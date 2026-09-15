import Foundation

/// Parses standard LRC (`[mm:ss.xx]line`) and enhanced LRC with word tags (`<mm:ss.xx>word`).
public enum LRCParser {
    private static let wordTag = try! NSRegularExpression(pattern: #"<(\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?)>"#)

    public static func parse(_ raw: String, source: String) -> Lyrics? {
        struct Entry {
            var time: TimeInterval
            var body: String
        }
        var entries: [Entry] = []
        var offset: TimeInterval = 0

        for rawLine in raw.components(separatedBy: .newlines) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let content = rest[rest.index(after: rest.startIndex)..<close]
                if let time = parseTime(content) {
                    times.append(time)
                } else if content.lowercased().hasPrefix("offset:") {
                    // Positive offset means lyrics should appear earlier.
                    offset = (Double(content.dropFirst(7).trimmingCharacters(in: .whitespaces)) ?? 0) / 1000
                } else if !(times.isEmpty && content.contains(":")) {
                    break // Not a metadata tag like [ar:...]; it's part of the lyric text.
                }
                rest = rest[rest.index(after: close)...]
            }
            for time in times {
                entries.append(Entry(time: max(0, time - offset), body: String(rest)))
            }
        }

        guard !entries.isEmpty else { return nil }
        entries.sort { $0.time < $1.time }

        var lines: [LyricLine] = []
        var hasWordTags = false
        for (index, entry) in entries.enumerated() {
            let start = entry.time
            let nextStart = index + 1 < entries.count ? entries[index + 1].time : start + 10
            if let words = parseWordTags(entry.body, lineStart: start, lineEnd: nextStart, offset: offset) {
                hasWordTags = true
                lines.append(LyricLine(start: start, end: words.last?.end ?? nextStart, words: words))
            } else {
                let text = entry.body.trimmingCharacters(in: .whitespaces)
                let end = min(nextStart, start + WordTiming.estimatedDuration(for: text))
                lines.append(LyricLine(start: start, end: end, words: WordTiming.estimate(text: text, start: start, end: end)))
            }
        }

        lines = CreditFilter.apply(lines)
        guard lines.contains(where: { !$0.isBlank }) else { return nil }
        return Lyrics(lines: lines, timing: hasWordTags ? .word : .line, source: source)
    }

    private static func parseWordTags(_ body: String, lineStart: TimeInterval, lineEnd: TimeInterval, offset: TimeInterval) -> [LyricWord]? {
        let ns = body as NSString
        let matches = wordTag.matches(in: body, range: NSRange(location: 0, length: ns.length))
        guard let first = matches.first else { return nil }

        var words: [LyricWord] = []
        let leading = ns.substring(to: first.range.location)
        var pending: (text: String, start: TimeInterval)? = leading.trimmingCharacters(in: .whitespaces).isEmpty ? nil : (leading, lineStart)

        for (k, match) in matches.enumerated() {
            let time = max(0, (parseTime(Substring(ns.substring(with: match.range(at: 1)))) ?? lineStart) - offset)
            if let p = pending {
                words.append(LyricWord(text: p.text, start: p.start, end: max(time, p.start)))
                pending = nil
            }
            let textStart = match.range.location + match.range.length
            let textEnd = k + 1 < matches.count ? matches[k + 1].range.location : ns.length
            let text = ns.substring(with: NSRange(location: textStart, length: textEnd - textStart))
            if !text.isEmpty { pending = (text, time) }
        }
        // A word with no closing tag gets a short estimated duration.
        if let p = pending {
            let end = min(lineEnd, p.start + max(0.4, Double(p.text.count) * 0.15))
            words.append(LyricWord(text: p.text, start: p.start, end: max(end, p.start)))
        }
        return words.isEmpty ? nil : words
    }

    /// Accepts `mm:ss`, `mm:ss.xx`, `mm:ss.xxx` and `mm:ss:xx`.
    static func parseTime(_ string: Substring) -> TimeInterval? {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              let minutes = Double(parts[0]), parts[0].allSatisfy(\.isNumber) else { return nil }
        guard let seconds = Double(parts[1]), parts[1].allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        var fraction = 0.0
        if parts.count == 3 {
            guard let value = Double(parts[2]), parts[2].allSatisfy(\.isNumber) else { return nil }
            fraction = value / pow(10, Double(parts[2].count))
        }
        return minutes * 60 + seconds + fraction
    }
}

/// Removes "作词 : xxx" / "Composer: xxx" credit lines that many sources put at the top.
enum CreditFilter {
    private static let labels = [
        "作词", "作詞", "作曲", "编曲", "編曲", "制作", "製作", "监制", "監製", "混音", "录音", "錄音",
        "和声", "和聲", "吉他", "贝斯", "貝斯", "鼓", "母带", "母帶", "出品", "发行", "發行", "词", "詞", "曲",
        "op", "sp", "lyricist", "lyrics by", "composer", "composed by", "arranger", "arranged by",
        "producer", "produced by", "written by",
    ]

    static func isCredit(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
        let label = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard !label.isEmpty, label.count <= 16 else { return false }
        return labels.contains { label.hasPrefix($0) }
    }

    static func apply(_ lines: [LyricLine]) -> [LyricLine] {
        lines.filter { !isCredit($0.text) }
    }
}
