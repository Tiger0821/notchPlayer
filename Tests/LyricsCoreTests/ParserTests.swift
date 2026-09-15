import Testing
@testable import LyricsCore

// All lyric text below is made up for testing.

@Test func parsesStandardLRCWithEstimatedWords() throws {
    let lrc = """
    [ar:Test Artist]
    [ti:Test Song]
    [00:01.00]paper boats on a quiet river
    [00:05.50]夜空裡的小燈
    [00:09.00]
    """
    let lyrics = try #require(LRCParser.parse(lrc, source: "test"))
    #expect(lyrics.timing == .line)
    #expect(lyrics.lines.count == 3)
    #expect(lyrics.lines[0].text == "paper boats on a quiet river")
    #expect(lyrics.lines[0].words.count == 6)
    #expect(lyrics.lines[0].end <= 5.5)
    #expect(lyrics.lines[1].words.count == 6)
    #expect(lyrics.lines[2].isBlank)
}

@Test func parsesEnhancedLRCWordTags() throws {
    let lrc = "[00:10.00]<00:10.00>Walking <00:10.50>on <00:11.00>clouds<00:12.00>"
    let lyrics = try #require(LRCParser.parse(lrc, source: "test"))
    #expect(lyrics.timing == .word)
    let words = lyrics.lines[0].words
    #expect(words.map(\.text) == ["Walking ", "on ", "clouds"])
    #expect(words[1].start == 10.5 && words[1].end == 11.0)
    #expect(words[2].end == 12.0)
}

@Test func handlesRepeatedTimestampsAndOffset() throws {
    let lrc = "[offset:500]\n[00:02.00][00:20.00]echo line"
    let lyrics = try #require(LRCParser.parse(lrc, source: "test"))
    #expect(lyrics.lines.count == 2)
    #expect(abs(lyrics.lines[0].start - 1.5) < 0.001)
    #expect(abs(lyrics.lines[1].start - 19.5) < 0.001)
}

@Test func dropsCreditLines() throws {
    let lrc = "[00:00.00] 作词 : 某人\n[00:01.00] Composer: Someone\n[00:03.00]真正的第一句"
    let lyrics = try #require(LRCParser.parse(lrc, source: "test"))
    #expect(lyrics.lines.count == 1)
    #expect(lyrics.lines[0].text == "真正的第一句")
}

@Test func parsesYRC() throws {
    let yrc = """
    {"t":0,"c":[{"tx":"credits"}]}
    [1000,2000](1000,500,0)Hel(1500,500,0)lo (2000,1000,0)there (ok)
    """
    let lyrics = try #require(YRCParser.parse(yrc, source: "test"))
    #expect(lyrics.timing == .word)
    #expect(lyrics.lines.count == 1)
    #expect(lyrics.lines[0].text == "Hello there (ok)")
    #expect(lyrics.lines[0].words[2].start == 2.0)
    #expect(lyrics.lines[0].end == 3.0)
}

@Test func tokenizesMixedScripts() {
    #expect(WordTiming.tokenize("Hello, world").map(\.text) == ["Hello, ", "world"])
    #expect(WordTiming.tokenize("你好 world!").map(\.text) == ["你", "好 ", "world!"])
    #expect(WordTiming.tokenize("...").map(\.text) == ["..."])
}

@Test func lineIndexLookup() throws {
    let lyrics = try #require(LRCParser.parse("[00:01.00]a\n[00:03.00]b\n[00:06.00]c", source: "test"))
    #expect(lyrics.lineIndex(at: 0.5) == nil)
    #expect(lyrics.lineIndex(at: 3.0) == 1)
    #expect(lyrics.lineIndex(at: 100) == 2)
}

@Test func normalizesForMatching() {
    #expect(TextNormalize.key("Some Song (Remastered 2011)") == TextNormalize.key("some song"))
    #expect(TextNormalize.toSimplified("陳奕迅") == "陈奕迅")
    #expect(TextNormalize.looselyMatches("陳奕迅", "陈奕迅"))
    #expect(TextNormalize.primaryArtist("Artist A & Artist B") == "Artist A")
    #expect(TextNormalize.cleanTitle("Tune - Live Version") == "Tune")
}
