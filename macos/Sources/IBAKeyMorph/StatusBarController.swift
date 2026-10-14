import AppKit

/// Menu bar item showing the current layout ("EN", "RU") with the app menu.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: KeyMorphController
    private let enabledItem = NSMenuItem(title: "Включено", action: nil, keyEquivalent: "")
    private let autoSwitchItem = NSMenuItem(title: "Автоматическое переключение", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Разрешить доступ к клавиатуре…", action: nil, keyEquivalent: "")
    private let showSettings: () -> Void

    init(controller: KeyMorphController, showSettings: @escaping () -> Void) {
        self.controller = controller
        self.showSettings = showSettings
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "IBA KeyMorph", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
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
        let label = controller.inputSources.current()?.shortName ?? "⌨︎"
        let active = controller.settings.enabled && controller.isRunning
        let color: NSColor = active ? .labelColor : .tertiaryLabelColor
        statusItem.button?.attributedTitle = NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: color,
            ])
        statusItem.button?.toolTip = active ? "IBA KeyMorph — \(label)" : "IBA KeyMorph — выключен"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        enabledItem.state = controller.settings.enabled ? .on : .off
        autoSwitchItem.state = controller.settings.autoSwitch ? .on : .off
        autoSwitchItem.isEnabled = controller.settings.enabled
        permissionItem.isHidden = controller.isRunning
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
        _ = Permissions.isTrusted(prompt: true)
        Permissions.openAccessibilitySettings()
    }

    @objc private func openSettings() {
        showSettings()
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

            © IBA
            """
        alert.icon = NSApp.applicationIconImage
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
