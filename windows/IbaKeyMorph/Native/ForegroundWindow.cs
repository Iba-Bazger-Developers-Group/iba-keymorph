using System.Security.Principal;
using static IbaKeyMorph.Native.NativeMethods;

namespace IbaKeyMorph.Native;

/// <summary>Facts about the foreground window that decide whether KeyMorph may touch its text.</summary>
internal sealed class ForegroundWindow
{
    private static readonly bool SelfElevated = IsCurrentProcessElevated();

    private readonly Dictionary<uint, (string Name, bool Elevated)> _processes = new();

    public IntPtr Handle { get; private set; }

    public string ProcessName { get; private set; } = string.Empty;

    /// <summary>
    /// The window belongs to an elevated (or inaccessible) process while KeyMorph is not elevated:
    /// Windows would silently drop our synthetic input, so we must never swallow keys there.
    /// </summary>
    public bool Unreachable { get; private set; }

    /// <summary>Forces the next <see cref="Update"/> to report a change (e.g. after settings changed).</summary>
    public void Invalidate() => Handle = IntPtr.Zero;

    /// <summary>Re-reads the foreground window; returns true if it changed.</summary>
    public bool Update()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == Handle)
        {
            return false;
        }

        Handle = hwnd;
        GetWindowThreadProcessId(hwnd, out var pid);
        if (!_processes.TryGetValue(pid, out var info))
        {
            info = Inspect(pid);
            if (_processes.Count > 256)
            {
                _processes.Clear();
            }

            _processes[pid] = info;
        }

        ProcessName = info.Name;
        Unreachable = info.Elevated && !SelfElevated;
        return true;
    }

    /// <summary>True when the focused control is a classic password edit box.</summary>
    public bool IsPasswordFieldFocused()
    {
        var thread = GetWindowThreadProcessId(Handle, out _);
        var info = new GUITHREADINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<GUITHREADINFO>() };
        if (!GetGUIThreadInfo(thread, ref info) || info.hwndFocus == IntPtr.Zero)
        {
            return false;
        }

        var className = new char[64];
        var length = GetClassName(info.hwndFocus, className, className.Length);
        var name = new string(className, 0, Math.Max(length, 0));
        if (!name.Equals("Edit", StringComparison.OrdinalIgnoreCase) &&
            !name.StartsWith("WindowsForms10.EDIT", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        return ((long)GetWindowLongPtr(info.hwndFocus, GWL_STYLE) & ES_PASSWORD) != 0;
    }

    private static (string Name, bool Elevated) Inspect(uint pid)
    {
        var process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (process == IntPtr.Zero)
        {
            // Protected or system process: treat as unreachable.
            return (string.Empty, true);
        }

        try
        {
            var path = QueryImagePath(process);
            var name = path is null ? string.Empty : Path.GetFileNameWithoutExtension(path);
            return (name.ToLowerInvariant(), IsElevated(process));
        }
        finally
        {
            CloseHandle(process);
        }
    }

    private static bool IsElevated(IntPtr process)
    {
        if (!OpenProcessToken(process, TOKEN_QUERY, out var token))
        {
            return true;
        }

        try
        {
            return GetTokenInformation(token, TokenElevation, out var elevated, sizeof(int), out _) && elevated != 0;
        }
        finally
        {
            CloseHandle(token);
        }
    }

    private static bool IsCurrentProcessElevated()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }
}
