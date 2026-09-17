import Foundation

/// A line Music has been seen singing, and when it started singing it.
public struct LineAnchor: Equatable, Sendable {
    public var text: String
    public var start: TimeInterval

    public init(text: String, start: TimeInterval) {
        self.text = text
        self.start = start
    }
}

/// Lyrics moved onto someone else's clock, and how much of them that clock actually covered.
public struct RetimedLyrics: Equatable, Sendable {
    public var lyrics: Lyrics
    /// How many lines were matched by text. Everything between two matches is stretched to fit.
    public var matchedLines: Int
}

/// Puts lyrics fetched from somewhere else onto the line changes Music itself made.
///
/// The two sources are good at opposite things. NetEase has word-by-word lyrics for far more songs than
/// anyone else, but its timing is whatever the person who uploaded it typed, and it drifts — which is what
/// listening to the audio otherwise has to correct for. Music knows exactly when each line starts, because it
/// marks the line it is singing, but exposes no word timing at all. Matching the two by their text takes the
/// words from one and the clock from the other.
///
/// Matching is in order and forwards only, so a chorus lines up with the next time it is sung rather than the
/// first. Lines that don't match — a source's credits, a line one of them splits differently — are stretched
/// into place between the two matches around them, which is also what happens to the whole song ahead of the
/// last line Music has reached.
public enum TimingTransfer {
    /// Below this, a match is as likely to be a coincidence as a line, and moving the timing on the strength
    /// of it would be worse than leaving it alone.
    public static let minimumMatches = 2

    public static func apply(_ anchors: [LineAnchor], to lyrics: Lyrics) -> RetimedLyrics? {
        let pairs = pairs(anchors, lyrics)
        guard pairs.count >= minimumMatches else { return nil }

        var lines = lyrics.lines
        for i in lines.indices {
            let start = warp(lines[i].start, pairs)
            lines[i].start = start
            lines[i].end = max(warp(lines[i].end, pairs), start)
            for j in lines[i].words.indices {
                let wordStart = warp(lines[i].words[j].start, pairs)
                lines[i].words[j].start = wordStart
                lines[i].words[j].end = max(warp(lines[i].words[j].end, pairs), wordStart)
            }
        }
        return RetimedLyrics(
            lyrics: Lyrics(lines: lines, timing: lyrics.timing, source: lyrics.source),
            matchedLines: pairs.count)
    }

    /// Where a line starts now, against where Music started it. Both sides increase, so the mapping built
    /// from them never doubles back.
    private static func pairs(_ anchors: [LineAnchor], _ lyrics: Lyrics) -> [(old: TimeInterval, new: TimeInterval)] {
        let keys = lyrics.lines.map { TextNormalize.key($0.text) }
        var pairs: [(old: TimeInterval, new: TimeInterval)] = []
        var searchFrom = 0

        for anchor in anchors.sorted(by: { $0.start < $1.start }) {
            let key = TextNormalize.key(anchor.text)
            guard !key.isEmpty else { continue }
            guard let index = (searchFrom..<keys.count).first(where: { keys[$0] == key }) else { continue }
            searchFrom = index + 1
            let old = lyrics.lines[index].start
            // A line the fetched lyrics put out of order, or two lines Music started within one sample of
            // each other, would bend the mapping backwards. Keep the first of them and drop the rest.
            if let last = pairs.last, old <= last.old || anchor.start <= last.new { continue }
            pairs.append((old: old, new: max(0, anchor.start)))
        }
        return pairs
    }

    /// Piecewise linear: between two matched lines everything is stretched by however much that stretch of
    /// the song moved, and outside them it is shifted by the nearest match's correction.
    private static func warp(_ time: TimeInterval, _ pairs: [(old: TimeInterval, new: TimeInterval)]) -> TimeInterval {
        guard let first = pairs.first, let last = pairs.last else { return time }
        if time <= first.old { return max(0, time + (first.new - first.old)) }
        if time >= last.old { return max(0, time + (last.new - last.old)) }

        var low = 0, high = pairs.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if pairs[mid].old <= time { low = mid } else { high = mid }
        }
        let before = pairs[low], after = pairs[high]
        let span = after.old - before.old
        guard span > 0 else { return before.new }
        return before.new + (time - before.old) / span * (after.new - before.new)
    }
}
