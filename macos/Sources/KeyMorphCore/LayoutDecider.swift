public struct WordEvaluation {
    public let text: String
    public let core: String
    public let normalized: String
    public let wellFormed: Bool
    public let inDictionary: Bool
    public let score: Double
}

func isDecimalDigit(_ c: Character) -> Bool {
    c.unicodeScalars.contains { $0.properties.generalCategory == .decimalNumber }
}

/// Decides whether a word typed in one layout was really meant for another one.
/// Port of windows/IbaKeyMorph.Core/LayoutDecider.cs — the rules and constants must match.
public final class LayoutDecider {
    /// Shortest word (letters) corrected when the alternative is a dictionary word.
    public static let minDictionaryLength = 2

    /// Shortest word corrected on trigram statistics alone.
    public static let minStatisticalLength = 3

    /// Required advantage of the alternative, in average log-probability per symbol.
    public static let scoreMargin = 1.0

    /// The typed word must score below this to be considered gibberish.
    public static let implausibleScore = -3.2

    /// When the typed text is not even word-shaped, the alternative must score at least this.
    public static let plausibleScore = -3.0

    private let isException: (String) -> Bool

    public init(isException: @escaping (String) -> Bool = { _ in false }) {
        self.isException = isException
    }

    public static func evaluate(_ text: String, _ language: LanguageModel) -> WordEvaluation {
        let core = extractCore(text, language)
        let normalized = LanguageModel.normalize(core)
        let wellFormed = language.isWellFormed(normalized)
        let inDictionary = wellFormed && language.contains(normalized)
        let score = wellFormed ? language.score(normalized) : -Double.infinity
        return WordEvaluation(
            text: text, core: core, normalized: normalized,
            wellFormed: wellFormed, inDictionary: inDictionary, score: score)
    }

    /// Strips leading and trailing characters that are not letters of the language.
    public static func extractCore(_ text: String, _ language: LanguageModel) -> String {
        let chars = Array(text)
        var start = 0
        while start < chars.count && !language.isLetter(chars[start]) {
            start += 1
        }

        var end = chars.count - 1
        while end >= start && !language.isLetter(chars[end]) {
            end -= 1
        }

        return start > end ? "" : String(chars[start...end])
    }

    /// Whether `typed` (shown in `typedLanguage`) should be replaced by `alternative` (the same keys
    /// in a layout of `alternativeLanguage`). `confidence` ranks competing alternatives.
    public func shouldSwitch(
        typed: String,
        typedLanguage: LanguageModel,
        alternative: String,
        alternativeLanguage: LanguageModel
    ) -> (accepted: Bool, confidence: Double) {
        if typed.contains(where: isDecimalDigit) || alternative.contains(where: isDecimalDigit) {
            return (false, 0)
        }

        let current = LayoutDecider.evaluate(typed, typedLanguage)
        let other = LayoutDecider.evaluate(alternative, alternativeLanguage)

        if !other.wellFormed || other.normalized.count < LayoutDecider.minDictionaryLength {
            return (false, 0)
        }

        if current.inDictionary || isUserException(typed, typedLanguage) {
            return (false, 0)
        }

        if other.inDictionary {
            return (true, 100 + Double(other.normalized.count))
        }

        if other.normalized.count < LayoutDecider.minStatisticalLength {
            return (false, 0)
        }

        if !current.wellFormed {
            return (other.score >= LayoutDecider.plausibleScore, other.score)
        }

        let margin = other.score - current.score
        return (margin >= LayoutDecider.scoreMargin && current.score <= LayoutDecider.implausibleScore, margin)
    }

    /// Lookback rule for a short word right before a corrected one ("z ns" → "я ты"): only dictionary
    /// evidence counts, but single letters are allowed.
    public func shouldSwitchPrevious(
        typed: String,
        typedLanguage: LanguageModel,
        alternative: String,
        alternativeLanguage: LanguageModel
    ) -> Bool {
        if typed.contains(where: isDecimalDigit) || alternative.contains(where: isDecimalDigit) {
            return false
        }

        let current = LayoutDecider.evaluate(typed, typedLanguage)
        let other = LayoutDecider.evaluate(alternative, alternativeLanguage)
        return other.inDictionary && !current.inDictionary && !isUserException(typed, typedLanguage)
    }

    /// Normalised key used for the user exception list.
    public static func exceptionKey(_ typed: String, _ language: LanguageModel) -> String {
        LanguageModel.normalize(extractCore(typed, language))
    }

    private func isUserException(_ typed: String, _ language: LanguageModel) -> Bool {
        let key = LayoutDecider.exceptionKey(typed, language)
        return !key.isEmpty && isException(key)
    }
}
