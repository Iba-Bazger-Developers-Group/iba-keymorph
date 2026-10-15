import AppKit
import Carbon

// End-to-end check on a real macOS desktop: starts IBA KeyMorph, types into a text view with synthetic
// hardware key presses and verifies the corrected text and the selected input source.
// Usage: KeyMorphE2E "<path>/IBA KeyMorph.app/Contents/MacOS/IBAKeyMorph"
// Needs Accessibility access for the process that runs it (GitHub's macOS runners grant it).

setvbuf(stdout, nil, _IOLBF, 0)

@MainActor
final class Runner {
    /// US key positions; uppercase letters are typed with Shift.
    private static let keys: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z, " ": kVK_Space,
    ]

    private let app = NSApplication.shared
    private let source = CGEventSource(stateID: .hidSystemState)
    private var window: NSWindow!
    private var textView: NSTextView!

    func run(keymorphPath: String) -> Int32 {
        app.setActivationPolicy(.regular)
        app.finishLaunching()

        guard let english = Self.inputSource("com.apple.keylayout.US") ?? Self.inputSource("com.apple.keylayout.ABC"),
              let russian = Self.inputSource("com.apple.keylayout.Russian") else {
            print("FAIL: the US/ABC or Russian keyboard layout is not installed")
            return 1
        }

        TISEnableInputSource(english)
        TISEnableInputSource(russian)
        TISSelectInputSource(english)
        pump(0.5)
        print("Layouts: EN=\(Self.id(english)) RU=\(Self.id(russian)), current: \(Self.currentId()); " +
              "this process trusted for Accessibility: \(AXIsProcessTrusted())")

        let keymorph = Process()
        keymorph.executableURL = URL(fileURLWithPath: keymorphPath)
        do {
            try keymorph.run()
        } catch {
            print("FAIL: could not start IBA KeyMorph: \(error)")
            return 1
        }

        print("Started IBA KeyMorph (pid \(keymorph.processIdentifier)); waiting for it to tap the keyboard")
        pump(5)
        guard keymorph.isRunning else {
            print("FAIL: IBA KeyMorph exited with code \(keymorph.terminationStatus)")
            return 1
        }

        makeWindow()
        var failures = 0
        failures += check("Russian typed in the English layout", layout: english, keys: "ghbdtn ", expected: "привет ", expectedLayout: russian)
        failures += check("English typed in the Russian layout", layout: russian, keys: "hello ", expected: "hello ", expectedLayout: english)
        failures += check("Correct English stays", layout: english, keys: "hello world ", expected: "hello world ", expectedLayout: english)
        failures += check("Correct Russian stays", layout: russian, keys: "ghbdtn ", expected: "привет ", expectedLayout: russian)
        failures += checkUndo(english: english)

        if !keymorph.isRunning {
            print("FAIL: IBA KeyMorph crashed during the test (exit code \(keymorph.terminationStatus))")
            failures += 1
        }

        keymorph.terminate()
        print(failures == 0 ? "E2E: all checks passed" : "E2E: \(failures) check(s) failed")
        return failures == 0 ? 0 : 1
    }

    private func makeWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 200, y: 300, width: 700, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "KeyMorph E2E"
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as? NSTextView
        textView.font = .systemFont(ofSize: 18)
        // Keep macOS from changing the typed text on its own.
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        window.contentView = scroll
        bringToFront()
    }

    private func check(
        _ name: String, layout: TISInputSource, keys: String, expected: String, expectedLayout: TISInputSource
    ) -> Int {
        reset(layout)
        type(keys)
        let ok = waitFor(4) { self.textView.string == expected && Self.currentId() == Self.id(expectedLayout) }
        print("\(ok ? "PASS" : "FAIL") \(name): typed keys \"\(keys)\" → \"\(textView.string)\" (expected \"\(expected)\"), " +
              "layout \(Self.currentId()) (expected \(Self.id(expectedLayout)))")
        return ok ? 0 : 1
    }

    private func checkUndo(english: TISInputSource) -> Int {
        reset(english)
        type("ghbdtn ")
        guard waitFor(4, { self.textView.string == "привет " }) else {
            print("FAIL Double Shift undoes the correction: nothing was corrected first (\"\(textView.string)\")")
            return 1
        }

        pump(0.4)
        tapShift()
        pump(0.08)
        tapShift()
        let ok = waitFor(4) { self.textView.string == "ghbdtn " && Self.currentId() == Self.id(english) }
        print("\(ok ? "PASS" : "FAIL") Double Shift undoes the correction: \"\(textView.string)\" (expected \"ghbdtn \"), " +
              "layout \(Self.currentId())")
        return ok ? 0 : 1
    }

    private func reset(_ layout: TISInputSource) {
        bringToFront()
        textView.string = ""
        TISSelectInputSource(layout)
        pump(0.3)
    }

    private func bringToFront() {
        if app.isActive && window.isKeyWindow && window.firstResponder === textView {
            return
        }

        app.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        pump(0.5)
        print("Test window is key: \(window.isKeyWindow), app active: \(app.isActive)")
    }

    private func type(_ text: String) {
        for character in text {
            guard let code = Self.keys[Character(character.lowercased())] else {
                fatalError("No key for \(character)")
            }

            press(code, flags: character.isUppercase ? .maskShift : [])
            pump(0.04)
        }
    }

    private func press(_ code: Int, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else {
                continue
            }

            event.flags = flags
            event.post(tap: .cghidEventTap)
            pump(0.03)
        }
    }

    /// A left Shift press and release as the hardware reports it (modifier change events).
    private func tapShift() {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Shift), keyDown: down) else {
                continue
            }

            event.type = .flagsChanged
            event.flags = down ? CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x02) : []
            event.post(tap: .cghidEventTap)
            pump(0.03)
        }
    }

    private func waitFor(_ seconds: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() {
                return true
            }

            pump(0.05)
        }

        return condition()
    }

    /// Runs the event loop for a while so the window receives the posted keys.
    private func pump(_ seconds: Double) {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            while let event = app.nextEvent(
                matching: .any, until: Date().addingTimeInterval(0.01), inMode: .default, dequeue: true) {
                app.sendEvent(event)
            }
        } while Date() < deadline
    }

    private static func inputSource(_ id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        return list.first
    }

    private static func id(_ source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return "?"
        }

        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func currentId() -> String {
        id(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }
}

guard CommandLine.arguments.count == 2, FileManager.default.isExecutableFile(atPath: CommandLine.arguments[1]) else {
    print("Usage: KeyMorphE2E <path to IBAKeyMorph inside the app bundle>")
    exit(2)
}

let path = CommandLine.arguments[1]
exit(MainActor.assumeIsolated { Runner().run(keymorphPath: path) })
