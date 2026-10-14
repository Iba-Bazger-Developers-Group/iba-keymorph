import AppKit
import KeyMorphCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: KeyMorphController?
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let languages: LanguageStore
        do {
            languages = try AppResources.loadLanguages()
        } catch {
            let alert = NSAlert()
            alert.messageText = "IBA KeyMorph не может запуститься"
            alert.informativeText = "Не найдены словари (en.txt, ru.txt): \(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let settings = Settings()
        let controller = KeyMorphController(settings: settings, languages: languages)
        let settingsWindow = SettingsWindowController(settings: settings) { [weak controller] in
            controller?.applySettings()
            controller?.refreshExclusion()
        }
        let statusBar = StatusBarController(controller: controller) { [weak settingsWindow] in
            settingsWindow?.show()
        }
        controller.onLayoutSwitched = { [weak statusBar] in
            statusBar?.refresh()
        }

        self.controller = controller
        self.settingsWindow = settingsWindow
        self.statusBar = statusBar

        if !startMonitoring() {
            askForPermission(firstLaunch: !settings.onboarded)
        }

        settings.onboarded = true
    }

    /// Starts the event tap if Accessibility access is granted.
    private func startMonitoring() -> Bool {
        guard let controller = controller, Permissions.isTrusted(prompt: false), controller.start() else {
            return false
        }

        statusBar?.refresh()
        return true
    }

    private func askForPermission(firstLaunch: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = firstLaunch ? "Добро пожаловать в IBA KeyMorph" : "Нужен доступ к клавиатуре"
        alert.informativeText = """
            Чтобы исправлять раскладку, IBA KeyMorph должен видеть нажатия клавиш и печатать исправления.

            Откройте Системные настройки → Конфиденциальность и безопасность → Универсальный доступ \
            и включите IBA KeyMorph. Приложение начнёт работать сразу после этого.
            """
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Позже")
        if alert.runModal() == .alertFirstButtonReturn {
            _ = Permissions.isTrusted(prompt: true)
            Permissions.openAccessibilitySettings()
        }

        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(
            timeInterval: 1.5,
            target: self,
            selector: #selector(checkPermission),
            userInfo: nil,
            repeats: true)
    }

    @objc private func checkPermission() {
        if startMonitoring() {
            permissionTimer?.invalidate()
            permissionTimer = nil
        }
    }
}
