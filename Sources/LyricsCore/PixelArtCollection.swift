import Foundation

/// The built-in art plus the user's own pieces, their edits to built-ins, and the pieces they turned off.
public struct PixelArtCollection: Equatable, Sendable {
    public let builtIns: [PixelSprite]
    public private(set) var custom: [PixelSprite] = []
    /// Edited built-ins, by id.
    public private(set) var changed: [String: PixelSprite] = [:]
    public private(set) var disabled: Set<String> = []

    public init(builtIns: [PixelSprite] = BuiltInPixelArt.sprites) {
        self.builtIns = builtIns
    }

    /// Every piece with the user's edits applied: the built-ins in their usual order, then the user's own.
    public var sprites: [PixelSprite] {
        builtIns.map { changed[$0.id] ?? $0 } + custom
    }

    public func sprite(id: String) -> PixelSprite? {
        changed[id] ?? builtIns.first { $0.id == id } ?? custom.first { $0.id == id }
    }

    public func original(id: String) -> PixelSprite? {
        builtIns.first { $0.id == id }
    }

    public func isBuiltIn(_ id: String) -> Bool {
        original(id: id) != nil
    }

    public func isChanged(_ id: String) -> Bool {
        changed[id] != nil
    }

    public func isEnabled(_ id: String) -> Bool {
        !disabled.contains(id)
    }

    /// Matches the pieces that are turned on. The user's own art claims shared words first: newest custom pieces,
    /// then edited built-ins, then the rest.
    public func matcher() -> PixelArtMatcher {
        let preferred = Array(custom.reversed()) + builtIns.compactMap { changed[$0.id] }
        let ordered = preferred + builtIns.filter { changed[$0.id] == nil }
        return PixelArtMatcher(sprites: ordered.filter { isEnabled($0.id) }.map { ($0.id, $0.words) })
    }

    // MARK: - Changes

    /// Adds a new piece, or replaces the piece with the same id. A built-in saved unchanged stops counting as edited.
    public mutating func save(_ sprite: PixelSprite) {
        if let original = original(id: sprite.id) {
            changed[sprite.id] = sprite == original ? nil : sprite
        } else if let index = custom.firstIndex(where: { $0.id == sprite.id }) {
            custom[index] = sprite
        } else {
            custom.append(sprite)
        }
    }

    public mutating func reset(_ id: String) {
        changed[id] = nil
    }

    /// Removes one of the user's own pieces. Built-ins can only be turned off.
    public mutating func delete(_ id: String) {
        guard !isBuiltIn(id) else { return }
        custom.removeAll { $0.id == id }
        disabled.remove(id)
    }

    public mutating func setEnabled(_ enabled: Bool, id: String) {
        if enabled {
            disabled.remove(id)
        } else if sprite(id: id) != nil {
            disabled.insert(id)
        }
    }

    public mutating func duplicate(_ id: String, as newID: String) -> PixelSprite? {
        guard var copy = sprite(id: id) else { return nil }
        copy.id = newID
        copy.name = "\(copy.name) copy"
        custom.append(copy)
        return copy
    }

    // MARK: - Import and export

    public enum ImportError: LocalizedError {
        case notPixelArt

        public var errorDescription: String? { "This file isn't NotchLyrics pixel art." }
    }

    private struct ExportFile: Encodable {
        var app = "NotchLyrics"
        var version = 1
        var sprites: [PixelSprite]
    }

    private struct ImportFile: Decodable {
        var sprites: [LossySprite]
    }

    public static func exportData(for sprites: [PixelSprite]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(ExportFile(sprites: sprites))
    }

    /// Adds the pieces from an exported file (or a single exported piece) and returns how many. Pieces already in the
    /// collection are replaced rather than added twice, so importing a backup again changes nothing.
    public mutating func importSprites(from data: Data) throws -> Int {
        let decoder = JSONDecoder()
        var incoming: [PixelSprite]
        if let file = try? decoder.decode(ImportFile.self, from: data) {
            incoming = file.sprites.compactMap(\.sprite)
        } else if let sprite = try? decoder.decode(PixelSprite.self, from: data) {
            incoming = [sprite]
        } else {
            throw ImportError.notPixelArt
        }
        incoming = incoming.filter { !$0.isEmpty }.map { $0.trimmed() }
        guard !incoming.isEmpty else { throw ImportError.notPixelArt }
        incoming.forEach { save($0) }
        return incoming.count
    }

    // MARK: - Save file

    private struct Stored: Codable {
        var version = 1
        var custom: [PixelSprite]
        var changed: [PixelSprite]
        var disabled: [String]
    }

    private struct LossyStored: Decodable {
        var custom: [LossySprite]?
        var changed: [LossySprite]?
        var disabled: [String]?
    }

    /// Skips a piece that fails to decode instead of losing everything around it.
    private struct LossySprite: Decodable {
        var sprite: PixelSprite?

        init(from decoder: Decoder) throws {
            sprite = try? PixelSprite(from: decoder)
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let stored = Stored(custom: custom, changed: builtIns.compactMap { changed[$0.id] },
                            disabled: disabled.filter { sprite(id: $0) != nil }.sorted())
        return try encoder.encode(stored)
    }

    /// Reads a save file. Throws only when the file isn't a save file at all; unreadable pieces inside are skipped.
    public init(savedData data: Data, builtIns: [PixelSprite] = BuiltInPixelArt.sprites) throws {
        self.init(builtIns: builtIns)
        let stored = try JSONDecoder().decode(LossyStored.self, from: data)
        custom = (stored.custom ?? []).compactMap(\.sprite).filter { !isBuiltIn($0.id) }
        for sprite in (stored.changed ?? []).compactMap(\.sprite) where isBuiltIn(sprite.id) {
            changed[sprite.id] = sprite
        }
        disabled = Set(stored.disabled ?? [])
    }
}
