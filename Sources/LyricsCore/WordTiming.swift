import Foundation

/// Estimates per-word timing for lyrics that only have line timestamps.
public enum WordTiming {
    struct Token: Equatable {
        var text: String
        var weight: Double
    }

    /// Splits a line into highlightable units: one per CJK character, one per Latin word.
    /// Whitespace and punctuation stick to the preceding unit so the tokens rejoin to the original line.
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var buffer = ""
        var letters = 0
        var isCJK = false
        var hasContent = false
        var inWord = false

        func flush() {
            guard hasContent else { return }
            // Roughly one sung syllable per CJK character or per ~3 Latin letters.
            tokens.append(Token(text: buffer, weight: isCJK ? 1 : max(1, Double(letters) / 3)))
            buffer = ""
            letters = 0
            isCJK = false
            hasContent = false
        }

        for character in text {
            if character.isCJK {
                flush()
                buffer.append(character)
                isCJK = true
                hasContent = true
                inWord = false
            } else if character.isLetter || character.isNumber || character == "'" || character == "’" {
                if !inWord { flush() }
                buffer.append(character)
                letters += 1
                hasContent = true
                inWord = true
            } else {
                buffer.append(character)
                inWord = false
            }
        }

        if hasContent {
            flush()
        } else if !buffer.isEmpty {
            if tokens.isEmpty {
                tokens.append(Token(text: buffer, weight: 1))
            } else {
                tokens[tokens.count - 1].text += buffer
            }
        }
        return tokens
    }

    public static func estimate(text: String, start: TimeInterval, end: TimeInterval) -> [LyricWord] {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return [] }
        let totalWeight = tokens.reduce(0) { $0 + $1.weight }
        let span = max(end - start, 0)
        var cursor = start
        return tokens.map { token in
            let length = span * token.weight / totalWeight
            defer { cursor += length }
            return LyricWord(text: token.text, start: cursor, end: cursor + length)
        }
    }

    /// Rough upper bound on how long a line is actually sung, so the fill doesn't crawl through instrumental gaps.
    public static func estimatedDuration(for text: String) -> TimeInterval {
        let weight = tokenize(text).reduce(0) { $0 + $1.weight }
        return max(1.5, weight * 0.5 + 0.6)
    }
}

extension Character {
    var isCJK: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF, // Hiragana, Katakana
             0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F, // Han
             0xAC00...0xD7AF: // Hangul syllables
            return true
        default:
            return false
        }
    }
}
