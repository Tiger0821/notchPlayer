import Foundation

public struct LyricWord: Equatable, Sendable {
    /// Includes trailing whitespace/punctuation, so joining a line's words reproduces the line.
    public var text: String
    public var start: TimeInterval
    public var end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }

    /// 0 before the word starts, 1 once it has been sung.
    public func progress(at time: TimeInterval) -> Double {
        guard end > start else { return time >= start ? 1 : 0 }
        return min(max((time - start) / (end - start), 0), 1)
    }
}

public struct LyricLine: Equatable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var words: [LyricWord]

    public init(start: TimeInterval, end: TimeInterval, words: [LyricWord]) {
        self.start = start
        self.end = end
        self.words = words
    }

    public var text: String { words.map(\.text).joined() }
    public var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public enum LyricsTiming: Int, Comparable, Sendable {
    /// Only line timestamps; word timings are estimated.
    case line = 1
    /// Real per-word timestamps.
    case word = 2

    public static func < (lhs: LyricsTiming, rhs: LyricsTiming) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct Lyrics: Equatable, Sendable {
    public var lines: [LyricLine]
    public var timing: LyricsTiming
    public var source: String
    /// Position of each line among the sung (non-blank) lines. Blank lines keep the previous number, so
    /// alternating sides per sung line stays in step.
    public private(set) var lineOrdinals: [Int]

    public init(lines: [LyricLine], timing: LyricsTiming, source: String) {
        self.lines = lines
        self.timing = timing
        self.source = source
        var ordinal = -1
        lineOrdinals = lines.map { line in
            if !line.isBlank { ordinal += 1 }
            return max(ordinal, 0)
        }
    }

    /// Index of the last line that has started at `time`, or nil before the first line.
    public func lineIndex(at time: TimeInterval) -> Int? {
        var low = 0, high = lines.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].start <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    public func mapText(_ transform: (String) -> String) -> Lyrics {
        var copy = self
        for i in copy.lines.indices {
            for j in copy.lines[i].words.indices {
                copy.lines[i].words[j].text = transform(copy.lines[i].words[j].text)
            }
        }
        return copy
    }

    var containsKana: Bool {
        lines.contains { line in
            line.text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
        }
    }
}
