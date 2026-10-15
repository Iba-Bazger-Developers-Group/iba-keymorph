using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;

namespace IbaKeyMorph.UI;

/// <summary>IBA look: dark green surfaces, green accent, white text (same palette as IBA Publisher).</summary>
internal static class Theme
{
    public static readonly Color Background = Color.FromArgb(15, 26, 23);
    public static readonly Color Surface = Color.FromArgb(24, 37, 32);
    public static readonly Color SurfaceHover = Color.FromArgb(32, 50, 43);
    public static readonly Color Border = Color.FromArgb(47, 72, 61);
    public static readonly Color Accent = Color.FromArgb(46, 125, 91);
    public static readonly Color AccentHover = Color.FromArgb(57, 146, 107);
    public static readonly Color Glow = Color.FromArgb(46, 204, 113);
    public static readonly Color Text = Color.FromArgb(236, 243, 239);
    public static readonly Color Muted = Color.FromArgb(143, 166, 155);
    public static readonly Color Caption = Color.FromArgb(214, 170, 92);

    public static Font Font(float size, FontStyle style = FontStyle.Regular) => new("Segoe UI", size, style);

    public static Image Panda { get; } = LoadImage("IbaKeyMorph.Assets.panda.png");

    /// <summary>Dark title bar (Windows 10 2004+) tinted with the background colour (Windows 11).</summary>
    public static void ApplyChrome(Form form)
    {
        form.BackColor = Background;
        form.ForeColor = Text;
        form.HandleCreated += (_, _) =>
        {
            var on = 1;
            DwmSetWindowAttribute(form.Handle, DwmUseImmersiveDarkMode, ref on, sizeof(int));
            var caption = ColorTranslator.ToWin32(Background);
            DwmSetWindowAttribute(form.Handle, DwmCaptionColor, ref caption, sizeof(int));
        };
    }

    /// <summary>Dark scroll bars and selection for list views and text boxes.</summary>
    public static void DarkControl(Control control)
    {
        control.BackColor = Surface;
        control.ForeColor = Text;
        control.HandleCreated += (_, _) => SetWindowTheme(control.Handle, "DarkMode_Explorer", null);
    }

    /// <summary>Wraps a borderless control in a padded surface so it reads as a dark field.</summary>
    public static Panel Boxed(Control inner, int padding = 8)
    {
        var box = new Panel { BackColor = Surface, Padding = new Padding(padding) };
        inner.Dock = DockStyle.Fill;
        box.Controls.Add(inner);
        return box;
    }

    public static Label SectionCaption(string text) => new()
    {
        Text = text.ToUpperInvariant(),
        AutoSize = true,
        ForeColor = Caption,
        Font = Font(8.25f, FontStyle.Bold),
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

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
    private static extern int SetWindowTheme(IntPtr hwnd, string? appName, string? idList);

    private static Image LoadImage(string name)
    {
        using var stream = typeof(Theme).Assembly.GetManifestResourceStream(name);
        return stream is null ? new Bitmap(1, 1) : new Bitmap(Image.FromStream(stream));
    }
}

/// <summary>Context menu colours for the tray menu.</summary>
internal sealed class DarkMenuColors : ProfessionalColorTable
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

internal sealed class DarkMenuRenderer : ToolStripProfessionalRenderer
{
    public DarkMenuRenderer()
        : base(new DarkMenuColors())
    {
        RoundedEdges = false;
    }

    protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
    {
        e.TextColor = e.Item.Enabled ? Theme.Text : Theme.Muted;
        base.OnRenderItemText(e);
    }

    protected override void OnRenderItemCheck(ToolStripItemImageRenderEventArgs e)
    {
        var r = new Rectangle(e.ImageRectangle.X - 2, e.ImageRectangle.Y - 2, e.ImageRectangle.Width + 4, e.ImageRectangle.Height + 4);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using (var fill = new SolidBrush(Theme.Accent))
        using (var path = Theme.RoundedRectangle(r, 4))
        {
            e.Graphics.FillPath(fill, path);
        }

        using var pen = new Pen(Color.White, 2f);
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
