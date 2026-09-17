import Foundation
import Testing
@testable import LyricsCore

// All lyric text below is made up for testing.

/// One word per line, so a line's only word carries the line's own times.
private func lyrics(_ lines: [(TimeInterval, String)], timing: LyricsTiming = .word) -> Lyrics {
    let built = lines.enumerated().map { index, line -> LyricLine in
        let end = index + 1 < lines.count ? lines[index + 1].0 : line.0 + 2
        return LyricLine(start: line.0, end: end,
                         words: [LyricWord(text: line.1, start: line.0, end: end)])
    }
    return Lyrics(lines: built, timing: timing, source: "test")
}

@Test func movesLinesOntoTheAnchoredTimes() throws {
    // Fetched lyrics that run a second early throughout.
    let fetched = lyrics([(1, "paper boats"), (3, "on a quiet river"), (5, "lanterns drifting")])
    let anchors = [LineAnchor(text: "paper boats", start: 2), LineAnchor(text: "lanterns drifting", start: 6)]

    let retimed = try #require(TimingTransfer.apply(anchors, to: fetched))
    #expect(retimed.matchedLines == 2)
    #expect(retimed.lyrics.lines[0].start == 2)
    #expect(retimed.lyrics.lines[2].start == 6)
    // The unmatched middle line is stretched into place between them.
    #expect(retimed.lyrics.lines[1].start == 4)
    // The words inside a line travel with it.
    #expect(retimed.lyrics.lines[0].words[0].start == 2)
    #expect(retimed.lyrics.lines[2].words[0].start == 6)
}

@Test func stretchesRatherThanShiftsWhenTheGapsDiffer() throws {
    let fetched = lyrics([(0, "one"), (2, "two"), (4, "three")])
    // Music sings the same three lines over twice as long.
    let anchors = [LineAnchor(text: "one", start: 0), LineAnchor(text: "three", start: 8)]

    let retimed = try #require(TimingTransfer.apply(anchors, to: fetched))
    #expect(retimed.lyrics.lines[1].start == 4)
    #expect(retimed.lyrics.lines[2].start == 8)
}

@Test func keepsTheWordsAndTheSourceOfWhatItRetimed() throws {
    let fetched = lyrics([(1, "paper boats"), (3, "lanterns drifting")])
    let anchors = [LineAnchor(text: "paper boats", start: 5), LineAnchor(text: "lanterns drifting", start: 9)]

    let retimed = try #require(TimingTransfer.apply(anchors, to: fetched))
    #expect(retimed.lyrics.source == "test")
    #expect(retimed.lyrics.timing == .word)
    #expect(retimed.lyrics.lines.map { $0.text } == ["paper boats", "lanterns drifting"])
}

@Test func matchesAcrossSimplifiedAndTraditional() throws {
    let fetched = lyrics([(1, "夜空裡的小燈"), (3, "河上的紙船")])
    let anchors = [LineAnchor(text: "夜空里的小灯", start: 4), LineAnchor(text: "河上的纸船", start: 6)]

    let retimed = try #require(TimingTransfer.apply(anchors, to: fetched))
    #expect(retimed.matchedLines == 2)
    #expect(retimed.lyrics.lines[0].start == 4)
    #expect(retimed.lyrics.lines[1].start == 6)
}

@Test func matchesARepeatedLineToTheNextTimeItIsSung() throws {
    let fetched = lyrics([(0, "chorus"), (2, "verse"), (4, "chorus")])
    // Both anchors say "chorus"; the second one belongs to the second chorus, not the first.
    let anchors = [LineAnchor(text: "chorus", start: 1), LineAnchor(text: "chorus", start: 9)]

    let retimed = try #require(TimingTransfer.apply(anchors, to: fetched))
    #expect(retimed.lyrics.lines[0].start == 1)
    #expect(retimed.lyrics.lines[2].start == 9)
    #expect(retimed.lyrics.lines[1].start == 5)
}

@Test func leavesLyricsAloneWhenTooLittleMatches() {
    let fetched = lyrics([(1, "paper boats"), (3, "lanterns drifting")])
    #expect(TimingTransfer.apply([], to: fetched) == nil)
    #expect(TimingTransfer.apply([LineAnchor(text: "something else", start: 4)], to: fetched) == nil)
    // One match is a shift with nothing to check it against, so it isn't enough either.
    #expect(TimingTransfer.apply([LineAnchor(text: "paper boats", start: 4)], to: fetched) == nil)
}

@Test func neverRunsTimeBackwards() throws {
    let fetched = lyrics([(0, "one"), (1, "two"), (2, "three"), (3, "four")])
    let anchors = [LineAnchor(text: "one", start: 10), LineAnchor(text: "four", start: 11)]

    let retimed = try #require(TimingTransfer.apply(anchors, to: fetched))
    let starts = retimed.lyrics.lines.map { $0.start }
    #expect(starts == starts.sorted())
    #expect(retimed.lyrics.lines.allSatisfy { $0.end >= $0.start })
}

@Test func ignoresAnAnchorThatWouldBendTheTimingBackwards() throws {
    let fetched = lyrics([(0, "one"), (2, "two"), (4, "three")])
    // The middle anchor arrived out of order; taking it would send the song backwards.
    let anchors = [
        LineAnchor(text: "one", start: 0),
        LineAnchor(text: "two", start: 9),
        LineAnchor(text: "three", start: 8),
    ]

    let retimed = try #require(TimingTransfer.apply(anchors, to: fetched))
    #expect(retimed.matchedLines == 2)
    let starts = retimed.lyrics.lines.map { $0.start }
    #expect(starts == starts.sorted())
}

// MARK: - Music's line breaks

/// Word-timed lyrics whose lines are broken differently from Music's.
private func worded(_ lines: [(TimeInterval, String)]) -> Lyrics {
    let built = lines.enumerated().map { index, line -> LyricLine in
        let end = index + 1 < lines.count ? lines[index + 1].0 : line.0 + 2
        let parts = line.1.split(separator: " ").map(String.init)
        let step = (end - line.0) / Double(max(parts.count, 1))
        let words = parts.enumerated().map { i, word in
            LyricWord(text: i == parts.count - 1 ? word : word + " ",
                      start: line.0 + Double(i) * step, end: line.0 + Double(i + 1) * step)
        }
        return LyricLine(start: line.0, end: end, words: words)
    }
    return Lyrics(lines: built, timing: .word, source: "test")
}

@Test func putsTheWordsOntoMusicsOwnLineBreaks() throws {
    // The fetched lyrics run it as two long lines; Music breaks the same words into three.
    let fetched = worded([(0, "you and I are just like a couple of tots"), (4, "running along the meadow")])
    let pane = ["You and I", "are just like a couple of tots", "Running along the meadow"]
    let anchors = [LineAnchor(text: "You and I", start: 10), LineAnchor(text: "Running along the meadow", start: 16)]

    let out = try #require(TimingTransfer.resegment(fetched, onto: pane, anchors: anchors))
    #expect(out.lyrics.lines.count == 3)
    #expect(out.lyrics.lines.map { $0.text.trimmingCharacters(in: .whitespaces) }
            == ["you and I", "are just like a couple of tots", "running along the meadow"])
    // Music said when its own lines start, and they do.
    #expect(out.lyrics.lines[0].start == 10)
    #expect(out.lyrics.lines[2].start == 16)
    // The words kept their own timing, in order.
    #expect(out.lyrics.lines[1].words.count == 7)
    #expect(out.lyrics.lines[1].words.map { $0.start } == out.lyrics.lines[1].words.map { $0.start }.sorted())
}

@Test func keepsALineMusicHasThatTheLyricsDont() throws {
    let fetched = worded([(0, "paper boats"), (4, "lanterns drifting")])
    let pane = ["Paper boats", "Instrumental Break", "Lanterns drifting"]
    let anchors = [LineAnchor(text: "Paper boats", start: 1), LineAnchor(text: "Lanterns drifting", start: 9)]

    let out = try #require(TimingTransfer.resegment(fetched, onto: pane, anchors: anchors))
    #expect(out.lyrics.lines.count == 3)
    #expect(out.lyrics.lines[1].text.contains("Instrumental"))
    // It sits between its neighbours rather than at zero.
    #expect(out.lyrics.lines[1].start >= out.lyrics.lines[0].start)
    #expect(out.lyrics.lines[1].start <= out.lyrics.lines[2].start)
    let starts = out.lyrics.lines.map { $0.start }
    #expect(starts == starts.sorted())
}

@Test func matchesARepeatedPaneLineToTheNextTimeItAppears() throws {
    let fetched = worded([(0, "chorus line"), (2, "a verse"), (4, "chorus line")])
    let pane = ["Chorus line", "A verse", "Chorus line"]
    let anchors = [LineAnchor(text: "Chorus line", start: 0), LineAnchor(text: "A verse", start: 3)]

    let out = try #require(TimingTransfer.resegment(fetched, onto: pane, anchors: anchors))
    #expect(out.lyrics.lines.count == 3)
    // The third pane line took the second occurrence's words, not the first's.
    #expect(out.lyrics.lines[2].start > out.lyrics.lines[1].start)
}

@Test func leavesThingsAloneWhenThePaneIsAnotherSong() {
    let fetched = worded([(0, "paper boats"), (4, "lanterns drifting")])
    #expect(TimingTransfer.resegment(fetched, onto: ["something else", "and another"], anchors: []) == nil)
    #expect(TimingTransfer.resegment(fetched, onto: [], anchors: []) == nil)
}
