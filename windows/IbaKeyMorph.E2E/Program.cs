using System.Diagnostics;
using System.Runtime.InteropServices;

namespace IbaKeyMorph.E2E;

/// <summary>
/// End-to-end check on a real Windows desktop: starts IbaKeyMorph.exe, types into a text box with
/// synthetic hardware key presses (scan codes) and verifies the corrected text and layout.
/// Usage: IbaKeyMorph.E2E &lt;path to IbaKeyMorph.exe&gt;
/// </summary>
internal static class Program
{
    private const uint KLF_ACTIVATE = 0x1;
    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x2;
    private const uint KEYEVENTF_SCANCODE = 0x8;
    private const int VK_PAUSE = 0x13;

    private static Form _form = null!;
    private static TextBox _box = null!;
    private static IntPtr _english;
    private static IntPtr _russian;

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length != 1 || !File.Exists(args[0]))
        {
            Console.Error.WriteLine("Usage: IbaKeyMorph.E2E <path to IbaKeyMorph.exe>");
            return 2;
        }

        ApplicationConfiguration.Initialize();
        _english = LoadKeyboardLayout("00000409", KLF_ACTIVATE);
        _russian = LoadKeyboardLayout("00000419", 0);
        Console.WriteLine($"Layouts: EN={_english:X} RU={_russian:X}, installed: {string.Join(", ", InstalledLayouts().Select(h => h.ToString("X")))}");

        using var keymorph = Process.Start(new ProcessStartInfo(args[0]) { UseShellExecute = false });
        Console.WriteLine($"Started IbaKeyMorph (pid {keymorph!.Id}); waiting for it to hook the keyboard");
        Thread.Sleep(5000);
        if (keymorph.HasExited)
        {
            Console.Error.WriteLine($"IbaKeyMorph exited with code {keymorph.ExitCode}");
            return 1;
        }

        _form = new Form { Text = "KeyMorph E2E", Width = 700, Height = 220, TopMost = true, StartPosition = FormStartPosition.CenterScreen };
        _box = new TextBox { Dock = DockStyle.Fill, Multiline = true, Font = new Font("Segoe UI", 16f) };
        _form.Controls.Add(_box);
        _form.Show();
        Pump(300);
        BringToFront();

        var failures = 0;
        failures += Check("Russian typed in the English layout", _english, "ghbdtn ", "привет ", _russian);
        failures += Check("English typed in the Russian layout", _russian, "hello ", "hello ", _english);
        failures += Check("Correct English stays", _english, "hello world ", "hello world ", _english);
        failures += Check("Correct Russian stays", _russian, "ghbdtn ", "привет ", _russian);
        failures += CheckUndo();

        keymorph.Kill();
        Console.WriteLine(failures == 0 ? "E2E: all checks passed" : $"E2E: {failures} check(s) failed");
        return failures == 0 ? 0 : 1;
    }

    /// <summary>
    /// Types <paramref name="keys"/> as US-keyboard positions while <paramref name="layout"/> is active.
    /// </summary>
    private static int Check(string name, IntPtr layout, string keys, string expected, IntPtr expectedLayout)
    {
        Reset(layout);
        TypeKeys(keys, _english);
        var ok = WaitFor(() => _box.Text == expected && CurrentLayout() == expectedLayout, 4000);
        Console.WriteLine($"{(ok ? "PASS" : "FAIL")} {name}: typed keys \"{keys}\" → \"{_box.Text}\" (expected \"{expected}\"), " +
                          $"layout {CurrentLayout():X} (expected {expectedLayout:X})");
        return ok ? 0 : 1;
    }

    private static int CheckUndo()
    {
        Reset(_english);
        TypeKeys("ghbdtn ", _english);
        if (!WaitFor(() => _box.Text == "привет ", 4000))
        {
            Console.WriteLine($"FAIL Pause undoes the correction: nothing was corrected first (\"{_box.Text}\")");
            return 1;
        }

        Press(0, VK_PAUSE);
        var ok = WaitFor(() => _box.Text == "ghbdtn " && CurrentLayout() == _english, 4000);
        Console.WriteLine($"{(ok ? "PASS" : "FAIL")} Pause undoes the correction: \"{_box.Text}\" (expected \"ghbdtn \"), layout {CurrentLayout():X}");
        return ok ? 0 : 1;
    }

    private static void Reset(IntPtr layout)
    {
        BringToFront();
        _box.Clear();
        _box.Focus();
        ActivateKeyboardLayout(layout, 0);
        Pump(300);
    }

    /// <summary>Each character is the US-layout key to press; uppercase means Shift.</summary>
    private static void TypeKeys(string keys, IntPtr keyboard)
    {
        foreach (var c in keys)
        {
            var vkAndShift = VkKeyScanEx(c, keyboard);
            var vk = vkAndShift & 0xFF;
            var shift = (vkAndShift & 0x100) != 0;
            if (shift)
            {
                Press(0x2A, 0, down: true);
            }

            Press((ushort)MapVirtualKeyEx((uint)vk, 0, keyboard), 0);
            if (shift)
            {
                Press(0x2A, 0, up: true);
            }

            Pump(40);
        }
    }

    private static void Press(ushort scan, int vk, bool down = true, bool up = true)
    {
        var inputs = new List<INPUT>();
        var flags = scan != 0 ? KEYEVENTF_SCANCODE : 0;
        if (down)
        {
            inputs.Add(Key(scan, vk, flags));
        }

        if (up)
        {
            inputs.Add(Key(scan, vk, flags | KEYEVENTF_KEYUP));
        }

        SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf<INPUT>());
        Pump(30);
    }

    private static INPUT Key(ushort scan, int vk, uint flags) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion { ki = new KEYBDINPUT { wVk = (ushort)vk, wScan = scan, dwFlags = flags } },
    };

    private static bool WaitFor(Func<bool> condition, int timeoutMs)
    {
        var watch = Stopwatch.StartNew();
        while (watch.ElapsedMilliseconds < timeoutMs)
        {
            if (condition())
            {
                return true;
            }

            Pump(50);
        }

        return condition();
    }

    private static void Pump(int ms)
    {
        var watch = Stopwatch.StartNew();
        do
        {
            Application.DoEvents();
            Thread.Sleep(10);
        }
        while (watch.ElapsedMilliseconds < ms);
    }

    private static void BringToFront()
    {
        if (GetForegroundWindow() == _form.Handle)
        {
            return;
        }

        // Windows only lets the foreground process change the foreground; an Alt tap lifts that lock.
        Press(0x38, 0);
        SetForegroundWindow(_form.Handle);
        _form.Activate();
        Pump(200);
        Console.WriteLine($"Foreground is the test window: {GetForegroundWindow() == _form.Handle}");
    }

    private static IntPtr CurrentLayout() => GetKeyboardLayout(0);

    private static IntPtr[] InstalledLayouts()
    {
        var count = GetKeyboardLayoutList(0, null);
        var list = new IntPtr[count];
        GetKeyboardLayoutList(count, list);
        return list;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)]
        public MOUSEINPUT mi;

        [FieldOffset(0)]
        public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadKeyboardLayout(string pwszKLID, uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr ActivateKeyboardLayout(IntPtr hkl, uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr GetKeyboardLayout(uint idThread);

    [DllImport("user32.dll")]
    private static extern int GetKeyboardLayoutList(int nBuff, [Out] IntPtr[]? lpList);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern short VkKeyScanEx(char ch, IntPtr dwhkl);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKeyEx(uint uCode, uint uMapType, IntPtr dwhkl);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
}
