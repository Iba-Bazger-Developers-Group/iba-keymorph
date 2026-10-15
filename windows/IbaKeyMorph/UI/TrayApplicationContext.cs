using Microsoft.Win32;
using IbaKeyMorph.Settings;

namespace IbaKeyMorph.UI;

internal sealed class TrayApplicationContext : ApplicationContext
{
    private readonly AppSettings _settings;
    private readonly KeyMorphService _service;
    private readonly TrayIcons _icons = new();
    private readonly NotifyIcon _tray;
    private readonly ToolStripMenuItem _enabledItem;
    private readonly ToolStripMenuItem _autoSwitchItem;
    private readonly System.Windows.Forms.Timer _layoutTimer;
    private readonly Control _invoker = new();
    private SettingsForm? _settingsForm;
    private AboutForm? _aboutForm;
    private string _shownLabel = string.Empty;
    private bool _shownActive;

    public TrayApplicationContext()
    {
        _invoker.CreateControl();
        _settings = AppSettings.Load();
        _service = new KeyMorphService(_settings, SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext());

        _enabledItem = new ToolStripMenuItem("Включено", null, (_, _) => ToggleEnabled()) { CheckOnClick = false };
        _autoSwitchItem = new ToolStripMenuItem("Автоматическое переключение", null, (_, _) => ToggleAutoSwitch());
        var menu = new ContextMenuStrip
        {
            Renderer = new DarkMenuRenderer(),
            BackColor = Theme.Surface,
            ForeColor = Theme.Text,
            Font = Theme.Font(9.75f),
            ShowImageMargin = true,
        };
        menu.Items.Add(new ToolStripMenuItem("IBA KeyMorph", Theme.Panda, (_, _) => ShowAbout()) { Font = Theme.Font(9.75f, FontStyle.Bold) });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(_enabledItem);
        menu.Items.Add(_autoSwitchItem);
        menu.Items.Add(new ToolStripMenuItem("Исправить выделенный текст", null, (_, _) => ConvertSelectionFromMenu())
        {
            ShortcutKeyDisplayString = "Shift+Pause",
        });
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Настройки…", null, (_, _) => ShowSettings()));
        menu.Items.Add(new ToolStripMenuItem("О программе", null, (_, _) => ShowAbout()));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(new ToolStripMenuItem("Выход", null, (_, _) => ExitThread()));
        menu.Opening += (_, _) => RefreshMenu();

        _tray = new NotifyIcon
        {
            Icon = TrayIcons.AppIcon,
            Text = "IBA KeyMorph",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _tray.DoubleClick += (_, _) => ShowSettings();
        StartService(restart: false);

        _layoutTimer = new System.Windows.Forms.Timer { Interval = 300 };
        _layoutTimer.Tick += (_, _) => RefreshTrayIcon();
        _layoutTimer.Start();

        SystemEvents.PowerModeChanged += OnPowerModeChanged;
        SystemEvents.SessionSwitch += OnSessionSwitch;

        if (_settings.FirstRun)
        {
            _settings.FirstRun = false;
            _settings.Save();
            _tray.ShowBalloonTip(
                5000,
                "IBA KeyMorph работает",
                "Печатайте как обычно — раскладка исправится сама. Pause или двойной Shift отменяют исправление.",
                ToolTipIcon.Info);
        }

        RefreshTrayIcon();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            SystemEvents.SessionSwitch -= OnSessionSwitch;
            _layoutTimer.Dispose();
            _service.Dispose();
            _tray.Visible = false;
            _tray.Dispose();
            _icons.Dispose();
            _invoker.Dispose();
        }

        base.Dispose(disposing);
    }

    private void StartService(bool restart)
    {
        try
        {
            if (restart)
            {
                _service.Restart();
            }
            else
            {
                _service.Start();
            }
        }
        catch (InvalidOperationException ex)
        {
            // Keep running in the tray; resume/unlock retries the hooks.
            Log.Error("Keyboard hooks could not be installed", ex);
            _tray.ShowBalloonTip(
                5000,
                "IBA KeyMorph",
                "Не удалось подключиться к клавиатуре. Перезапустите программу или войдите в систему заново.",
                ToolTipIcon.Warning);
        }
    }

    private void RefreshTrayIcon()
    {
        string label;
        try
        {
            label = _service.CurrentLayout().ShortName;
        }
        catch (Exception ex)
        {
            Log.Error("Could not read current layout", ex);
            return;
        }

        if (label == _shownLabel && _settings.Enabled == _shownActive)
        {
            return;
        }

        _shownLabel = label;
        _shownActive = _settings.Enabled;
        _tray.Icon = _icons.For(label, _settings.Enabled);
        _tray.Text = _settings.Enabled ? $"IBA KeyMorph — {label}" : $"IBA KeyMorph — выключен ({label})";
    }

    private void RefreshMenu()
    {
        _enabledItem.Checked = _settings.Enabled;
        _autoSwitchItem.Checked = _settings.AutoSwitch;
        _autoSwitchItem.Enabled = _settings.Enabled;
    }

    private void ToggleEnabled()
    {
        _settings.Enabled = !_settings.Enabled;
        _settings.Save();
        _service.ApplySettings();
        RefreshTrayIcon();
    }

    private void ToggleAutoSwitch()
    {
        _settings.AutoSwitch = !_settings.AutoSwitch;
        _settings.Save();
        _service.ApplySettings();
    }

    private async void ConvertSelectionFromMenu()
    {
        // The menu took focus; give it back to the previous window before copying.
        await Task.Delay(250);
        await _service.ConvertSelectionAsync();
    }

    private void ShowSettings()
    {
        if (_settingsForm is { IsDisposed: false })
        {
            _settingsForm.Activate();
            return;
        }

        _settingsForm = new SettingsForm(_settings, _service);
        _settingsForm.FormClosed += (_, _) =>
        {
            _service.ApplySettings();
            _settingsForm = null;
        };
        _settingsForm.Show();
        _settingsForm.Activate();
    }

    private void ShowAbout()
    {
        if (_aboutForm is { IsDisposed: false })
        {
            _aboutForm.Activate();
            return;
        }

        _aboutForm = new AboutForm();
        _aboutForm.FormClosed += (_, _) => _aboutForm = null;
        _aboutForm.Show();
        _aboutForm.Activate();
    }

    private void OnPowerModeChanged(object? sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode == PowerModes.Resume)
        {
            _invoker.BeginInvoke(() => StartService(restart: true));
        }
    }

    private void OnSessionSwitch(object? sender, SessionSwitchEventArgs e)
    {
        if (e.Reason is SessionSwitchReason.SessionUnlock or SessionSwitchReason.ConsoleConnect or SessionSwitchReason.RemoteConnect)
        {
            _invoker.BeginInvoke(() => StartService(restart: true));
        }
    }
}
