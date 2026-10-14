/// Detects words typed with Caps Lock left on by accident: "hELLO", "пРИВЕТ".
public enum CaseFix {
    public static let minLetters = 3

    public static func shouldFix(keys: [KeyStroke], display: String) -> Bool {
        if keys.isEmpty || keys.contains(where: { !$0.caps }) {
            return false
        }

        let letters = display.filter { $0.isLetter }
        guard letters.count >= minLetters, let first = letters.first, first.isLowercase else {
            return false
        }

        return letters.dropFirst().allSatisfy { $0.isUppercase }
    }

    public static func swapCase(_ text: String) -> String {
        String(text.map { $0.isLetter ? toggledCase($0) : $0 })
    }
}

/// Recognises two quick taps of the same modifier (e.g. Shift) with no other key in between.
public final class DoubleTapDetector {
    private let maxHoldMs: Int
    private let maxGapMs: Int
    private var key: Int?
    private var isDown = false
    private var downAt = 0
    private var lastUpAt = 0
    private var taps = 0

    public init(maxHoldMs: Int = 250, maxGapMs: Int = 350) {
        self.maxHoldMs = maxHoldMs
        self.maxGapMs = maxGapMs
    }

    public func keyDown(_ key: Int, nowMs: Int) {
        if isDown && self.key == key {
            return // auto-repeat
        }

        if self.key != key || nowMs - lastUpAt > maxGapMs {
            taps = 0
        }

        self.key = key
        isDown = true
        downAt = nowMs
    }

    /// Returns true when this release completes a double tap.
    public func keyUp(_ key: Int, nowMs: Int) -> Bool {
        if !isDown || self.key != key {
            reset()
            return false
        }

        isDown = false
        if nowMs - downAt > maxHoldMs {
            taps = 0
            return false
        }

        taps += 1
        lastUpAt = nowMs
        if taps < 2 {
            return false
        }

        taps = 0
        return true
    }

    /// Any other key or mouse button cancels a pending double tap.
    public func reset() {
        key = nil
        isDown = false
        taps = 0
    }
}

/// Re-types arbitrary text as if the same keys had been pressed in another layout.
public enum TextConverter {
    public static func convert(_ text: String, from: any KeyboardLayout, to: any KeyboardLayout) -> String {
        let map = buildMap(from: from, to: to)
        return text.map { map[$0] ?? String($0) }.joined()
    }

    public static func buildMap(from: any KeyboardLayout, to: any KeyboardLayout) -> [Character: String] {
        var map: [Character: String] = [:]
        for shift in [false, true] {
            for code in from.printableKeyCodes {
                let key = KeyStroke(code: code, shift: shift, caps: false)
                let source = from.render(key)
                let target = to.render(key)
                if source.count == 1, let c = source.first, !target.isEmpty, map[c] == nil {
                    map[c] = target
                }
            }
        }

        return map
    }

    /// Picks the conversion for selected text: the source layout is the one whose language owns most
    /// of the letters, the target is the best-scoring other layout.
    public static func pickConversion(
        _ text: String,
        layouts: [any KeyboardLayout]
    ) -> (from: any KeyboardLayout, to: any KeyboardLayout)? {
        var from: (any KeyboardLayout)?
        var bestLetters = 0
        for layout in layouts {
            guard let language = layout.language else { continue }
            let letters = text.filter { language.isLetter($0) }.count
            if letters > bestLetters {
                from = layout
                bestLetters = letters
            }
        }

        guard let source = from, let sourceLanguage = source.language else {
            return nil
        }

        var to: (any KeyboardLayout)?
        var bestScore = -Double.infinity
        for layout in layouts {
            if layout.id == source.id || layout.language?.code == sourceLanguage.code {
                continue
            }

            let converted = convert(text, from: source, to: layout)
            let score = layout.language.map { averageScore(converted, $0) } ?? -Double.greatestFiniteMagnitude
            if to == nil || score > bestScore {
                to = layout
                bestScore = score
            }
        }

        guard let target = to else {
            return nil
        }

        return (from: source, to: target)
    }

    private static func averageScore(_ text: String, _ language: LanguageModel) -> Double {
        let evaluations = text.split(whereSeparator: { $0.isWhitespace })
            .map { LayoutDecider.evaluate(String($0), language) }
            .filter { $0.wellFormed }
        if evaluations.isEmpty {
            return -Double.greatestFiniteMagnitude
        }

        let total = evaluations.reduce(0.0) { $0 + ($1.inDictionary ? 0 : $1.score) }
        return total / Double(evaluations.count)
    }
}
