namespace IbaKeyMorph.UI;

/// <summary>Lets the user tick running programs to exclude, with search and icons.</summary>
internal sealed class AppPickerForm : Form
{
    private readonly HashSet<string> _alreadyExcluded;
    private readonly TextBox _search = new() { BorderStyle = BorderStyle.None, PlaceholderText = "Поиск программы…" };
    private readonly ToggleRow _background = new("Показать фоновые процессы");
    private readonly AppListView _list = new(checkBoxes: true) { MultiSelect = false };
    private readonly HashSet<string> _checked = new(StringComparer.OrdinalIgnoreCase);
    private IReadOnlyList<AppEntry> _apps = Array.Empty<AppEntry>();

    public AppPickerForm(IEnumerable<string> alreadyExcluded)
    {
        _alreadyExcluded = new HashSet<string>(alreadyExcluded, StringComparer.OrdinalIgnoreCase);
        Text = "Добавить программы";
        Icon = TrayIcons.AppIcon;
        Font = Theme.Font(9.75f);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MinimizeBox = false;
        MaximizeBox = false;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.CenterParent;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(520, 560);
        Padding = new Padding(20);
        Theme.ApplyChrome(this);

        var title = new Label
        {
            Text = "Где не исправлять раскладку?",
            AutoSize = true,
            Font = Theme.Font(14f, FontStyle.Bold),
            ForeColor = Theme.Text,
            Margin = new Padding(0, 0, 0, 4),
        };
        var subtitle = Theme.MutedText("Отметьте программы. Сейчас показаны открытые окна.", 480);

        _list.ItemChecked += (_, e) =>
        {
            if (e.Item.Tag is AppEntry app)
            {
                if (e.Item.Checked)
                {
                    _checked.Add(app.ProcessName);
                }
                else
                {
                    _checked.Remove(app.ProcessName);
                }
            }

            UpdateAddButton();
        };
        _list.MouseClick += (_, e) =>
        {
            // The check box itself is toggled natively; a click anywhere else on the row toggles too.
            if (e.X > 28 && _list.GetItemAt(e.X, e.Y) is { } item)
            {
                item.Checked = !item.Checked;
            }
        };

        Theme.DarkControl(_search);
        _search.TextChanged += (_, _) => Fill();
        _background.CheckedChanged += (_, _) => Reload();

        AddButton = new IbaButton("Добавить", ButtonKind.Primary) { DialogResult = DialogResult.OK, Width = 140, Enabled = false };
        var cancel = new IbaButton("Отмена") { DialogResult = DialogResult.Cancel, Width = 120 };
        AcceptButton = AddButton;
        CancelButton = cancel;

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, BackColor = Theme.Background };
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.Controls.Add(title, 0, 0);
        layout.Controls.Add(subtitle, 0, 1);
        var searchBox = Theme.Boxed(_search, 10);
        searchBox.Dock = DockStyle.Fill;
        searchBox.Margin = new Padding(0, 12, 0, 4);
        layout.Controls.Add(searchBox, 0, 2);
        _background.AutoSize = true;
        layout.Controls.Add(_background, 0, 3);
        var listBox = Theme.Boxed(_list, 6);
        listBox.Dock = DockStyle.Fill;
        listBox.Margin = new Padding(0, 6, 0, 12);
        layout.Controls.Add(listBox, 0, 4);

        var buttons = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            BackColor = Theme.Background,
            Margin = Padding.Empty,
        };
        cancel.Margin = new Padding(8, 0, 0, 0);
        buttons.Controls.Add(cancel);
        buttons.Controls.Add(AddButton);
        layout.Controls.Add(buttons, 0, 5);
        Controls.Add(layout);

        Shown += (_, _) => Reload();
    }

    public IbaButton AddButton { get; }

    /// <summary>Picked programs (process names), in display order.</summary>
    public IReadOnlyList<AppEntry> Selected =>
        _apps.Where(a => _checked.Contains(a.ProcessName)).ToList();

    private void Reload()
    {
        Cursor = Cursors.WaitCursor;
        try
        {
            _apps = AppCatalog.Running(_background.Checked)
                .Where(a => !_alreadyExcluded.Contains(a.ProcessName))
                .ToList();
            foreach (var app in _apps)
            {
                _list.AddIcon(app.ProcessName, app.Path);
            }

            Fill();
        }
        finally
        {
            Cursor = Cursors.Default;
        }
    }

    private void Fill()
    {
        var filter = _search.Text.Trim();
        _list.BeginUpdate();
        _list.Items.Clear();
        foreach (var app in _apps)
        {
            if (filter.Length > 0 &&
                !app.DisplayName.Contains(filter, StringComparison.CurrentCultureIgnoreCase) &&
                !app.ProcessName.Contains(filter, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            _list.Items.Add(new ListViewItem(app.DisplayName, app.ProcessName)
            {
                Tag = app,
                Checked = _checked.Contains(app.ProcessName),
            });
        }

        _list.EndUpdate();
        UpdateAddButton();
    }

    private void UpdateAddButton()
    {
        AddButton.Enabled = _checked.Count > 0;
        AddButton.Text = _checked.Count > 1 ? $"Добавить ({_checked.Count})" : "Добавить";
    }
}
