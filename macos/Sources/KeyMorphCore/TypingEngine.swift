public enum BoundaryKind {
    case space
    case enter
    case tab
}

/// Something the platform layer must do, in order.
public enum EngineAction {
    /// Press Backspace this many times.
    case erase(Int)
    /// Type text as Unicode (layout independent).
    case type(String)
    /// Re-send the word boundary key that was swallowed (Space, Return or Tab).
    case replayBoundary
    /// Switch the focused application to this layout.
    case switchLayout(any KeyboardLayout)
    /// Turn Caps Lock off.
    case capsLockOff
    /// The user reverted a correction: never correct this word again.
    case learnException(String)
}

/// `swallow`: the key that triggered the result must not reach the application; the actions replace it.
public struct EngineResult {
    public let swallow: Bool
    public let actions: [EngineAction]

    public init(swallow: Bool, actions: [EngineAction]) {
        self.swallow = swallow
        self.actions = actions
    }

    public static var passThrough: EngineResult { EngineResult(swallow: false, actions: []) }

    public static var swallowOnly: EngineResult { EngineResult(swallow: true, actions: []) }
}

public final class EngineOptions {
    public var autoSwitch = true
    public var fixCapsLock = true
    public var correctPreviousShortWord = true

    public init() {}
}

/// Platform-independent state machine: tracks the word being typed, decides on corrections and
/// produces the edit actions. Port of windows/IbaKeyMorph.Core/TypingEngine.cs.
public final class TypingEngine {
    private final class Word {
        var keys: [KeyStroke] = []
        var layout: any KeyboardLayout
        var userChosen = false
        var corrected = false

        init(layout: any KeyboardLayout) {
            self.layout = layout
        }

        var display: String { layout.render(keys) }
    }

    private struct Correction {
        let removed: String
        let inserted: String
        let from: any KeyboardLayout
        let originalKeys: [KeyStroke]
        let learnWord: String
    }

    private let decider: LayoutDecider
    private let options: EngineOptions
    private var current: Word?
    private var last: Word?
    private var lastTrailingSpaces = -1
    private var lastCorrection: Correction?

    public init(decider: LayoutDecider, options: EngineOptions) {
        self.decider = decider
        self.options = options
    }

    /// Text of the word being typed, for diagnostics and tests.
    public var currentWord: String { current?.display ?? "" }

    public func reset() {
        current = nil
        last = nil
        lastTrailingSpaces = -1
        lastCorrection = nil
    }

    public func onCharacterKey(_ key: KeyStroke, layout: any KeyboardLayout) {
        lastCorrection = nil
        if let word = current, word.layout.id != layout.id {
            // The layout changed in the middle of a word: what is on screen is no longer known.
            reset()
        }

        let word = current ?? Word(layout: layout)
        word.keys.append(key)
        current = word
    }

    public func onBackspace() {
        lastCorrection = nil
        if let word = current {
            word.keys.removeLast()
            if word.keys.isEmpty {
                current = nil
            }

            return
        }

        if let previous = last, lastTrailingSpaces > 0 {
            lastTrailingSpaces -= 1
            if lastTrailingSpaces == 0 {
                current = previous
                last = nil
                lastTrailingSpaces = -1
            }

            return
        }

        reset()
    }

    public func onBoundary(_ kind: BoundaryKind, layouts: [any KeyboardLayout]) -> EngineResult {
        lastCorrection = nil
        guard let word = current else {
            if kind == .space, last != nil, lastTrailingSpaces >= 0 {
                lastTrailingSpaces += 1
            } else {
                last = nil
                lastTrailingSpaces = -1
            }

            return .passThrough
        }

        current = nil
        let previous = lastTrailingSpaces == 1 ? last : nil
        let result = correct(word, previous: previous, kind: kind, layouts: layouts)

        last = kind == .space ? word : nil
        lastTrailingSpaces = kind == .space ? 1 : -1
        return result
    }

    /// Hotkey: undo the last automatic correction, or convert the current/last word to the next layout.
    public func convertLastWord(layouts: [any KeyboardLayout]) -> EngineResult {
        if let correction = lastCorrection, let word = last, lastTrailingSpaces >= 1 {
            lastCorrection = nil
            let spaces = String(repeating: " ", count: lastTrailingSpaces)
            word.keys = correction.originalKeys
            word.layout = correction.from
            word.userChosen = true
            word.corrected = false

            var actions: [EngineAction] = [
                .erase(correction.inserted.count + lastTrailingSpaces),
                .type(correction.removed + spaces),
                .switchLayout(correction.from),
            ]
            if !correction.learnWord.isEmpty {
                actions.append(.learnException(correction.learnWord))
            }

            return EngineResult(swallow: true, actions: actions)
        }

        if let word = current, !word.keys.isEmpty {
            return convert(word, trailingSpaces: 0, layouts: layouts)
        }

        if let word = last, lastTrailingSpaces >= 1 {
            return convert(word, trailingSpaces: lastTrailingSpaces, layouts: layouts)
        }

        return .swallowOnly
    }

    private func convert(_ word: Word, trailingSpaces: Int, layouts: [any KeyboardLayout]) -> EngineResult {
        guard let target = pickManualTarget(word, layouts: layouts) else {
            return .swallowOnly
        }

        let spaces = String(repeating: " ", count: trailingSpaces)
        let before = word.display
        word.layout = target
        word.userChosen = true
        word.corrected = false

        return EngineResult(swallow: true, actions: [
            .erase(before.count + trailingSpaces),
            .type(word.display + spaces),
            .switchLayout(target),
        ])
    }

    private func correct(
        _ word: Word,
        previous: Word?,
        kind: BoundaryKind,
        layouts: [any KeyboardLayout]
    ) -> EngineResult {
        let original = word.display
        let target = options.autoSwitch && !word.userChosen ? pickAutomaticTarget(word, layouts: layouts) : nil
        let fixCase = options.fixCapsLock && CaseFix.shouldFix(keys: word.keys, display: original)
        if target == nil && !fixCase {
            return .passThrough
        }

        let originalKeys = word.keys
        let from = word.layout
        if let target = target {
            word.layout = target
            word.corrected = true
        }

        if fixCase {
            word.keys = word.keys.map { KeyStroke(code: $0.code, shift: $0.shift, caps: !$0.caps) }
        }

        var removed = original
        var inserted = word.display

        if let target = target, let previous = previous, shouldCorrectPrevious(previous, from: from, target: target) {
            let previousBefore = previous.display
            previous.layout = target
            previous.corrected = true
            removed = previousBefore + " " + removed
            inserted = previous.display + " " + inserted
        }

        var actions: [EngineAction] = [
            .erase(removed.count),
            .type(inserted),
            .replayBoundary,
        ]
        if let target = target {
            actions.append(.switchLayout(target))
        }

        if fixCase {
            actions.append(.capsLockOff)
        }

        if target != nil, kind == .space, let fromLanguage = from.language {
            let learn = removed == original ? LayoutDecider.exceptionKey(original, fromLanguage) : ""
            lastCorrection = Correction(
                removed: removed, inserted: inserted, from: from, originalKeys: originalKeys, learnWord: learn)
        }

        return EngineResult(swallow: true, actions: actions)
    }

    private func shouldCorrectPrevious(_ previous: Word, from: any KeyboardLayout, target: any KeyboardLayout) -> Bool {
        guard options.correctPreviousShortWord, !previous.userChosen, !previous.corrected,
              previous.layout.id == from.id,
              let fromLanguage = from.language, let targetLanguage = target.language else {
            return false
        }

        return decider.shouldSwitchPrevious(
            typed: previous.display,
            typedLanguage: fromLanguage,
            alternative: target.render(previous.keys),
            alternativeLanguage: targetLanguage)
    }

    private func pickAutomaticTarget(_ word: Word, layouts: [any KeyboardLayout]) -> (any KeyboardLayout)? {
        guard let typedLanguage = word.layout.language else {
            return nil
        }

        let typed = word.display
        var best: (any KeyboardLayout)?
        var bestConfidence = -Double.infinity
        for layout in layouts {
            guard let language = layout.language, language.code != typedLanguage.code else {
                continue
            }

            let alternative = layout.render(word.keys)
            let decision = decider.shouldSwitch(
                typed: typed, typedLanguage: typedLanguage,
                alternative: alternative, alternativeLanguage: language)
            if decision.accepted && decision.confidence > bestConfidence {
                best = layout
                bestConfidence = decision.confidence
            }
        }

        return best
    }

    private func pickManualTarget(_ word: Word, layouts: [any KeyboardLayout]) -> (any KeyboardLayout)? {
        let others = layouts.filter { $0.id != word.layout.id }
        if others.count <= 1 {
            return others.first
        }

        // Several candidates: prefer the most plausible rendering, falling back to list order.
        var best: (any KeyboardLayout)?
        var bestScore = -Double.infinity
        for layout in others {
            var score = -Double.infinity
            if let language = layout.language {
                let evaluation = LayoutDecider.evaluate(layout.render(word.keys), language)
                score = evaluation.inDictionary ? 0 : evaluation.score
            }

            if best == nil || score > bestScore {
                best = layout
                bestScore = score
            }
        }

        return best
    }
}
