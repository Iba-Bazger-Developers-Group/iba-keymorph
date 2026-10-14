using IbaKeyMorph.Core;
using Xunit;
using Xunit.Abstractions;

namespace IbaKeyMorph.Core.Tests;

/// <summary>Quality gates over the word lists: no false corrections, high recall.</summary>
public class CorpusTests
{
    private readonly ITestOutputHelper _output;
    private readonly LayoutDecider _decider = new();

    public CorpusTests(ITestOutputHelper output) => _output = output;

    private static TableLayout EnLayout => BuiltInLayouts.English;

    private static TableLayout RuLayout => BuiltInLayouts.Russian;

    public static TheoryData<string, string> WordSets => new()
    {
        { "en.txt", "en" },
        { "ru.txt", "ru" },
        { "tests/heldout-en.txt", "en" },
        { "tests/heldout-ru.txt", "ru" },
        { "tests/validation-en.txt", "en" },
        { "tests/validation-ru.txt", "ru" },
    };

    [Theory]
    [MemberData(nameof(WordSets))]
    public void CorrectlyTypedWordsAreNeverSwitched(string file, string language)
    {
        var (own, other) = Layouts(language);
        var falsePositives = TestData.Words(file)
            .Where(w => _decider.ShouldSwitch(w, own.Language!, TestData.Retype(w, own, other), other.Language!, out _))
            .ToList();

        Assert.True(falsePositives.Count == 0, string.Join(" ", falsePositives));
    }

    [Theory]
    [MemberData(nameof(WordSets))]
    public void WordsTypedInTheWrongLayoutAreSwitched(string file, string language)
    {
        var (own, other) = Layouts(language);
        var words = TestData.Words(file).Where(w => w.Length >= LayoutDecider.MinDictionaryLength).ToList();
        var dictionary = !file.StartsWith("tests/", StringComparison.Ordinal);
        var outOfVocabulary = words.Where(w => dictionary || !own.Language!.Contains(w)).ToList();

        var misses = outOfVocabulary
            .Where(w => !_decider.ShouldSwitch(TestData.Retype(w, own, other), other.Language!, w, own.Language!, out _))
            .ToList();
        var recall = 1.0 - (double)misses.Count / outOfVocabulary.Count;
        _output.WriteLine($"{file}: recall {recall:P1}, misses: {string.Join(' ', misses.Take(40))}");

        Assert.True(recall >= (dictionary ? 0.99 : 0.80), $"Recall {recall:P1} is too low");
    }

    [Fact]
    public void NoDictionaryWordLooksLikeAnotherDictionaryWordUnlessListed()
    {
        // Pairs that are real words in both layouts. Neither side gets corrected; extend consciously.
        var known = new HashSet<string> { "in", "her", "here", "exe", "шт", "рук", "руку", "учу", "руб", "беру" };
        var conflicts = new List<string>();
        foreach (var w in TestData.Words("en.txt"))
        {
            if (LayoutDecider.Evaluate(TestData.Retype(w, EnLayout, RuLayout), Languages.Russian).InDictionary && !known.Contains(w))
            {
                conflicts.Add(w);
            }
        }

        foreach (var w in TestData.Words("ru.txt"))
        {
            if (LayoutDecider.Evaluate(TestData.Retype(w, RuLayout, EnLayout), Languages.English).InDictionary && !known.Contains(w))
            {
                conflicts.Add(w);
            }
        }

        Assert.Empty(conflicts);
    }

    private static (TableLayout Own, TableLayout Other) Layouts(string language) =>
        language == "en" ? (EnLayout, RuLayout) : (RuLayout, EnLayout);
}
