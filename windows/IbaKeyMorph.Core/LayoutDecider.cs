namespace IbaKeyMorph.Core;

public sealed record WordEvaluation(
    string Text,
    string Core,
    string Normalized,
    bool WellFormed,
    bool InDictionary,
    double Score);

/// <summary>
/// Decides whether a word typed in one layout was really meant for another one.
/// The Swift port in macos/Sources/KeyMorphCore/LayoutDecider.swift mirrors these rules.
/// </summary>
public sealed class LayoutDecider
{
    /// <summary>Shortest word (letters) corrected when the alternative is a dictionary word.</summary>
    public const int MinDictionaryLength = 2;

    /// <summary>Shortest word corrected on trigram statistics alone.</summary>
    public const int MinStatisticalLength = 3;

    /// <summary>Required advantage of the alternative, in average log-probability per symbol.</summary>
    public const double ScoreMargin = 1.0;

    /// <summary>The typed word must score below this to be considered gibberish.</summary>
    public const double ImplausibleScore = -3.2;

    /// <summary>When the typed text is not even word-shaped, the alternative must score at least this.</summary>
    public const double PlausibleScore = -3.0;

    private readonly Func<string, bool> _isException;

    public LayoutDecider(Func<string, bool>? isException = null)
    {
        _isException = isException ?? (_ => false);
    }

    public static WordEvaluation Evaluate(string text, LanguageModel language)
    {
        var core = ExtractCore(text, language);
        var normalized = LanguageModel.Normalize(core);
        var wellFormed = language.IsWellFormed(normalized);
        var inDictionary = wellFormed && language.Contains(normalized);
        var score = wellFormed ? language.Score(normalized) : double.NegativeInfinity;
        return new WordEvaluation(text, core, normalized, wellFormed, inDictionary, score);
    }

    /// <summary>Strips leading and trailing characters that are not letters of the language.</summary>
    public static string ExtractCore(string text, LanguageModel language)
    {
        var start = 0;
        while (start < text.Length && !language.IsLetter(text[start]))
        {
            start++;
        }

        var end = text.Length - 1;
        while (end >= start && !language.IsLetter(text[end]))
        {
            end--;
        }

        return start > end ? string.Empty : text.Substring(start, end - start + 1);
    }

    /// <summary>
    /// True when <paramref name="typed"/> (shown in <paramref name="typedLanguage"/>) should be replaced by
    /// <paramref name="alternative"/> (the same keys in a layout of <paramref name="alternativeLanguage"/>).
    /// <paramref name="confidence"/> ranks competing alternatives.
    /// </summary>
    public bool ShouldSwitch(
        string typed,
        LanguageModel typedLanguage,
        string alternative,
        LanguageModel alternativeLanguage,
        out double confidence)
    {
        confidence = 0;
        if (typed.Any(char.IsDigit) || alternative.Any(char.IsDigit))
        {
            return false;
        }

        var current = Evaluate(typed, typedLanguage);
        var other = Evaluate(alternative, alternativeLanguage);

        if (!other.WellFormed || other.Normalized.Length < MinDictionaryLength)
        {
            return false;
        }

        if (current.InDictionary || IsException(typed, typedLanguage))
        {
            return false;
        }

        if (other.InDictionary)
        {
            confidence = 100 + other.Normalized.Length;
            return true;
        }

        if (other.Normalized.Length < MinStatisticalLength)
        {
            return false;
        }

        if (!current.WellFormed)
        {
            confidence = other.Score;
            return other.Score >= PlausibleScore;
        }

        var margin = other.Score - current.Score;
        confidence = margin;
        return margin >= ScoreMargin && current.Score <= ImplausibleScore;
    }

    /// <summary>
    /// Lookback rule for a short word right before a corrected one ("z ns" → "я ты"): only dictionary
    /// evidence counts, but single letters are allowed.
    /// </summary>
    public bool ShouldSwitchPrevious(
        string typed,
        LanguageModel typedLanguage,
        string alternative,
        LanguageModel alternativeLanguage)
    {
        if (typed.Any(char.IsDigit) || alternative.Any(char.IsDigit))
        {
            return false;
        }

        var current = Evaluate(typed, typedLanguage);
        var other = Evaluate(alternative, alternativeLanguage);
        return other.InDictionary && !current.InDictionary && !IsException(typed, typedLanguage);
    }

    /// <summary>Normalised key used for the user exception list.</summary>
    public static string ExceptionKey(string typed, LanguageModel language) =>
        LanguageModel.Normalize(ExtractCore(typed, language));

    private bool IsException(string typed, LanguageModel language)
    {
        var key = ExceptionKey(typed, language);
        return key.Length > 0 && _isException(key);
    }
}
