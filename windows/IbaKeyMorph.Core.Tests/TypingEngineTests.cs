using IbaKeyMorph.Core;
using Xunit;

namespace IbaKeyMorph.Core.Tests;

public class TypingEngineTests
{
    private static TableLayout En => BuiltInLayouts.English;

    private static TableLayout Ru => BuiltInLayouts.Russian;

    [Fact]
    public void RussianTypedInEnglishLayoutIsCorrected()
    {
        var sim = new Simulator(En).Type("привет как дела ", Ru);

        Assert.Equal("привет как дела ", sim.ToString());
        Assert.Same(Ru, sim.Active);
    }

    [Fact]
    public void EnglishTypedInRussianLayoutIsCorrected()
    {
        var sim = new Simulator(Ru).Type("hello world ", En);

        Assert.Equal("hello world ", sim.ToString());
        Assert.Same(En, sim.Active);
    }

    [Fact]
    public void CorrectTextIsLeftAlone()
    {
        var sim = new Simulator(Ru).Type("привет как дела ", Ru);

        Assert.Equal("привет как дела ", sim.ToString());
        Assert.All(sim.Results, r => Assert.False(r.Swallow));
    }

    [Fact]
    public void PunctuationFollowsTheIntendedLayout()
    {
        var sim = new Simulator(En).Type("привет, как дела? ", Ru);

        Assert.Equal("привет, как дела? ", sim.ToString());
    }

    [Fact]
    public void CapitalisedWordsKeepTheirCase()
    {
        var sim = new Simulator(En).Type("Привет Мир ", Ru);

        Assert.Equal("Привет Мир ", sim.ToString());
    }

    [Fact]
    public void ShortWordBeforeACorrectedWordIsCorrectedToo()
    {
        var sim = new Simulator(En).Type("я тебя ", Ru);

        Assert.Equal("я тебя ", sim.ToString());
    }

    [Fact]
    public void LookbackCanBeDisabled()
    {
        var sim = new Simulator(En, new EngineOptions { CorrectPreviousShortWord = false }).Type("я тебя ", Ru);

        Assert.Equal("z тебя ", sim.ToString());
    }

    [Fact]
    public void SingleLetterAloneIsNotCorrected()
    {
        var sim = new Simulator(En).Type("я ", Ru);

        Assert.Equal("z ", sim.ToString());
    }

    [Fact]
    public void EnterAndTabAreWordBoundaries()
    {
        var sim = new Simulator(En).Type("привет\nпока\t", Ru);

        Assert.Equal("привет\nпока\t", sim.ToString());
    }

    [Fact]
    public void WordsWithDigitsAreNotCorrected()
    {
        var sim = new Simulator(En).Type("ghbdtn2 ", En);

        Assert.Equal("ghbdtn2 ", sim.ToString());
    }

    [Fact]
    public void AutoSwitchCanBeDisabled()
    {
        var sim = new Simulator(En, new EngineOptions { AutoSwitch = false }).Type("привет ", Ru);

        Assert.Equal("ghbdtn ", sim.ToString());
    }

    [Fact]
    public void HotkeyUndoesTheLastCorrectionAndLearnsTheWord()
    {
        var sim = new Simulator(En).Type("ghbdtn ", En);
        Assert.Equal("привет ", sim.ToString());

        sim.Hotkey();

        Assert.Equal("ghbdtn ", sim.ToString());
        Assert.Same(En, sim.Active);
        Assert.Contains("ghbdtn", sim.Learned);

        sim.Type("ghbdtn ", En);
        Assert.Equal("ghbdtn ghbdtn ", sim.ToString());
    }

    [Fact]
    public void HotkeyUndoWorksAfterExtraSpaces()
    {
        var sim = new Simulator(En).Type("ghbdtn  ", En).Hotkey();

        Assert.Equal("ghbdtn  ", sim.ToString());
    }

    [Fact]
    public void HotkeyConvertsTheWordBeingTyped()
    {
        var sim = new Simulator(En).Type("ghb", En).Hotkey();

        Assert.Equal("при", sim.ToString());
        Assert.Same(Ru, sim.Active);

        sim.Type("вет ", Ru);
        Assert.Equal("привет ", sim.ToString());
    }

    [Fact]
    public void HotkeyConvertsTheLastWordAfterSpace()
    {
        // "the" is an English word, so it is not corrected automatically; the hotkey forces it.
        var sim = new Simulator(En).Type("the ", En).Hotkey();

        Assert.Equal("еру ", sim.ToString());
        Assert.Same(Ru, sim.Active);
    }

    [Fact]
    public void HotkeyTogglesBackAndForth()
    {
        var sim = new Simulator(En).Type("the", En).Hotkey().Hotkey();

        Assert.Equal("the", sim.ToString());
        Assert.Same(En, sim.Active);
    }

    [Fact]
    public void ManuallyConvertedWordIsNotAutoCorrected()
    {
        var sim = new Simulator(Ru).Type("руддщ", Ru).Hotkey().Hotkey().Type(" ", Ru);

        Assert.Equal("руддщ ", sim.ToString());
    }

    [Fact]
    public void BackspaceEditsTheCurrentWord()
    {
        var sim = new Simulator(En).Type("ghbdtx\bn ", En);

        Assert.Equal("привет ", sim.ToString());
    }

    [Fact]
    public void BackspaceAfterSpaceResumesTheWord()
    {
        var sim = new Simulator(Ru).Type("hel \blo ", En);

        Assert.Equal("hello ", sim.ToString());
    }

    [Fact]
    public void AccidentalCapsLockIsFixed()
    {
        var sim = new Simulator(En) { Caps = true };
        sim.Type("Hello ", En);

        Assert.Equal("Hello ", sim.ToString());
        Assert.False(sim.Caps);
    }

    [Fact]
    public void AccidentalCapsLockIsFixedTogetherWithLayout()
    {
        var sim = new Simulator(En) { Caps = true };
        sim.Type("Привет ", Ru);

        Assert.Equal("Привет ", sim.ToString());
        Assert.Same(Ru, sim.Active);
        Assert.False(sim.Caps);
    }

    [Fact]
    public void DeliberateCapitalsAreKept()
    {
        var sim = new Simulator(En) { Caps = true };
        sim.Type("nasa ", En);

        Assert.Equal("NASA ", sim.ToString());
        Assert.True(sim.Caps);
    }

    [Fact]
    public void LayoutChangeInTheMiddleOfAWordResetsTracking()
    {
        var engine = new TypingEngine(new LayoutDecider(), new EngineOptions());
        engine.OnCharacterKey(En.Find('g')!.Value, En);
        engine.OnCharacterKey(En.Find('h')!.Value, Ru);

        Assert.Equal("р", engine.CurrentWord);
    }

    [Fact]
    public void BoundaryWithoutWordPassesThrough()
    {
        var engine = new TypingEngine(new LayoutDecider(), new EngineOptions());
        var layouts = new IKeyboardLayout[] { En, Ru };

        Assert.Same(EngineResult.PassThrough, engine.OnBoundary(BoundaryKind.Space, layouts));
        Assert.Same(EngineResult.SwallowOnly, engine.ConvertLastWord(layouts));
    }
}
