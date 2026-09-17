import Foundation

public struct TrackQuery: Hashable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    /// Seconds; 0 when unknown (e.g. radio streams).
    public var duration: TimeInterval

    public init(title: String, artist: String, album: String, duration: TimeInterval) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

/// Where lyrics can be fetched from. Music's own lyrics view isn't one of these: the app reads it out of
/// Music's window rather than fetching it, and it has its own switch.
public enum LyricsSourceKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case localFiles
    case netease
    case lrclib

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .localFiles: "Local Files"
        case .netease: "NetEase Cloud Music"
        case .lrclib: "LRCLIB"
        }
    }

    /// What this source stamps on the lyrics it returns, which is how a `Lyrics` says where it came from.
    /// Not the title: these are short and fixed, and something that has to recognise a `Lyrics.source` can't
    /// use a name meant for reading.
    public var sourceName: String {
        switch self {
        case .localFiles: "Local file"
        case .netease: "NetEase"
        case .lrclib: "LRCLIB"
        }
    }
}

public enum LyricsFormat: String, Codable, Sendable {
    case lrc
    case yrc
}

/// Unparsed lyrics as fetched, which is what gets cached.
public struct RawLyrics: Codable, Equatable, Sendable {
    public var format: LyricsFormat
    public var text: String
    public var source: String

    public func parse() -> Lyrics? {
        switch format {
        case .lrc: LRCParser.parse(text, source: source)
        case .yrc: YRCParser.parse(text, source: source)
        }
    }
}

enum HTTP {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        return URLSession(configuration: config)
    }()

    static func json(_ url: URL, headers: [String: String]) async -> Any? {
        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func url(_ base: String, _ query: [(String, String)]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        return components.url!
    }
}

/// https://lrclib.net — open database of line-synced lyrics.
struct LRCLibProvider {
    private static let headers = ["User-Agent": "NotchLyrics/0.1 (personal macOS notch lyrics display)"]

    func fetch(_ query: TrackQuery) async -> RawLyrics? {
        if !query.album.isEmpty, query.duration > 0,
           let exact = await HTTP.json(HTTP.url("https://lrclib.net/api/get", [
               ("track_name", query.title),
               ("artist_name", query.artist),
               ("album_name", query.album),
               ("duration", String(Int(query.duration.rounded()))),
           ]), headers: Self.headers) as? [String: Any],
           let synced = exact["syncedLyrics"] as? String, !synced.isEmpty {
            return RawLyrics(format: .lrc, text: synced, source: LyricsSourceKind.lrclib.sourceName)
        }

        let searchURL = HTTP.url("https://lrclib.net/api/search", [
            ("track_name", TextNormalize.cleanTitle(query.title)),
            ("artist_name", TextNormalize.primaryArtist(query.artist)),
        ])
        guard let results = await HTTP.json(searchURL, headers: Self.headers) as? [[String: Any]] else { return nil }

        let best = results.compactMap { result -> (diff: Double, lyrics: String)? in
            guard let synced = result["syncedLyrics"] as? String, !synced.isEmpty,
                  TextNormalize.looselyMatches(result["trackName"] as? String ?? "", query.title) else { return nil }
            let duration = result["duration"] as? Double ?? 0
            let diff = query.duration > 0 && duration > 0 ? abs(duration - query.duration) : 0
            return diff <= 3 ? (diff, synced) : nil
        }.min { $0.diff < $1.diff }

        return best.map { RawLyrics(format: .lrc, text: $0.lyrics, source: LyricsSourceKind.lrclib.sourceName) }
    }
}

/// NetEase Cloud Music (unofficial API). Its YRC lyrics have real per-word timing, mostly for Chinese songs.
struct NetEaseProvider {
    private static let headers = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
        "Referer": "https://music.163.com",
    ]

    func fetch(_ query: TrackQuery) async -> RawLyrics? {
        var lineFallback: RawLyrics?
        for id in await candidates(for: query).prefix(3) {
            guard let json = await HTTP.json(
                URL(string: "https://music.163.com/api/song/lyric/v1?id=\(id)&lv=0&kv=0&tv=0&rv=0&yv=0&ytv=0&yrv=0")!,
                headers: Self.headers) as? [String: Any] else { continue }

            if let yrc = (json["yrc"] as? [String: Any])?["lyric"] as? String,
               YRCParser.parse(yrc, source: LyricsSourceKind.netease.sourceName) != nil {
                return RawLyrics(format: .yrc, text: yrc, source: LyricsSourceKind.netease.sourceName)
            }
            if lineFallback == nil,
               let lrc = (json["lrc"] as? [String: Any])?["lyric"] as? String,
               LRCParser.parse(lrc, source: LyricsSourceKind.netease.sourceName) != nil {
                lineFallback = RawLyrics(format: .lrc, text: lrc, source: LyricsSourceKind.netease.sourceName)
            }
        }
        return lineFallback
    }

    /// Song ids whose title and length match, best first. Covers and remixes with other lengths are rejected.
    private func candidates(for query: TrackQuery) async -> [Int] {
        let term = "\(TextNormalize.cleanTitle(query.title)) \(TextNormalize.primaryArtist(query.artist))"
        let url = HTTP.url("https://music.163.com/api/cloudsearch/pc", [
            ("s", TextNormalize.toSimplified(term)), ("type", "1"), ("limit", "10"),
        ])
        guard let json = await HTTP.json(url, headers: Self.headers) as? [String: Any],
              let songs = (json["result"] as? [String: Any])?["songs"] as? [[String: Any]] else { return [] }

        let scored = songs.compactMap { song -> (score: Double, id: Int)? in
            guard let id = song["id"] as? Int, let name = song["name"] as? String,
                  TextNormalize.looselyMatches(name, query.title) else { return nil }
            var durationDiff = 0.0
            if query.duration > 0, let ms = song["dt"] as? Double {
                durationDiff = abs(ms / 1000 - query.duration)
            }
            guard durationDiff <= 3 else { return nil }
            let artists = (song["ar"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let artistMatches = artists.contains {
                TextNormalize.looselyMatches($0, query.artist) || TextNormalize.looselyMatches($0, TextNormalize.primaryArtist(query.artist))
            }
            // Artist names may be localized differently (e.g. "Eason Chan" vs 陳奕迅); accept only a near-exact length then.
            guard artistMatches || durationDiff <= 1 else { return nil }
            return ((artistMatches ? 0 : 5) + durationDiff, id)
        }
        return scored.sorted { $0.score < $1.score }.map(\.id)
    }
}

/// `.lrc` files named "Artist - Title.lrc" or "Title.lrc" in a user folder (subfolders included).
struct LocalProvider {
    let folder: URL

    func fetch(_ query: TrackQuery) -> RawLyrics? {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }

        let fullKey = TextNormalize.key("\(query.artist) \(query.title)")
        let primaryKey = TextNormalize.key("\(TextNormalize.primaryArtist(query.artist)) \(query.title)")
        let titleKey = TextNormalize.key(query.title)
        var titleOnlyMatch: URL?

        for case let url as URL in enumerator where url.pathExtension.lowercased() == "lrc" {
            let name = TextNormalize.key(url.deletingPathExtension().lastPathComponent)
            if name == fullKey || name == primaryKey {
                return read(url)
            } else if name == titleKey, titleOnlyMatch == nil {
                titleOnlyMatch = url
            }
        }
        return titleOnlyMatch.flatMap(read)
    }

    private func read(_ url: URL) -> RawLyrics? {
        var encoding = String.Encoding.utf8
        guard let text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, usedEncoding: &encoding)) else { return nil }
        return RawLyrics(format: .lrc, text: text, source: LyricsSourceKind.localFiles.sourceName)
    }
}
