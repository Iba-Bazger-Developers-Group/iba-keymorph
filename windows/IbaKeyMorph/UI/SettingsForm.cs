using IbaKeyMorph.Core;
using IbaKeyMorph.Settings;

namespace IbaKeyMorph.UI;

/// <summary>Settings window, built in code to keep the project designer-free.</summary>
internal sealed class SettingsForm : Form
{
    private readonly AppSettings _settings;
    private readonly CheckBox _autoSwitch = Check("Автоматически исправлять раскладку при наборе");
    private readonly CheckBox _previousWord = Check("Исправлять и короткое слово перед исправленным («z ns» → «я ты»)");
    private readonly CheckBox _capsLock = Check("Исправлять слова, набранные со случайно включённым Caps Lock");
    private readonly CheckBox _pause = Check("Pause — исправить последнее слово, Shift+Pause — выделенный текст");
    private readonly CheckBox _doubleShift = Check("Двойное нажатие Shift — исправить последнее слово");
    private readonly CheckBox _sound = Check("Звук при переключении раскладки");
    private readonly CheckBox _autostart = Check("Запускать IBA KeyMorph при входе в Windows");
    private readonly TextBox _exceptions = Lines();
    private readonly TextBox _apps = Lines();

    public SettingsForm(AppSettings settings)
    {
        _settings = settings;
        Text = "IBA KeyMorph — настройки";
        Icon = TrayIcons.AppIcon;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(560, 430);
        Font = new Font("Segoe UI", 9f);

        var tabs = new TabControl { Dock = DockStyle.Fill };
        tabs.TabPages.Add(Page("Основные", General()));
        tabs.TabPages.Add(Page("Исключения", WithCaption(
            "Слова, которые никогда не исправляются (по одному в строке).\r\n" +
            "Слово добавляется сюда автоматически, если отменить исправление клавишей Pause или двойным Shift.",
            _exceptions)));
        tabs.TabPages.Add(Page("Программы", WithCaption(
            "Программы, в которых автоисправление отключено — имя процесса без .exe (по одному в строке).\r\n" +
            "В окнах программ, запущенных от имени администратора, KeyMorph не вмешивается в ввод.",
            _apps)));

        var ok = new Button { Text = "Сохранить", DialogResult = DialogResult.OK, AutoSize = true };
        var cancel = new Button { Text = "Отмена", DialogResult = DialogResult.Cancel, AutoSize = true };
        ok.Click += (_, _) => SaveAndClose();
        AcceptButton = ok;
        CancelButton = cancel;

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            Padding = new Padding(8),
        };
        buttons.Controls.Add(cancel);
        buttons.Controls.Add(ok);

        Controls.Add(tabs);
        Controls.Add(buttons);
        LoadValues();
    }

    private static CheckBox Check(string text) => new() { Text = text, AutoSize = true, Margin = new Padding(3, 6, 3, 6) };

    private static TextBox Lines() => new()
    {
        Multiline = true,
        ScrollBars = ScrollBars.Vertical,
        Dock = DockStyle.Fill,
        AcceptsReturn = true,
        Font = new Font("Consolas", 10f),
    };

    private static TabPage Page(string title, Control content)
    {
        var page = new TabPage(title) { Padding = new Padding(10) };
        content.Dock = DockStyle.Fill;
        page.Controls.Add(content);
        return page;
    }

    private static Control WithCaption(string caption, Control body)
    {
        var layout = new TableLayoutPanel { ColumnCount = 1, RowCount = 2 };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(new Label { Text = caption, AutoSize = true, MaximumSize = new Size(520, 0), Margin = new Padding(0, 0, 0, 8) }, 0, 0);
        layout.Controls.Add(body, 0, 1);
        return layout;
    }

    private Control General()
    {
        var panel = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoScroll = true };
        panel.Controls.AddRange(new Control[] { _autoSwitch, _previousWord, _capsLock, _pause, _doubleShift, _sound, _autostart });
        panel.Controls.Add(new Label
        {
            AutoSize = true,
            MaximumSize = new Size(520, 0),
            Margin = new Padding(3, 16, 3, 3),
            ForeColor = SystemColors.GrayText,
            Text = "Если исправление было ошибочным, сразу нажмите Pause (или дважды Shift): слово вернётся " +
                   "и больше не будет исправляться.",
        });
        return panel;
    }

    private void LoadValues()
    {
        _autoSwitch.Checked = _settings.AutoSwitch;
        _previousWord.Checked = _settings.CorrectPreviousShortWord;
        _capsLock.Checked = _settings.FixCapsLock;
        _pause.Checked = _settings.PauseHotkeys;
        _doubleShift.Checked = _settings.DoubleShiftHotkey;
        _sound.Checked = _settings.PlaySound;
        _autostart.Checked = Autostart.IsEnabled;
        _exceptions.Text = string.Join(Environment.NewLine, _settings.Exceptions);
        _apps.Text = string.Join(Environment.NewLine, _settings.ExcludedApps);
    }

    private void SaveAndClose()
    {
        _settings.AutoSwitch = _autoSwitch.Checked;
        _settings.CorrectPreviousShortWord = _previousWord.Checked;
        _settings.FixCapsLock = _capsLock.Checked;
        _settings.PauseHotkeys = _pause.Checked;
        _settings.DoubleShiftHotkey = _doubleShift.Checked;
        _settings.PlaySound = _sound.Checked;
        _settings.Exceptions = new SortedSet<string>(
            SplitLines(_exceptions.Text).Select(LanguageModel.Normalize),
            StringComparer.Ordinal);
        _settings.ExcludedApps = new SortedSet<string>(
            SplitLines(_apps.Text).Select(a => a.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? a[..^4] : a),
            StringComparer.OrdinalIgnoreCase);
        _settings.Save();

        try
        {
            Autostart.Set(_autostart.Checked);
        }
        catch (Exception ex) when (ex is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            Log.Error("Could not change autostart", ex);
            MessageBox.Show(this, "Не удалось изменить автозапуск: " + ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        Close();
    }

    private static IEnumerable<string> SplitLines(string text) =>
        text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
}
