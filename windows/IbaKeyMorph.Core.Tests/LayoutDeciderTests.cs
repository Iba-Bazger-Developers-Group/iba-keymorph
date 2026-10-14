using IbaKeyMorph.Core;
using Xunit;

namespace IbaKeyMorph.Core.Tests;

public class LayoutDeciderTests
{
    private readonly LayoutDecider _decider = new();

    private static LanguageModel En => Languages.English;

    private static LanguageModel Ru => Languages.Russian;

    [Theory]
    [InlineData("ghbdtn", "привет")]
    [InlineData("Ghbdtn", "Привет")]
    [InlineData("ltkf", "дела")]
    [InlineData("yt", "не")]
    [InlineData("ghbdtn?", "привет,")]
    [InlineData("rjvgm.nth", "компьютер")]
    [InlineData("rfkmrekznjh", "калькулятор")]
    public void SwitchesEnglishGibberishToRussian(string typed, string alternative)
    {
        Assert.True(_decider.ShouldSwitch(typed, En, alternative, Ru, out _));
    }

    [Theory]
    [InlineData("руддщ", "hello")]
    [InlineData("цщкдв", "world")]
    [InlineData("пщщв", "good")]
    [InlineData("вщтэе", "don't")]
    [InlineData("ершт", "thin")]
    public void SwitchesRussianGibberishToEnglish(string typed, string alternative)
    {
        Assert.True(_decider.ShouldSwitch(typed, Ru, alternative, En, out _));
    }

    [Theory]
    [InlineData("hello", "руддщ")]
    [InlineData("the", "еру")]
    [InlineData("github", "пшерги")]
    [InlineData("in", "шт")]
    [InlineData("z", "я")]
    [InlineData("iPhone", "шЗрщту")]
    [InlineData("abc123", "фис123")]
    public void KeepsEnglish(string typed, string alternative)
    {
        Assert.False(_decider.ShouldSwitch(typed, En, alternative, Ru, out _));
    }

    [Theory]
    [InlineData("привет", "ghbdtn")]
    [InlineData("руб", "he,")]
    [InlineData("шт", "in")]
    [InlineData("ёлка", "`krf")]
    [InlineData("кто-то", "rnj-nj")]
    public void KeepsRussian(string typed, string alternative)
    {
        Assert.False(_decider.ShouldSwitch(typed, Ru, alternative, En, out _));
    }

    [Fact]
    public void DictionaryCollisionPrefersTheDictionaryWord()
    {
        // "herb" and "руки" share keys; only "руки" is in a dictionary, so it wins. Undoing the
        // correction with the hotkey adds "herb" to the user's exceptions.
        Assert.True(_decider.ShouldSwitch("herb", En, "руки", Ru, out _));
    }

    [Fact]
    public void UserExceptionsAreRespected()
    {
        var decider = new LayoutDecider(word => word == "ghbdtn");

        Assert.False(decider.ShouldSwitch("ghbdtn", En, "привет", Ru, out _));
    }

    [Fact]
    public void ExtractCoreStripsPunctuation()
    {
        Assert.Equal("привет", LayoutDecider.ExtractCore("«привет»,", Ru));
        Assert.Equal("don't", LayoutDecider.ExtractCore("(don't)", En));
        Assert.Equal(string.Empty, LayoutDecider.ExtractCore("?!", En));
    }

    [Fact]
    public void PreviousWordRuleUsesDictionaryOnly()
    {
        Assert.True(_decider.ShouldSwitchPrevious("z", En, "я", Ru));
        Assert.True(_decider.ShouldSwitchPrevious("b", En, "и", Ru));
        Assert.False(_decider.ShouldSwitchPrevious("a", En, "ф", Ru));
        Assert.False(_decider.ShouldSwitchPrevious("x", En, "ч", Ru));
    }
}
