import Foundation

/// Word list plus an interpolated character trigram model for one language.
/// Port of windows/IbaKeyMorph.Core/LanguageModel.cs — keep both numerically identical
/// (checked against data/tests/golden-scores.tsv).
public final class LanguageModel {
    private static let lambda3 = 0.6
    private static let lambda2 = 0.3
    private static let lambda1 = 0.1
    private static let startMark: Character = "^"
    private static let endMark: Character = "$"

    public let code: String
    private let letters: Set<Character>
    private let connectors: Set<Character>
    private let vocabulary: Int
    private var words = Set<String>()
    private var trigrams = [String: Int]()
    private var trigramContexts = [String: Int]()
    private var bigrams = [String: Int]()
    private var bigramContexts = [Character: Int]()
    private var unigrams = [Character: Int]()
    private var total = 0

    public init(code: String, letters: String, connectors: String, words: [String]) {
        self.code = code
        self.letters = Set(letters)
        var allConnectors = Set(connectors)
        allConnectors.insert("-")
        self.connectors = allConnectors
        self.vocabulary = Set(letters).count + connectors.count + 1

        for raw in words {
            let word = LanguageModel.normalize(raw)
            if !isWellFormed(word) || self.words.contains(word) {
                continue
            }

            self.words.insert(word)
            for segment in word.split(separator: "-") {
                train(String(segment))
            }
        }
    }

    public var wordCount: Int { words.count }

    public static func normalize(_ text: String) -> String {
        String(text.lowercased().map { $0 == "ё" ? "е" : $0 })
    }

    public static func normalize(_ c: Character) -> Character {
        let lower = String(c).lowercased()
        guard lower.count == 1, let first = lower.first else { return c }
        return first == "ё" ? "е" : first
    }

    public func isLetter(_ c: Character) -> Bool {
        letters.contains(LanguageModel.normalize(c))
    }

    /// Letters only, with connectors (hyphen, apostrophe) allowed strictly inside.
    public func isWellFormed(_ normalized: String) -> Bool {
        let chars = Array(normalized)
        guard let first = chars.first, let last = chars.last,
              letters.contains(first), letters.contains(last) else {
            return false
        }

        for i in chars.indices {
            let c = chars[i]
            if letters.contains(c) {
                continue
            }

            if !connectors.contains(c) || !letters.contains(chars[i - 1]) {
                return false
            }
        }

        return true
    }

    public func contains(_ normalized: String) -> Bool {
        if words.contains(normalized) {
            return true
        }

        if !normalized.contains("-") {
            return false
        }

        let parts = normalized.split(separator: "-").map(String.init)
        return !parts.isEmpty && parts.allSatisfy { words.contains($0) }
    }

    /// Average natural-log probability per predicted symbol. Higher is more plausible.
    public func score(_ normalized: String) -> Double {
        var sum = 0.0
        var count = 0
        for segment in normalized.split(separator: "-") {
            let sequence = Array("^^" + String(segment) + "$")
            for i in 2..<sequence.count {
                sum += log(probability(sequence[i - 2], sequence[i - 1], sequence[i]))
                count += 1
            }
        }

        return count == 0 ? -Double.infinity : sum / Double(count)
    }

    private func probability(_ a: Character, _ b: Character, _ c: Character) -> Double {
        var p3 = 0.0
        if let contextCount = trigramContexts[String([a, b])] {
            p3 = Double(trigrams[String([a, b, c])] ?? 0) / Double(contextCount)
        }

        var p2 = 0.0
        if let bigramContextCount = bigramContexts[b] {
            p2 = Double(bigrams[String([b, c])] ?? 0) / Double(bigramContextCount)
        }

        let p1 = (Double(unigrams[c] ?? 0) + 1.0) / Double(total + vocabulary)
        return LanguageModel.lambda3 * p3 + LanguageModel.lambda2 * p2 + LanguageModel.lambda1 * p1
    }

    private func train(_ segment: String) {
        let sequence = Array("^^" + segment + "$")
        for i in 2..<sequence.count {
            let a = sequence[i - 2]
            let b = sequence[i - 1]
            let c = sequence[i]
            trigrams[String([a, b, c]), default: 0] += 1
            trigramContexts[String([a, b]), default: 0] += 1
            bigrams[String([b, c]), default: 0] += 1
            bigramContexts[b, default: 0] += 1
            unigrams[c, default: 0] += 1
            total += 1
        }
    }
}

public enum Languages {
    public static let englishLetters = "abcdefghijklmnopqrstuvwxyz"
    public static let russianLetters = "абвгдежзийклмнопрстуфхцчшщъыьэюя"

    /// Whitespace-separated words; everything after "#" on a line is a comment.
    public static func parseWordList(_ text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline }) {
            var line = rawLine
            if let hash = line.firstIndex(of: "#") {
                line = line[..<hash]
            }

            for word in line.split(whereSeparator: { $0.isWhitespace }) {
                result.append(String(word))
            }
        }

        return result
    }

    public static func english(words: [String]) -> LanguageModel {
        LanguageModel(code: "en", letters: englishLetters, connectors: "'", words: words)
    }

    public static func russian(words: [String]) -> LanguageModel {
        LanguageModel(code: "ru", letters: russianLetters, connectors: "", words: words)
    }
}

/// The supported language models, loaded from data/en.txt and data/ru.txt.
public final class LanguageStore {
    public let english: LanguageModel
    public let russian: LanguageModel

    public init(english: LanguageModel, russian: LanguageModel) {
        self.english = english
        self.russian = russian
    }

    /// Loads en.txt and ru.txt from a directory.
    public convenience init(directory: URL) throws {
        let en = try String(contentsOf: directory.appendingPathComponent("en.txt"), encoding: .utf8)
        let ru = try String(contentsOf: directory.appendingPathComponent("ru.txt"), encoding: .utf8)
        self.init(
            english: Languages.english(words: Languages.parseWordList(en)),
            russian: Languages.russian(words: Languages.parseWordList(ru)))
    }

    /// Two-letter ISO 639-1 code → model, or nil when the language is not supported.
    public func model(for code: String?) -> LanguageModel? {
        switch code?.lowercased() {
        case "en": return english
        case "ru": return russian
        default: return nil
        }
    }
}
