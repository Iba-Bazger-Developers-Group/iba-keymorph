namespace IbaKeyMorph.Core;

/// <summary>
/// Word list plus an interpolated character trigram model for one language.
/// The Swift port in macos/Sources/KeyMorphCore must stay numerically identical.
/// </summary>
public sealed class LanguageModel
{
    private const double Lambda3 = 0.6;
    private const double Lambda2 = 0.3;
    private const double Lambda1 = 0.1;
    private const char StartMark = '^';
    private const char EndMark = '$';

    private readonly HashSet<char> _letters;
    private readonly HashSet<char> _connectors;
    private readonly HashSet<string> _words = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _trigrams = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _trigramContexts = new(StringComparer.Ordinal);
    private readonly Dictionary<string, int> _bigrams = new(StringComparer.Ordinal);
    private readonly Dictionary<char, int> _bigramContexts = new();
    private readonly Dictionary<char, int> _unigrams = new();
    private readonly int _vocabulary;
    private int _total;

    public LanguageModel(string code, string letters, string connectors, IEnumerable<string> words)
    {
        Code = code;
        _letters = new HashSet<char>(letters);
        _connectors = new HashSet<char>(connectors) { '-' };
        _vocabulary = _letters.Count + connectors.Length + 1;

        foreach (var raw in words)
        {
            var word = Normalize(raw);
            if (!IsWellFormed(word) || !_words.Add(word))
            {
                continue;
            }

            foreach (var segment in word.Split('-', StringSplitOptions.RemoveEmptyEntries))
            {
                Train(segment);
            }
        }
    }

    public string Code { get; }

    public int WordCount => _words.Count;

    public static string Normalize(string text) =>
        text.ToLowerInvariant().Replace('ё', 'е');

    public static char Normalize(char c)
    {
        var lower = char.ToLowerInvariant(c);
        return lower == 'ё' ? 'е' : lower;
    }

    public bool IsLetter(char c) => _letters.Contains(Normalize(c));

    /// <summary>Letters only, with connectors (hyphen, apostrophe) allowed strictly inside.</summary>
    public bool IsWellFormed(string normalized)
    {
        if (normalized.Length == 0 || !_letters.Contains(normalized[0]) || !_letters.Contains(normalized[^1]))
        {
            return false;
        }

        for (var i = 0; i < normalized.Length; i++)
        {
            var c = normalized[i];
            if (_letters.Contains(c))
            {
                continue;
            }

            if (!_connectors.Contains(c) || !_letters.Contains(normalized[i - 1]))
            {
                return false;
            }
        }

        return true;
    }

    public bool Contains(string normalized)
    {
        if (_words.Contains(normalized))
        {
            return true;
        }

        if (!normalized.Contains('-'))
        {
            return false;
        }

        var parts = normalized.Split('-', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length > 0 && parts.All(_words.Contains);
    }

    /// <summary>Average natural-log probability per predicted symbol. Higher is more plausible.</summary>
    public double Score(string normalized)
    {
        double sum = 0;
        var count = 0;
        foreach (var segment in normalized.Split('-', StringSplitOptions.RemoveEmptyEntries))
        {
            var sequence = $"{StartMark}{StartMark}{segment}{EndMark}";
            for (var i = 2; i < sequence.Length; i++)
            {
                sum += Math.Log(Probability(sequence[i - 2], sequence[i - 1], sequence[i]));
                count++;
            }
        }

        return count == 0 ? double.NegativeInfinity : sum / count;
    }

    private double Probability(char a, char b, char c)
    {
        double p3 = 0;
        if (_trigramContexts.TryGetValue(string.Concat(a, b), out var contextCount))
        {
            _trigrams.TryGetValue(string.Concat(a, b, c), out var n);
            p3 = (double)n / contextCount;
        }

        double p2 = 0;
        if (_bigramContexts.TryGetValue(b, out var bigramContextCount))
        {
            _bigrams.TryGetValue(string.Concat(b, c), out var n);
            p2 = (double)n / bigramContextCount;
        }

        _unigrams.TryGetValue(c, out var u);
        var p1 = (u + 1.0) / (_total + _vocabulary);

        return Lambda3 * p3 + Lambda2 * p2 + Lambda1 * p1;
    }

    private void Train(string segment)
    {
        var sequence = $"{StartMark}{StartMark}{segment}{EndMark}";
        for (var i = 2; i < sequence.Length; i++)
        {
            char a = sequence[i - 2], b = sequence[i - 1], c = sequence[i];
            Increment(_trigrams, string.Concat(a, b, c));
            Increment(_trigramContexts, string.Concat(a, b));
            Increment(_bigrams, string.Concat(b, c));
            Increment(_bigramContexts, b);
            Increment(_unigrams, c);
            _total++;
        }
    }

    private static void Increment<TKey>(Dictionary<TKey, int> map, TKey key)
        where TKey : notnull
    {
        map.TryGetValue(key, out var n);
        map[key] = n + 1;
    }
}
