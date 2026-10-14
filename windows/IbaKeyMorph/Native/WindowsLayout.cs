using System.Globalization;
using IbaKeyMorph.Core;
using static IbaKeyMorph.Native.NativeMethods;

namespace IbaKeyMorph.Native;

/// <summary>An installed keyboard layout (HKL). Key codes are hardware scan codes.</summary>
internal sealed class WindowsLayout : IKeyboardLayout
{
    // Scan codes of keys that type characters: digit row, three letter rows, OEM keys and the ISO key.
    private static readonly int[] PrintableScanCodes =
        Enumerable.Range(0x02, 12)
            .Concat(Enumerable.Range(0x10, 12))
            .Concat(Enumerable.Range(0x1E, 12))
            .Concat(new[] { 0x2B })
            .Concat(Enumerable.Range(0x2C, 10))
            .Concat(new[] { 0x56 })
            .ToArray();

    private static readonly HashSet<int> PrintableSet = new(PrintableScanCodes);

    private readonly Dictionary<KeyStroke, string> _cache = new();

    public WindowsLayout(IntPtr hkl)
    {
        Handle = hkl;
        Id = ((long)hkl).ToString("X", CultureInfo.InvariantCulture);
        var languageId = (int)((long)hkl & 0xFFFF);
        string iso;
        try
        {
            iso = CultureInfo.GetCultureInfo(languageId).TwoLetterISOLanguageName;
        }
        catch (CultureNotFoundException)
        {
            iso = "??";
        }

        ShortName = iso.ToUpperInvariant();
        Language = Languages.ForCode(iso);
    }

    public IntPtr Handle { get; }

    public string Id { get; }

    public string ShortName { get; }

    public LanguageModel? Language { get; }

    public IReadOnlyList<int> PrintableKeyCodes => PrintableScanCodes;

    public static bool IsPrintable(int scanCode, bool extended) => !extended && PrintableSet.Contains(scanCode);

    public string Render(KeyStroke key)
    {
        if (_cache.TryGetValue(key, out var cached))
        {
            return cached;
        }

        var vk = MapVirtualKeyEx((uint)key.Code, MAPVK_VSC_TO_VK_EX, Handle);
        var state = new byte[256];
        if (key.Shift)
        {
            state[VK_SHIFT] = 0x80;
        }

        if (key.Caps)
        {
            state[VK_CAPITAL] = 0x01;
        }

        var buffer = new char[8];
        var count = ToUnicodeEx(vk, (uint)key.Code, state, buffer, buffer.Length, TOUNICODE_NO_STATE_CHANGE, Handle);

        // Dead keys (count < 0), ligatures and control characters are not tracked.
        var text = count == 1 && !char.IsControl(buffer[0]) ? buffer[0].ToString() : string.Empty;
        _cache[key] = text;
        return text;
    }

    public override string ToString() => $"{ShortName} ({Id})";
}
