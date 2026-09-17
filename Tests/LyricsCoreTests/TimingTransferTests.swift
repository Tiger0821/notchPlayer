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
