import AppKit

/// Menu bar item showing the current layout ("EN", "RU") with the app menu.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: KeyMorphController
    private let enabledItem = NSMenuItem(title: "Включено", action: nil, keyEquivalent: "")
    private let autoSwitchItem = NSMenuItem(title: "Автоматическое переключение", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Выдать доступ к клавиатуре…", action: nil, keyEquivalent: "")
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let diagnosticsItem = NSMenuItem(title: "Подробная диагностика (пишет слова в журнал)", action: nil, keyEquivalent: "")
    private let showSettings: () -> Void
    private let requestAccess: () -> Void

    init(controller: KeyMorphController, showSettings: @escaping () -> Void, requestAccess: @escaping () -> Void) {
        self.controller = controller
        self.showSettings = showSettings
        self.requestAccess = requestAccess
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "IBA KeyMorph \(AppResources.version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        enabledItem.target = self
        enabledItem.action = #selector(toggleEnabled)
        menu.addItem(enabledItem)

        autoSwitchItem.target = self
        autoSwitchItem.action = #selector(toggleAutoSwitch)
        menu.addItem(autoSwitchItem)

        menu.addItem(item("Исправить выделенный текст  ⌥⌥", #selector(convertSelection)))
        menu.addItem(.separator())

        permissionItem.target = self
        permissionItem.action = #selector(openPermissions)
        menu.addItem(permissionItem)
        menu.addItem(item("Настройки…", #selector(openSettings), key: ","))
        menu.addItem(item("Открыть журнал", #selector(openLog)))
        diagnosticsItem.target = self
        diagnosticsItem.action = #selector(toggleDiagnostics)
        menu.addItem(diagnosticsItem)
        menu.addItem(item("О программе IBA KeyMorph", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Выйти", #selector(quit), key: "q"))
        statusItem.menu = menu

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil)
        refresh()
    }

    func refresh() {
        let layout = controller.inputSources.current()?.shortName ?? "⌨︎"
        let active = controller.settings.enabled && controller.isRunning
        // Without keyboard access the label says so instead of looking like a working layout indicator.
        let label = controller.isRunning ? layout : "\(layout) ⚠︎"
        let color: NSColor = active ? .labelColor : .tertiaryLabelColor
        statusItem.button?.attributedTitle = NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: color,
            ])
        statusItem.button?.toolTip = controller.isRunning
            ? (active ? "IBA KeyMorph — \(layout)" : "IBA KeyMorph — выключен")
            : "IBA KeyMorph — нет доступа к клавиатуре"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let status = controller.status
        statusLine.attributedTitle = NSAttributedString(
            string: (status.problem ? "⚠︎ " : "") + status.text,
            attributes: [
                .font: NSFont.menuFont(ofSize: 12),
                .foregroundColor: status.problem ? NSColor.systemOrange : NSColor.secondaryLabelColor,
            ])
        enabledItem.state = controller.settings.enabled ? .on : .off
        autoSwitchItem.state = controller.settings.autoSwitch ? .on : .off
        autoSwitchItem.isEnabled = controller.settings.enabled
        permissionItem.isHidden = controller.isRunning
        diagnosticsItem.state = controller.settings.diagnosticLog ? .on : .off
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func inputSourceChanged() {
        refresh()
    }

    @objc private func toggleEnabled() {
        controller.settings.enabled.toggle()
        controller.applySettings()
        refresh()
    }

    @objc private func toggleAutoSwitch() {
        controller.settings.autoSwitch.toggle()
        controller.applySettings()
    }

    @objc private func convertSelection() {
        Task {
            // Let the menu close and focus return to the previous app first.
            try? await Task.sleep(nanoseconds: 250_000_000)
            await controller.convertSelection()
        }
    }

    @objc private func openPermissions() {
        requestAccess()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func openLog() {
        Log.open()
    }

    @objc private func toggleDiagnostics() {
        controller.settings.diagnosticLog.toggle()
        Log.info("Detailed diagnostics \(controller.settings.diagnosticLog ? "on" : "off")")
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "IBA KeyMorph \(AppResources.version)"
        alert.informativeText = """
            Автоматическое переключение раскладки клавиатуры EN ⇄ RU.

            Горячие клавиши:
            ⇧⇧ (дважды Shift) — исправить или отменить последнее слово
            ⌥⌥ (дважды Option) — исправить выделенный текст

            Журнал: ~/Library/Logs/IBA KeyMorph/keymorph.log

            © IBA
            """
        alert.icon = AppResources.panda
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
