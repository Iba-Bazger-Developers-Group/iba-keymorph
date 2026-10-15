using IbaKeyMorph.Core;
using IbaKeyMorph.Settings;

namespace IbaKeyMorph.UI;

/// <summary>Settings window in the IBA style, built in code (no designer).</summary>
internal sealed class SettingsForm : Form
{
    private const int ContentWidth = 600;

    private readonly AppSettings _settings;
    private readonly KeyMorphService _service;
    private readonly ToggleRow _autoSwitch = new("Автоматически исправлять раскладку при наборе");
    private readonly ToggleRow _previousWord = new("Исправлять и короткое слово перед исправленным («z ns» → «я ты»)");
    private readonly ToggleRow _capsLock = new("Исправлять слова, набранные со случайным Caps Lock");
    private readonly ToggleRow _pause = new("Pause — последнее слово, Shift+Pause — выделенный текст");
    private readonly ToggleRow _doubleShift = new("Двойной Shift — исправить или отменить последнее слово");
    private readonly ToggleRow _sound = new("Звук при переключении раскладки");
    private readonly ToggleRow _autostart = new("Запускать IBA KeyMorph при входе в Windows");
    private readonly TextBox _exceptions = new()
    {
        Multiline = true,
        ScrollBars = ScrollBars.Vertical,
        AcceptsReturn = true,
        BorderStyle = BorderStyle.None,
        Font = new Font("Consolas", 10.5f),
    };

    private readonly AppListView _apps = new(checkBoxes: false) { MultiSelect = true };
    private readonly SortedDictionary<string, AppEntry> _excluded = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<(IbaButton Tab, Control Page)> _pages = new();
    private readonly IbaButton _remove = new("Удалить") { Width = 110, Enabled = false };

    public SettingsForm(AppSettings settings, KeyMorphService service)
    {
        _settings = settings;
        _service = service;
        Text = "IBA KeyMorph — настройки";
        Icon = TrayIcons.AppIcon;
        Font = Theme.Font(9.75f);
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(ContentWidth + 48, 700);
        Padding = new Padding(24, 20, 24, 20);
        Theme.ApplyChrome(this);

        var root = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, BackColor = Theme.Background };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize)); // header
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize)); // status card
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize)); // tabs
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100)); // page
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize)); // footer
        root.Controls.Add(Header(), 0, 0);
        root.Controls.Add(StatusCard(), 0, 1);
        root.Controls.Add(Tabs(), 0, 2);

        var pageHost = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Background, Margin = new Padding(0, 12, 0, 12) };
        foreach (var (_, page) in _pages)
        {
            page.Dock = DockStyle.Fill;
            pageHost.Controls.Add(page);
        }

        root.Controls.Add(pageHost, 0, 3);
        root.Controls.Add(Footer(), 0, 4);
        Controls.Add(root);

        LoadValues();
        ShowPage(0);
    }

    private Control Header()
    {
        var header = new TableLayoutPanel
        {
            ColumnCount = 2,
            RowCount = 2,
            AutoSize = true,
            Dock = DockStyle.Fill,
            BackColor = Theme.Background,
            Margin = new Padding(0, 0, 0, 16),
        };
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 92));
        header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        var logo = new PictureBox
        {
            Image = Theme.Panda,
            SizeMode = PictureBoxSizeMode.Zoom,
            Size = new Size(76, 76),
            Margin = new Padding(0, 0, 16, 0),
        };
        header.Controls.Add(logo, 0, 0);
        header.SetRowSpan(logo, 2);
        header.Controls.Add(new Label
        {
            Text = "IBA KeyMorph",
            AutoSize = true,
            Font = Theme.Font(22f, FontStyle.Bold),
            ForeColor = Theme.Text,
            Margin = new Padding(0, 6, 0, 0),
        }, 1, 0);
        header.Controls.Add(Theme.MutedText("Раскладка исправляется сама. EN ⇄ RU, Windows и macOS.", 480), 1, 1);
        return header;
    }

    private Control StatusCard()
    {
        var card = new TableLayoutPanel
        {
            ColumnCount = 1,
            AutoSize = true,
            Dock = DockStyle.Fill,
            BackColor = Theme.Surface,
            Padding = new Padding(18, 14, 18, 14),
            Margin = new Padding(0, 0, 0, 14),
        };
        card.Controls.Add(Theme.SectionCaption("Состояние"));

        var layout = SafeLayout();
        var running = _settings.Enabled;
        card.Controls.Add(new Label
        {
            Text = running ? $"Работает · {layout}" : $"Выключено · {layout}",
            AutoSize = true,
            Font = Theme.Font(16f, FontStyle.Bold),
            ForeColor = running ? Theme.Text : Theme.Muted,
            Margin = new Padding(0, 0, 0, 2),
        });

        var installed = _service.Layouts.Installed;
        var supported = installed.Where(l => l.Language is not null).Select(l => l.ShortName).Distinct().ToList();
        var version = typeof(SettingsForm).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
        var detail = supported.Count >= 2
            ? $"Версия {version} · раскладки: {string.Join(", ", installed.Select(l => l.ShortName).Distinct())}"
            : $"Версия {version} · для автоисправления нужны раскладки EN и RU";
        card.Controls.Add(new Label
        {
            Text = detail,
            AutoSize = true,
            ForeColor = supported.Count >= 2 ? Theme.Muted : Theme.Caption,
            Font = Theme.Font(9.5f),
        });
        return card;
    }

    private Control Tabs()
    {
        var tabs = new FlowLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            BackColor = Theme.Background,
            Margin = Padding.Empty,
            WrapContents = false,
        };
        AddPage(tabs, "Основные", GeneralPage());
        AddPage(tabs, "Исключения", ExceptionsPage());
        AddPage(tabs, "Программы", ProgramsPage());
        return tabs;
    }

    private void AddPage(FlowLayoutPanel tabs, string title, Control page)
    {
        var index = _pages.Count;
        var tab = new IbaButton(title, ButtonKind.Tab) { Width = 150, Margin = new Padding(0, 0, 10, 0) };
        tab.Click += (_, _) => ShowPage(index);
        tabs.Controls.Add(tab);
        _pages.Add((tab, page));
    }

    internal void ShowPage(int index)
    {
        for (var i = 0; i < _pages.Count; i++)
        {
            _pages[i].Tab.Selected = i == index;
            _pages[i].Page.Visible = i == index;
        }
    }

    private Control GeneralPage()
    {
        var panel = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoScroll = true,
            BackColor = Theme.Background,
            Padding = new Padding(0, 6, 0, 0),
        };
        foreach (var toggle in new[] { _autoSwitch, _previousWord, _capsLock, _pause, _doubleShift, _sound, _autostart })
        {
            toggle.Size = new Size(ContentWidth - 8, toggle.GetPreferredSize(Size.Empty).Height);
            panel.Controls.Add(toggle);
        }

        var hint = Theme.MutedText(
            "Ошиблись с исправлением? Сразу нажмите Pause или дважды Shift — слово вернётся и больше не будет исправляться.",
            ContentWidth);
        hint.Margin = new Padding(0, 14, 0, 0);
        panel.Controls.Add(hint);
        return panel;
    }

    private Control ExceptionsPage()
    {
        var page = Column();
        page.Controls.Add(Theme.MutedText(
            "Слова, которые никогда не исправляются, по одному в строке. Слово попадает сюда само, если отменить исправление.",
            ContentWidth), 0, 0);
        Theme.DarkControl(_exceptions);
        var box = Theme.Boxed(_exceptions, 10);
        box.Dock = DockStyle.Fill;
        box.Margin = new Padding(0, 10, 0, 0);
        page.Controls.Add(box, 0, 1);
        return page;
    }

    private Control ProgramsPage()
    {
        var page = Column();
        page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        page.Controls.Add(Theme.MutedText(
            "В этих программах раскладка не исправляется автоматически. В окна программ, запущенных от имени " +
            "администратора, KeyMorph не вмешивается.",
            ContentWidth), 0, 0);

        _apps.SelectedIndexChanged += (_, _) => _remove.Enabled = _apps.SelectedItems.Count > 0;
        _apps.KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Delete)
            {
                RemoveSelectedApps();
            }
        };
        var box = Theme.Boxed(_apps, 6);
        box.Dock = DockStyle.Fill;
        box.Margin = new Padding(0, 10, 0, 10);
        page.Controls.Add(box, 0, 1);

        var addRunning = new IbaButton("Добавить из запущенных…", ButtonKind.Primary) { Width = 230 };
        var addFile = new IbaButton("Выбрать .exe…") { Width = 150 };
        addRunning.Click += (_, _) => AddFromRunning();
        addFile.Click += (_, _) => AddFromFile();
        _remove.Click += (_, _) => RemoveSelectedApps();
        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, BackColor = Theme.Background, WrapContents = false };
        addRunning.Margin = addFile.Margin = new Padding(0, 0, 10, 0);
        buttons.Controls.AddRange(new Control[] { addRunning, addFile, _remove });
        page.Controls.Add(buttons, 0, 2);
        return page;
    }

    private static TableLayoutPanel Column()
    {
        var page = new TableLayoutPanel { ColumnCount = 1, BackColor = Theme.Background, Padding = new Padding(0, 6, 0, 0) };
        page.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        page.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        return page;
    }

    private Control Footer()
    {
        var footer = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Dock = DockStyle.Fill, BackColor = Theme.Background };
        footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        footer.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        var hint = Theme.MutedText("Pause, Shift Shift — слово · Shift+Pause — выделение", 360);
        hint.Anchor = AnchorStyles.Left;
        footer.Controls.Add(hint, 0, 0);

        var save = new IbaButton("Сохранить", ButtonKind.Primary) { Width = 140 };
        var cancel = new IbaButton("Отмена") { Width = 120, DialogResult = DialogResult.Cancel };
        save.Click += (_, _) => SaveAndClose();
        AcceptButton = save;
        CancelButton = cancel;
        var buttons = new FlowLayoutPanel { AutoSize = true, BackColor = Theme.Background, WrapContents = false, Margin = Padding.Empty };
        cancel.Margin = new Padding(10, 0, 0, 0);
        save.Margin = Padding.Empty;
        buttons.Controls.Add(save);
        buttons.Controls.Add(cancel);
        footer.Controls.Add(buttons, 1, 0);
        return footer;
    }

    private string SafeLayout()
    {
        try
        {
            return _service.CurrentLayout().ShortName;
        }
        catch (Exception ex)
        {
            Log.Error("Could not read current layout", ex);
            return "?";
        }
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

        var running = AppCatalog.Running(includeBackground: true).ToDictionary(a => a.ProcessName, StringComparer.OrdinalIgnoreCase);
        foreach (var name in _settings.ExcludedApps)
        {
            _excluded[name] = AppCatalog.Describe(name, running);
        }

        FillApps();
    }

    private void FillApps()
    {
        _apps.BeginUpdate();
        _apps.Items.Clear();
        foreach (var app in _excluded.Values.OrderBy(a => a.DisplayName, StringComparer.CurrentCultureIgnoreCase))
        {
            _apps.AddIcon(app.ProcessName, app.Path);
            _apps.Items.Add(new ListViewItem(app.DisplayName, app.ProcessName) { Tag = app });
        }

        _apps.EndUpdate();
        _remove.Enabled = false;
    }

    private void AddFromRunning()
    {
        using var picker = new AppPickerForm(_excluded.Keys);
        if (picker.ShowDialog(this) != DialogResult.OK)
        {
            return;
        }

        foreach (var app in picker.Selected)
        {
            _excluded[app.ProcessName] = app;
        }

        FillApps();
    }

    private void AddFromFile()
    {
        using var dialog = new OpenFileDialog
        {
            Title = "Выберите программу",
            Filter = "Программы (*.exe)|*.exe",
            InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
        };
        if (dialog.ShowDialog(this) != DialogResult.OK)
        {
            return;
        }

        var app = AppCatalog.FromFile(dialog.FileName);
        _excluded[app.ProcessName] = app;
        FillApps();
    }

    private void RemoveSelectedApps()
    {
        foreach (ListViewItem item in _apps.SelectedItems)
        {
            if (item.Tag is AppEntry app)
            {
                _excluded.Remove(app.ProcessName);
            }
        }

        FillApps();
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
            _exceptions.Text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(LanguageModel.Normalize),
            StringComparer.Ordinal);
        _settings.ExcludedApps = new SortedSet<string>(_excluded.Keys, StringComparer.OrdinalIgnoreCase);
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

        DialogResult = DialogResult.OK;
        Close();
    }
}
