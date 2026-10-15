import AppKit

@main
enum IBAKeyMorphApp {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render-ui"), index + 1 < arguments.count {
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.finishLaunching()
            UISnapshots.render(to: URL(fileURLWithPath: arguments[index + 1]))
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menu bar only: no Dock icon (Info.plist also sets LSUIElement).
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
