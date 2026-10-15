using System.Runtime.InteropServices;
using static IbaKeyMorph.Native.NativeMethods;

namespace IbaKeyMorph.Native;

internal readonly record struct KeyboardEvent(int VirtualKey, int ScanCode, bool IsDown, bool IsExtended, bool IsInjected, nuint ExtraInfo);

/// <summary>
/// Global WH_KEYBOARD_LL / WH_MOUSE_LL hooks. Callbacks run on the thread that installed the hooks
/// (the UI thread, which pumps messages) and must return quickly.
/// </summary>
internal sealed class LowLevelHooks : IDisposable
{
    private readonly HookProc _keyboardProc;
    private readonly HookProc _mouseProc;
    private readonly Func<KeyboardEvent, bool> _onKey;
    private readonly Action _onMouseDown;
    private readonly Action<Exception> _onError;
    private IntPtr _keyboardHook;
    private IntPtr _mouseHook;
    private int _lastCallbackTick = Environment.TickCount;

    /// <param name="onKey">Returns true to swallow the key.</param>
    public LowLevelHooks(Func<KeyboardEvent, bool> onKey, Action onMouseDown, Action<Exception> onError)
    {
        _onKey = onKey;
        _onMouseDown = onMouseDown;
        _onError = onError;
        // Delegates are kept in fields so the GC does not collect them while Windows holds pointers.
        _keyboardProc = KeyboardCallback;
        _mouseProc = MouseCallback;
    }

    public void Install()
    {
        Uninstall();
        var module = GetModuleHandle(null);
        _keyboardHook = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardProc, module, 0);
        if (_keyboardHook == IntPtr.Zero)
        {
            throw new InvalidOperationException($"SetWindowsHookEx(WH_KEYBOARD_LL) failed: {Marshal.GetLastWin32Error()}");
        }

        _mouseHook = SetWindowsHookEx(WH_MOUSE_LL, _mouseProc, module, 0);
        _lastCallbackTick = Environment.TickCount;
    }

    /// <summary>
    /// Windows unhooks a low-level hook without notice (after a timeout, sometimes after sleep). If the
    /// session saw input that our hooks did not, they are gone.
    /// </summary>
    public bool LooksRemoved()
    {
        if (_keyboardHook == IntPtr.Zero)
        {
            return true;
        }

        var info = new LASTINPUTINFO { cbSize = (uint)Marshal.SizeOf<LASTINPUTINFO>() };
        if (!GetLastInputInfo(ref info))
        {
            return false;
        }

        var missedFor = unchecked((int)(info.dwTime - (uint)_lastCallbackTick));
        return missedFor > 1500;
    }

    public void Uninstall()
    {
        if (_keyboardHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_keyboardHook);
            _keyboardHook = IntPtr.Zero;
        }

        if (_mouseHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_mouseHook);
            _mouseHook = IntPtr.Zero;
        }
    }

    public void Dispose() => Uninstall();

    private IntPtr KeyboardCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        _lastCallbackTick = Environment.TickCount;
        if (nCode >= 0)
        {
            try
            {
                var data = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
                var message = (int)wParam;
                var isDown = message is WM_KEYDOWN or WM_SYSKEYDOWN;
                var e = new KeyboardEvent(
                    (int)data.vkCode,
                    (int)data.scanCode,
                    isDown,
                    (data.flags & LLKHF_EXTENDED) != 0,
                    (data.flags & LLKHF_INJECTED) != 0,
                    data.dwExtraInfo);
                if (_onKey(e))
                {
                    return 1;
                }
            }
            catch (Exception ex)
            {
                _onError(ex);
            }
        }

        return CallNextHookEx(_keyboardHook, nCode, wParam, lParam);
    }

    private IntPtr MouseCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        _lastCallbackTick = Environment.TickCount;
        if (nCode >= 0 && (int)wParam is WM_LBUTTONDOWN or WM_RBUTTONDOWN or WM_MBUTTONDOWN or WM_XBUTTONDOWN)
        {
            try
            {
                _onMouseDown();
            }
            catch (Exception ex)
            {
                _onError(ex);
            }
        }

        return CallNextHookEx(_mouseHook, nCode, wParam, lParam);
    }
}
