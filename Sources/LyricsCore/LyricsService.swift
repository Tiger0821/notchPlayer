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

    /// Picks the best lyrics available. Ranking: local word-timed > NetEase word-timed > local line-timed
    /// > LRCLIB line-timed > NetEase line-timed.
    public func lyrics(for query: TrackQuery, useNetEase: Bool, convertToTraditional: Bool, ignoreCache: Bool) async -> Lyrics? {
        let localLyrics = local.fetch(query)?.parse()

        var remoteLyrics: Lyrics?
        if localLyrics?.timing != .word {
            let cacheURL = cacheFile(for: query, useNetEase: useNetEase)
            if !ignoreCache, let cached = loadCache(cacheURL) {
                remoteLyrics = cached.raw?.parse()
            } else {
                async let lrclib = LRCLibProvider().fetch(query)
                async let netease = fetchNetEase(query, enabled: useNetEase)
                let candidates = await [netease, lrclib].compactMap { $0 }
                let best = candidates
                    .compactMap { raw in raw.parse().map { (raw, $0) } }
                    .max { Self.score($0.1) < Self.score($1.1) }
                saveCache(best?.0, to: cacheURL)
                remoteLyrics = best?.1
            }
        }

        guard var result = [localLyrics, remoteLyrics].compactMap({ $0 }).max(by: { Self.score($0) < Self.score($1) }) else {
            return nil
        }
        if convertToTraditional, !result.containsKana {
            result = result.mapText(TextNormalize.toTraditional)
        }
        return result
    }

    private func fetchNetEase(_ query: TrackQuery, enabled: Bool) async -> RawLyrics? {
        guard enabled else { return nil }
        return await NetEaseProvider().fetch(query)
    }

    static func score(_ lyrics: Lyrics) -> Int {
        let sourceBonus = switch lyrics.source {
        case "Local file": 2
        case "LRCLIB": 1
        default: 0
        }
        return lyrics.timing.rawValue * 10 + sourceBonus
    }

    // MARK: - Cache

    private struct CacheEntry: Codable {
        var raw: RawLyrics?
        var savedAt: Date
    }

    private func cacheFile(for query: TrackQuery, useNetEase: Bool) -> URL {
        let identity = "\(query.title)|\(query.artist)|\(Int(query.duration.rounded()))|netease=\(useNetEase)"
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
