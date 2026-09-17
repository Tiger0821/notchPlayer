import Foundation
import LyricsCore

/// The pixel art collection the app shows and edits, saved to ~/Library/Application Support/NotchLyrics/pixel-art.json.
@MainActor
final class PixelArtLibrary: ObservableObject {
    @Published private(set) var collection: PixelArtCollection

    private var matcher: PixelArtMatcher
    private var lineCache: [String: [Int: PixelSprite]] = [:]
    private let fileURL: URL

    init(folder: URL) {
        let url = folder.appendingPathComponent("pixel-art.json")
        let loaded = Self.load(from: url)
        fileURL = url
        collection = loaded
        matcher = loaded.matcher()
    }

    static func newID() -> String {
        "custom-" + UUID().uuidString.lowercased()
    }

    var sprites: [PixelSprite] { collection.sprites }

    func sprite(id: String) -> PixelSprite? { collection.sprite(id: id) }
    func original(id: String) -> PixelSprite? { collection.original(id: id) }
    func contains(_ id: String) -> Bool { collection.sprite(id: id) != nil }
    func isBuiltIn(_ id: String) -> Bool { collection.isBuiltIn(id) }
    func isChanged(_ id: String) -> Bool { collection.isChanged(id) }
    func isEnabled(_ id: String) -> Bool { collection.isEnabled(id) }

    /// Art for a line, keyed by the index of the word each piece follows.
    func art(for line: LyricLine) -> [Int: PixelSprite] {
        let key = line.words.map(\.text).joined(separator: "\u{1}")
        if let cached = lineCache[key] { return cached }
        var result: [Int: PixelSprite] = [:]
        for match in matcher.matches(in: line.words) {
            result[match.wordIndex] = collection.sprite(id: match.spriteID)
        }
        if lineCache.count > 500 { lineCache.removeAll() }
        lineCache[key] = result
        return result
    }

    func save(_ sprite: PixelSprite) { change { $0.save(sprite) } }
    func reset(_ id: String) { change { $0.reset(id) } }
    func delete(_ id: String) { change { $0.delete(id) } }
    func setEnabled(_ enabled: Bool, id: String) { change { $0.setEnabled(enabled, id: id) } }

    func duplicate(_ id: String) -> PixelSprite? {
        var copy: PixelSprite?
        change { copy = $0.duplicate(id, as: Self.newID()) }
        return copy
    }

    func importSprites(from data: Data) throws -> Int {
        var updated = collection
        let count = try updated.importSprites(from: data)
        change { $0 = updated }
        return count
    }

    func exportData(for sprites: [PixelSprite]) throws -> Data {
        try PixelArtCollection.exportData(for: sprites)
    }

    private func change(_ update: (inout PixelArtCollection) -> Void) {
        update(&collection)
        matcher = collection.matcher()
        lineCache.removeAll()
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try collection.encoded().write(to: fileURL, options: .atomic)
        } catch {
            Log.pixelArt.error("couldn't save pixel art: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func load(from url: URL) -> PixelArtCollection {
        guard let data = try? Data(contentsOf: url) else { return PixelArtCollection() }
        do {
            return try PixelArtCollection(savedData: data)
        } catch {
            // Keep the unreadable file rather than overwriting it with the next change.
            let backup = url.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            Log.pixelArt.error("couldn't read \(url.path, privacy: .public), moved it aside: \(error.localizedDescription, privacy: .public)")
            return PixelArtCollection()
        }
    }
}
