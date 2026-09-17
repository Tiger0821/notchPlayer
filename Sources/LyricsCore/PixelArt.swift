import Foundation

/// How a sprite moves once it has popped in beside its word.
public enum PixelMotion: String, Codable, CaseIterable, Sendable {
    /// Stays beside the word.
    case stay
    /// Hops a few times.
    case bounce
    /// Pulses like a heartbeat.
    case beat
    /// Glimmers.
    case twinkle
    /// Drives off toward the outer edge of the strip.
    case drive
    /// Takes off up and away.
    case fly
    /// Drifts upward and fades.
    case float
    /// Drops down and fades.
    case fall

    /// Whether the sprite leaves its place, after which the gap it opened in the line closes again.
    public var leaves: Bool {
        switch self {
        case .drive, .fly, .float, .fall: true
        case .stay, .bounce, .beat, .twinkle: false
        }
    }
}

public enum PixelSpriteError: Error, Equatable {
    case empty
    case tooLarge
    case tooManyFrames
    case unevenRows
    case frameSizesDiffer
    case unknownColor(Character)
}

/// A small, optionally animated pixel image that pops in beside the words that trigger it.
public struct PixelSprite: Identifiable, Hashable, Sendable {
    public static let maxSize = 16
    public static let maxFrames = 4
    public static let framesPerSecondRange: ClosedRange<Double> = 0.5...24

    public var id: String
    public var name: String
    public var width: Int
    public var height: Int
    /// Each frame holds `width × height` colors row by row, as 0xRRGGBBAA. Alpha 0 is transparent.
    public var frames: [[UInt32]]
    public var framesPerSecond: Double
    /// Words and short phrases, in English or Chinese, that show this sprite.
    public var words: [String]
    public var motion: PixelMotion

    public init(id: String, name: String, width: Int, height: Int, frames: [[UInt32]],
                framesPerSecond: Double = 4, words: [String], motion: PixelMotion) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.frames = frames
        self.framesPerSecond = min(max(framesPerSecond, Self.framesPerSecondRange.lowerBound), Self.framesPerSecondRange.upperBound)
        self.words = words
        self.motion = motion
    }

    /// Builds a sprite from text grids, one character per pixel: `.` is transparent, anything else a palette key.
    public init(id: String, name: String, rows: [[String]], palette: [Character: UInt32],
                framesPerSecond: Double = 4, words: [String], motion: PixelMotion) throws {
        guard let first = rows.first, let firstRow = first.first, !firstRow.isEmpty else { throw PixelSpriteError.empty }
        let width = firstRow.count
        let height = first.count
        guard width <= Self.maxSize, height <= Self.maxSize else { throw PixelSpriteError.tooLarge }
        guard rows.count <= Self.maxFrames else { throw PixelSpriteError.tooManyFrames }

        var frames: [[UInt32]] = []
        for frame in rows {
            guard frame.count == height else { throw PixelSpriteError.frameSizesDiffer }
            var pixels: [UInt32] = []
            pixels.reserveCapacity(width * height)
            for row in frame {
                guard row.count == width else { throw PixelSpriteError.unevenRows }
                for character in row {
                    if character == "." {
                        pixels.append(0)
                    } else if let color = palette[character] {
                        pixels.append(color)
                    } else {
                        throw PixelSpriteError.unknownColor(character)
                    }
                }
            }
            frames.append(pixels)
        }
        self.init(id: id, name: name, width: width, height: height, frames: frames,
                  framesPerSecond: framesPerSecond, words: words, motion: motion)
    }

    /// The frame showing `elapsed` seconds after the sprite appeared.
    public func frameIndex(at elapsed: TimeInterval) -> Int {
        guard frames.count > 1, elapsed > 0 else { return 0 }
        return Int(elapsed * framesPerSecond) % frames.count
    }

    public var isEmpty: Bool {
        frames.allSatisfy { frame in frame.allSatisfy { $0 & 0xFF == 0 } }
    }

    /// Crops the transparent rows and columns that every frame shares, so the sprite sits snugly beside its word.
    public func trimmed() -> PixelSprite {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for frame in frames {
            for y in 0..<height {
                for x in 0..<width where frame[y * width + x] & 0xFF != 0 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0, maxX - minX + 1 != width || maxY - minY + 1 != height else { return self }

        var copy = self
        copy.width = maxX - minX + 1
        copy.height = maxY - minY + 1
        copy.frames = frames.map { frame in
            (minY...maxY).flatMap { y in (minX...maxX).map { x in frame[y * width + x] } }
        }
        return copy
    }

    /// How bright a color is drawn in the white style: palette colors use hand-tuned levels, others follow luminance.
    public static func whiteLevel(for color: UInt32) -> Double {
        if let level = BuiltInPixelArt.whiteLevels[color | 0xFF] { return level }
        let red = Double((color >> 24) & 0xFF) / 255
        let green = Double((color >> 16) & 0xFF) / 255
        let blue = Double((color >> 8) & 0xFF) / 255
        return min(max(0.2 + 1.1 * (0.299 * red + 0.587 * green + 0.114 * blue), 0.2), 1)
    }
}

// MARK: - File format

/// Sprites are stored as a palette plus one text grid per frame, so exported files stay readable:
///
///     {"id": "heart", "name": "Heart", "motion": "beat", "fps": 4, "words": ["love", "愛"],
///      "palette": {"a": "#FF4D6D"}, "frames": [[".aa.aa.", "aaaaaaa", ".aaaaa.", "..aaa..", "...a..."]]}
extension PixelSprite: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, motion, fps, words, palette, frames
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var palette: [Character: UInt32] = [:]
        for (key, hex) in try container.decode([String: String].self, forKey: .palette) {
            guard key.count == 1, let character = key.first, character != ".", let color = Self.color(hex: hex) else {
                throw DecodingError.dataCorruptedError(forKey: .palette, in: container, debugDescription: "Bad palette entry “\(key)”")
            }
            palette[character] = color
        }
        do {
            try self.init(
                id: container.decode(String.self, forKey: .id),
                name: container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled",
                rows: container.decode([[String]].self, forKey: .frames),
                palette: palette,
                framesPerSecond: container.decodeIfPresent(Double.self, forKey: .fps) ?? 4,
                words: container.decodeIfPresent([String].self, forKey: .words) ?? [],
                motion: (try? container.decodeIfPresent(PixelMotion.self, forKey: .motion)) ?? .stay)
        } catch let error as PixelSpriteError {
            throw DecodingError.dataCorruptedError(forKey: .frames, in: container, debugDescription: "Invalid pixels: \(error)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var keys: [UInt32: Character] = [:]
        var palette: [String: String] = [:]
        let rows = frames.map { pixels in
            (0..<height).map { y in
                String((0..<width).map { x -> Character in
                    let color = pixels[y * width + x]
                    guard color & 0xFF != 0 else { return "." }
                    if let key = keys[color] { return key }
                    let key = Self.paletteKey(keys.count)
                    keys[color] = key
                    palette[String(key)] = Self.hex(color)
                    return key
                })
            }
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(motion, forKey: .motion)
        try container.encode(framesPerSecond, forKey: .fps)
        try container.encode(words, forKey: .words)
        try container.encode(palette, forKey: .palette)
        try container.encode(rows, forKey: .frames)
    }

    /// Readable single-character keys first; very colorful sprites continue into CJK ideographs, which never run out.
    private static let asciiKeys = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&()*+,-/:;<=>?@[]^_{|}~")

    static func paletteKey(_ index: Int) -> Character {
        guard index >= asciiKeys.count else { return asciiKeys[index] }
        return Character(Unicode.Scalar(0x4E00 + UInt32(index - asciiKeys.count))!)
    }

    /// `#RRGGBB` when opaque, `#RRGGBBAA` otherwise.
    public static func hex(_ color: UInt32) -> String {
        color & 0xFF == 0xFF ? String(format: "#%06X", color >> 8) : String(format: "#%08X", color)
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA`.
    public static func color(hex: String) -> UInt32? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt32(text, radix: 16) else { return nil }
        return text.count == 6 ? value << 8 | 0xFF : value
    }
}
