using System.Text;
using IbaKeyMorph.Core;

namespace IbaKeyMorph.Core.Tests;

/// <summary>
/// A fake text field plus keyboard: the user presses the keys of the text they intend to write,
/// the active layout decides what appears, and engine actions are applied like the real apps do.
/// </summary>
internal sealed class Simulator
{
    private readonly IReadOnlyList<IKeyboardLayout> _layouts;

    public Simulator(TableLayout active, EngineOptions? options = null)
    {
        _layouts = new IKeyboardLayout[] { BuiltInLayouts.English, BuiltInLayouts.Russian };
        Active = active;
        var decider = new LayoutDecider(word => Learned.Contains(word));
        Engine = new TypingEngine(decider, options ?? new EngineOptions());
    }

    public TypingEngine Engine { get; }

    public TableLayout Active { get; private set; }

    public bool Caps { get; set; }

    public StringBuilder Text { get; } = new();

    public HashSet<string> Learned { get; } = new();

    public List<EngineResult> Results { get; } = new();

    public override string ToString() => Text.ToString();

    /// <summary>Presses the keys that produce <paramref name="text"/> in <paramref name="intended"/>.</summary>
    public Simulator Type(string text, TableLayout intended)
    {
        foreach (var c in text)
        {
            switch (c)
            {
                case ' ':
                    Boundary(BoundaryKind.Space, ' ');
                    break;
                case '\n':
                    Boundary(BoundaryKind.Enter, '\n');
                    break;
                case '\t':
                    Boundary(BoundaryKind.Tab, '\t');
                    break;
                case '\b':
                    Engine.OnBackspace();
                    Text.Length--;
                    break;
                default:
                    // With Caps Lock on, the user still presses the keys of the intended text.
                    var key = intended.Find(c, Caps);
                    if (key is null)
                    {
                        throw new ArgumentException($"No key for '{c}' in {intended.ShortName}");
                    }

                    Engine.OnCharacterKey(key.Value, Active);
                    Text.Append(Active.Render(key.Value));
                    break;
            }
        }

        return this;
    }

    public Simulator Hotkey()
    {
        Apply(Engine.ConvertLastWord(_layouts), null);
        return this;
    }

    private void Boundary(BoundaryKind kind, char c)
    {
        var result = Engine.OnBoundary(kind, _layouts);
        if (!result.Swallow)
        {
            Text.Append(c);
        }

        Apply(result, c);
    }

    private void Apply(EngineResult result, char? boundary)
    {
        Results.Add(result);
        foreach (var action in result.Actions)
        {
            switch (action)
            {
                case EngineAction.Erase erase:
                    Text.Length -= erase.Count;
                    break;
                case EngineAction.Type type:
                    Text.Append(type.Text);
                    break;
                case EngineAction.ReplayBoundary:
                    Text.Append(boundary ?? throw new InvalidOperationException("Nothing to replay"));
                    break;
                case EngineAction.SwitchLayout switchLayout:
                    Active = (TableLayout)switchLayout.Layout;
                    break;
                case EngineAction.CapsLockOff:
                    Caps = false;
                    break;
                case EngineAction.LearnException learn:
                    Learned.Add(learn.Word);
                    break;
            }
        }
    }
}
