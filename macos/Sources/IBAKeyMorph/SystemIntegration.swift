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

/// After an update macOS can keep showing the previous icon (Finder, Dock, Launchpad) and can know several copies of the app.
/// On the first start of a new version the app registers itself again with Launch Services and touches its own bundle so the
/// icon caches are rebuilt; it also writes every copy macOS knows into the log. Nothing is deleted.
enum LaunchServicesRefresh {
    private static let versionKey = "launchServicesRegisteredBuild"
    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/" +
        "LaunchServices.framework/Support/lsregister"

    static func run() {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return } // `swift run` has no bundle

        let copies = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .map(\.path)
        if copies.count > 1 {
            Log.info("Several copies of IBA KeyMorph are known to macOS: \(copies.joined(separator: "; ")). " +
                     "Running: \(path). Remove the old ones (macos/scripts/update-keymorph.sh does it).")
        }

        let current = "\(AppResources.version)-\(AppResources.build)"
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: versionKey) != current else { return }
        defaults.set(current, forKey: versionKey)

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: lsregister)
            process.arguments = ["-f", path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            if (try? process.run()) != nil {
                process.waitUntilExit()
            }

            // A fresh modification date makes Finder and the Dock look at the bundle's icon again.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
            Log.info("Registered \(path) with Launch Services for \(current)")
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

    /// Monochrome globe + orbit for the menu bar (Contents/Resources/menu-glyph.png, or assets/ in a source checkout).
    /// A template image: macOS tints it for the light/dark menu bar and for highlighted state.
    static let menuGlyph: NSImage? = {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("assets/menu-glyph.png")
        let url = Bundle.main.url(forResource: "menu-glyph", withExtension: "png") ?? source
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 22, height: 11) // the file is 44x22 for Retina
        image.isTemplate = true
        return image
    }()

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "dev"
    }
}
