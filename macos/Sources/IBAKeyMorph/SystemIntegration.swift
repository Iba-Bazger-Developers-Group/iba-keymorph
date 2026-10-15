import AppKit
import ApplicationServices
import Carbon
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

    /// Input Monitoring: lets an event tap see keystrokes (Accessibility covers it too).
    static var canListen: Bool { CGPreflightListenEventAccess() }

    /// Lets the app post synthetic keystrokes (Accessibility covers it too).
    static var canPost: Bool { CGPreflightPostEventAccess() }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Replaces the app's Accessibility entry with a fresh one and opens the settings pane.
    /// An ad-hoc signed update no longer matches the entry the user enabled for the previous build:
    /// the switch still looks on, but macOS denies access. A new entry only needs to be switched on.
    static func resetAndRequest() {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.iba.keymorph"
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", bundleId]
        do {
            try reset.run()
            reset.waitUntilExit()
            Log.info("tccutil reset Accessibility \(bundleId): exit code \(reset.terminationStatus)")
        } catch {
            Log.info("tccutil reset failed: \(error.localizedDescription)")
        }

        _ = isTrusted(prompt: true)
        openAccessibilitySettings()
    }
}

enum SecureInput {
    /// While secure keyboard entry is on (password fields, Terminal's "Secure Keyboard Entry", some
    /// password managers), macOS hides keystrokes from every event tap.
    static var isEnabled: Bool { IsSecureEventInputEnabled() }

    /// The app that turned secure keyboard entry on.
    static func ownerName() -> String? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let property = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0),
              let users = property.takeRetainedValue() as? [[String: Any]] else {
            return nil
        }

        for user in users {
            if let pid = (user["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0 {
                return NSRunningApplication(processIdentifier: pid)?.localizedName ?? "процесс \(pid)"
            }
        }

        return nil
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

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }
}
