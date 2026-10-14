using System.Reflection;

namespace IbaKeyMorph.Core;

public static class Languages
{
    public const string EnglishLetters = "abcdefghijklmnopqrstuvwxyz";
    public const string RussianLetters = "абвгдежзийклмнопрстуфхцчшщъыьэюя";

    private static readonly Lazy<LanguageModel> LazyEnglish =
        new(() => new LanguageModel("en", EnglishLetters, "'", ParseWordList(ReadResource("en"))));

    private static readonly Lazy<LanguageModel> LazyRussian =
        new(() => new LanguageModel("ru", RussianLetters, string.Empty, ParseWordList(ReadResource("ru"))));

    public static LanguageModel English => LazyEnglish.Value;

    public static LanguageModel Russian => LazyRussian.Value;

    /// <summary>Two-letter ISO 639-1 code → model, or null when the language is not supported.</summary>
    public static LanguageModel? ForCode(string? code) => code?.ToLowerInvariant() switch
    {
        "en" => English,
        "ru" => Russian,
        _ => null,
    };

    /// <summary>Whitespace-separated words; everything after '#' on a line is a comment.</summary>
    public static IEnumerable<string> ParseWordList(string text)
    {
        foreach (var rawLine in text.Split('\n'))
        {
            var hash = rawLine.IndexOf('#');
            var line = hash >= 0 ? rawLine[..hash] : rawLine;
            foreach (var word in line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries))
            {
                yield return word;
            }
        }
    }

    private static string ReadResource(string code)
    {
        var name = $"IbaKeyMorph.Data.{code}.txt";
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)
            ?? throw new InvalidOperationException($"Embedded word list '{name}' is missing.");
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
