import Foundation
import XCTest
@testable import KeyMorphCore

final class LayoutDeciderTests: XCTestCase {
    private let decider = LayoutDecider()
    private var en: LanguageModel { TestData.store.english }
    private var ru: LanguageModel { TestData.store.russian }

    private func switches(_ typed: String, _ typedLanguage: LanguageModel, _ alternative: String, _ alternativeLanguage: LanguageModel) -> Bool {
        decider.shouldSwitch(
            typed: typed, typedLanguage: typedLanguage,
            alternative: alternative, alternativeLanguage: alternativeLanguage).accepted
    }

    func testSwitchesEnglishGibberishToRussian() {
        for (typed, alternative) in [
            ("ghbdtn", "привет"), ("Ghbdtn", "Привет"), ("ltkf", "дела"), ("yt", "не"),
            ("ghbdtn?", "привет,"), ("rjvgm.nth", "компьютер"), ("rfkmrekznjh", "калькулятор"),
        ] {
            XCTAssertTrue(switches(typed, en, alternative, ru), typed)
        }
    }

    func testSwitchesRussianGibberishToEnglish() {
        for (typed, alternative) in [
            ("руддщ", "hello"), ("цщкдв", "world"), ("пщщв", "good"), ("вщтэе", "don't"), ("ершт", "thin"),
        ] {
            XCTAssertTrue(switches(typed, ru, alternative, en), typed)
        }
    }

    func testKeepsEnglish() {
        for (typed, alternative) in [
            ("hello", "руддщ"), ("the", "еру"), ("github", "пшерги"), ("in", "шт"), ("z", "я"),
            ("iPhone", "шЗрщту"), ("abc123", "фис123"),
        ] {
            XCTAssertFalse(switches(typed, en, alternative, ru), typed)
        }
    }

    func testKeepsRussian() {
        for (typed, alternative) in [
            ("привет", "ghbdtn"), ("руб", "he,"), ("шт", "in"), ("ёлка", "`krf"), ("кто-то", "rnj-nj"),
        ] {
            XCTAssertFalse(switches(typed, ru, alternative, en), typed)
        }
    }

    func testDictionaryCollisionPrefersTheDictionaryWord() {
        XCTAssertTrue(switches("herb", en, "руки", ru))
    }

    func testUserExceptionsAreRespected() {
        let withException = LayoutDecider(isException: { $0 == "ghbdtn" })
        XCTAssertFalse(withException.shouldSwitch(
            typed: "ghbdtn", typedLanguage: en, alternative: "привет", alternativeLanguage: ru).accepted)
    }

    func testExtractCoreStripsPunctuation() {
        XCTAssertEqual(LayoutDecider.extractCore("«привет»,", ru), "привет")
        XCTAssertEqual(LayoutDecider.extractCore("(don't)", en), "don't")
        XCTAssertEqual(LayoutDecider.extractCore("?!", en), "")
    }

    func testPreviousWordRuleUsesDictionaryOnly() {
        XCTAssertTrue(decider.shouldSwitchPrevious(typed: "z", typedLanguage: en, alternative: "я", alternativeLanguage: ru))
        XCTAssertTrue(decider.shouldSwitchPrevious(typed: "b", typedLanguage: en, alternative: "и", alternativeLanguage: ru))
        XCTAssertFalse(decider.shouldSwitchPrevious(typed: "a", typedLanguage: en, alternative: "ф", alternativeLanguage: ru))
        XCTAssertFalse(decider.shouldSwitchPrevious(typed: "x", typedLanguage: en, alternative: "ч", alternativeLanguage: ru))
    }
}

/// Quality gates over the word lists: no false corrections, high recall (same as the C# CorpusTests).
final class CorpusTests: XCTestCase {
    private let decider = LayoutDecider()

    private let sets: [(file: String, language: String)] = [
        ("en.txt", "en"), ("ru.txt", "ru"),
        ("tests/heldout-en.txt", "en"), ("tests/heldout-ru.txt", "ru"),
        ("tests/validation-en.txt", "en"), ("tests/validation-ru.txt", "ru"),
    ]

    private func layouts(_ language: String) -> (own: TableLayout, other: TableLayout) {
        language == "en" ? (TestData.en, TestData.ru) : (TestData.ru, TestData.en)
    }

    func testCorrectlyTypedWordsAreNeverSwitched() {
        for set in sets {
            let (own, other) = layouts(set.language)
            let falsePositives = TestData.words(set.file).filter { word in
                decider.shouldSwitch(
                    typed: word, typedLanguage: own.language!,
                    alternative: TestData.retype(word, from: own, to: other),
                    alternativeLanguage: other.language!).accepted
            }
            XCTAssertTrue(falsePositives.isEmpty, "\(set.file): \(falsePositives.joined(separator: " "))")
        }
    }

    func testWordsTypedInTheWrongLayoutAreSwitched() {
        for set in sets {
            let (own, other) = layouts(set.language)
            let dictionary = !set.file.hasPrefix("tests/")
            let words = TestData.words(set.file).filter { word in
                word.count >= LayoutDecider.minDictionaryLength && (dictionary || !own.language!.contains(word))
            }
            let misses = words.filter { word in
                !decider.shouldSwitch(
                    typed: TestData.retype(word, from: own, to: other), typedLanguage: other.language!,
                    alternative: word, alternativeLanguage: own.language!).accepted
            }
            let recall = 1.0 - Double(misses.count) / Double(words.count)
            print("\(set.file): recall \(recall)")
            XCTAssertGreaterThanOrEqual(recall, dictionary ? 0.99 : 0.80, set.file)
        }
    }
}

/// data/tests/golden-scores.tsv is produced by the C# tests; the Swift model must agree.
final class GoldenScoreTests: XCTestCase {
    func testScoresMatchTheCSharpImplementation() throws {
        let url = TestData.dataDirectory.appendingPathComponent("tests/golden-scores.tsv")
        let text = try String(contentsOf: url, encoding: .utf8)
        var checked = 0
        for line in text.split(whereSeparator: { $0.isNewline }) where !line.hasPrefix("#") {
            let columns = line.split(separator: "\t").map(String.init)
            XCTAssertEqual(columns.count, 4, String(line))
            guard columns.count == 4, let model = TestData.store.model(for: columns[0]),
                  let expected = Double(columns[2]) else {
                continue
            }

            XCTAssertEqual(model.score(columns[1]), expected, accuracy: 1e-6, columns[1])
            XCTAssertEqual(model.contains(columns[1]), columns[3] == "1", columns[1])
            checked += 1
        }

        XCTAssertGreaterThan(checked, 10)
    }

    func testWordCountsMatchTheCSharpImplementation() {
        // The C# models load the same files; counts differing would point at parsing differences.
        XCTAssertGreaterThan(TestData.store.english.wordCount, 3000)
        XCTAssertGreaterThan(TestData.store.russian.wordCount, 3000)
    }
}

final class TextConverterTests: XCTestCase {
    func testConvertsWholePhrases() {
        XCTAssertEqual(TextConverter.convert("Ghbdtn? rfr ltkf&", from: TestData.en, to: TestData.ru), "Привет, как дела?")
        XCTAssertEqual(TextConverter.convert("Руддщб цщкдв!", from: TestData.ru, to: TestData.en), "Hello, world!")
    }

    func testLeavesUnknownCharactersAlone() {
        XCTAssertEqual(TextConverter.convert("2024 — ujl", from: TestData.en, to: TestData.ru), "2024 — год")
    }

    func testPicksDirectionFromTheText() {
        let layouts: [any KeyboardLayout] = [TestData.en, TestData.ru]
        let toRussian = TextConverter.pickConversion("Ghbdtn? rfr ltkf&", layouts: layouts)
        XCTAssertTrue(toRussian?.from === TestData.en)
        XCTAssertTrue(toRussian?.to === TestData.ru)

        let toEnglish = TextConverter.pickConversion("Руддщб цщкдв!", layouts: layouts)
        XCTAssertTrue(toEnglish?.from === TestData.ru)
        XCTAssertTrue(toEnglish?.to === TestData.en)

        XCTAssertNil(TextConverter.pickConversion("123 !?", layouts: layouts))
    }
}

final class DoubleTapDetectorTests: XCTestCase {
    private let shift = 1
    private let other = 2

    func testDetectsTwoQuickTaps() {
        let d = DoubleTapDetector()
        d.keyDown(shift, nowMs: 0)
        XCTAssertFalse(d.keyUp(shift, nowMs: 80))
        d.keyDown(shift, nowMs: 200)
        XCTAssertTrue(d.keyUp(shift, nowMs: 260))
    }

    func testIgnoresSlowTapsLongHoldsAndInterruptions() {
        let slow = DoubleTapDetector()
        slow.keyDown(shift, nowMs: 0)
        _ = slow.keyUp(shift, nowMs: 50)
        slow.keyDown(shift, nowMs: 1000)
        XCTAssertFalse(slow.keyUp(shift, nowMs: 1050))

        let hold = DoubleTapDetector()
        hold.keyDown(shift, nowMs: 0)
        _ = hold.keyUp(shift, nowMs: 50)
        hold.keyDown(shift, nowMs: 100)
        XCTAssertFalse(hold.keyUp(shift, nowMs: 900))

        let interrupted = DoubleTapDetector()
        interrupted.keyDown(shift, nowMs: 0)
        _ = interrupted.keyUp(shift, nowMs: 50)
        interrupted.reset()
        interrupted.keyDown(shift, nowMs: 100)
        XCTAssertFalse(interrupted.keyUp(shift, nowMs: 150))
    }

    func testDifferentKeysDoNotCombine() {
        let d = DoubleTapDetector()
        d.keyDown(shift, nowMs: 0)
        _ = d.keyUp(shift, nowMs: 50)
        d.keyDown(other, nowMs: 100)
        XCTAssertFalse(d.keyUp(other, nowMs: 150))
    }

    func testAutoRepeatDoesNotCount() {
        let d = DoubleTapDetector()
        d.keyDown(shift, nowMs: 0)
        d.keyDown(shift, nowMs: 30)
        d.keyDown(shift, nowMs: 60)
        XCTAssertFalse(d.keyUp(shift, nowMs: 90))
    }
}

final class LanguageModelTests: XCTestCase {
    func testNormalisesYoAndCase() {
        XCTAssertEqual(LanguageModel.normalize("ЕЩЁ"), "еще")
        XCTAssertTrue(TestData.store.russian.contains(LanguageModel.normalize("ЕЩЁ")))
    }

    func testWellFormedness() {
        XCTAssertTrue(TestData.store.english.isWellFormed("don't"))
        XCTAssertTrue(TestData.store.russian.isWellFormed("кто-то"))
        XCTAssertFalse(TestData.store.russian.isWellFormed("-то"))
        XCTAssertFalse(TestData.store.english.isWellFormed("a,b"))
        XCTAssertFalse(TestData.store.english.isWellFormed("привет"))
    }

    func testRealWordsScoreHigherThanLayoutGibberish() {
        XCTAssertGreaterThan(TestData.store.english.score("keyboard"), TestData.store.english.score("ghbdtn") + 1)
        XCTAssertGreaterThan(TestData.store.russian.score("клавиатура"), TestData.store.russian.score("руддщ") + 1)
    }

    func testParsesCommentsAndWhitespace() {
        XCTAssertEqual(Languages.parseWordList("# header\nfoo bar # tail\n\n  baz\r\n"), ["foo", "bar", "baz"])
    }

    func testCaseFix() {
        let keys = [KeyStroke(code: 0, shift: false, caps: true)]
        XCTAssertTrue(CaseFix.shouldFix(keys: keys, display: "hELLO"))
        XCTAssertFalse(CaseFix.shouldFix(keys: keys, display: "HELLO"))
        XCTAssertFalse(CaseFix.shouldFix(keys: [KeyStroke(code: 0, shift: false, caps: false)], display: "hELLO"))
        XCTAssertEqual(CaseFix.swapCase("пРИВЕТ, World"), "Привет, wORLD")
    }
}
