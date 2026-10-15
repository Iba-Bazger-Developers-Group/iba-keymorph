import AppKit
import KeyMorphCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: KeyMorphController?
    private var statusBar: StatusBarController?
    private var settingsWindow: SettingsWindowController?
    private var accessTimer: Timer?
    private var askingForAccess = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.info("IBA KeyMorph \(AppResources.version) (\(AppResources.build)) on macOS " +
                 "\(ProcessInfo.processInfo.operatingSystemVersionString), \(Self.architecture), " +
                 "app: \(Bundle.main.bundlePath)")
        Log.info("Access: accessibility \(Permissions.isTrusted(prompt: false)), " +
                 "input monitoring \(Permissions.canListen), post events \(Permissions.canPost)")

        let languages: LanguageStore
        do {
            languages = try AppResources.loadLanguages()
        } catch {
            Log.info("Word lists are missing: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "IBA KeyMorph не может запуститься"
            alert.informativeText = "Не найдены словари (en.txt, ru.txt): \(error.localizedDescription)"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        let settings = Settings()
        let controller = KeyMorphController(settings: settings, languages: languages)
        let settingsWindow = SettingsWindowController(
            settings: settings,
            status: { [weak controller] in
                guard let controller = controller else {
                    return StatusInfo(running: false, layout: "—", detail: "", problem: true)
                }

                let status = controller.status
                return StatusInfo(
                    running: controller.isRunning,
                    layout: controller.inputSources.current()?.shortName ?? "—",
                    detail: status.text,
                    problem: status.problem)
            },
            onChange: { [weak controller] in
                controller?.applySettings()
                controller?.refreshExclusion()
            },
            onFixAccess: { [weak self] in self?.requestAccess() })
        let statusBar = StatusBarController(
            controller: controller,
            showSettings: { [weak settingsWindow] in settingsWindow?.show() },
            requestAccess: { [weak self] in self?.requestAccess() })
        controller.onLayoutSwitched = { [weak statusBar] in
            statusBar?.refresh()
        }

        controller.onStopped = { [weak self] in
            self?.statusBar?.refresh()
            self?.waitForAccess()
        }

        self.controller = controller
        self.settingsWindow = settingsWindow
        self.statusBar = statusBar

        let firstLaunch = !settings.onboarded
        settings.onboarded = true
        if startMonitoring() {
            if firstLaunch {
                settingsWindow.show()
            }
        } else {
            askForAccess(firstLaunch: firstLaunch)
        }
    }

    /// Opening the app again (Finder, Launchpad, Spotlight) while it runs shows the settings window:
    /// a menu bar app has no other window, and its menu bar item may be hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow?.show()
        return false
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    /// Starts the event tap if Accessibility access is granted.
    private func startMonitoring() -> Bool {
        guard let controller = controller else {
            return false
        }

        if controller.isRunning {
            return true
        }

        guard Permissions.isTrusted(prompt: false) else {
            return false
        }

        guard controller.start() else {
            Log.info("Accessibility access is granted, but the keyboard event tap could not be created " +
                     "(input monitoring \(Permissions.canListen), post events \(Permissions.canPost))")
            return false
        }

        statusBar?.refresh()
        return true
    }

    private func askForAccess(firstLaunch: Bool) {
        waitForAccess()
        guard !askingForAccess else { return }
        askingForAccess = true
        defer { askingForAccess = false }

        Log.info("No keyboard access yet; asking the user")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = AppResources.panda
        alert.messageText = firstLaunch ? "Добро пожаловать в IBA KeyMorph" : "Нужен доступ к клавиатуре"
        alert.informativeText = """
            Чтобы исправлять раскладку, IBA KeyMorph должен видеть нажатия клавиш и печатать исправления.

            Нажмите «Выдать доступ» и в открывшемся «Универсальном доступе» включите переключатель \
            у IBA KeyMorph. Программа заработает сразу, перезапускать не нужно.

            Если IBA KeyMorph там уже включён (например, после обновления), это запись старой версии: \
            кнопка заменит её новой, останется включить переключатель ещё раз.
            """
        alert.addButton(withTitle: "Выдать доступ")
        alert.addButton(withTitle: "Позже")
        if alert.runModal() == .alertFirstButtonReturn {
            requestAccess()
        }
    }

    private func requestAccess() {
        if startMonitoring() {
            settingsWindow?.show()
            return
        }

        Permissions.resetAndRequest()
        waitForAccess()
    }

    /// Polls until access is granted, then starts the tap without a restart.
    private func waitForAccess() {
        guard accessTimer == nil else { return }
        accessTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAccess() }
        }
    }

    private func checkAccess() {
        guard startMonitoring() else { return }
        accessTimer?.invalidate()
        accessTimer = nil
        Log.info("Keyboard access granted; IBA KeyMorph is running")
        settingsWindow?.show()
    }
}
