import XCTest
@testable import KeyMorphCore

final class TypingEngineTests: XCTestCase {
    private var en: TableLayout { TestData.en }
    private var ru: TableLayout { TestData.ru }

    func testRussianTypedInEnglishLayoutIsCorrected() {
        let sim = Simulator(en).type("привет как дела ", ru)
        XCTAssertEqual(sim.text, "привет как дела ")
        XCTAssertTrue(sim.active === ru)
    }

    func testEnglishTypedInRussianLayoutIsCorrected() {
        let sim = Simulator(ru).type("hello world ", en)
        XCTAssertEqual(sim.text, "hello world ")
        XCTAssertTrue(sim.active === en)
    }

    func testCorrectTextIsLeftAlone() {
        let sim = Simulator(ru).type("привет как дела ", ru)
        XCTAssertEqual(sim.text, "привет как дела ")
        XCTAssertTrue(sim.results.allSatisfy { !$0.swallow })
    }

    func testPunctuationFollowsTheIntendedLayout() {
        XCTAssertEqual(Simulator(en).type("привет, как дела? ", ru).text, "привет, как дела? ")
    }

    func testCapitalisedWordsKeepTheirCase() {
        XCTAssertEqual(Simulator(en).type("Привет Мир ", ru).text, "Привет Мир ")
    }

    func testShortWordBeforeACorrectedWordIsCorrectedToo() {
        XCTAssertEqual(Simulator(en).type("я тебя ", ru).text, "я тебя ")
    }

    func testLookbackCanBeDisabled() {
        let options = EngineOptions()
        options.correctPreviousShortWord = false
        XCTAssertEqual(Simulator(en, options: options).type("я тебя ", ru).text, "z тебя ")
    }

    func testSingleLetterAloneIsNotCorrected() {
        XCTAssertEqual(Simulator(en).type("я ", ru).text, "z ")
    }

    func testEnterAndTabAreWordBoundaries() {
        XCTAssertEqual(Simulator(en).type("привет\nпока\t", ru).text, "привет\nпока\t")
    }

    func testWordsWithDigitsAreNotCorrected() {
        XCTAssertEqual(Simulator(en).type("ghbdtn2 ", en).text, "ghbdtn2 ")
    }

    func testAutoSwitchCanBeDisabled() {
        let options = EngineOptions()
        options.autoSwitch = false
        XCTAssertEqual(Simulator(en, options: options).type("привет ", ru).text, "ghbdtn ")
    }

    func testHotkeyUndoesTheLastCorrectionAndLearnsTheWord() {
        let sim = Simulator(en).type("ghbdtn ", en)
        XCTAssertEqual(sim.text, "привет ")

        sim.hotkey()
        XCTAssertEqual(sim.text, "ghbdtn ")
        XCTAssertTrue(sim.active === en)
        XCTAssertTrue(sim.learned.contains("ghbdtn"))

        sim.type("ghbdtn ", en)
        XCTAssertEqual(sim.text, "ghbdtn ghbdtn ")
    }

    func testHotkeyUndoWorksAfterExtraSpaces() {
        XCTAssertEqual(Simulator(en).type("ghbdtn  ", en).hotkey().text, "ghbdtn  ")
    }

    func testHotkeyConvertsTheWordBeingTyped() {
        let sim = Simulator(en).type("ghb", en).hotkey()
        XCTAssertEqual(sim.text, "при")
        XCTAssertTrue(sim.active === ru)

        sim.type("вет ", ru)
        XCTAssertEqual(sim.text, "привет ")
    }

    func testHotkeyConvertsTheLastWordAfterSpace() {
        let sim = Simulator(en).type("the ", en).hotkey()
        XCTAssertEqual(sim.text, "еру ")
        XCTAssertTrue(sim.active === ru)
    }

    func testHotkeyTogglesBackAndForth() {
        let sim = Simulator(en).type("the", en).hotkey().hotkey()
        XCTAssertEqual(sim.text, "the")
        XCTAssertTrue(sim.active === en)
    }

    func testManuallyConvertedWordIsNotAutoCorrected() {
        XCTAssertEqual(Simulator(ru).type("руддщ", ru).hotkey().hotkey().type(" ", ru).text, "руддщ ")
    }

    func testBackspaceEditsTheCurrentWord() {
        XCTAssertEqual(Simulator(en).type("ghbdtx\u{8}n ", en).text, "привет ")
    }

    func testBackspaceAfterSpaceResumesTheWord() {
        XCTAssertEqual(Simulator(ru).type("hel \u{8}lo ", en).text, "hello ")
    }

    func testAccidentalCapsLockIsFixed() {
        let sim = Simulator(en)
        sim.caps = true
        sim.type("Hello ", en)
        XCTAssertEqual(sim.text, "Hello ")
        XCTAssertFalse(sim.caps)
    }

    func testAccidentalCapsLockIsFixedTogetherWithLayout() {
        let sim = Simulator(en)
        sim.caps = true
        sim.type("Привет ", ru)
        XCTAssertEqual(sim.text, "Привет ")
        XCTAssertTrue(sim.active === ru)
        XCTAssertFalse(sim.caps)
    }

    func testDeliberateCapitalsAreKept() {
        let sim = Simulator(en)
        sim.caps = true
        sim.type("nasa ", en)
        XCTAssertEqual(sim.text, "NASA ")
        XCTAssertTrue(sim.caps)
    }

    func testLayoutChangeInTheMiddleOfAWordResetsTracking() {
        let engine = TypingEngine(decider: LayoutDecider(), options: EngineOptions())
        engine.onCharacterKey(en.find("g")!, layout: en)
        engine.onCharacterKey(en.find("h")!, layout: ru)
        XCTAssertEqual(engine.currentWord, "р")
    }

    func testBoundaryWithoutWordPassesThrough() {
        let engine = TypingEngine(decider: LayoutDecider(), options: EngineOptions())
        let layouts: [any KeyboardLayout] = [en, ru]
        let boundary = engine.onBoundary(.space, layouts: layouts)
        XCTAssertFalse(boundary.swallow)
        XCTAssertTrue(boundary.actions.isEmpty)

        let hotkey = engine.convertLastWord(layouts: layouts)
        XCTAssertTrue(hotkey.swallow)
        XCTAssertTrue(hotkey.actions.isEmpty)
    }
}
