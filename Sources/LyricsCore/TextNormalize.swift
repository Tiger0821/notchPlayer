import Foundation

public enum TextNormalize {
    public static func toSimplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }

    public static func toTraditional(_ text: String) -> String {
        guard text.contains(where: \.isCJK) else { return text }
        return text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    /// Drops decorations such as "(feat. …)", "[Live]", "【…】" and "- Remastered 2011".
    public static func cleanTitle(_ title: String) -> String {
        var cleaned = title.replacingOccurrences(
            of: #"\s*[\(\[（【][^\)\]）】]*[\)\]）】]"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(
            of: #"\s+-\s+.*(remaster|live|version|edit|mix|single|mono|stereo).*$"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? title : cleaned
    }

    public static func primaryArtist(_ artist: String) -> String {
        var result = artist
        for separator in [" & ", ", ", " feat. ", " feat ", " ft. ", " x ", " with ", "/", "、", "＆", ";"] {
            if let range = result.range(of: separator, options: .caseInsensitive) {
                result = String(result[..<range.lowerBound])
            }
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? artist : trimmed
    }

    /// Comparison key that ignores case, Traditional/Simplified script, width, accents, punctuation and spacing.
    public static func key(_ text: String) -> String {
        let folded = toSimplified(cleanTitle(text))
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    public static func looselyMatches(_ a: String, _ b: String) -> Bool {
        let ka = key(a), kb = key(b)
        guard !ka.isEmpty, !kb.isEmpty else { return false }
        return ka == kb || ka.contains(kb) || kb.contains(ka)
    }
}
