import AppKit
import ApplicationServices
import IOKit
import IOKit.hidsystem
import KeyMorphCore
import ServiceManagement

enum CapsLock {
    // Values from <IOKit/hidsystem/IOHIDShared.h>.
    private static let hidSystemClass = "IOHIDSystem"
    private static let paramConnectType: UInt32 = 1 // kIOHIDParamConnectType
    private static let capsLockState: Int32 = 1 // kIOHIDCapsLockState

    /// Sets the Caps Lock state through the HID system (also updates the keyboard LED).
    static func set(_ on: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(hidSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, paramConnectType, &connection) == KERN_SUCCESS else {
            return
        }

        defer { IOServiceClose(connection) }
        IOHIDSetModifierLockState(connection, capsLockState, on)
    }
}

enum Permissions {
    /// Whether the app may observe and post keyboard events (Accessibility).
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum AppResources {
    /// Loads the word lists bundled in Contents/Resources (or data/ in a source checkout for `swift run`).
    static func loadLanguages() throws -> LanguageStore {
        if let english = Bundle.main.url(forResource: "en", withExtension: "txt") {
            return try LanguageStore(directory: english.deletingLastPathComponent())
        }

        let sourceData = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // IBAKeyMorph
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("data")
        return try LanguageStore(directory: sourceData)
    }

    /// The IBA panda logo (Contents/Resources/panda-logo.png, or assets/ in a source checkout).
    static let panda: NSImage = {
        if let url = Bundle.main.url(forResource: "panda-logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("assets/panda-logo.png")
        return NSImage(contentsOf: source) ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
    }()

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
