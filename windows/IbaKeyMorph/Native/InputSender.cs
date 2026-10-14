using System.Runtime.InteropServices;
using static IbaKeyMorph.Native.NativeMethods;

namespace IbaKeyMorph.Native;

/// <summary>Builds and sends synthetic input tagged with <see cref="Marker"/> so the hook can skip it.</summary>
internal sealed class InputSender
{
    /// <summary>"IBKM": identifies events injected by IBA KeyMorph.</summary>
    public static readonly nuint Marker = 0x49424B4D;

    private static readonly int InputSize = Marshal.SizeOf<INPUT>();
    private readonly List<INPUT> _pending = new();

    public InputSender Backspace(int count)
    {
        for (var i = 0; i < count; i++)
        {
            Key(VK_BACK, 0, extended: false);
        }

        return this;
    }

    public InputSender Text(string text)
    {
        foreach (var c in text)
        {
            _pending.Add(Keyboard(0, c, KEYEVENTF_UNICODE));
            _pending.Add(Keyboard(0, c, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP));
        }

        return this;
    }

    public InputSender Key(int vk, int scanCode, bool extended)
    {
        var flags = extended ? KEYEVENTF_EXTENDEDKEY : 0;
        _pending.Add(Keyboard((ushort)vk, (ushort)scanCode, flags));
        _pending.Add(Keyboard((ushort)vk, (ushort)scanCode, flags | KEYEVENTF_KEYUP));
        return this;
    }

    public InputSender KeyDown(int vk)
    {
        _pending.Add(Keyboard((ushort)vk, 0, 0));
        return this;
    }

    public InputSender KeyUp(int vk)
    {
        _pending.Add(Keyboard((ushort)vk, 0, KEYEVENTF_KEYUP));
        return this;
    }

    /// <summary>Releases modifiers the user is still holding (e.g. Shift of Shift+Pause).</summary>
    public InputSender ReleaseHeldModifiers()
    {
        foreach (var vk in new[] { VK_LSHIFT, VK_RSHIFT, VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN })
        {
            if (IsKeyDown(vk))
            {
                KeyUp(vk);
            }
        }

        return this;
    }

    public InputSender Chord(int modifier, int vk)
    {
        KeyDown(modifier);
        Key(vk, 0, extended: false);
        KeyUp(modifier);
        return this;
    }

    /// <summary>Sends everything queued so far. Returns false if Windows rejected the input.</summary>
    public bool Flush()
    {
        if (_pending.Count == 0)
        {
            return true;
        }

        var inputs = _pending.ToArray();
        _pending.Clear();
        return SendInput((uint)inputs.Length, inputs, InputSize) == inputs.Length;
    }

    private static INPUT Keyboard(ushort vk, ushort scan, uint flags) => new()
    {
        type = INPUT_KEYBOARD,
        U = new InputUnion
        {
            ki = new KEYBDINPUT { wVk = vk, wScan = scan, dwFlags = flags, dwExtraInfo = Marker },
        },
    };
}
