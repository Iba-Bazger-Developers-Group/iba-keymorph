using System.Diagnostics;
using System.Media;
using IbaKeyMorph.Core;
using IbaKeyMorph.Native;
using IbaKeyMorph.Settings;
using static IbaKeyMorph.Native.NativeMethods;

namespace IbaKeyMorph;

/// <summary>
/// Glue between the global hooks, the platform-independent <see cref="TypingEngine"/> and Windows:
/// turns keystrokes into engine calls and engine actions into synthetic input.
/// </summary>
internal sealed class KeyMorphService : IDisposable
{
    private const int ShiftTapKey = 1;

    private readonly AppSettings _settings;
    private readonly SynchronizationContext _ui;
    private readonly LowLevelHooks _hooks;
    private readonly LayoutService _layouts = new();
    private readonly ForegroundWindow _foreground = new();
    private readonly DoubleTapDetector _doubleShift = new();
    private readonly HashSet<int> _swallowedKeyUps = new();
    private readonly EngineOptions _engineOptions = new();
    private readonly TypingEngine _engine;
    private readonly SoundPlayer? _sound;
    private readonly System.Windows.Forms.Timer _watchdog = new() { Interval = 2000 };
    private long _lastWatchdogLog = long.MinValue;
    private bool _capsOn;
    private bool _capsDown;
    private bool _excluded;
    private bool _busy;

    public KeyMorphService(AppSettings settings, SynchronizationContext ui)
    {
        _settings = settings;
        _ui = ui;
        _engine = new TypingEngine(new LayoutDecider(word => _settings.Exceptions.Contains(word)), _engineOptions);
        _hooks = new LowLevelHooks(OnKey, OnMouseDown, ex => Log.Error("Hook callback failed", ex));
        _capsOn = (GetKeyState(VK_CAPITAL) & 1) != 0;
        _sound = LoadSound();
        _watchdog.Tick += (_, _) => CheckHooks();
        ApplySettings();
    }

    public LayoutService Layouts => _layouts;

    public void Start()
    {
        WarmUp();
        _watchdog.Start(); // also retries if the first install fails
        _hooks.Install();
    }

    /// <summary>Hooks can be dropped by Windows after sleep or session switches; re-installing is cheap.</summary>
    public void Restart()
    {
        _engine.Reset();
        _hooks.Install();
    }

    public void ApplySettings()
    {
        _engineOptions.AutoSwitch = _settings.AutoSwitch;
        _engineOptions.FixCapsLock = _settings.FixCapsLock;
        _engineOptions.CorrectPreviousShortWord = _settings.CorrectPreviousShortWord;
        _engine.Reset();
        _foreground.Invalidate();
    }

    public WindowsLayout CurrentLayout() => _layouts.Current(GetForegroundWindow());

    public async Task ConvertSelectionAsync()
    {
        if (_busy)
        {
            return;
        }

        _busy = true;
        try
        {
            _engine.Reset();
            var foreground = GetForegroundWindow();
            var target = await SelectionConverter.ConvertAsync(_layouts.Installed);
            if (target is not null)
            {
                _layouts.Switch(target, foreground);
                PlaySwitchSound();
            }
        }
        catch (Exception ex)
        {
            Log.Error("Selection conversion failed", ex);
        }
        finally
        {
            _busy = false;
        }
    }

    public void Dispose()
    {
        _watchdog.Dispose();
        _hooks.Dispose();
        _sound?.Dispose();
    }

    /// <summary>Windows silently drops a hook whose callback is slow once; pay model load + JIT up front.</summary>
    private void WarmUp()
    {
        var timer = Stopwatch.StartNew();
        var english = BuiltInLayouts.English;
        IKeyboardLayout[] builtIn = { english, BuiltInLayouts.Russian };
        var probe = new TypingEngine(new LayoutDecider(word => _settings.Exceptions.Contains(word)), new EngineOptions());
        foreach (var c in "z ghbdtn ")
        {
            if (c == ' ')
            {
                probe.OnBoundary(BoundaryKind.Space, builtIn);
            }
            else
            {
                probe.OnCharacterKey(english.Find(c)!.Value, english);
            }
        }

        probe.ConvertLastWord(builtIn);
        probe.OnCharacterKey(english.Find('x')!.Value, english);
        probe.OnBackspace();
        TextConverter.PickConversion("ghbdtn", builtIn);

        var installed = _layouts.Installed;
        foreach (var layout in installed)
        {
            foreach (var code in layout.PrintableKeyCodes)
            {
                layout.Render(new KeyStroke(code, false, false));
                layout.Render(new KeyStroke(code, true, false));
            }
        }

        new ForegroundWindow().Update();
        _ = _layouts.Current(GetForegroundWindow());
        _ = new InputSender().Backspace(1).Text("x");

        Log.Info($"Started in {timer.ElapsedMilliseconds} ms; layouts: " +
                 string.Join(", ", installed.Select(l => $"{l.ShortName} {l.Id} {(l.Language is null ? "(no dictionary)" : l.Language.Code)}")));
        if (installed.Count(l => l.Language is not null) < 2)
        {
            Log.Info("Automatic correction needs both an English and a Russian layout to be installed.");
        }
    }

    private void CheckHooks()
    {
        if (!_hooks.LooksRemoved())
        {
            return;
        }

        try
        {
            _engine.Reset();
            _hooks.Install();
            var now = Environment.TickCount64;
            if (now - _lastWatchdogLog > 600_000)
            {
                _lastWatchdogLog = now;
                Log.Info("Keyboard hook stopped receiving input (removed by Windows?); reinstalled");
            }
        }
        catch (InvalidOperationException ex)
        {
            Log.Error("Could not reinstall keyboard hook", ex);
        }
    }

    private bool OnKey(KeyboardEvent e)
    {
        if (e.IsInjected)
        {
            if (e.ExtraInfo != InputSender.Marker)
            {
                // Another program is typing (remote control, macros): our picture of the text is stale.
                _engine.Reset();
                TrackCapsLock(e);
            }

            return false;
        }

        if (!e.IsDown)
        {
            return OnKeyUp(e);
        }

        TrackCapsLock(e);
        if (!_settings.Enabled || _busy)
        {
            return false;
        }

        if (_foreground.Update())
        {
            _engine.Reset();
            _excluded = _foreground.Unreachable || _settings.ExcludedApps.Contains(_foreground.ProcessName);
        }

        var vk = e.VirtualKey;
        if (vk is VK_SHIFT or VK_LSHIFT or VK_RSHIFT)
        {
            // Alt+Shift / Ctrl+Shift are layout-switch chords, not taps.
            if (IsKeyDown(VK_CONTROL) || IsKeyDown(VK_MENU) || IsKeyDown(VK_LWIN) || IsKeyDown(VK_RWIN))
            {
                _doubleShift.Reset();
            }
            else
            {
                _doubleShift.KeyDown(ShiftTapKey, Environment.TickCount64);
            }

            return false;
        }

        _doubleShift.Reset();

        if (vk == VK_PAUSE && _settings.PauseHotkeys)
        {
            return OnPause();
        }

        if (vk is VK_CAPITAL or VK_LCONTROL or VK_RCONTROL or VK_CONTROL or VK_LMENU or VK_RMENU or VK_MENU or VK_LWIN or VK_RWIN)
        {
            return false;
        }

        if (IsKeyDown(VK_CONTROL) || IsKeyDown(VK_MENU) || IsKeyDown(VK_LWIN) || IsKeyDown(VK_RWIN))
        {
            // Shortcuts (and AltGr) do not type into the current word.
            _engine.Reset();
            return false;
        }

        if (_excluded)
        {
            return false;
        }

        switch (vk)
        {
            case VK_SPACE:
                return OnBoundary(BoundaryKind.Space, e);
            case VK_RETURN:
                return OnBoundary(BoundaryKind.Enter, e);
            case VK_TAB:
                return OnBoundary(BoundaryKind.Tab, e);
            case VK_BACK:
                _engine.OnBackspace();
                return false;
        }

        if (!WindowsLayout.IsPrintable(e.ScanCode, e.IsExtended))
        {
            _engine.Reset();
            return false;
        }

        var layout = _layouts.Current(_foreground.Handle);
        var key = new KeyStroke(e.ScanCode, IsKeyDown(VK_SHIFT), _capsOn);
        if (layout.Render(key).Length == 0)
        {
            _engine.Reset();
            return false;
        }

        _engine.OnCharacterKey(key, layout);
        return false;
    }

    private bool OnKeyUp(KeyboardEvent e)
    {
        if (e.VirtualKey == VK_CAPITAL)
        {
            _capsDown = false;
        }

        if (_swallowedKeyUps.Remove(e.VirtualKey))
        {
            return true;
        }

        if (_settings.Enabled && _settings.DoubleShiftHotkey && !_busy &&
            e.VirtualKey is VK_SHIFT or VK_LSHIFT or VK_RSHIFT &&
            _doubleShift.KeyUp(ShiftTapKey, Environment.TickCount64) && !_excluded)
        {
            Execute(_engine.ConvertLastWord(_layouts.Installed), null);
        }

        return false;
    }

    private bool OnPause()
    {
        _swallowedKeyUps.Add(VK_PAUSE);
        if (IsKeyDown(VK_SHIFT))
        {
            _ui.Post(_ => _ = ConvertSelectionAsync(), null);
        }
        else if (!_excluded)
        {
            Execute(_engine.ConvertLastWord(_layouts.Installed), null);
        }

        return true;
    }

    private bool OnBoundary(BoundaryKind kind, KeyboardEvent e)
    {
        var result = _engine.OnBoundary(kind, _layouts.Installed);
        if (!result.Swallow)
        {
            return false;
        }

        if (_foreground.IsPasswordFieldFocused())
        {
            _engine.Reset();
            return false;
        }

        Execute(result, e);
        _swallowedKeyUps.Add(e.VirtualKey);
        return true;
    }

    private void Execute(EngineResult result, KeyboardEvent? boundary)
    {
        var input = new InputSender();
        var switched = false;
        foreach (var action in result.Actions)
        {
            switch (action)
            {
                case EngineAction.Erase erase:
                    input.Backspace(erase.Count);
                    break;
                case EngineAction.Type type:
                    input.Text(type.Text);
                    break;
                case EngineAction.ReplayBoundary when boundary is { } b:
                    input.Key(b.VirtualKey, b.ScanCode, b.IsExtended);
                    break;
                case EngineAction.CapsLockOff when _capsOn:
                    input.Key(VK_CAPITAL, 0x3A, extended: false);
                    _capsOn = false;
                    break;
                case EngineAction.SwitchLayout switchLayout:
                    input.Flush();
                    _layouts.Switch(switchLayout.Layout, _foreground.Handle);
                    switched = true;
                    break;
                case EngineAction.LearnException learn:
                    _ui.Post(_ => Learn(learn.Word), null);
                    break;
            }
        }

        if (!input.Flush())
        {
            Log.Error("SendInput was rejected; resetting");
            _engine.Reset();
        }

        if (switched)
        {
            PlaySwitchSound();
        }
    }

    private void Learn(string word)
    {
        if (_settings.Exceptions.Add(word))
        {
            _settings.Save();
        }
    }

    private void OnMouseDown()
    {
        _engine.Reset();
        _doubleShift.Reset();
    }

    private void TrackCapsLock(KeyboardEvent e)
    {
        if (e.VirtualKey != VK_CAPITAL || !e.IsDown || _capsDown)
        {
            return;
        }

        _capsDown = !e.IsInjected;
        _capsOn = !_capsOn;
    }

    private void PlaySwitchSound()
    {
        if (_settings.PlaySound)
        {
            _sound?.Play();
        }
    }

    private static SoundPlayer? LoadSound()
    {
        var stream = typeof(KeyMorphService).Assembly.GetManifestResourceStream("IbaKeyMorph.Assets.switch.wav");
        if (stream is null)
        {
            return null;
        }

        var player = new SoundPlayer(stream);
        player.Load();
        return player;
    }
}
