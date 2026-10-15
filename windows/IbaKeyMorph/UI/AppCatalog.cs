using System.Diagnostics;
using IbaKeyMorph.Native;

namespace IbaKeyMorph.UI;

/// <summary>A program as shown in the exclusion list: process name (the stored key) plus display info.</summary>
internal sealed record AppEntry(string ProcessName, string DisplayName, string? Path);

/// <summary>Finds running programs and describes them with friendly names and icons.</summary>
internal static class AppCatalog
{
    private static readonly Dictionary<string, string> KnownNames = new(StringComparer.OrdinalIgnoreCase)
    {
        ["windowsterminal"] = "Windows Terminal",
        ["putty"] = "PuTTY",
        ["mstsc"] = "Подключение к удалённому рабочему столу",
        ["vmconnect"] = "Hyper-V: подключение к виртуальной машине",
        ["keepass"] = "KeePass",
        ["keepassxc"] = "KeePassXC",
        ["1password"] = "1Password",
        ["bitwarden"] = "Bitwarden",
        ["cmd"] = "Командная строка",
        ["powershell"] = "Windows PowerShell",
        ["pwsh"] = "PowerShell",
    };

    // Shell hosts whose windows belong to other apps; excluding them would not do what the user expects.
    private static readonly HashSet<string> Hidden = new(StringComparer.OrdinalIgnoreCase)
    {
        "applicationframehost", "textinputhost", "shellexperiencehost", "startmenuexperiencehost",
        "searchhost", "searchapp", "lockapp", "systemsettingsbroker", "ibakeymorph",
    };

    /// <summary>
    /// Running programs, one entry per process name. By default only those with a visible top-level
    /// window (what the user thinks of as "open programs").
    /// </summary>
    public static IReadOnlyList<AppEntry> Running(bool includeBackground)
    {
        var windowed = includeBackground ? null : ProcessesWithWindows();
        var entries = new Dictionary<string, AppEntry>(StringComparer.OrdinalIgnoreCase);
        var sessionId = Process.GetCurrentProcess().SessionId;

        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    var name = process.ProcessName;
                    if (process.SessionId != sessionId || Hidden.Contains(name) || entries.ContainsKey(name) ||
                        (windowed is not null && !windowed.Contains((uint)process.Id)))
                    {
                        continue;
                    }

                    var path = NativeMethods.QueryImagePath((uint)process.Id);
                    entries[name] = new AppEntry(name.ToLowerInvariant(), DisplayNameFor(name, path), path);
                }
                catch (InvalidOperationException)
                {
                    // The process exited while we were looking at it.
                }
            }
        }

        return entries.Values
            .OrderBy(e => e.DisplayName, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    /// <summary>Describes a stored process name, using a running instance for the path when there is one.</summary>
    public static AppEntry Describe(string processName, IReadOnlyDictionary<string, AppEntry> running) =>
        running.TryGetValue(processName, out var entry)
            ? entry with { ProcessName = processName }
            : new AppEntry(processName, DisplayNameFor(processName, null), null);

    public static AppEntry FromFile(string exePath)
    {
        var name = System.IO.Path.GetFileNameWithoutExtension(exePath);
        return new AppEntry(name.ToLowerInvariant(), DisplayNameFor(name, exePath), exePath);
    }

    /// <summary>Icon of the executable, or the generic application icon.</summary>
    public static Icon IconFor(string? path)
    {
        if (path is not null)
        {
            try
            {
                var icon = Icon.ExtractAssociatedIcon(path);
                if (icon is not null)
                {
                    return icon;
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
            {
                // Fall back to the generic icon.
            }
        }

        return (Icon)SystemIcons.Application.Clone();
    }

    private static string DisplayNameFor(string processName, string? path)
    {
        if (path is not null)
        {
            try
            {
                var description = FileVersionInfo.GetVersionInfo(path).FileDescription?.Trim();
                if (!string.IsNullOrEmpty(description))
                {
                    return description;
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException)
            {
                // Fall back to the known names or the process name.
            }
        }

        return KnownNames.TryGetValue(processName, out var known) ? known : processName;
    }

    /// <summary>Process ids that own a visible, unowned, titled top-level window.</summary>
    private static HashSet<uint> ProcessesWithWindows()
    {
        var ids = new HashSet<uint>();
        NativeMethods.EnumWindows(
            (hwnd, _) =>
            {
                if (NativeMethods.IsWindowVisible(hwnd) &&
                    NativeMethods.GetWindow(hwnd, NativeMethods.GW_OWNER) == IntPtr.Zero &&
                    NativeMethods.GetWindowTextLength(hwnd) > 0)
                {
                    NativeMethods.GetWindowThreadProcessId(hwnd, out var pid);
                    ids.Add(pid);
                }

                return true;
            },
            IntPtr.Zero);
        return ids;
    }
}
