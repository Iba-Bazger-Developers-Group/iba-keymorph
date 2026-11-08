using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace IbaKeyMorph.UI;

/// <summary>
/// IBA brandbook 4.2: IBA Blue for the one main action, white cards on Mist, Ink text, an orange dot as
/// the rare accent, Manrope type (embedded; Segoe UI if it cannot be loaded). See BRAND.md.
/// </summary>
internal static class Theme
{
    // Brandbook palette.
    public static readonly Color Blue = Color.FromArgb(0, 85, 253);      // IBA Blue  #0055FD
    public static readonly Color Ink = Color.FromArgb(16, 20, 33);       // Ink       #101421
    public static readonly Color Mist = Color.FromArgb(240, 243, 250);   // Mist      #F0F3FA
    public static readonly Color Orange = Color.FromArgb(255, 165, 0);   // Orange    #FFA500

    // Roles.
    public static readonly Color Background = Mist;
    public static readonly Color Surface = Color.White;
    public static readonly Color SurfaceHover = Color.FromArgb(230, 236, 249);
    public static readonly Color Border = Color.FromArgb(214, 222, 238);
    public static readonly Color BorderStrong = Color.FromArgb(150, 162, 188);
    public static readonly Color Accent = Blue;
    public static readonly Color AccentHover = Color.FromArgb(0, 70, 208);   // Blue pressed/hover, white text 7.7:1
    public static readonly Color FocusRing = Ink;
    public static readonly Color Text = Ink;
    public static readonly Color Muted = Color.FromArgb(84, 96, 120);        // 6.4:1 on white, 5.7:1 on Mist
    public static readonly Color Caption = AccentHover;                      // small captions in blue, never orange
    public static readonly Color Success = Color.FromArgb(21, 120, 79);
    public static readonly Color Warning = Color.FromArgb(154, 91, 0);       // problems: text, never colour alone

    private const string BrandFamily = "Manrope";
    private const string FallbackFamily = "Segoe UI";
    private static readonly string Family = LoadBrandFont() ? BrandFamily : FallbackFamily;

    public static Font Font(float size, FontStyle style = FontStyle.Regular) => new(Family, size, style);

    public static Image Panda { get; } = LoadImage("IbaKeyMorph.Assets.panda.png");

    /// <summary>Light title bar tinted with the Mist background (Windows 11); plain on older Windows.</summary>
    public static void ApplyChrome(Form form)
    {
        form.BackColor = Background;
        form.ForeColor = Text;
        form.HandleCreated += (_, _) =>
        {
            var off = 0;
            DwmSetWindowAttribute(form.Handle, DwmUseImmersiveDarkMode, ref off, sizeof(int));
            var caption = ColorTranslator.ToWin32(Background);
            DwmSetWindowAttribute(form.Handle, DwmCaptionColor, ref caption, sizeof(int));
            var text = ColorTranslator.ToWin32(Ink);
            DwmSetWindowAttribute(form.Handle, DwmTextColor, ref text, sizeof(int));
        };
    }

    /// <summary>White field with Ink text and the light scroll bars of the system theme.</summary>
    public static void StyleControl(Control control)
    {
        control.BackColor = Surface;
        control.ForeColor = Text;
        control.HandleCreated += (_, _) => SetWindowTheme(control.Handle, "Explorer", null);
    }

    /// <summary>Wraps a borderless control in a white bordered card so it reads as a field.</summary>
    public static Panel Boxed(Control inner, int padding = 8)
    {
        var box = new CardPanel { Padding = new Padding(padding), Radius = 10 };
        inner.Dock = DockStyle.Fill;
        box.Controls.Add(inner);
        return box;
    }

    public static Label SectionCaption(string text) => new()
    {
        Text = text.ToUpperInvariant(),
        AutoSize = true,
        ForeColor = Caption,
        Font = Font(8.5f, FontStyle.Bold),
        Margin = new Padding(0, 0, 0, 6),
    };

    public static Label MutedText(string text, int maxWidth) => new()
    {
        Text = text,
        AutoSize = true,
        MaximumSize = new Size(maxWidth, 0),
        ForeColor = Muted,
        Font = Font(9f),
    };

    /// <summary>Centered message that replaces an empty list or field: what is missing and what to do.</summary>
    public static Label EmptyState(string text) => new()
    {
        Text = text,
        AutoSize = false,
        Dock = DockStyle.Fill,
        TextAlign = ContentAlignment.MiddleCenter,
        ForeColor = Muted,
        BackColor = Surface,
        Font = Font(10f),
        Padding = new Padding(24),
        Visible = false,
    };

    public static GraphicsPath RoundedRectangle(RectangleF r, float radius)
    {
        var d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
        var path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    private const int DwmUseImmersiveDarkMode = 20;
    private const int DwmCaptionColor = 35;
    private const int DwmTextColor = 36;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    private static extern int SetWindowTheme(IntPtr hwnd, string? appName, string? idList);

    [DllImport("gdi32.dll")]
    private static extern IntPtr AddFontMemResourceEx(IntPtr pbFont, uint cbFont, IntPtr pdv, ref uint pcFonts);

    /// <summary>
    /// Registers the embedded Manrope files for this process (GDI and GDI+ both see them) and checks that
    /// the family resolves; otherwise the window text falls back to Segoe UI, the brandbook's system face.
    /// </summary>
    private static bool LoadBrandFont()
    {
        try
        {
            foreach (var resource in new[] { "IbaKeyMorph.Assets.Manrope-Regular.ttf", "IbaKeyMorph.Assets.Manrope-Bold.ttf" })
            {
                using var stream = typeof(Theme).Assembly.GetManifestResourceStream(resource);
                if (stream is null)
                {
                    return false;
                }

                var bytes = new byte[stream.Length];
                stream.ReadExactly(bytes);
                // The memory must stay valid for the life of the process, so it is never freed.
                var memory = Marshal.AllocCoTaskMem(bytes.Length);
                Marshal.Copy(bytes, 0, memory, bytes.Length);
                uint count = 0;
                if (AddFontMemResourceEx(memory, (uint)bytes.Length, IntPtr.Zero, ref count) == IntPtr.Zero)
                {
                    return false;
                }
            }

            using var probe = new Font(BrandFamily, 10f);
            return string.Equals(probe.Name, BrandFamily, StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception ex) when (ex is IOException or ArgumentException or ExternalException or InvalidOperationException)
        {
            return false;
        }
    }

    private static Image LoadImage(string name)
    {
        using var stream = typeof(Theme).Assembly.GetManifestResourceStream(name);
        if (stream is null)
        {
            return new Bitmap(1, 1);
        }

        // The panda tile is a square picture; round its corners like an app icon.
        using var source = new Bitmap(Image.FromStream(stream));
        var rounded = new Bitmap(source.Width, source.Height);
        using var g = Graphics.FromImage(rounded);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        using var path = RoundedRectangle(new RectangleF(0, 0, source.Width, source.Height), source.Width * 0.2237f);
        g.SetClip(path);
        g.DrawImage(source, 0, 0, source.Width, source.Height);
        return rounded;
    }
}

/// <summary>White rounded card with a thin border (brandbook: cards on Mist, 10–16 px radius).</summary>
internal class CardPanel : Panel
{
    public CardPanel()
    {
        BackColor = Theme.Surface;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    }

    public float Radius { get; set; } = 12;

    protected override void OnPaint(PaintEventArgs e) => CardPaint.Draw(e.Graphics, this, Radius);
}

/// <summary>Table layout drawn as a card.</summary>
internal sealed class CardTable : TableLayoutPanel
{
    public CardTable()
    {
        BackColor = Theme.Surface;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
    }

    protected override void OnPaint(PaintEventArgs e) => CardPaint.Draw(e.Graphics, this, 12);
}

internal static class CardPaint
{
    public static void Draw(Graphics g, Control card, float radius)
    {
        g.Clear(card.Parent?.BackColor ?? Theme.Background);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        var rect = new RectangleF(0.5f, 0.5f, card.Width - 1.5f, card.Height - 1.5f);
        using var path = Theme.RoundedRectangle(rect, radius);
        using var fill = new SolidBrush(Theme.Surface);
        using var pen = new Pen(Theme.Border);
        g.FillPath(fill, path);
        g.DrawPath(pen, path);
    }
}

/// <summary>Small filled circle: status dot (with a word beside it) and the orange brand dot.</summary>
internal sealed class Dot : Control
{
    public Dot(Color color, int size = 12)
    {
        Color = color;
        Size = new Size(size, size);
        Margin = new Padding(0, 0, 8, 0);
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.SupportsTransparentBackColor, true);
        TabStop = false;
    }

    public Color Color { get; set; }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.Clear(Parent?.BackColor ?? Theme.Background);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var brush = new SolidBrush(Color);
        e.Graphics.FillEllipse(brush, 0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
    }
}

/// <summary>Context menu colours for the tray menu: white surface, Ink text, Blue selection.</summary>
internal sealed class BrandMenuColors : ProfessionalColorTable
{
    public override Color ToolStripDropDownBackground => Theme.Surface;
    public override Color MenuBorder => Theme.Border;
    public override Color MenuItemBorder => Theme.Accent;
    public override Color MenuItemSelected => Theme.Accent;
    public override Color MenuItemSelectedGradientBegin => Theme.Accent;
    public override Color MenuItemSelectedGradientEnd => Theme.Accent;
    public override Color MenuItemPressedGradientBegin => Theme.AccentHover;
    public override Color MenuItemPressedGradientEnd => Theme.AccentHover;
    public override Color ImageMarginGradientBegin => Theme.Surface;
    public override Color ImageMarginGradientMiddle => Theme.Surface;
    public override Color ImageMarginGradientEnd => Theme.Surface;
    public override Color SeparatorDark => Theme.Border;
    public override Color SeparatorLight => Theme.Border;
    public override Color CheckBackground => Theme.Accent;
    public override Color CheckSelectedBackground => Theme.AccentHover;
    public override Color CheckPressedBackground => Theme.AccentHover;
}

internal sealed class BrandMenuRenderer : ToolStripProfessionalRenderer
{
    public BrandMenuRenderer()
        : base(new BrandMenuColors())
    {
        RoundedEdges = false;
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        // White on the blue selection, Ink on white, Muted when unavailable.
        e.TextColor = !e.Item.Enabled ? Theme.Muted : e.Item.Selected ? Color.White : Theme.Text;
        base.OnRenderItemText(e);
    }

    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
    {
        var r = new Rectangle(e.ImageRectangle.X - 2, e.ImageRectangle.Y - 2, e.ImageRectangle.Width + 4, e.ImageRectangle.Height + 4);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        // On the blue selection the tick box turns white so it stays visible.
        var selected = e.Item.Selected;
        using (var fill = new SolidBrush(selected ? Color.White : Theme.Accent))
        using (var path = Theme.RoundedRectangle(r, 4))
        {
            e.Graphics.FillPath(fill, path);
        }

        using var pen = new Pen(selected ? Theme.Accent : Color.White, 2f);
        var cx = r.X + r.Width / 2f;
        var cy = r.Y + r.Height / 2f;
        e.Graphics.DrawLines(pen, new[]
        {
            new PointF(cx - r.Width * 0.25f, cy),
            new PointF(cx - r.Width * 0.06f, cy + r.Height * 0.2f),
            new PointF(cx + r.Width * 0.27f, cy - r.Height * 0.22f),
        });
    }
}
