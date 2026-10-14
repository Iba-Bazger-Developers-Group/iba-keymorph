namespace IbaKeyMorph.Core;

public enum BoundaryKind
{
    Space,
    Enter,
    Tab,
}

/// <summary>Something the platform layer must do, in order.</summary>
public abstract record EngineAction
{
    /// <summary>Press Backspace <paramref name="Count"/> times.</summary>
    public sealed record Erase(int Count) : EngineAction;

    /// <summary>Type text as Unicode (layout independent).</summary>
    public sealed record Type(string Text) : EngineAction;

    /// <summary>Re-send the word boundary key that was swallowed (Space, Enter or Tab).</summary>
    public sealed record ReplayBoundary : EngineAction;

    /// <summary>Switch the focused window to this layout.</summary>
    public sealed record SwitchLayout(IKeyboardLayout Layout) : EngineAction;

    /// <summary>Turn Caps Lock off.</summary>
    public sealed record CapsLockOff : EngineAction;

    /// <summary>The user reverted a correction: never correct this word again.</summary>
    public sealed record LearnException(string Word) : EngineAction;
}

/// <summary>
/// <paramref name="Swallow"/>: the key that triggered the result must not reach the application;
/// the actions replace it.
/// </summary>
public sealed record EngineResult(bool Swallow, IReadOnlyList<EngineAction> Actions)
{
    public static readonly EngineResult PassThrough = new(false, Array.Empty<EngineAction>());

    public static readonly EngineResult SwallowOnly = new(true, Array.Empty<EngineAction>());

    public bool ChangesText => Actions.Any(a => a is EngineAction.Erase or EngineAction.Type);
}

public sealed class EngineOptions
{
    public bool AutoSwitch { get; set; } = true;

    public bool FixCapsLock { get; set; } = true;

    public bool CorrectPreviousShortWord { get; set; } = true;
}

/// <summary>
/// Platform-independent state machine: tracks the word being typed, decides on corrections and
/// produces the edit actions. The macOS app uses a line-by-line Swift port.
/// </summary>
public sealed class TypingEngine
{
    private readonly LayoutDecider _decider;
    private readonly EngineOptions _options;

    private Word? _current;
    private Word? _last;
    private int _lastTrailingSpaces = -1;
    private Correction? _lastCorrection;

    public TypingEngine(LayoutDecider decider, EngineOptions options)
    {
        _decider = decider;
        _options = options;
    }

    /// <summary>Text of the word being typed, for diagnostics and tests.</summary>
    public string CurrentWord => _current?.Display ?? string.Empty;

    public void Reset()
    {
        _current = null;
        _last = null;
        _lastTrailingSpaces = -1;
        _lastCorrection = null;
    }

    public void OnCharacterKey(KeyStroke key, IKeyboardLayout layout)
    {
        _lastCorrection = null;
        if (_current is not null && _current.Layout.Id != layout.Id)
        {
            // The layout changed in the middle of a word: what is on screen is no longer known.
            Reset();
        }

        _current ??= new Word(layout);
        _current.Keys.Add(key);
    }

    public void OnBackspace()
    {
        _lastCorrection = null;
        if (_current is not null)
        {
            _current.Keys.RemoveAt(_current.Keys.Count - 1);
            if (_current.Keys.Count == 0)
            {
                _current = null;
            }

            return;
        }

        if (_last is not null && _lastTrailingSpaces > 0)
        {
            _lastTrailingSpaces--;
            if (_lastTrailingSpaces == 0)
            {
                _current = _last;
                _last = null;
                _lastTrailingSpaces = -1;
            }

            return;
        }

        Reset();
    }

    public EngineResult OnBoundary(BoundaryKind kind, IReadOnlyList<IKeyboardLayout> layouts)
    {
        _lastCorrection = null;
        var word = _current;
        if (word is null)
        {
            if (kind == BoundaryKind.Space && _last is not null && _lastTrailingSpaces >= 0)
            {
                _lastTrailingSpaces++;
            }
            else
            {
                _last = null;
                _lastTrailingSpaces = -1;
            }

            return EngineResult.PassThrough;
        }

        _current = null;
        var previous = _last is not null && _lastTrailingSpaces == 1 ? _last : null;
        var result = Correct(word, previous, kind, layouts);

        _last = kind == BoundaryKind.Space ? word : null;
        _lastTrailingSpaces = kind == BoundaryKind.Space ? 1 : -1;
        return result;
    }

    /// <summary>
    /// Hotkey: undo the last automatic correction, or convert the current/last word to the next layout.
    /// </summary>
    public EngineResult ConvertLastWord(IReadOnlyList<IKeyboardLayout> layouts)
    {
        if (_lastCorrection is { } correction && _last is not null && _lastTrailingSpaces >= 1)
        {
            _lastCorrection = null;
            var spaces = new string(' ', _lastTrailingSpaces);
            _last.Keys.Clear();
            _last.Keys.AddRange(correction.OriginalKeys);
            _last.Layout = correction.From;
            _last.UserChosen = true;
            _last.Corrected = false;

            var actions = new List<EngineAction>
            {
                new EngineAction.Erase(correction.Inserted.Length + _lastTrailingSpaces),
                new EngineAction.Type(correction.Removed + spaces),
                new EngineAction.SwitchLayout(correction.From),
            };
            if (correction.LearnWord.Length > 0)
            {
                actions.Add(new EngineAction.LearnException(correction.LearnWord));
            }

            return new EngineResult(true, actions);
        }

        if (_current is { Keys.Count: > 0 } current)
        {
            return ConvertWord(current, 0, layouts);
        }

        if (_last is not null && _lastTrailingSpaces >= 1)
        {
            return ConvertWord(_last, _lastTrailingSpaces, layouts);
        }

        return EngineResult.SwallowOnly;
    }

    private EngineResult ConvertWord(Word word, int trailingSpaces, IReadOnlyList<IKeyboardLayout> layouts)
    {
        var target = PickManualTarget(word, layouts);
        if (target is null)
        {
            return EngineResult.SwallowOnly;
        }

        var spaces = new string(' ', trailingSpaces);
        var before = word.Display;
        word.Layout = target;
        word.UserChosen = true;
        word.Corrected = false;

        return new EngineResult(true, new EngineAction[]
        {
            new EngineAction.Erase(before.Length + trailingSpaces),
            new EngineAction.Type(word.Display + spaces),
            new EngineAction.SwitchLayout(target),
        });
    }

    private EngineResult Correct(Word word, Word? previous, BoundaryKind kind, IReadOnlyList<IKeyboardLayout> layouts)
    {
        var original = word.Display;
        var target = _options.AutoSwitch && !word.UserChosen ? PickAutomaticTarget(word, layouts) : null;
        var fixCase = _options.FixCapsLock && CaseFix.ShouldFix(word.Keys, original);
        if (target is null && !fixCase)
        {
            return EngineResult.PassThrough;
        }

        var originalKeys = word.Keys.ToList();
        var from = word.Layout;
        if (target is not null)
        {
            word.Layout = target;
            word.Corrected = true;
        }

        if (fixCase)
        {
            for (var i = 0; i < word.Keys.Count; i++)
            {
                word.Keys[i] = word.Keys[i] with { Caps = !word.Keys[i].Caps };
            }
        }

        var removed = original;
        var inserted = word.Display;

        if (target is not null && previous is not null && ShouldCorrectPrevious(previous, from, target))
        {
            var previousBefore = previous.Display;
            previous.Layout = target;
            previous.Corrected = true;
            removed = previousBefore + " " + removed;
            inserted = previous.Display + " " + inserted;
        }

        var actions = new List<EngineAction>
        {
            new EngineAction.Erase(removed.Length),
            new EngineAction.Type(inserted),
            new EngineAction.ReplayBoundary(),
        };
        if (target is not null)
        {
            actions.Add(new EngineAction.SwitchLayout(target));
        }

        if (fixCase)
        {
            actions.Add(new EngineAction.CapsLockOff());
        }

        if (target is not null && kind == BoundaryKind.Space && from.Language is { } fromLanguage)
        {
            var learn = removed == original ? LayoutDecider.ExceptionKey(original, fromLanguage) : string.Empty;
            _lastCorrection = new Correction(removed, inserted, from, originalKeys, learn);
        }

        return new EngineResult(true, actions);
    }

    private bool ShouldCorrectPrevious(Word previous, IKeyboardLayout from, IKeyboardLayout target)
    {
        if (!_options.CorrectPreviousShortWord || previous.UserChosen || previous.Corrected ||
            previous.Layout.Id != from.Id || from.Language is null || target.Language is null)
        {
            return false;
        }

        return _decider.ShouldSwitchPrevious(
            previous.Display,
            from.Language,
            target.Render(previous.Keys),
            target.Language);
    }

    private IKeyboardLayout? PickAutomaticTarget(Word word, IReadOnlyList<IKeyboardLayout> layouts)
    {
        if (word.Layout.Language is not { } typedLanguage)
        {
            return null;
        }

        var typed = word.Display;
        IKeyboardLayout? best = null;
        var bestConfidence = double.NegativeInfinity;
        foreach (var layout in layouts)
        {
            if (layout.Language is not { } language || language.Code == typedLanguage.Code)
            {
                continue;
            }

            var alternative = layout.Render(word.Keys);
            if (_decider.ShouldSwitch(typed, typedLanguage, alternative, language, out var confidence) &&
                confidence > bestConfidence)
            {
                best = layout;
                bestConfidence = confidence;
            }
        }

        return best;
    }

    private static IKeyboardLayout? PickManualTarget(Word word, IReadOnlyList<IKeyboardLayout> layouts)
    {
        var others = layouts.Where(l => l.Id != word.Layout.Id).ToList();
        if (others.Count <= 1)
        {
            return others.FirstOrDefault();
        }

        // Several candidates: prefer the most plausible rendering, falling back to list order.
        IKeyboardLayout? best = null;
        var bestScore = double.NegativeInfinity;
        foreach (var layout in others)
        {
            var score = layout.Language is { } language
                ? LayoutDecider.Evaluate(layout.Render(word.Keys), language) switch
                {
                    { InDictionary: true } => 0,
                    var e => e.Score,
                }
                : double.NegativeInfinity;
            if (best is null || score > bestScore)
            {
                best = layout;
                bestScore = score;
            }
        }

        return best;
    }

    private sealed class Word
    {
        public Word(IKeyboardLayout layout) => Layout = layout;

        public List<KeyStroke> Keys { get; } = new();

        public IKeyboardLayout Layout { get; set; }

        public bool UserChosen { get; set; }

        public bool Corrected { get; set; }

        public string Display => Layout.Render(Keys);
    }

    private sealed record Correction(
        string Removed,
        string Inserted,
        IKeyboardLayout From,
        IReadOnlyList<KeyStroke> OriginalKeys,
        string LearnWord);
}
