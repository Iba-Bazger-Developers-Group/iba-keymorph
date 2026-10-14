using IbaKeyMorph.Core;

namespace IbaKeyMorph.Core.Tests;

internal static class TestData
{
    /// <summary>The repository's data directory (sources, not the copy in bin), found by walking up.</summary>
    public static string SourceDataDirectory
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir is not null)
            {
                var candidate = Path.Combine(dir.FullName, "data");
                if (File.Exists(Path.Combine(candidate, "en.txt")) && Directory.Exists(Path.Combine(dir.FullName, "windows")))
                {
                    return candidate;
                }

                dir = dir.Parent;
            }

            throw new DirectoryNotFoundException("Repository data directory not found.");
        }
    }

    public static IReadOnlyList<string> Words(string relativePath) =>
        Languages.ParseWordList(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "data", relativePath)))
            .Select(LanguageModel.Normalize)
            .Distinct()
            .ToList();

    /// <summary>Re-types a word as the same keys pressed in another layout.</summary>
    public static string Retype(string word, TableLayout from, TableLayout to)
    {
        var keys = new List<KeyStroke>();
        foreach (var c in word)
        {
            var key = from.Find(c) ?? throw new ArgumentException($"No key for '{c}'");
            keys.Add(key);
        }

        return to.Render(keys);
    }
}
