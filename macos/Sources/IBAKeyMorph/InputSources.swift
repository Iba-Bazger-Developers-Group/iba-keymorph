import Carbon
import Foundation
import KeyMorphCore

/// An enabled keyboard input source with its Unicode key layout. Key codes are virtual key codes
/// (physical positions), so the same keys can be rendered in every layout.
final class MacLayout: KeyboardLayout {
    /// Virtual key codes of keys that type characters (letters, digits, punctuation, ISO section key).
    static let printableCodes: [Int] = Array(0x00...0x23) + Array(0x25...0x2F) + [0x32]
    private static let printableSet = Set(printableCodes)

    let source: TISInputSource
    let id: String
    let shortName: String
    let language: LanguageModel?
    let printableKeyCodes: [Int] = MacLayout.printableCodes
    private let layoutData: Data
    private var cache: [KeyStroke: String] = [:]

    init?(source: TISInputSource, store: LanguageStore) {
        guard let id: String = MacLayout.property(source, kTISPropertyInputSourceID),
              let data: CFData = MacLayout.property(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }

        let languages: [String] = MacLayout.property(source, kTISPropertyInputSourceLanguages) ?? []
        let primary = languages.first.map { String($0.prefix(2)).lowercased() }
        self.source = source
        self.id = id
        self.layoutData = data as Data
        self.language = store.model(for: primary)
        self.shortName = (primary ?? "??").uppercased()
    }

    static func isPrintable(_ code: Int) -> Bool { printableSet.contains(code) }

    func render(_ key: KeyStroke) -> String {
        if let cached = cache[key] {
            return cached
        }

        var modifiers: UInt32 = 0
        if key.shift {
            modifiers |= UInt32(shiftKey >> 8) & 0xFF
        }

        if key.caps {
            modifiers |= UInt32(alphaLock >> 8) & 0xFF
        }

        let capacity = 8
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: capacity)
        let status = layoutData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OSStatus in
            guard let base = raw.baseAddress else { return -50 } // paramErr
            return UCKeyTranslate(
                base.assumingMemoryBound(to: UCKeyboardLayout.self),
                UInt16(key.code),
                UInt16(kUCKeyActionDown),
                modifiers,
                UInt32(LMGetKbdType()),
                0,
                &deadKeyState,
                capacity,
                &length,
                &chars)
        }

        // Dead keys (deadKeyState != 0), ligatures and control characters are not tracked.
        var text = ""
        if status == 0 && deadKeyState == 0 && length == 1 {
            let candidate = String(utf16CodeUnits: chars, count: length)
            if let scalar = candidate.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar) {
                text = candidate
            }
        }

        cache[key] = text
        return text
    }

    private static func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }

        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
    }
}

/// Enabled keyboard layouts, the current one, and switching. Call from the main thread.
final class InputSourceManager {
    private let store: LanguageStore
    private var layouts: [MacLayout] = []
    private var refreshedAt = Date.distantPast

    init(store: LanguageStore) {
        self.store = store
    }

    var enabled: [MacLayout] {
        if Date().timeIntervalSince(refreshedAt) > 2 {
            refresh()
        }

        return layouts
    }

    /// The selected keyboard layout, or nil for input methods without a plain key layout.
    func current() -> MacLayout? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }

        let id = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        if let known = enabled.first(where: { $0.id == id }) {
            return known
        }

        refresh()
        return layouts.first(where: { $0.id == id })
    }

    func select(_ layout: MacLayout) {
        TISSelectInputSource(layout.source)
    }

    func refresh() {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue() as? [TISInputSource] ?? []
        let previous = Dictionary(layouts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        layouts = sources.compactMap { source -> MacLayout? in
            guard let layout = MacLayout(source: source, store: store) else { return nil }
            return previous[layout.id] ?? layout
        }
        refreshedAt = Date()
    }
}
