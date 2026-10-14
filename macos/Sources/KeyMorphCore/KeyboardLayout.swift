/// A physical key press. `code` is a platform key id (virtual key code on macOS).
public struct KeyStroke: Hashable {
    public var code: Int
    public var shift: Bool
    public var caps: Bool

    public init(code: Int, shift: Bool, caps: Bool) {
        self.code = code
        self.shift = shift
        self.caps = caps
    }
}

public protocol KeyboardLayout: AnyObject {
    /// Stable platform id (input source id on macOS).
    var id: String { get }

    /// Short label for the UI, e.g. "EN".
    var shortName: String { get }

    /// Language model for this layout or nil when the language is unsupported.
    var language: LanguageModel? { get }

    /// Key codes that produce printable characters; used to build text converters.
    var printableKeyCodes: [Int] { get }

    /// Text the key produces in this layout, or an empty string.
    func render(_ key: KeyStroke) -> String
}

extension KeyboardLayout {
    public func render(_ keys: [KeyStroke]) -> String {
        keys.map { render($0) }.joined()
    }
}

func toggledCase(_ c: Character) -> Character {
    let s = c.isUppercase ? c.lowercased() : c.uppercased()
    guard s.count == 1, let first = s.first else { return c }
    return first
}

/// Layout defined by two strings (unshifted and shifted characters per key position).
public final class TableLayout: KeyboardLayout {
    public let id: String
    public let shortName: String
    public let language: LanguageModel?
    public let printableKeyCodes: [Int]
    private let normal: [Character]
    private let shifted: [Character]

    public init(id: String, shortName: String, language: LanguageModel?, normal: String, shifted: String) {
        precondition(normal.count == shifted.count, "Normal and shifted rows must have the same length.")
        self.id = id
        self.shortName = shortName
        self.language = language
        self.normal = Array(normal)
        self.shifted = Array(shifted)
        self.printableKeyCodes = Array(0..<normal.count)
    }

    public func render(_ key: KeyStroke) -> String {
        guard key.code >= 0, key.code < normal.count else { return "" }
        var c = key.shift ? shifted[key.code] : normal[key.code]
        if key.caps && c.isLetter {
            c = toggledCase(c)
        }

        return String(c)
    }

    /// Key (position) that produces `c`, for tests and simulators.
    public func find(_ c: Character, caps: Bool = false) -> KeyStroke? {
        if let index = normal.firstIndex(of: c) {
            return KeyStroke(code: index, shift: false, caps: caps)
        }

        if let index = shifted.firstIndex(of: c) {
            return KeyStroke(code: index, shift: true, caps: caps)
        }

        return nil
    }
}

public enum BuiltInLayouts {
    // Positions follow the US keyboard: `1234567890-= qwertyuiop[]\ asdfghjkl;' zxcvbnm,./
    public static let usNormal = "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./"
    public static let usShifted = "~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?"
    public static let ruNormal = "ё1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю."
    public static let ruShifted = "Ё!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЪ/ФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,"

    public static func english(_ language: LanguageModel?) -> TableLayout {
        TableLayout(id: "builtin:en-US", shortName: "EN", language: language, normal: usNormal, shifted: usShifted)
    }

    public static func russian(_ language: LanguageModel?) -> TableLayout {
        TableLayout(id: "builtin:ru-RU", shortName: "RU", language: language, normal: ruNormal, shifted: ruShifted)
    }
}
