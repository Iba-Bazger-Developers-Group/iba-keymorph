import Foundation
import XCTest
@testable import KeyMorphCore

enum TestData {
    /// Repository root, derived from this file's location: macos/Tests/KeyMorphCoreTests/TestSupport.swift.
    static let repositoryRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let dataDirectory = repositoryRoot.appendingPathComponent("data")

    // swiftlint:disable:next force_try
    static let store: LanguageStore = try! LanguageStore(directory: dataDirectory)

    static let en = BuiltInLayouts.english(store.english)

    static let ru = BuiltInLayouts.russian(store.russian)

    static func words(_ relativePath: String) -> [String] {
        let url = dataDirectory.appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Cannot read \(url.path)")
            return []
        }

        var seen = Set<String>()
        return Languages.parseWordList(text)
            .map { LanguageModel.normalize($0) }
            .filter { seen.insert($0).inserted }
    }

    /// Re-types a word as the same keys pressed in another layout.
    static func retype(_ word: String, from: TableLayout, to: TableLayout) -> String {
        var keys: [KeyStroke] = []
        for c in word {
            guard let key = from.find(c) else {
                XCTFail("No key for '\(c)'")
                return ""
            }

            keys.append(key)
        }

        return to.render(keys)
    }
}

/// A fake text field plus keyboard: the user presses the keys of the text they intend to write,
/// the active layout decides what appears, and engine actions are applied like the real apps do.
final class Simulator {
    private final class LearnedWords {
        var words = Set<String>()
    }

    private let learnedWords: LearnedWords
    let layouts: [any KeyboardLayout]
    let engine: TypingEngine
    var active: TableLayout
    var caps = false
    var text = ""
    var results: [EngineResult] = []

    init(_ active: TableLayout, options: EngineOptions = EngineOptions()) {
        let learned = LearnedWords()
        self.learnedWords = learned
        self.layouts = [TestData.en, TestData.ru]
        self.active = active
        self.engine = TypingEngine(
            decider: LayoutDecider(isException: { learned.words.contains($0) }),
            options: options)
    }

    var learned: Set<String> { learnedWords.words }

    /// Presses the keys that produce `input` in `intended` ("\u{8}" is Backspace).
    @discardableResult
    func type(_ input: String, _ intended: TableLayout) -> Simulator {
        for c in input {
            switch c {
            case " ":
                boundary(.space, c)
            case "\n":
                boundary(.enter, c)
            case "\t":
                boundary(.tab, c)
            case "\u{8}":
                engine.onBackspace()
                text.removeLast()
            default:
                // With Caps Lock on, the user still presses the keys of the intended text.
                guard let key = intended.find(c, caps: caps) else {
                    XCTFail("No key for '\(c)' in \(intended.shortName)")
                    return self
                }

                engine.onCharacterKey(key, layout: active)
                text += active.render(key)
            }
        }

        return self
    }

    @discardableResult
    func hotkey() -> Simulator {
        apply(engine.convertLastWord(layouts: layouts), boundary: nil)
        return self
    }

    private func boundary(_ kind: BoundaryKind, _ c: Character) {
        let result = engine.onBoundary(kind, layouts: layouts)
        if !result.swallow {
            text.append(c)
        }

        apply(result, boundary: c)
    }

    private func apply(_ result: EngineResult, boundary: Character?) {
        results.append(result)
        for action in result.actions {
            switch action {
            case .erase(let count):
                text.removeLast(count)
            case .type(let typed):
                text += typed
            case .replayBoundary:
                if let boundary = boundary {
                    text.append(boundary)
                } else {
                    XCTFail("Nothing to replay")
                }
            case .switchLayout(let layout):
                if let table = layout as? TableLayout {
                    active = table
                }
            case .capsLockOff:
                caps = false
            case .learnException(let word):
                learnedWords.words.insert(word)
            }
        }
    }
}
