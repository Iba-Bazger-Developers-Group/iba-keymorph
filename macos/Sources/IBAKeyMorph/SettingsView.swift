import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let onChange: () -> Void

    @State private var exceptionsText: String
    @State private var appsText: String
    @State private var launchAtLogin: Bool
    @State private var loginItemError: String?

    init(settings: Settings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
        _exceptionsText = State(initialValue: settings.exceptions.joined(separator: "\n"))
        _appsText = State(initialValue: settings.excludedApps.joined(separator: "\n"))
        _launchAtLogin = State(initialValue: LoginItem.isEnabled)
    }

    var body: some View {
        TabView {
            general
                .tabItem { Label("Основные", systemImage: "keyboard") }
            listEditor(
                caption: "Слова, которые никогда не исправляются (по одному в строке). Слово добавляется сюда " +
                    "автоматически, если отменить исправление двойным ⇧ Shift.",
                text: $exceptionsText,
                save: { settings.setExceptions(lines(exceptionsText)) })
                .tabItem { Label("Исключения", systemImage: "text.badge.xmark") }
            listEditor(
                caption: "Программы, в которых автоисправление отключено — идентификаторы (bundle id), по одному " +
                    "в строке. Например: com.apple.Terminal.",
                text: $appsText,
                save: { settings.setExcludedApps(lines(appsText)) })
                .tabItem { Label("Программы", systemImage: "app.badge") }
        }
        .padding(16)
        .frame(width: 560, height: 420)
    }

    private var general: some View {
        Form {
            Toggle("Автоматически исправлять раскладку при наборе", isOn: binding(\.autoSwitch))
            Toggle("Исправлять и короткое слово перед исправленным («z ns» → «я ты»)", isOn: binding(\.correctPreviousShortWord))
            Toggle("Исправлять слова, набранные со случайно включённым Caps Lock", isOn: binding(\.fixCapsLock))
            Toggle("Двойное нажатие ⇧ Shift — исправить или отменить последнее слово", isOn: binding(\.doubleShiftHotkey))
            Toggle("Двойное нажатие ⌥ Option — исправить выделенный текст", isOn: binding(\.doubleOptionHotkey))
            Toggle("Звук при переключении раскладки", isOn: binding(\.playSound))
            Toggle("Запускать IBA KeyMorph при входе в систему", isOn: $launchAtLogin)
            if let error = loginItemError {
                Text(error).foregroundColor(.red).font(.caption)
            }

            Text("Если исправление было ошибочным, сразу дважды нажмите ⇧ Shift: слово вернётся и больше " +
                 "не будет исправляться.")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .onChange(of: launchAtLogin) { enabled in
            do {
                try LoginItem.set(enabled)
                loginItemError = nil
            } catch {
                loginItemError = "Не удалось изменить автозапуск: \(error.localizedDescription)"
            }
        }
    }

    private func listEditor(caption: String, text: Binding<String>, save: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .border(Color.secondary.opacity(0.3))
            HStack {
                Spacer()
                Button("Сохранить") {
                    save()
                    onChange()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                settings[keyPath: keyPath] = value
                onChange()
            })
    }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: Settings
    private let onChange: () -> Void

    init(settings: Settings, onChange: @escaping () -> Void) {
        self.settings = settings
        self.onChange = onChange
    }

    func show() {
        // Rebuild a closed window so the lists show words learned in the meantime.
        if let window = window, !window.isVisible {
            self.window = nil
        }

        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, onChange: onChange))
            let window = NSWindow(contentViewController: hosting)
            window.title = "IBA KeyMorph — настройки"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
