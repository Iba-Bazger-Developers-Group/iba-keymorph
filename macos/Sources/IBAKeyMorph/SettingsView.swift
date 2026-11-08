import AppKit
import CoreText
import SwiftUI
import UniformTypeIdentifiers

/// IBA brandbook 4.2: Blue #0055FD for the one main action, white cards on Mist, Ink text,
/// Orange #FFA500 as the rare accent. Type is Manrope (bundled), system font if it cannot be loaded.
/// The same values are used by the Windows app (see BRAND.md).
enum IBA {
    // Brandbook palette.
    static let blue = Color(red: 0 / 255, green: 85 / 255, blue: 253 / 255)      // IBA Blue  #0055FD
    static let ink = Color(red: 16 / 255, green: 20 / 255, blue: 33 / 255)       // Ink       #101421
    static let mist = Color(red: 240 / 255, green: 243 / 255, blue: 250 / 255)   // Mist      #F0F3FA
    static let orange = Color(red: 255 / 255, green: 165 / 255, blue: 0 / 255)   // Orange    #FFA500

    // Roles.
    static let background = mist
    static let surface = Color.white
    static let surfaceHover = Color(red: 230 / 255, green: 236 / 255, blue: 249 / 255)
    static let border = Color(red: 214 / 255, green: 222 / 255, blue: 238 / 255)
    static let borderStrong = Color(red: 150 / 255, green: 162 / 255, blue: 188 / 255)
    static let accent = blue
    static let accentHover = Color(red: 0 / 255, green: 70 / 255, blue: 208 / 255)  // white text 7.7:1
    static let text = ink
    static let muted = Color(red: 84 / 255, green: 96 / 255, blue: 120 / 255)       // 6.4:1 on white
    static let caption = accentHover        // small captions are blue, never orange
    static let success = Color(red: 21 / 255, green: 120 / 255, blue: 79 / 255)
    static let warning = Color(red: 154 / 255, green: 91 / 255, blue: 0 / 255)      // text, always with a word or ⚠︎
    static let backgroundNS = NSColor(red: 240 / 255, green: 243 / 255, blue: 250 / 255, alpha: 1)

    /// Manrope Regular and Bold are registered for this process from Contents/Resources
    /// (or assets/fonts in a source checkout); false means the system font is used instead.
    static let hasManrope: Bool = {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // IBAKeyMorph
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // repository root
        for name in ["Manrope-Regular", "Manrope-Bold"] {
            let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                ?? repository.appendingPathComponent("assets/fonts/\(name).ttf")
            // An already registered font is not an error here.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }

        return NSFont(name: "Manrope-Regular", size: 12) != nil
    }()

    /// Only Regular and Bold ship, so every weight at semibold and above is Bold.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let bold = weight == .bold || weight == .semibold || weight == .heavy || weight == .black
        if hasManrope {
            return .custom(bold ? "Manrope-Bold" : "Manrope-Regular", size: size)
        }

        return .system(size: size, weight: bold ? .bold : .regular)
    }
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
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let fill = primary
            ? (configuration.isPressed ? IBA.accentHover : IBA.accent)
            : (configuration.isPressed ? IBA.surfaceHover : IBA.surface)
        configuration.label
            .font(IBA.font(13, .bold))
            .foregroundColor(primary ? Color.white : IBA.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(primary ? IBA.accent : IBA.border, lineWidth: 1))
            // Visible keyboard focus: an Ink ring outside the button.
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(IBA.ink, lineWidth: 2).padding(-3).opacity(isFocused ? 1 : 0))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// IBA switch: IBA Blue when on, independent of window focus and the system accent colour.
struct IBASwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 16)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? IBA.accent : IBA.borderStrong)
                    .frame(width: 40, height: 22)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(.horizontal, 3)
            }
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(configuration.isOn ? "включено" : "выключено"))
    }
}

extension View {
    /// White surface, thin border and rounded corners: the IBA card.
    func ibaCard(radius: CGFloat = 12) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius).fill(IBA.surface))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(IBA.border, lineWidth: 1))
    }
}

/// Message shown in place of an empty list or field: what is missing and what to do about it.
struct EmptyState: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(IBA.font(13))
            .foregroundColor(IBA.muted)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
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

/// What the status card shows; re-read every second while the settings window is open.
struct StatusInfo {
    var running: Bool
    var layout: String
    var detail: String
    var problem: Bool
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let status: () -> StatusInfo
    let onChange: () -> Void
    let onClose: () -> Void
    let onFixAccess: () -> Void

    @State private var tab = 0
    @State private var exceptionsText: String
    @State private var launchAtLogin: Bool
    @State private var loginItemError: String?
    @State private var selectedApps = Set<String>()
    @State private var showPicker = false

    init(
        settings: Settings,
        status: @escaping () -> StatusInfo,
        initialTab: Int = 0,
        onChange: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onFixAccess: @escaping () -> Void = {}
    ) {
        self.settings = settings
        self.status = status
        self.onChange = onChange
        self.onClose = onClose
        self.onFixAccess = onFixAccess
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
        .font(IBA.font(13))
        .tint(IBA.accent)
        .preferredColorScheme(.light)
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
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("IBA KeyMorph").font(IBA.font(28, .bold))
                    // The orange dot of the IBA mark: the one rare accent of the window.
                    Circle().fill(IBA.orange).frame(width: 9, height: 9).accessibilityHidden(true)
                }
                Text("Переключатель раскладки клавиатуры. Автоисправление EN ⇄ RU.").foregroundColor(IBA.muted)
            }
        }
    }

    private var statusCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let info = status()
            let working = info.running && settings.enabled
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("СОСТОЯНИЕ").font(IBA.font(11, .bold)).foregroundColor(IBA.caption)
                    // Status is a word plus a dot, never the colour alone.
                    HStack(spacing: 8) {
                        Circle()
                            .fill(working ? IBA.success : (info.running ? IBA.borderStrong : IBA.warning))
                            .frame(width: 11, height: 11)
                            .accessibilityHidden(true)
                        Text(!info.running ? "Не работает" : settings.enabled ? "Работает · \(info.layout)" : "Выключено · \(info.layout)")
                            .font(IBA.font(20, .bold))
                            .foregroundColor(working ? IBA.text : IBA.muted)
                    }
                    Text((info.problem ? "⚠︎ " : "") + info.detail)
                        .foregroundColor(info.problem ? IBA.warning : IBA.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Версия \(AppResources.version)").font(IBA.font(11)).foregroundColor(IBA.muted)
                }

                Spacer(minLength: 0)
                if !info.running {
                    Button("Выдать доступ…", action: onFixAccess)
                        .buttonStyle(IBAButtonStyle(primary: true))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ibaCard()
        }
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
                Text("⚠︎ " + error).foregroundColor(IBA.warning).font(.callout)
            }

            toggle("Подробный журнал: записывать каждое слово (для поиска проблем)", \.diagnosticLog)

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
                .overlay(alignment: .center) {
                    if exceptionsText.isEmpty {
                        EmptyState("Пока пусто. Слова, которые не нужно исправлять, появятся здесь: напишите их по одному в строке "
                                   + "или отмените исправление двойным ⇧ Shift.")
                    }
                }
                .ibaCard(radius: 10)
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
                        Text(bundleId).font(IBA.font(11)).foregroundColor(IBA.muted)
                    }
                    .padding(.vertical, 2)
                    .tag(bundleId)
                }
            }
            .scrollContentBackground(.hidden)
            .background(IBA.surface)
            .overlay(alignment: .center) {
                if settings.excludedApps.isEmpty {
                    EmptyState("Исключений нет: раскладка исправляется во всех программах. Добавьте терминал, "
                               + "менеджер паролей или удалённый рабочий стол — там автоисправление мешает.")
                }
            }
            .ibaCard(radius: 10)
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
                .font(IBA.font(12))
                .foregroundColor(IBA.muted)
            Spacer()
            Button("Журнал") { Log.open() }
                .buttonStyle(IBAButtonStyle())
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
        Toggle(title, isOn: isOn)
            .toggleStyle(IBASwitchStyle())
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
            Text("Где не исправлять раскладку?").font(IBA.font(18, .bold))
            Text("Отметьте программы. Показаны открытые приложения.").foregroundColor(IBA.muted)
            TextField("Поиск программы…", text: $search)
                .textFieldStyle(.plain)
                .padding(10)
                .background(IBA.surface)
                .ibaCard(radius: 10)
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
                            Text(app.id).font(IBA.font(11)).foregroundColor(IBA.muted)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .scrollContentBackground(.hidden)
            .background(IBA.surface)
            .overlay(alignment: .center) {
                if filtered.isEmpty {
                    EmptyState(search.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "Нет открытых программ, которых ещё нет в списке исключений."
                        : "Ничего не найдено. Измените запрос.")
                }
            }
            .ibaCard(radius: 10)
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
        .font(IBA.font(13))
        .tint(IBA.accent)
        .preferredColorScheme(.light)
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
    private let status: () -> StatusInfo
    private let onChange: () -> Void
    private let onFixAccess: () -> Void

    init(
        settings: Settings,
        status: @escaping () -> StatusInfo,
        onChange: @escaping () -> Void,
        onFixAccess: @escaping () -> Void
    ) {
        self.settings = settings
        self.status = status
        self.onChange = onChange
        self.onFixAccess = onFixAccess
    }

    func show() {
        // Rebuild a closed window so the lists show words learned in the meantime.
        if let window = window, !window.isVisible {
            self.window = nil
        }

        if window == nil {
            let view = SettingsView(
                settings: settings,
                status: status,
                onChange: onChange,
                onClose: { [weak self] in self?.window?.close() },
                onFixAccess: onFixAccess)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "IBA KeyMorph — настройки"
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.backgroundColor = IBA.backgroundNS
            window.appearance = NSAppearance(named: .aqua)
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
