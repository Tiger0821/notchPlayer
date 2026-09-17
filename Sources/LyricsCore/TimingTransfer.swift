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

    /// Rebuilds the lyrics on Music's lines: Apple decides where a line starts and ends, the fetched lyrics
    /// supply the words inside it and their per-word timing.
    ///
    /// Line for line, the two sources rarely agree — one puts "you and I are just like a couple of tots" on
    /// one line where the other breaks it in two, and a credit line exists on one side only. Matching whole
    /// lines against each other then finds almost nothing. Matching runs over the words instead, as one
    /// stream with the punctuation and the capitals taken out, so where Apple's line falls inside the fetched
    /// words is a plain search, and every one of its lines lands whatever either side did with the breaks.
    ///
    /// What you see is then Apple's: its line is what the strip shows, and its next line is what comes next.
    public static func resegment(_ lyrics: Lyrics, onto paneLines: [String], anchors: [LineAnchor]) -> RetimedLyrics? {
        let words = lyrics.lines.flatMap(\.words)
        guard !words.isEmpty, !paneLines.isEmpty else { return nil }

        // One normalised string of the whole song, and where each word sits in it.
        var stream = ""
        var spans: [Range<Int>] = []
        for word in words {
            let key = TextNormalize.key(word.text)
            spans.append(stream.count..<(stream.count + key.count))
            stream += key
        }
        let characters = Array(stream)

        var built: [LyricLine] = []
        var searchFrom = 0
        var matched = 0
        for text in paneLines {
            let key = Array(TextNormalize.key(text))
            guard !key.isEmpty, let at = index(of: key, in: characters, from: searchFrom) else {
                // An instrumental break, or a line the fetched lyrics simply don't have. It still belongs on
                // screen — Apple showing it is the point — so keep it with its own estimated words.
                built.append(LyricLine(start: 0, end: 0, words: WordTiming.estimate(text: text, start: 0, end: 0)))
                continue
            }
            let range = at..<(at + key.count)
            let inside = words.indices.filter { spans[$0].overlaps(range) || (spans[$0].isEmpty && range.contains(spans[$0].lowerBound)) }
            searchFrom = range.upperBound
            matched += 1
            guard let first = inside.first, let last = inside.last else {
                built.append(LyricLine(start: 0, end: 0, words: WordTiming.estimate(text: text, start: 0, end: 0)))
                continue
            }
            built.append(LyricLine(start: words[first].start, end: words[last].end,
                                   words: Array(words[first...last])))
        }
        guard matched >= minimumMatches else { return nil }

        // Lines that matched nothing have no times of their own; put them between their neighbours so the
        // order still holds, and let the anchors correct whichever of them Music reaches.
        fill(&built)
        let onAppleLines = Lyrics(lines: built, timing: lyrics.timing, source: lyrics.source)
        guard let moved = apply(anchors, to: onAppleLines) else {
            return RetimedLyrics(lyrics: onAppleLines, matchedLines: 0)
        }
        return moved
    }

    /// Gives a line that matched nothing a place in time: between the lines around it.
    private static func fill(_ lines: inout [LyricLine]) {
        for i in lines.indices where lines[i].end == 0 && lines[i].start == 0 {
            let before = lines[..<i].last { $0.end > 0 }
            let after = lines[(i + 1)...].first { $0.end > 0 }
            let start = before?.end ?? max(0, (after?.start ?? 0) - 2)
            let end = after?.start ?? start + 2
            lines[i] = LyricLine(start: start, end: max(start, end),
                                 words: WordTiming.estimate(text: lines[i].text, start: start, end: max(start, end)))
        }
    }

    /// Where `needle` starts in `haystack` at or after `from`.
    private static func index(of needle: [Character], in haystack: [Character], from: Int) -> Int? {
        let last = haystack.count - needle.count
        guard !needle.isEmpty, last >= 0, from <= last else { return nil }
        for start in from...last where Array(haystack[start..<(start + needle.count)]) == needle {
            return start
        }
        return nil
    }

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
