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
        Font = Theme.Font(9.5f, FontStyle.Bold);
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

        // Primary and selected tabs: blue with white text (5.6:1). Everything else: white with a border.
        var filled = Kind == ButtonKind.Primary || (Kind == ButtonKind.Tab && _selected);
        var (fill, border) = filled
            ? (_hover && Enabled ? Theme.AccentHover : Theme.Accent, Theme.Accent)
            : (_hover && Enabled ? Theme.SurfaceHover : Theme.Surface, _hover && Enabled ? Theme.BorderStrong : Theme.Border);
        var textColor = filled ? Color.White : Theme.Text;
        if (!Enabled)
        {
            fill = Theme.Mist;
            border = Theme.Border;
            textColor = Theme.Muted;
        }

        var rect = new RectangleF(1.5f, 1.5f, Width - 3.5f, Height - 3.5f);
        using (var path = Theme.RoundedRectangle(rect, 10))
        using (var brush = new SolidBrush(fill))
        using (var pen = new Pen(border))
        {
            g.FillPath(brush, path);
            g.DrawPath(pen, path);
        }

        if (Focused && ShowFocusCues)
        {
            // Visible keyboard focus: an Ink ring outside the button.
            var ring = new RectangleF(0.75f, 0.75f, Width - 2.5f, Height - 2.5f);
            using var ringPath = Theme.RoundedRectangle(ring, 11);
            using var ringPen = new Pen(Theme.FocusRing, 2f);
            g.DrawPath(ringPen, ringPath);
        }

        TextRenderer.DrawText(g, Text, Font, ClientRectangle, textColor,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
    }
}

/// <summary>A label with a switch at the right edge — the IBA replacement for check boxes.</summary>
internal sealed class ToggleRow : Control
{
    private const int SwitchWidth = 40;
    private const int SwitchHeight = 22;
    private bool _checked;

    public ToggleRow(string text)
    {
        Text = text;
        Font = Theme.Font(9.5f);
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
        // A long label wraps inside the width it is given (the switch keeps its place on the right).
        var available = proposedSize.Width > 0 ? proposedSize.Width : (Width > 0 ? Width : int.MaxValue / 4);
        var textWidth = Math.Max(40, available - SwitchWidth - 14);
        var text = TextRenderer.MeasureText(Text, Font, new Size(textWidth, 0), TextFormatFlags.WordBreak | TextFormatFlags.Left);
        return new Size(SwitchWidth + 12 + text.Width + 4, Math.Max(SwitchHeight + 10, text.Height + 10));
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
        var track = new RectangleF(Width - SwitchWidth - 2, top, SwitchWidth, SwitchHeight);
        // On = IBA Blue; off = a mid grey-blue track so the state is visible without colour alone (knob side).
        var off = Color.FromArgb(150, 162, 188);
        using (var path = Theme.RoundedRectangle(track, SwitchHeight / 2f))
        using (var brush = new SolidBrush(_checked ? Theme.Accent : off))
        {
            g.FillPath(brush, path);
        }

        if (Focused && ShowFocusCues)
        {
            var ring = new RectangleF(track.X - 3, track.Y - 3, track.Width + 6, track.Height + 6);
            using var ringPath = Theme.RoundedRectangle(ring, ring.Height / 2f);
            using var ringPen = new Pen(Theme.FocusRing, 2f);
            g.DrawPath(ringPen, ringPath);
        }

        var knob = SwitchHeight - 8;
        var x = _checked ? track.Right - knob - 4 : track.X + 4;
        g.FillEllipse(Brushes.White, x, top + 4, knob, knob);

        var textRect = new Rectangle(0, 0, Width - SwitchWidth - 14, Height);
        TextRenderer.DrawText(g, Text, Font, textRect, ForeColor,
            TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.WordBreak);
    }
}

/// <summary>
/// Owner-drawn program list: icon, name, process name on the right, IBA Blue selection and
/// optional check boxes. Items carry an <see cref="AppEntry"/> in <see cref="ListViewItem.Tag"/>.
/// </summary>
internal sealed class AppListView : ListView
{
    private const int CheckSize = 16;

    public AppListView(bool checkBoxes)
    {
        View = View.Details;
        CheckBoxes = checkBoxes;
        FullRowSelect = true;
        HeaderStyle = ColumnHeaderStyle.None;
        BorderStyle = BorderStyle.None;
        OwnerDraw = true;
        Font = Theme.Font(9.5f);
        SmallImageList = new ImageList { ColorDepth = ColorDepth.Depth32Bit, ImageSize = new Size(28, 28) };
        Columns.Add(string.Empty);
        Theme.StyleControl(this);
        SetStyle(ControlStyles.OptimizedDoubleBuffer, true);
        DrawItem += (_, e) => PaintItem(e);
        DrawSubItem += (_, _) => { };
        Resize += (_, _) => Columns[0].Width = Math.Max(100, ClientSize.Width);
    }

    public ImageList Icons => SmallImageList!;

    public void AddIcon(string key, string? path)
    {
        if (Icons.Images.ContainsKey(key))
        {
            return;
        }

        using var icon = AppCatalog.IconFor(path);
        Icons.Images.Add(key, icon.ToBitmap());
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            SmallImageList?.Dispose();
        }

        base.Dispose(disposing);
    }

    private void PaintItem(DrawListViewItemEventArgs e)
    {
        var g = e.Graphics;
        var bounds = new Rectangle(0, e.Bounds.Y, ClientSize.Width, e.Bounds.Height);
        var selected = e.Item.Selected;
        using (var background = new SolidBrush(selected ? Theme.Accent : Theme.Surface))
        {
            g.FillRectangle(background, bounds);
        }

        var x = bounds.X + 6;
        if (CheckBoxes)
        {
            var box = new Rectangle(x, bounds.Y + (bounds.Height - CheckSize) / 2, CheckSize, CheckSize);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = Theme.RoundedRectangle(box, 4))
            using (var fill = new SolidBrush(e.Item.Checked ? Theme.Accent : Theme.Surface))
            using (var border = new Pen(e.Item.Checked ? Theme.Accent : Theme.BorderStrong))
            {
                g.FillPath(fill, path);
                g.DrawPath(border, path);
            }

            if (e.Item.Checked)
            {
                using var tick = new Pen(Color.White, 2f);
                g.DrawLines(tick, new[]
                {
                    new PointF(box.X + 3.5f, box.Y + 8.5f),
                    new PointF(box.X + 6.5f, box.Y + 11.5f),
                    new PointF(box.X + 12.5f, box.Y + 4.5f),
                });
            }

            g.SmoothingMode = SmoothingMode.Default;
            x += CheckSize + 10;
        }

        var key = e.Item.ImageKey;
        if (!string.IsNullOrEmpty(key) && Icons.Images.ContainsKey(key))
        {
            var size = Math.Min(22, bounds.Height - 6);
            g.DrawImage(Icons.Images[key]!, new Rectangle(x, bounds.Y + (bounds.Height - size) / 2, size, size));
            x += size + 10;
        }

        var secondary = e.Item.Tag is AppEntry app ? app.ProcessName + ".exe" : string.Empty;
        var secondaryWidth = TextRenderer.MeasureText(secondary, Font).Width;
        var right = bounds.Right - 10;
        TextRenderer.DrawText(g, secondary, Font, new Rectangle(right - secondaryWidth, bounds.Y, secondaryWidth, bounds.Height),
            selected ? Color.White : Theme.Muted, TextFormatFlags.VerticalCenter | TextFormatFlags.Right | TextFormatFlags.SingleLine);
        TextRenderer.DrawText(g, e.Item.Text, Font, new Rectangle(x, bounds.Y, Math.Max(0, right - secondaryWidth - 12 - x), bounds.Height),
            selected ? Color.White : Theme.Text, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
    }
}
