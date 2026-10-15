import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// IBA palette (same as the Windows app and IBA Publisher).
enum IBA {
    static let background = Color(red: 15 / 255, green: 26 / 255, blue: 23 / 255)
    static let surface = Color(red: 24 / 255, green: 37 / 255, blue: 32 / 255)
    static let surfaceHover = Color(red: 32 / 255, green: 50 / 255, blue: 43 / 255)
    static let border = Color(red: 47 / 255, green: 72 / 255, blue: 61 / 255)
    static let accent = Color(red: 46 / 255, green: 125 / 255, blue: 91 / 255)
    static let accentHover = Color(red: 57 / 255, green: 146 / 255, blue: 107 / 255)
    static let glow = Color(red: 46 / 255, green: 204 / 255, blue: 113 / 255)
    static let text = Color(red: 236 / 255, green: 243 / 255, blue: 239 / 255)
    static let muted = Color(red: 143 / 255, green: 166 / 255, blue: 155 / 255)
    static let caption = Color(red: 214 / 255, green: 170 / 255, blue: 92 / 255)
    static let backgroundNS = NSColor(red: 15 / 255, green: 26 / 255, blue: 23 / 255, alpha: 1)
}

struct IBAButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        IBAButtonBody(configuration: configuration, primary: primary)
    }
}

private struct IBAButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let fill = primary
            ? (configuration.isPressed ? IBA.accentHover : IBA.accent)
            : (configuration.isPressed ? IBA.surfaceHover : IBA.surface)
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(IBA.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(primary ? IBA.accent : IBA.border, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// Name and icon of an app by bundle id, whether or not it is running.
enum AppInfo {
    private static let knownNames = [
        "com.apple.Terminal": "Терминал",
        "com.googlecode.iterm2": "iTerm2",
        "dev.warp.Warp-Stable": "Warp",
        "net.kovidgoyal.kitty": "kitty",
        "io.alacritty": "Alacritty",
        "com.github.wez.wezterm": "WezTerm",
        "com.apple.ScreenSharing": "Общий экран",
        "com.microsoft.rdc.macos": "Microsoft Remote Desktop",
        "com.1password.1password": "1Password",
        "com.bitwarden.desktop": "Bitwarden",
        "org.keepassxc.keepassxc": "KeePassXC",
    ]

    static func name(_ bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let name = FileManager.default.displayName(atPath: url.path)
            return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
        }

        return knownNames[bundleId] ?? bundleId
    }

    static func icon(_ bundleId: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return NSWorkspace.shared.icon(for: .application)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let currentLayout: String
    let onChange: () -> Void
    let onClose: () -> Void

    @State private var tab = 0
    @State private var exceptionsText: String
    @State private var launchAtLogin: Bool
    @State private var loginItemError: String?
    @State private var selectedApps = Set<String>()
    @State private var showPicker = false

    init(
        settings: Settings,
        currentLayout: String,
        initialTab: Int = 0,
        onChange: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.settings = settings
        self.currentLayout = currentLayout
        self.onChange = onChange
        self.onClose = onClose
        _tab = State(initialValue: initialTab)
        _exceptionsText = State(initialValue: settings.exceptions.joined(separator: "\n"))
        _launchAtLogin = State(initialValue: LoginItem.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusCard
            tabBar
            Group {
                switch tab {
                case 0: general
                case 1: exceptions
                default: programs
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .padding(24)
        .frame(width: 640, height: 700)
        .background(IBA.background)
        .foregroundColor(IBA.text)
        .tint(IBA.accent)
        .preferredColorScheme(.dark)
        .onDisappear(perform: saveExceptions)
        .sheet(isPresented: $showPicker) {
            RunningAppsPicker(excluded: Set(settings.excludedApps)) { bundleIds in
                settings.setExcludedApps(settings.excludedApps + bundleIds)
                onChange()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: AppResources.panda)
                .resizable()
                .interpolation(.high)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("IBA KeyMorph").font(.system(size: 28, weight: .bold))
                Text("Раскладка исправляется сама. EN ⇄ RU, Windows и macOS.").foregroundColor(IBA.muted)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("СОСТОЯНИЕ").font(.system(size: 11, weight: .bold)).foregroundColor(IBA.caption)
            Text(settings.enabled ? "Работает · \(currentLayout)" : "Выключено · \(currentLayout)")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(settings.enabled ? IBA.text : IBA.muted)
            Text("Версия \(AppResources.version)").foregroundColor(IBA.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IBA.surface)
    }

    private var tabBar: some View {
        HStack(spacing: 10) {
            ForEach(Array(["Основные", "Исключения", "Программы"].enumerated()), id: \.offset) { index, title in
                Button(title) { tab = index }
                    .buttonStyle(IBAButtonStyle(primary: tab == index))
            }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 12) {
            toggle("Автоматически исправлять раскладку при наборе", \.autoSwitch)
            toggle("Исправлять и короткое слово перед исправленным («z ns» → «я ты»)", \.correctPreviousShortWord)
            toggle("Исправлять слова, набранные со случайным Caps Lock", \.fixCapsLock)
            toggle("Двойной ⇧ Shift — исправить или отменить последнее слово", \.doubleShiftHotkey)
            toggle("Двойной ⌥ Option — исправить выделенный текст", \.doubleOptionHotkey)
            toggle("Звук при переключении раскладки", \.playSound)
            switchRow("Запускать IBA KeyMorph при входе в систему", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        try LoginItem.set(enabled)
                        loginItemError = nil
                    } catch {
                        loginItemError = "Не удалось изменить автозапуск: \(error.localizedDescription)"
                    }
                }
            if let error = loginItemError {
                Text(error).foregroundColor(IBA.caption).font(.callout)
            }

            Text("Ошиблись с исправлением? Сразу дважды нажмите ⇧ Shift — слово вернётся и больше не будет исправляться.")
                .foregroundColor(IBA.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private var exceptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Слова, которые никогда не исправляются, по одному в строке. Слово попадает сюда само, если отменить исправление.")
                .foregroundColor(IBA.muted)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $exceptionsText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(IBA.surface)
        }
    }

    private var programs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("В этих программах раскладка не исправляется автоматически.")
                .foregroundColor(IBA.muted)
            List(selection: $selectedApps) {
                ForEach(settings.excludedApps, id: \.self) { bundleId in
                    HStack(spacing: 10) {
                        Image(nsImage: AppInfo.icon(bundleId)).resizable().frame(width: 22, height: 22)
                        Text(AppInfo.name(bundleId)).foregroundColor(IBA.text)
                        Spacer()
                        Text(bundleId).font(.system(size: 11)).foregroundColor(IBA.muted)
                    }
                    .padding(.vertical, 2)
                    .tag(bundleId)
                }
            }
            .scrollContentBackground(.hidden)
            .background(IBA.surface)
            .onDeleteCommand(perform: removeSelectedApps)
            HStack(spacing: 10) {
                Button("Добавить из запущенных…") { showPicker = true }
                    .buttonStyle(IBAButtonStyle(primary: true))
                Button("Выбрать приложение…", action: chooseApplications)
                    .buttonStyle(IBAButtonStyle())
                Button("Удалить", action: removeSelectedApps)
                    .buttonStyle(IBAButtonStyle())
                    .disabled(selectedApps.isEmpty)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("⇧⇧ — последнее слово · ⌥⌥ — выделенный текст")
                .font(.system(size: 12))
                .foregroundColor(IBA.muted)
            Spacer()
            Button("Готово") {
                saveExceptions()
                onClose()
            }
            .buttonStyle(IBAButtonStyle(primary: true))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func toggle(_ title: String, _ keyPath: ReferenceWritableKeyPath<Settings, Bool>) -> some View {
        switchRow(title, isOn: Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                settings[keyPath: keyPath] = value
                onChange()
            }))
    }

    /// Label on the left, switch aligned to the right edge.
    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func saveExceptions() {
        let words = exceptionsText.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        settings.setExceptions(words)
        onChange()
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Добавить"
        guard panel.runModal() == .OK else { return }
        let bundleIds = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        settings.setExcludedApps(settings.excludedApps + bundleIds)
        onChange()
    }

    private func removeSelectedApps() {
        settings.setExcludedApps(settings.excludedApps.filter { !selectedApps.contains($0) })
        selectedApps.removeAll()
        onChange()
    }
}

struct RunningApp: Identifiable {
    let id: String
    let name: String
    let icon: NSImage
}

/// Sheet listing open applications to exclude, with search and check boxes.
struct RunningAppsPicker: View {
    let excluded: Set<String>
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var checked = Set<String>()
    @State private var apps: [RunningApp] = []

    init(excluded: Set<String>, onAdd: @escaping ([String]) -> Void) {
        self.excluded = excluded
        self.onAdd = onAdd
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Где не исправлять раскладку?").font(.system(size: 18, weight: .bold))
            Text("Отметьте программы. Показаны открытые приложения.").foregroundColor(IBA.muted)
            TextField("Поиск программы…", text: $search)
                .textFieldStyle(.plain)
                .padding(10)
                .background(IBA.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            List {
                ForEach(filtered) { app in
                    Toggle(isOn: Binding(
                        get: { checked.contains(app.id) },
                        set: { isOn in
                            if isOn {
                                checked.insert(app.id)
                            } else {
                                checked.remove(app.id)
                            }
                        })) {
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon).resizable().frame(width: 22, height: 22)
                            Text(app.name)
                            Spacer()
                            Text(app.id).font(.system(size: 11)).foregroundColor(IBA.muted)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .scrollContentBackground(.hidden)
            .background(IBA.surface)
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .buttonStyle(IBAButtonStyle())
                Button(checked.count > 1 ? "Добавить (\(checked.count))" : "Добавить") {
                    onAdd(apps.map(\.id).filter { checked.contains($0) })
                    dismiss()
                }
                .buttonStyle(IBAButtonStyle(primary: true))
                .disabled(checked.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 540)
        .background(IBA.background)
        .foregroundColor(IBA.text)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
    }

    private var filtered: [RunningApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return apps
        }

        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private func load() {
        var seen = Set<String>()
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                      !excluded.contains(id), seen.insert(id).inserted else {
                    return nil
                }

                return RunningApp(
                    id: id,
                    name: app.localizedName ?? id,
                    icon: app.icon ?? NSWorkspace.shared.icon(for: .application))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: Settings
    private let currentLayout: () -> String
    private let onChange: () -> Void

    init(settings: Settings, currentLayout: @escaping () -> String, onChange: @escaping () -> Void) {
        self.settings = settings
        self.currentLayout = currentLayout
        self.onChange = onChange
    }

    func show() {
        // Rebuild a closed window so the lists show words learned in the meantime.
        if let window = window, !window.isVisible {
            self.window = nil
        }

        if window == nil {
            let view = SettingsView(
                settings: settings,
                currentLayout: currentLayout(),
                onChange: onChange,
                onClose: { [weak self] in self?.window?.close() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "IBA KeyMorph — настройки"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.backgroundColor = IBA.backgroundNS
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
