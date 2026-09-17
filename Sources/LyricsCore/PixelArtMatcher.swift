import Foundation

/// Finds the words in a lyric line that get a pixel sprite.
///
/// English words match whole words only ("car" never matches "scar" or "cares") plus their regular plurals, and
/// Chinese matches characters in either script. Longer phrases win, so "break my heart" beats "heart" and 飛機
/// (plane) beats 飛 (fly). Each sprite shows at most once per line.
public struct PixelArtMatcher: Sendable {
    public struct Match: Equatable, Sendable {
        /// The sprite pops in right after this word, as the word starts being sung.
        public var wordIndex: Int
        public var spriteID: String

        public init(wordIndex: Int, spriteID: String) {
            self.wordIndex = wordIndex
            self.spriteID = spriteID
        }
    }

    /// Keeps busy lines readable.
    public static let maxPerLine = 3

    private enum Target: Sendable {
        case sprite(String)
        case ignore
    }

    private var targets: [String: Target] = [:]
    private var longestPhrase = 1

    /// When two sprites claim the same word, the earlier one wins. `ignored` phrases never show art.
    public init(sprites: [(id: String, words: [String])], ignored: [String] = BuiltInPixelArt.ignoredPhrases) {
        for phrase in ignored {
            register(phrase, as: .ignore)
        }
        for sprite in sprites {
            for word in sprite.words {
                register(word, as: .sprite(sprite.id))
            }
        }
    }

    public func matches(in words: [LyricWord]) -> [Match] {
        let tokens = Self.tokens(in: words)
        var matches: [Match] = []
        var shown = Set<String>()
        var index = 0

        search: while index < tokens.count, matches.count < Self.maxPerLine {
            for length in stride(from: min(longestPhrase, tokens.count - index), through: 1, by: -1) {
                let key = Self.key(tokens[index..<index + length].map(\.text))
                guard let target = targets[key] else { continue }
                if case .sprite(let id) = target, shown.insert(id).inserted {
                    matches.append(Match(wordIndex: tokens[index + length - 1].wordIndex, spriteID: id))
                }
                index += length
                continue search
            }
            index += 1
        }
        return matches
    }

    private mutating func register(_ phrase: String, as target: Target) {
        let tokens = Self.tokens(in: [LyricWord(text: phrase, start: 0, end: 0)]).map(\.text)
        guard let last = tokens.last else { return }

        var forms = [tokens]
        if last.first?.isCJK == false {
            forms += Self.pluralForms(of: last).map { Array(tokens.dropLast()) + [$0] }
        }
        for form in forms {
            let key = Self.key(form)
            if targets[key] == nil { targets[key] = target }
            longestPhrase = max(longestPhrase, form.count)
        }
    }

    // MARK: - Tokens

    struct Token: Equatable {
        var text: String
        /// The lyric word holding the token's last character.
        var wordIndex: Int
    }

    private static func key(_ tokens: [String]) -> String {
        tokens.joined(separator: "\u{1}")
    }

    /// Latin words, normalized, and single CJK characters in Simplified script. Words may span several lyric
    /// words, since word-timed lyrics sometimes split one word into syllables.
    static func tokens(in words: [LyricWord]) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        var bufferWord = 0

        func flush() {
            let text = normalizeLatin(buffer)
            if !text.isEmpty { tokens.append(Token(text: text, wordIndex: bufferWord)) }
            buffer = ""
        }

        for (index, word) in words.enumerated() {
            // Traditional and Simplified text meet in Simplified: that direction has no ambiguous characters.
            let text = word.text.contains(where: \.isCJK) ? TextNormalize.toSimplified(word.text) : word.text
            for character in text {
                if character.isCJK {
                    flush()
                    tokens.append(Token(text: String(character), wordIndex: index))
                } else if character.isLetter || character.isNumber || character == "'" || character == "’" {
                    buffer.append(character)
                    bufferWord = index
                } else {
                    flush()
                }
            }
        }
        flush()
        return tokens
    }

    /// Lowercases and drops accents; "lovin'" becomes "loving", "heart's" becomes "heart", "'cause" becomes "cause".
    static func normalizeLatin(_ word: String) -> String {
        var text = word.replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        if text.count > 3, text.hasSuffix("in'") { text = String(text.dropLast()) + "g" }
        if text.hasSuffix("'s") { text = String(text.dropLast(2)) }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }

    /// Regular English plurals only, so a trigger word can't swallow a different word: "car" → "cars", not "cares".
    static func pluralForms(of word: String) -> [String] {
        guard word.count > 1, word.last?.isLetter == true else { return [] }
        if ["s", "x", "z", "ch", "sh"].contains(where: word.hasSuffix) { return [word + "es"] }
        if word.hasSuffix("y"), let before = word.dropLast().last, !"aeiou".contains(before) {
            return [String(word.dropLast()) + "ies"]
        }
        return [word + "s"]
    }
}
