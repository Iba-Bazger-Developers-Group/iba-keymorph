namespace IbaKeyMorph.Core;

/// <summary>Detects words typed with Caps Lock left on by accident: "hELLO", "пРИВЕТ".</summary>
public static class CaseFix
{
    public const int MinLetters = 3;

    public static bool ShouldFix(IReadOnlyList<KeyStroke> keys, string display)
    {
        if (keys.Count == 0 || keys.Any(k => !k.Caps))
        {
            return false;
        }

        var letters = display.Where(char.IsLetter).ToList();
        return letters.Count >= MinLetters &&
               char.IsLower(letters[0]) &&
               letters.Skip(1).All(char.IsUpper);
    }

    public static string SwapCase(string text) =>
        string.Concat(text.Select(c =>
            char.IsUpper(c) ? char.ToLowerInvariant(c) : char.IsLower(c) ? char.ToUpperInvariant(c) : c));
}
