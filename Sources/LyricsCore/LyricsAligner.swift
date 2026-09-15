import Foundation

/// A lyric unit (one CJK character or one Latin word) at a point in time.
public struct TimedUnit: Equatable, Sendable {
    public var key: String
    public var time: TimeInterval
    public var isCJK: Bool

    public init(key: String, time: TimeInterval, isCJK: Bool) {
        self.key = key
        self.time = time
        self.isCJK = isCJK
    }
}

public struct AlignmentEstimate: Equatable, Sendable {
    /// Seconds to add to the playback position to get the lyric time.
    public var offset: TimeInterval
    /// Distinct recognized phrases that agree on this offset.
    public var support: Int
    /// Share of all phrase-match weight that agrees with this offset (0–1).
    public var agreement: Double
}

/// Estimates how far lyric timestamps are from actual playback by matching words recognized from the audio
/// against the lyrics. Short phrases (3 CJK characters or 2 words) vote for an offset; repeated phrases such as
/// choruses vote for every place they occur, with less weight, so the true offset forms the densest cluster.
public struct LyricsAligner: Sendable {
    public static let maxOffset: TimeInterval = 20

    private struct Vote: Sendable {
        var offset: Double
        var weight: Double
        var time: Double
    }

    private let lyricGrams: [String: [TimeInterval]]
    private var votes: [Vote] = []
    private var seen = Set<String>()

    public init(lyrics: Lyrics) {
        var units: [TimedUnit] = []
        for line in lyrics.lines {
            for word in line.words {
                units += Self.units(from: word.text, start: word.start, end: word.end)
            }
        }
        var index: [String: [TimeInterval]] = [:]
        for gram in Self.grams(units) {
            index[gram.key, default: []].append(gram.time)
        }
        lyricGrams = index
    }

    public var matchedPhraseCount: Int { Set(votes.map(\.time)).count }

    /// Adds units recognized from the audio, timed on the playback clock.
    public mutating func add(_ units: [TimedUnit]) {
        for gram in Self.grams(units) {
            // The same phrase can come back in more than one result; count it once.
            guard seen.insert("\(gram.key)@\(Int((gram.time * 4).rounded()))").inserted,
                  let occurrences = lyricGrams[gram.key] else { continue }
            let candidates = occurrences.map { $0 - gram.time }.filter { abs($0) <= Self.maxOffset }
            guard !candidates.isEmpty else { continue }
            let weight = 1 / Double(candidates.count)
            votes += candidates.map { Vote(offset: $0, weight: weight, time: gram.time) }
        }
    }

    public func estimate() -> AlignmentEstimate? {
        guard let best = Self.densestWindow(votes) else { return nil }
        let rivals = votes.filter { abs($0.offset - best.center) > 1 }
        let rivalWeight = Self.densestWindow(rivals)?.weight ?? 0
        let support = Set(best.members.map { ($0.time * 4).rounded() }).count
        let totalWeight = votes.reduce(0) { $0 + $1.weight }

        guard support >= 4, best.weight >= 2, best.weight >= rivalWeight * 2 else { return nil }
        return AlignmentEstimate(offset: best.center, support: support, agreement: best.weight / totalWeight)
    }

    // MARK: - Helpers

    private static func densestWindow(_ votes: [Vote], width: Double = 0.4) -> (center: Double, weight: Double, members: [Vote])? {
        guard !votes.isEmpty else { return nil }
        let sorted = votes.sorted { $0.offset < $1.offset }
        var best = (weight: 0.0, lower: 0, upper: 0)
        var upper = 0
        var sum = 0.0
        for lower in sorted.indices {
            while upper < sorted.count, sorted[upper].offset - sorted[lower].offset <= width {
                sum += sorted[upper].weight
                upper += 1
            }
            if sum > best.weight { best = (sum, lower, upper) }
            sum -= sorted[lower].weight
        }
        let members = Array(sorted[best.lower..<best.upper])
        return (weightedMedian(members), best.weight, members)
    }

    private static func weightedMedian(_ votes: [Vote]) -> Double {
        let total = votes.reduce(0) { $0 + $1.weight }
        var running = 0.0
        for vote in votes {
            running += vote.weight
            if running >= total / 2 { return vote.offset }
        }
        return votes.last?.offset ?? 0
    }

    static func grams(_ units: [TimedUnit]) -> [(key: String, time: TimeInterval)] {
        units.indices.compactMap { i in
            let length = units[i].isCJK ? 3 : 2
            guard i + length <= units.count else { return nil }
            let slice = units[i..<(i + length)]
            // Skip phrases that span a long pause; those units likely aren't adjacent in the lyrics.
            guard slice.last!.time - slice.first!.time < Double(length) * 1.5 else { return nil }
            return (slice.map(\.key).joined(separator: "|"), units[i].time)
        }
    }

    /// Splits text into CJK characters and Latin words, spreading `start...end` across them.
    public static func units(from text: String, start: TimeInterval, end: TimeInterval) -> [TimedUnit] {
        var pieces: [(text: String, isCJK: Bool)] = []
        var word = ""
        func flushWord() {
            if !word.isEmpty { pieces.append((word, false)) }
            word = ""
        }
        for character in text {
            if character.isCJK {
                flushWord()
                pieces.append((String(character), true))
            } else if character.isLetter || character.isNumber {
                word.append(character)
            } else if character != "'" && character != "’" {
                flushWord()
            }
        }
        flushWord()
        guard !pieces.isEmpty else { return [] }

        let step = max(end - start, 0) / Double(pieces.count)
        return pieces.enumerated().compactMap { index, piece in
            let key = TextNormalize.toSimplified(piece.text)
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            guard !key.isEmpty else { return nil }
            return TimedUnit(key: key, time: start + step * Double(index), isCJK: piece.isCJK)
        }
    }
}
