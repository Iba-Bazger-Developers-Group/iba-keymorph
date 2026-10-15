import AppKit
import Carbon
import KeyMorphCore

/// Glue between the event tap, the platform-independent `TypingEngine` and macOS:
/// turns key events into engine calls and engine actions into synthetic input.
@MainActor
final class KeyMorphController: NSObject {
    private enum Tap {
        static let shift = 1
        static let option = 2
    }

    // Device-dependent modifier bits (NX_DEVICE*KEYMASK) to tell left and right keys apart.
    private static let leftShiftMask: UInt64 = 0x02
    private static let rightShiftMask: UInt64 = 0x04
    private static let leftOptionMask: UInt64 = 0x20
    private static let rightOptionMask: UInt64 = 0x40

    let settings: Settings
    let inputSources: InputSourceManager
    private let monitor = KeyboardMonitor()
    private let synthesizer = KeySynthesizer()
    private let engineOptions: EngineOptions
    private let engine: TypingEngine
    private let doubleTap = DoubleTapDetector()
    private var swallowedKeyUps = Set<Int64>()
    private var frontmostBundleId: String?
    private var excluded = false
    private var busy = false
    private var watchdog: Timer?
    private var lastWatchdogLog: TimeInterval?

    private static let diagnosticsFromEnvironment = ProcessInfo.processInfo.environment["IBA_KEYMORPH_DIAGNOSTICS"] == "1"
    private var diagnostics: Bool { settings.diagnosticLog || Self.diagnosticsFromEnvironment }

    /// Key presses the tap received and words corrected since launch (shown in the menu and settings).
    private(set) var keysSeen = 0
    private(set) var corrections = 0

    /// Called after KeyMorph switched the layout itself (to refresh the menu bar title).
    var onLayoutSwitched: (() -> Void)?

    /// Called when the event tap was lost and could not be recreated (usually: access was revoked).
    var onStopped: (() -> Void)?

    init(settings: Settings, languages: LanguageStore) {
        self.settings = settings
        self.inputSources = InputSourceManager(store: languages)
        let options = EngineOptions()
        self.engineOptions = options
        self.engine = TypingEngine(
            decider: LayoutDecider(isException: { settings.isException($0) }),
            options: options)
        super.init()
        applySettings()
        monitor.handler = { [unowned self] type, event, proxy in
            self.handle(type: type, event: event, proxy: proxy)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil)
        updateFrontmostApplication(NSWorkspace.shared.frontmostApplication)
    }

    var isRunning: Bool { monitor.isRunning }

    /// Starts the event tap; fails until the user grants Accessibility access.
    func start() -> Bool {
        guard monitor.start() else {
            return false
        }

        Log.info("Keyboard tap started; layouts: \(describeLayouts()); current: \(inputSources.current()?.id ?? "none")")
        if Set(inputSources.enabled.compactMap { $0.language?.code }).count < 2 {
            Log.info("Automatic correction needs both an English and a Russian keyboard layout " +
                     "(System Settings → Keyboard → Input Sources).")
        }

        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTap() }
        }

        return true
    }

    func describeLayouts() -> String {
        let layouts = inputSources.enabled
        guard !layouts.isEmpty else { return "none" }
        return layouts.map { "\($0.shortName) \($0.id) \($0.language?.code ?? "(no dictionary)")" }
            .joined(separator: ", ")
    }

    /// One line for the menu and the settings window: how it is going, or what stops KeyMorph.
    var status: (text: String, problem: Bool) {
        if !monitor.isRunning {
            return Permissions.isTrusted(prompt: false)
                ? ("Перехват клавиатуры не запущен — перезапустите IBA KeyMorph", true)
                : ("Нет доступа к клавиатуре — нажмите «Выдать доступ…»", true)
        }

        if SecureInput.isEnabled {
            let owner = SecureInput.ownerName().map { " в «\($0)»" } ?? ""
            return ("Включён защищённый ввод\(owner): macOS прячет нажатия от всех программ", true)
        }

        if Set(inputSources.enabled.compactMap { $0.language?.code }).count < 2 {
            return ("Нужны раскладки English и Русская (Настройки → Клавиатура → Источники ввода)", true)
        }

        if !settings.enabled {
            return ("Выключено", false)
        }

        return ("Нажатий перехвачено: \(keysSeen) · исправлено слов: \(corrections)", false)
    }

    /// Recovers a tap that stopped receiving keys. macOS may disable a tap, and a tap created around a
    /// permission change can stay silent; the HID system's own last key press tells us keys were missed.
    private func checkTap() {
        guard monitor.isRunning else { return }
        if !monitor.isEnabled {
            monitor.reenable()
            logWatchdog("Keyboard tap was found disabled; re-enabled")
            return
        }

        let sinceKey = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        let keyAt = ProcessInfo.processInfo.systemUptime - sinceKey
        guard sinceKey > 0.5, sinceKey < 10, keyAt > monitor.lastKeyDownAt + 1, !SecureInput.isEnabled else {
            return
        }

        engine.reset()
        monitor.stop()
        if monitor.start() {
            logWatchdog("Keyboard tap did not receive keys pressed \(String(format: "%.1f", sinceKey)) s ago; recreated it")
        } else {
            watchdog?.invalidate()
            watchdog = nil
            Log.info("Keyboard tap did not receive keys and could not be recreated (access revoked?)")
            onStopped?()
        }
    }

    private func logWatchdog(_ message: String) {
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastWatchdogLog, now - last < 600 {
            return
        }

        lastWatchdogLog = now
        Log.info(message)
    }

    func applySettings() {
        engineOptions.autoSwitch = settings.autoSwitch
        engineOptions.fixCapsLock = settings.fixCapsLock
        engineOptions.correctPreviousShortWord = settings.correctPreviousShortWord
        engine.reset()
    }

    /// Copies the selection, converts it to the other layout, pastes it back and restores the clipboard.
    func convertSelection() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        engine.reset()

        let pasteboard = NSPasteboard.general
        let backup = PasteboardBackup(pasteboard)
        let before = pasteboard.changeCount
        synthesizer.post(synthesizer.key(CGKeyCode(kVK_ANSI_C), flags: .maskCommand), proxy: nil)

        var waited = 0
        while pasteboard.changeCount == before && waited < 600 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            waited += 20
        }

        guard pasteboard.changeCount != before,
              let text = pasteboard.string(forType: .string), !text.isEmpty,
              let conversion = TextConverter.pickConversion(text, layouts: inputSources.enabled) else {
            backup.restore(to: pasteboard)
            return
        }

        let converted = TextConverter.convert(text, from: conversion.from, to: conversion.to)
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        synthesizer.post(synthesizer.key(CGKeyCode(kVK_ANSI_V), flags: .maskCommand), proxy: nil)

        // Give the target application time to read the clipboard before restoring it.
        try? await Task.sleep(nanoseconds: 400_000_000)
        backup.restore(to: pasteboard)

        if let target = conversion.to as? MacLayout {
            inputSources.select(target)
            layoutSwitched()
        }
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent, proxy: CGEventTapProxy) -> Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            engine.reset()
            doubleTap.reset()
            return false
        case .flagsChanged:
            handleFlagsChanged(event, proxy: proxy)
            return false
        case .keyUp:
            return swallowedKeyUps.remove(event.getIntegerValueField(.keyboardEventKeycode)) != nil
        case .keyDown:
            keysSeen += 1
            return handleKeyDown(event, proxy: proxy)
        default:
            return false
        }
    }

    private func handleKeyDown(_ event: CGEvent, proxy: CGEventTapProxy) -> Bool {
        doubleTap.reset()
        guard settings.enabled, !busy else {
            return false
        }

        if IsSecureEventInputEnabled() {
            // A password field (or another secure input) is focused.
            engine.reset()
            return false
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            // Shortcuts and ⌥-characters do not type into the current word.
            engine.reset()
            return false
        }

        if excluded {
            return false
        }

        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch code {
        case kVK_Space:
            return boundary(.space, event: event, proxy: proxy)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return boundary(.enter, event: event, proxy: proxy)
        case kVK_Tab:
            return boundary(.tab, event: event, proxy: proxy)
        case kVK_Delete:
            engine.onBackspace()
            return false
        default:
            break
        }

        guard MacLayout.isPrintable(code), let layout = inputSources.current() else {
            engine.reset()
            return false
        }

        let key = KeyStroke(code: code, shift: flags.contains(.maskShift), caps: flags.contains(.maskAlphaShift))
        if layout.render(key).isEmpty {
            engine.reset()
        } else {
            engine.onCharacterKey(key, layout: layout)
        }

        return false
    }

    private func handleFlagsChanged(_ event: CGEvent, proxy: CGEventTapProxy) {
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let raw = flags.rawValue
        let now = Int(ProcessInfo.processInfo.systemUptime * 1000)

        switch code {
        case kVK_Shift, kVK_RightShift:
            let isDown = raw & (code == kVK_Shift ? Self.leftShiftMask : Self.rightShiftMask) != 0
            if isDown {
                if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
                    doubleTap.reset()
                } else {
                    doubleTap.keyDown(Tap.shift, nowMs: now)
                }
            } else if doubleTap.keyUp(Tap.shift, nowMs: now), settings.enabled, settings.doubleShiftHotkey,
                      !busy, !excluded {
                let result = engine.convertLastWord(layouts: inputSources.enabled)
                if diagnostics {
                    Log.info("Double Shift → " + (result.actions.isEmpty ? "nothing to convert" : describe(result.actions)))
                }

                execute(result, boundaryEvent: nil, proxy: proxy)
            }
        case kVK_Option, kVK_RightOption:
            let isDown = raw & (code == kVK_Option ? Self.leftOptionMask : Self.rightOptionMask) != 0
            if isDown {
                if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskShift) {
                    doubleTap.reset()
                } else {
                    doubleTap.keyDown(Tap.option, nowMs: now)
                }
            } else if doubleTap.keyUp(Tap.option, nowMs: now), settings.enabled, settings.doubleOptionHotkey, !busy {
                Task { await self.convertSelection() }
            }
        default:
            // Caps Lock, Command, Control, Fn: no word editing, but they cancel a pending double tap.
            if code != kVK_CapsLock {
                doubleTap.reset()
            }
        }
    }

    private func boundary(_ kind: BoundaryKind, event: CGEvent, proxy: CGEventTapProxy) -> Bool {
        let word = diagnostics ? engine.currentWord : ""
        let result = engine.onBoundary(kind, layouts: inputSources.enabled)
        if !word.isEmpty {
            let layout = inputSources.current()
            Log.info("Word \"\(word)\" in \(layout?.shortName ?? "?") (\(layout?.id ?? "?")) → " +
                     (result.swallow ? describe(result.actions) : "keep"))
        }

        guard result.swallow else {
            return false
        }

        execute(result, boundaryEvent: event, proxy: proxy)
        swallowedKeyUps.insert(event.getIntegerValueField(.keyboardEventKeycode))
        return true
    }

    private func describe(_ actions: [EngineAction]) -> String {
        actions.map { action -> String in
            switch action {
            case .erase(let count): return "erase \(count)"
            case .type(let text): return "type \"\(text)\""
            case .replayBoundary: return "replay boundary"
            case .switchLayout(let layout): return "switch to \(layout.shortName) (\(layout.id))"
            case .capsLockOff: return "Caps Lock off"
            case .learnException(let word): return "never correct \"\(word)\" again"
            }
        }
        .joined(separator: "; ")
    }

    private func execute(_ result: EngineResult, boundaryEvent: CGEvent?, proxy: CGEventTapProxy?) {
        if result.actions.contains(where: { if case .type = $0 { return true } else { return false } }) {
            corrections += 1
        }

        var events: [CGEvent] = []
        var target: MacLayout?
        for action in result.actions {
            switch action {
            case .erase(let count):
                events += synthesizer.backspaces(count)
            case .type(let text):
                events += synthesizer.text(text)
            case .replayBoundary:
                if let original = boundaryEvent {
                    events += synthesizer.replay(original)
                }
            case .switchLayout(let layout):
                target = layout as? MacLayout
            case .capsLockOff:
                CapsLock.set(false)
            case .learnException(let word):
                settings.addException(word)
            }
        }

        synthesizer.post(events, proxy: proxy)
        if let target = target {
            inputSources.select(target)
            layoutSwitched()
        }
    }

    private func layoutSwitched() {
        if settings.playSound {
            NSSound(named: NSSound.Name("Tink"))?.play()
        }

        onLayoutSwitched?()
    }

    // MARK: - Frontmost application

    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        updateFrontmostApplication(app)
    }

    private func updateFrontmostApplication(_ app: NSRunningApplication?) {
        frontmostBundleId = app?.bundleIdentifier
        excluded = settings.isExcluded(bundleId: frontmostBundleId)
        engine.reset()
        if diagnostics {
            Log.info("App: \(app?.localizedName ?? "?") (\(frontmostBundleId ?? "no bundle id"))" +
                     (excluded ? " — excluded in settings" : ""))
        }
    }

    func refreshExclusion() {
        excluded = settings.isExcluded(bundleId: frontmostBundleId)
    }
}

/// A full copy of the pasteboard items, so the user's clipboard survives selection conversion.
struct PasteboardBackup {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy[type] = data
                }
            }

            return copy
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }

            return item
        }

        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
