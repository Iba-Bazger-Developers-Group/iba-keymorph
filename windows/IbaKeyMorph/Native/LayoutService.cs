using IbaKeyMorph.Core;
using static IbaKeyMorph.Native.NativeMethods;

namespace IbaKeyMorph.Native;

/// <summary>Installed layouts, the layout of the focused window and switching between them.</summary>
internal sealed class LayoutService
{
    private readonly Dictionary<IntPtr, WindowsLayout> _known = new();
    private IReadOnlyList<WindowsLayout> _installed = Array.Empty<WindowsLayout>();
    private long _refreshedAt = long.MinValue;

    public IReadOnlyList<WindowsLayout> Installed
    {
        get
        {
            var now = Environment.TickCount64;
            if (now - _refreshedAt > 2000)
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
        if (layout is WindowsLayout target && foregroundWindow != IntPtr.Zero)
        {
            PostMessage(foregroundWindow, WM_INPUTLANGCHANGEREQUEST, IntPtr.Zero, target.Handle);
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
