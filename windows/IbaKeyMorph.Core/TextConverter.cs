namespace IbaKeyMorph.Core;

/// <summary>Re-types arbitrary text as if the same keys had been pressed in another layout.</summary>
public static class TextConverter
{
    public static string Convert(string text, IKeyboardLayout from, IKeyboardLayout to)
    {
        var map = BuildMap(from, to);
        var result = new System.Text.StringBuilder(text.Length);
        foreach (var c in text)
        {
            result.Append(map.TryGetValue(c, out var replacement) ? replacement : c.ToString());
        }

        return result.ToString();
    }

    public static Dictionary<char, string> BuildMap(IKeyboardLayout from, IKeyboardLayout to)
    {
        var map = new Dictionary<char, string>();
        foreach (var shift in new[] { false, true })
        {
            foreach (var code in from.PrintableKeyCodes)
            {
                var key = new KeyStroke(code, shift, false);
                var source = from.Render(key);
                var target = to.Render(key);
                if (source.Length == 1 && target.Length > 0 && !map.ContainsKey(source[0]))
                {
                    map[source[0]] = target;
                }
            }
        }

        return map;
    }

    /// <summary>
    /// Picks the conversion for selected text: the source layout is the one whose language owns most
    /// of the letters, the target is the best-scoring other layout.
    /// </summary>
    public static (IKeyboardLayout From, IKeyboardLayout To)? PickConversion(
        string text,
        IReadOnlyList<IKeyboardLayout> layouts)
    {
        IKeyboardLayout? from = null;
        var bestLetters = 0;
        foreach (var layout in layouts)
        {
            if (layout.Language is not { } language)
            {
                continue;
            }

            var letters = text.Count(language.IsLetter);
            if (letters > bestLetters)
            {
                from = layout;
                bestLetters = letters;
            }
        }

        if (from is null)
        {
            return null;
        }

        IKeyboardLayout? to = null;
        var bestScore = double.NegativeInfinity;
        foreach (var layout in layouts)
        {
            if (layout.Id == from.Id || (layout.Language is { } l && l.Code == from.Language!.Code))
            {
                continue;
            }

            var converted = Convert(text, from, layout);
            var score = layout.Language is { } language ? AverageScore(converted, language) : double.MinValue;
            if (to is null || score > bestScore)
            {
                to = layout;
                bestScore = score;
            }
        }

        return to is null ? null : (from, to);
    }

    private static double AverageScore(string text, LanguageModel language)
    {
        var words = text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .Select(w => LayoutDecider.Evaluate(w, language))
            .Where(e => e.WellFormed)
            .ToList();
        return words.Count == 0 ? double.MinValue : words.Average(e => e.InDictionary ? 0 : e.Score);
    }
}
