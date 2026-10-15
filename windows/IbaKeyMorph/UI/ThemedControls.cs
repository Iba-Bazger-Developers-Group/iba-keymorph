using System.Drawing.Drawing2D;

namespace IbaKeyMorph.UI;

internal enum ButtonKind
{
    Primary,
    Secondary,
    Tab,
}

/// <summary>Rounded button with IBA colours; Tab buttons light up when <see cref="Selected"/>.</summary>
internal sealed class IbaButton : Button
{
    private bool _hover;
    private bool _selected;

    public IbaButton(string text, ButtonKind kind = ButtonKind.Secondary)
    {
        Text = text;
        Kind = kind;
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        Font = Theme.Font(9.75f, FontStyle.Bold);
        ForeColor = Theme.Text;
        BackColor = Theme.Background;
        Cursor = Cursors.Hand;
        Height = 40;
        Padding = new Padding(18, 0, 18, 0);
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
    }

    public ButtonKind Kind { get; }

    public bool Selected
    {
        get => _selected;
        set
        {
            _selected = value;
            Invalidate();
        }
    }

    public override Size GetPreferredSize(Size proposedSize)
    {
        var text = TextRenderer.MeasureText(Text, Font);
        return new Size(text.Width + Padding.Horizontal, Math.Max(Height, text.Height + 16));
    }

    protected override void OnMouseEnter(EventArgs e)
    {
        _hover = true;
        Invalidate();
        base.OnMouseEnter(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        _hover = false;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Parent?.BackColor ?? Theme.Background);

        var (fill, border) = Kind switch
        {
            ButtonKind.Primary => (_hover ? Theme.AccentHover : Theme.Accent, Theme.Accent),
            ButtonKind.Tab when _selected => (Theme.Accent, Theme.Accent),
            _ => (_hover ? Theme.SurfaceHover : Theme.Surface, Theme.Border),
        };
        if (!Enabled)
        {
            fill = Theme.Surface;
        }

        var rect = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
        using (var path = Theme.RoundedRectangle(rect, 8))
        using (var brush = new SolidBrush(fill))
        using (var pen = new Pen(Focused && ShowFocusCues ? Theme.Glow : border))
        {
            g.FillPath(brush, path);
            g.DrawPath(pen, path);
        }

        TextRenderer.DrawText(g, Text, Font, ClientRectangle, Enabled ? Theme.Text : Theme.Muted,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
    }
}

/// <summary>A switch with a label to its right — the IBA replacement for check boxes.</summary>
internal sealed class ToggleRow : Control
{
    private const int SwitchWidth = 40;
    private const int SwitchHeight = 22;
    private bool _checked;

    public ToggleRow(string text)
    {
        Text = text;
        Font = Theme.Font(10f);
        ForeColor = Theme.Text;
        BackColor = Theme.Background;
        Cursor = Cursors.Hand;
        Margin = new Padding(0, 4, 0, 4);
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint |
                 ControlStyles.Selectable | ControlStyles.StandardClick, true);
        TabStop = true;
        AccessibleRole = AccessibleRole.CheckButton;
    }

    public event EventHandler? CheckedChanged;

    public bool Checked
    {
        get => _checked;
        set
        {
            if (_checked == value)
            {
                return;
            }

            _checked = value;
            Invalidate();
            CheckedChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public override Size GetPreferredSize(Size proposedSize)
    {
        var text = TextRenderer.MeasureText(Text, Font);
        return new Size(SwitchWidth + 12 + text.Width + 4, Math.Max(SwitchHeight + 8, text.Height + 8));
    }

    protected override void OnClick(EventArgs e)
    {
        Focus();
        Checked = !Checked;
        base.OnClick(e);
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.KeyCode == Keys.Space)
        {
            Checked = !Checked;
            e.Handled = true;
        }

        base.OnKeyDown(e);
    }

    protected override void OnGotFocus(EventArgs e)
    {
        Invalidate();
        base.OnGotFocus(e);
    }

    protected override void OnLostFocus(EventArgs e)
    {
        Invalidate();
        base.OnLostFocus(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(BackColor);

        var top = (Height - SwitchHeight) / 2f;
        var track = new RectangleF(1, top, SwitchWidth, SwitchHeight);
        using (var path = Theme.RoundedRectangle(track, SwitchHeight / 2f))
        using (var brush = new SolidBrush(_checked ? Theme.Accent : Theme.Surface))
        using (var pen = new Pen(Focused ? Theme.Glow : _checked ? Theme.Accent : Theme.Border, Focused ? 1.5f : 1f))
        {
            g.FillPath(brush, path);
            g.DrawPath(pen, path);
        }

        var knob = SwitchHeight - 8;
        var x = _checked ? track.Right - knob - 4 : track.X + 4;
        using (var brush = new SolidBrush(_checked ? Color.White : Theme.Muted))
        {
            g.FillEllipse(brush, x, top + 4, knob, knob);
        }

        var textRect = new Rectangle(SwitchWidth + 12, 0, Width - SwitchWidth - 12, Height);
        TextRenderer.DrawText(g, Text, Font, textRect, ForeColor,
            TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.WordBreak);
    }
}
