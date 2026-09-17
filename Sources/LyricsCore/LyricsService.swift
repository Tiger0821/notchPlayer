import CryptoKit
import Foundation

public actor LyricsService {
    private let local: LocalProvider
    private let cacheDirectory: URL

    public init(localFolder: URL, cacheDirectory: URL) {
        self.local = LocalProvider(folder: localFolder)
        self.cacheDirectory = cacheDirectory
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Tries each source in the order given and takes the first that has lyrics for the track, so the ranking
    /// is the user's rather than ours.
    public func lyrics(
        for query: TrackQuery, order: [LyricsSourceKind], preferWordTiming: Bool,
        convertToTraditional: Bool, ignoreCache: Bool
    ) async -> Lyrics? {
        let cacheURL = cacheFile(for: query, order: order, preferWordTiming: preferWordTiming)
        if !ignoreCache, let cached = loadCache(cacheURL) {
            return finish(cached.raw?.parse(), convertToTraditional: convertToTraditional)
        }
        // Each source is asked once; whether a word-by-word version beats a higher-ranked line-timed one is
        // the user's call, so run the list twice — word timing first, then anything.
        var fetched: [(source: LyricsSourceKind, raw: RawLyrics, lyrics: Lyrics)] = []
        for source in order {
            guard let raw = await fetch(source, query), let parsed = raw.parse() else { continue }
            fetched.append((source, raw, parsed))
            if !preferWordTiming { break }
            if parsed.timing == .word { break }
        }
        let best = preferWordTiming
            ? (fetched.first { $0.lyrics.timing == .word } ?? fetched.first)
            : fetched.first
        saveCache(best?.raw, to: cacheURL)
        return finish(best?.lyrics, convertToTraditional: convertToTraditional)
    }

    private func fetch(_ source: LyricsSourceKind, _ query: TrackQuery) async -> RawLyrics? {
        switch source {
        case .localFiles: local.fetch(query)
        case .netease: await NetEaseProvider().fetch(query)
        case .lrclib: await LRCLibProvider().fetch(query)
        }
    }

    private func finish(_ lyrics: Lyrics?, convertToTraditional: Bool) -> Lyrics? {
        guard let lyrics else { return nil }
        guard convertToTraditional, !lyrics.containsKana else { return lyrics }
        return lyrics.mapText(TextNormalize.toTraditional)
    }

    // MARK: - Cache

    private struct CacheEntry: Codable {
        var raw: RawLyrics?
        var savedAt: Date
    }

    private func cacheFile(for query: TrackQuery, order: [LyricsSourceKind], preferWordTiming: Bool) -> URL {
        let identity = "\(query.title)|\(query.artist)|\(Int(query.duration.rounded()))|order=\(order.map(\.rawValue).joined(separator: ","))|word=\(preferWordTiming)"
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(digest).json")
    }

    private func loadCache(_ url: URL) -> CacheEntry? {
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(CacheEntry.self, from: data) else { return nil }
        // "Not found" may just mean we were offline, so retry those after 30 minutes.
        if entry.raw == nil, Date().timeIntervalSince(entry.savedAt) > 30 * 60 { return nil }
        return entry
    }

    private func saveCache(_ raw: RawLyrics?, to url: URL) {
        guard let data = try? JSONEncoder().encode(CacheEntry(raw: raw, savedAt: Date())) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
