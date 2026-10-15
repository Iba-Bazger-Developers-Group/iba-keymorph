using IbaKeyMorph.Core;
using static IbaKeyMorph.Native.NativeMethods;

namespace IbaKeyMorph.Native;

/// <summary>Installed layouts, the layout of the focused window and switching between them.</summary>
internal sealed class LayoutService
{
    private readonly Dictionary<IntPtr, WindowsLayout> _known = new();
    private IReadOnlyList<WindowsLayout> _installed = Array.Empty<WindowsLayout>();
    private long? _refreshedAt;

    public IReadOnlyList<WindowsLayout> Installed
    {
        get
        {
            var now = Environment.TickCount64;
            if (_refreshedAt is not { } last || now - last > 2000)
            {
                Refresh();
                _refreshedAt = now;
            }

            return _installed;
        }
    }

    /// <summary>Layout of the thread that owns the foreground window.</summary>
    public WindowsLayout Current(IntPtr foregroundWindow)
    {
        var thread = GetWindowThreadProcessId(foregroundWindow, out _);
        return Get(GetKeyboardLayout(thread));
    }

    public void Switch(IKeyboardLayout layout, IntPtr foregroundWindow)
    {
        if (layout is not WindowsLayout target || foregroundWindow == IntPtr.Zero)
        {
            return;
        }

        // The request is a "set", not a toggle, so asking both the top-level window and the control
        // with keyboard focus is safe; some frameworks only honour one of them.
        PostMessage(foregroundWindow, WM_INPUTLANGCHANGEREQUEST, IntPtr.Zero, target.Handle);
        var thread = GetWindowThreadProcessId(foregroundWindow, out _);
        var info = new GUITHREADINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<GUITHREADINFO>() };
        if (GetGUIThreadInfo(thread, ref info) && info.hwndFocus != IntPtr.Zero && info.hwndFocus != foregroundWindow)
        {
            PostMessage(info.hwndFocus, WM_INPUTLANGCHANGEREQUEST, IntPtr.Zero, target.Handle);
        }
    }

    private void Refresh()
    {
        var count = GetKeyboardLayoutList(0, null);
        var handles = new IntPtr[Math.Max(count, 0)];
        if (count > 0)
        {
            GetKeyboardLayoutList(count, handles);
        }

        _installed = handles.Select(Get).ToList();
    }

    private WindowsLayout Get(IntPtr hkl)
    {
        if (!_known.TryGetValue(hkl, out var layout))
        {
            layout = new WindowsLayout(hkl);
            _known[hkl] = layout;
        }

        return layout;
    }
}
