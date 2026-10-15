import AppKit
import SwiftUI

/// `IBAKeyMorph --render-ui <dir>` draws the windows into PNG files and exits; CI uses it to review
/// the UI without a person at the screen. The event tap is not started.
@MainActor
enum UISnapshots {
    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "com.iba.keymorph.snapshots") ?? .standard
        let settings = Settings(defaults: defaults)
        let working = StatusInfo(running: true, layout: "EN", detail: "Нажатий перехвачено: 128 · исправлено слов: 7", problem: false)
        for tab in 0..<3 {
            let view = SettingsView(settings: settings, status: { working }, initialTab: tab, onChange: {}, onClose: {})
            save(view, size: NSSize(width: 640, height: 700), to: directory.appendingPathComponent("settings-\(tab + 1).png"))
        }

        let noAccess = StatusInfo(
            running: false, layout: "EN", detail: "Нет доступа к клавиатуре — нажмите «Выдать доступ…»", problem: true)
        save(SettingsView(settings: settings, status: { noAccess }, onChange: {}, onClose: {}),
             size: NSSize(width: 640, height: 700), to: directory.appendingPathComponent("settings-no-access.png"))

        save(RunningAppsPicker(excluded: [], onAdd: { _ in }), size: NSSize(width: 540, height: 540),
             to: directory.appendingPathComponent("picker.png"))
    }

    private static func save<Content: View>(_ view: Content, size: NSSize, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))

        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }

        window.orderOut(nil)
    }
}
