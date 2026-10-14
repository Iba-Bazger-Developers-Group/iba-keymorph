namespace IbaKeyMorph.Core;

/// <summary>A physical key press. <see cref="Code"/> is a platform key id (scan code on Windows).</summary>
public readonly record struct KeyStroke(int Code, bool Shift, bool Caps);

public interface IKeyboardLayout
{
    /// <summary>Stable platform id (HKL on Windows, input source id on macOS).</summary>
    string Id { get; }

    /// <summary>Short label for the UI, e.g. "EN".</summary>
    string ShortName { get; }

    /// <summary>Language model for this layout or null when the language is unsupported.</summary>
    LanguageModel? Language { get; }

    /// <summary>Key codes that produce printable characters; used to build text converters.</summary>
    IReadOnlyList<int> PrintableKeyCodes { get; }

    /// <summary>Text the key produces in this layout, or an empty string.</summary>
    string Render(KeyStroke key);
}

public static class KeyboardLayoutExtensions
{
    public static string Render(this IKeyboardLayout layout, IEnumerable<KeyStroke> keys) =>
        string.Concat(keys.Select(layout.Render));
}

/// <summary>Layout defined by two strings (unshifted and shifted characters per key position).</summary>
public sealed class TableLayout : IKeyboardLayout
{
    private readonly string _normal;
    private readonly string _shifted;

    public TableLayout(string id, string shortName, LanguageModel? language, string normal, string shifted)
    {
        if (normal.Length != shifted.Length)
        {
            throw new ArgumentException("Normal and shifted rows must have the same length.");
        }

        Id = id;
        ShortName = shortName;
        Language = language;
        _normal = normal;
        _shifted = shifted;
        PrintableKeyCodes = Enumerable.Range(0, normal.Length).ToArray();
    }

    public string Id { get; }

    public string ShortName { get; }

    public LanguageModel? Language { get; }

    public IReadOnlyList<int> PrintableKeyCodes { get; }

    public string Render(KeyStroke key)
    {
        if (key.Code < 0 || key.Code >= _normal.Length)
        {
            return string.Empty;
        }

        var c = key.Shift ? _shifted[key.Code] : _normal[key.Code];
        if (key.Caps && char.IsLetter(c))
        {
            c = char.IsUpper(c) ? char.ToLowerInvariant(c) : char.ToUpperInvariant(c);
        }

        return c.ToString();
    }

    /// <summary>Key code (position) that produces <paramref name="c"/>, for tests and simulators.</summary>
    public KeyStroke? Find(char c, bool caps = false)
    {
        var index = _normal.IndexOf(c);
        if (index >= 0)
        {
            return new KeyStroke(index, false, caps);
        }

        index = _shifted.IndexOf(c);
        return index >= 0 ? new KeyStroke(index, true, caps) : null;
    }
}

public static class BuiltInLayouts
{
    // Positions follow the US keyboard: `1234567890-= qwertyuiop[]\ asdfghjkl;' zxcvbnm,./
    public const string UsNormal = "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./";
    public const string UsShifted = "~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?";
    public const string RuNormal = "ё1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю.";
    public const string RuShifted = "Ё!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЪ/ФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,";

    private static readonly Lazy<TableLayout> LazyEnglish =
        new(() => new TableLayout("builtin:en-US", "EN", Languages.English, UsNormal, UsShifted));

    private static readonly Lazy<TableLayout> LazyRussian =
        new(() => new TableLayout("builtin:ru-RU", "RU", Languages.Russian, RuNormal, RuShifted));

    public static TableLayout English => LazyEnglish.Value;

    public static TableLayout Russian => LazyRussian.Value;
}
