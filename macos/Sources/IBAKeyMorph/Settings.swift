import Combine
import Foundation
import KeyMorphCore

/// User preferences stored in UserDefaults (domain com.iba.keymorph).
final class Settings: ObservableObject {
    private enum Key {
        static let enabled = "enabled"
        static let autoSwitch = "autoSwitch"
        static let correctPreviousShortWord = "correctPreviousShortWord"
        static let fixCapsLock = "fixCapsLock"
        static let doubleShift = "doubleShiftHotkey"
        static let doubleOption = "doubleOptionHotkey"
        static let playSound = "playSound"
        static let exceptions = "exceptions"
        static let excludedApps = "excludedApps"
        static let onboarded = "onboarded"
    }

    static let defaultExcludedApps = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "com.apple.ScreenSharing",
        "com.microsoft.rdc.macos",
        "com.1password.1password",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
    ]

    private let defaults: UserDefaults

    /// Master switch: when off, KeyMorph ignores the keyboard completely.
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: Key.enabled) } }
    @Published var autoSwitch: Bool { didSet { defaults.set(autoSwitch, forKey: Key.autoSwitch) } }
    @Published var correctPreviousShortWord: Bool {
        didSet { defaults.set(correctPreviousShortWord, forKey: Key.correctPreviousShortWord) }
    }
    @Published var fixCapsLock: Bool { didSet { defaults.set(fixCapsLock, forKey: Key.fixCapsLock) } }
    /// ⇧⇧: convert (or undo) the last word.
    @Published var doubleShiftHotkey: Bool { didSet { defaults.set(doubleShiftHotkey, forKey: Key.doubleShift) } }
    /// ⌥⌥: convert the selected text.
    @Published var doubleOptionHotkey: Bool { didSet { defaults.set(doubleOptionHotkey, forKey: Key.doubleOption) } }
    @Published var playSound: Bool { didSet { defaults.set(playSound, forKey: Key.playSound) } }
    /// Words that are never corrected (normalised: lower case, ё → е).
    @Published private(set) var exceptions: [String]
    /// Bundle identifiers of apps where automatic correction is off.
    @Published private(set) var excludedApps: [String]

    var onboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.autoSwitch: true,
            Key.correctPreviousShortWord: true,
            Key.fixCapsLock: true,
            Key.doubleShift: true,
            Key.doubleOption: true,
            Key.playSound: false,
            Key.exceptions: [String](),
            Key.excludedApps: Settings.defaultExcludedApps,
        ])
        enabled = defaults.bool(forKey: Key.enabled)
        autoSwitch = defaults.bool(forKey: Key.autoSwitch)
        correctPreviousShortWord = defaults.bool(forKey: Key.correctPreviousShortWord)
        fixCapsLock = defaults.bool(forKey: Key.fixCapsLock)
        doubleShiftHotkey = defaults.bool(forKey: Key.doubleShift)
        doubleOptionHotkey = defaults.bool(forKey: Key.doubleOption)
        playSound = defaults.bool(forKey: Key.playSound)
        exceptions = defaults.stringArray(forKey: Key.exceptions) ?? []
        excludedApps = defaults.stringArray(forKey: Key.excludedApps) ?? Settings.defaultExcludedApps
    }

    func isException(_ word: String) -> Bool {
        exceptions.contains(word)
    }

    func addException(_ word: String) {
        guard !exceptions.contains(word) else { return }
        setExceptions(exceptions + [word])
    }

    func setExceptions(_ words: [String]) {
        exceptions = Array(Set(words.map { LanguageModel.normalize($0) }.filter { !$0.isEmpty })).sorted()
        defaults.set(exceptions, forKey: Key.exceptions)
    }

    func setExcludedApps(_ bundleIds: [String]) {
        excludedApps = Array(Set(bundleIds.filter { !$0.isEmpty })).sorted()
        defaults.set(excludedApps, forKey: Key.excludedApps)
    }

    func isExcluded(bundleId: String?) -> Bool {
        guard let bundleId = bundleId else { return false }
        return excludedApps.contains { $0.caseInsensitiveCompare(bundleId) == .orderedSame }
    }
}
