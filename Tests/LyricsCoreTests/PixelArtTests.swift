import Foundation
import Testing
@testable import LyricsCore

// All lyric text below is made up for testing.

private let matcher = PixelArtMatcher(sprites: BuiltInPixelArt.sprites.map { ($0.id, $0.words) })

private func words(_ text: String) -> [LyricWord] {
    WordTiming.estimate(text: text, start: 0, end: 4)
}

private func art(_ text: String) -> [String] {
    matcher.matches(in: words(text)).map(\.spriteID)
}

@Test func matchesWholeEnglishWordsAndPlurals() {
    #expect(art("Parked two cars by the river") == ["car"])
    #expect(art("The buses never came") == ["bus"])
    #expect(art("An old scar that nobody cares about") == [])
    #expect(art("Starting over, restarting again") == [])
    #expect(art("Butterflies at midnight") == ["butterfly"])
}

@Test func placesArtAfterTheLastWordOfAPhrase() throws {
    let line = words("you broke my heart again")
    let match = try #require(matcher.matches(in: line).first)
    #expect(match.spriteID == "broken_heart")
    #expect(line[match.wordIndex].text.hasPrefix("heart"))
    #expect(art("wishing on a shooting star") == ["star"])
}

@Test func matchesChineseInEitherScript() throws {
    #expect(art("坐飛機去看你") == ["plane"])
    #expect(art("坐飞机去看你") == ["plane"])
    #expect(art("我想飛") == ["bird"])
    #expect(art("我愛你") == ["heart"])
    #expect(art("小心一點") == [])
    #expect(art("今天很開心") == ["smile"])

    let line = words("窗外下著雨")
    let match = try #require(matcher.matches(in: line).first)
    #expect(line[match.wordIndex].text == "雨")
}

@Test func showsEachSpriteOncePerLineAndLimitsBusyLines() {
    #expect(art("love, love, love me tonight") == ["heart"])
    #expect(art("sun and moon and stars and rain and snow") == ["sun", "moon", "star"])
}

@Test func normalizesApostrophesAndCase() {
    #expect(art("Lovin’ every minute") == ["heart"])
    #expect(art("The HEART'S still beating") == ["heart"])
    #expect(art("Rain's comin' down") == ["rain"])
}

@Test func joinsSyllablesSplitAcrossWords() throws {
    let line = [LyricWord(text: "Rain", start: 0, end: 0.5), LyricWord(text: "bow ", start: 0.5, end: 1),
                LyricWord(text: "road", start: 1, end: 2)]
    #expect(matcher.matches(in: line) == [PixelArtMatcher.Match(wordIndex: 1, spriteID: "rainbow")])
}

@Test func earlierSpritesWinSharedWords() {
    let custom = PixelArtMatcher(sprites: [("mine", ["fly", "寶貝"]), ("bird", ["fly", "bird"])])
    #expect(custom.matches(in: words("I could fly")).map(\.spriteID) == ["mine"])
    #expect(custom.matches(in: words("my bird")).map(\.spriteID) == ["bird"])
    #expect(custom.matches(in: words("我的寶貝")).map(\.spriteID) == ["mine"])
}

@Test func builtInSpritesAreWellFormedAndOwnTheirWords() {
    let sprites = BuiltInPixelArt.sprites
    #expect(sprites.count == 50)
    #expect(Set(sprites.map(\.id)).count == sprites.count)

    for sprite in sprites {
        #expect((1...PixelSprite.maxSize).contains(sprite.width), "\(sprite.id)")
        #expect((1...PixelSprite.maxSize).contains(sprite.height), "\(sprite.id)")
        #expect((1...PixelSprite.maxFrames).contains(sprite.frames.count), "\(sprite.id)")
        #expect(sprite.frames.allSatisfy { $0.count == sprite.width * sprite.height }, "\(sprite.id)")
        #expect(sprite.trimmed() == sprite, "\(sprite.id) has a transparent border")
        #expect(!sprite.words.isEmpty, "\(sprite.id)")
        for word in sprite.words {
            // Each word, sung on its own, must show its own sprite rather than one that claimed it first.
            #expect(matcher.matches(in: [LyricWord(text: word, start: 0, end: 1)]).first?.spriteID == sprite.id,
                    "“\(word)” doesn't show \(sprite.id)")
        }
    }
}

@Test func spritesRoundTripThroughJSON() throws {
    let heart = try #require(BuiltInPixelArt.sprites.first { $0.id == "heart" })
    let decoded = try JSONDecoder().decode(PixelSprite.self, from: JSONEncoder().encode(heart))
    #expect(decoded == heart)

    // More colors than there are readable keys.
    let colorful = PixelSprite(id: "colorful", name: "Colorful", width: 16, height: 16,
                               frames: [(0..<256).map { UInt32($0) << 8 | 0xFF }, (0..<256).map { UInt32($0) << 16 | 0x80 }],
                               framesPerSecond: 8, words: ["rainbow road"], motion: .twinkle)
    #expect(try JSONDecoder().decode(PixelSprite.self, from: JSONEncoder().encode(colorful)) == colorful)
}

@Test func rejectsMalformedSprites() {
    let json = ##"{"id":"x","palette":{"a":"#FF0000"},"frames":[["aa","a"]]}"##
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(PixelSprite.self, from: Data(json.utf8)) }
    #expect(throws: PixelSpriteError.unknownColor("b")) {
        try PixelSprite(id: "x", name: "x", rows: [["ab"]], palette: ["a": 0xFF0000FF], words: [], motion: .stay)
    }
}

@Test func trimsTransparentBordersSharedByAllFrames() throws {
    let palette: [Character: UInt32] = ["a": 0xFF0000FF]
    let sprite = try PixelSprite(id: "x", name: "x", rows: [["....", ".a..", "...."], ["....", "..a.", "...."]],
                                 palette: palette, words: [], motion: .stay)
    let trimmed = sprite.trimmed()
    #expect(trimmed.width == 2 && trimmed.height == 1)
    #expect(trimmed.frames == [[0xFF0000FF, 0], [0, 0xFF0000FF]])
    #expect(PixelSprite.color(hex: "#3D8BFF") == 0x3D8BFFFF)
    #expect(PixelSprite.hex(0x3D8BFF80) == "#3D8BFF80")
}

// MARK: - Editor canvas

@Test func centersSpritesOnTheCanvasAndTrimsBack() throws {
    let heart = try #require(BuiltInPixelArt.sprites.first { $0.id == "heart" })
    let frames = PixelCanvas.frames(for: heart)
    #expect(frames.count == 1 && frames[0].count == 16 * 16)
    // 13 × 12 sits 1 pixel from the left and 2 from the top.
    #expect(frames[0][2 * 16 + 1 + 2] == heart.frames[0][2])
    let roundTrip = PixelSprite(id: heart.id, name: heart.name, width: 16, height: 16, frames: frames,
                                framesPerSecond: heart.framesPerSecond, words: heart.words, motion: heart.motion).trimmed()
    #expect(roundTrip == heart)
}

@Test func drawsUnbrokenLines() {
    let points = PixelCanvas.line(from: .init(x: 1, y: 14), to: .init(x: 12, y: 3))
    #expect(points.first == .init(x: 1, y: 14) && points.last == .init(x: 12, y: 3))
    #expect(zip(points, points.dropFirst()).allSatisfy { abs($0.x - $1.x) <= 1 && abs($0.y - $1.y) <= 1 })
    #expect(PixelCanvas.line(from: .init(x: 5, y: 5), to: .init(x: 5, y: 5)) == [.init(x: 5, y: 5)])
}

@Test func fillsOnlyTheEnclosedArea() {
    let red: UInt32 = 0xFF0000FF, blue: UInt32 = 0x0000FFFF
    var frame = PixelCanvas.blankFrame()
    // A 4 × 4 ring of red with its top-left corner at (2, 2).
    for i in 2...5 {
        for (x, y) in [(i, 2), (i, 5), (2, i), (5, i)] { frame[y * 16 + x] = red }
    }
    var inside = frame
    PixelCanvas.fill(&inside, at: .init(x: 3, y: 3), with: blue)
    #expect(inside.filter { $0 == blue }.count == 4)
    #expect(inside[0] == 0)

    var outside = frame
    PixelCanvas.fill(&outside, at: .init(x: 0, y: 0), with: blue)
    #expect(outside.filter { $0 == blue }.count == 256 - 12 - 4)
    #expect(PixelCanvas.flipped(PixelCanvas.flipped(frame)) == frame)
    #expect(PixelCanvas.flipped(frame)[2 * 16 + 13] == red)
}

// MARK: - Collection

private func customSprite(_ id: String, words: [String]) -> PixelSprite {
    PixelSprite(id: id, name: "Mine", width: 2, height: 1, frames: [[0x00FF00FF, 0x00FF00FF]], words: words, motion: .bounce)
}

@Test func collectionKeepsEditsCustomArtAndSwitches() throws {
    var collection = PixelArtCollection()
    var heart = try #require(collection.sprite(id: "heart"))
    heart.words.append("寶貝")
    collection.save(heart)
    collection.save(customSprite("custom-1", words: ["fly"]))
    collection.setEnabled(false, id: "moon")

    #expect(collection.isChanged("heart"))
    #expect(collection.sprites.count == 51 && collection.sprites.last?.id == "custom-1")
    #expect(collection.sprites.first { $0.id == "heart" }?.words.last == "寶貝")

    let matcher = collection.matcher()
    #expect(matcher.matches(in: words("我的寶貝")).map(\.spriteID) == ["heart"])
    // The user's own art wins words it shares with a built-in, and turned-off art never shows.
    #expect(matcher.matches(in: words("I could fly")).map(\.spriteID) == ["custom-1"])
    #expect(matcher.matches(in: words("under the moon")).isEmpty)

    // Saving a built-in exactly as it shipped is no longer an edit.
    collection.save(try #require(collection.original(id: "heart")))
    #expect(!collection.isChanged("heart"))

    collection.delete("heart")
    #expect(collection.sprite(id: "heart") != nil)
    collection.delete("custom-1")
    #expect(collection.sprite(id: "custom-1") == nil)

    let duplicate = collection.duplicate("star", as: "custom-2")
    let copy = try #require(duplicate)
    #expect(copy.name == "Star copy" && collection.sprite(id: "custom-2") == copy)
}

@Test func collectionSavesAndSkipsUnreadablePieces() throws {
    var collection = PixelArtCollection()
    var bus = try #require(collection.sprite(id: "bus"))
    bus.motion = .fly
    collection.save(bus)
    collection.save(customSprite("custom-1", words: ["tram"]))
    collection.setEnabled(false, id: "rain")

    let data = try collection.encoded()
    #expect(try PixelArtCollection(savedData: data) == collection)

    // One damaged piece doesn't take the rest of the file with it.
    var json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("#00FF00"))
    json = json.replacingOccurrences(of: "#00FF00", with: "green")
    let recovered = try PixelArtCollection(savedData: Data(json.utf8))
    #expect(recovered.custom.isEmpty)
    #expect(recovered.sprite(id: "bus")?.motion == .fly)
    #expect(!recovered.isEnabled("rain"))

    #expect(throws: (any Error).self) { try PixelArtCollection(savedData: Data("not json".utf8)) }
}

@Test func importingTwiceDoesNotDuplicate() throws {
    var source = PixelArtCollection()
    var car = try #require(source.sprite(id: "car"))
    car.words = ["ride"]
    source.save(car)
    source.save(customSprite("custom-9", words: ["tram"]))
    let exported = try PixelArtCollection.exportData(for: source.sprites)

    var target = PixelArtCollection()
    #expect(try target.importSprites(from: exported) == 51)
    #expect(try target.importSprites(from: exported) == 51)
    #expect(target.sprites.count == 51)
    #expect(target.sprite(id: "car")?.words == ["ride"])
    // Unedited built-ins in the file don't count as edits.
    #expect(!target.isChanged("heart"))

    let single = try JSONEncoder().encode(customSprite("custom-10", words: []))
    #expect(try target.importSprites(from: single) == 1)
    #expect(throws: PixelArtCollection.ImportError.self) { try target.importSprites(from: Data("{}".utf8)) }
}
