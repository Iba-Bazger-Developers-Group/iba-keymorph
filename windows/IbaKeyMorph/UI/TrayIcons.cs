using System.Drawing.Drawing2D;
using System.Drawing.Text;
using IbaKeyMorph.Native;

namespace IbaKeyMorph.UI;

/// <summary>Draws the tray badge with the current layout ("EN", "RU") and caches the icons.</summary>
internal sealed class TrayIcons : IDisposable
{
    private readonly Dictionary<(string, bool), Icon> _cache = new();

    public static Icon AppIcon { get; } = LoadAppIcon();

    public Icon For(string label, bool active)
    {
        var key = (label, active);
        if (_cache.TryGetValue(key, out var icon))
        {
            return icon;
        }

        icon = Draw(label, active);
        _cache[key] = icon;
        return icon;
    }

    public void Dispose()
    {
        foreach (var icon in _cache.Values)
        {
            DestroyIconHandle(icon);
        }

        _cache.Clear();
    }

    private static Icon Draw(string label, bool active)
    {
        var size = SystemInformation.SmallIconSize.Width;
        using var bitmap = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bitmap))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.Clear(Color.Transparent);

            var color = !active ? Color.FromArgb(120, 120, 120) : label switch
            {
                "EN" => Color.FromArgb(37, 99, 235),
                "RU" => Color.FromArgb(220, 38, 38),
                _ => Color.FromArgb(124, 58, 237),
            };
            using var background = new SolidBrush(color);
            using var path = RoundedRectangle(new RectangleF(0, 0, size - 1, size - 1), size / 4f);
            g.FillPath(background, path);

            var text = label.Length > 2 ? label[..2] : label;
            using var font = new Font("Segoe UI", size * 0.42f, FontStyle.Bold, GraphicsUnit.Pixel);
            using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            g.DrawString(text, font, Brushes.White, new RectangleF(0, 0, size, size + 1), format);
        }

        var handle = bitmap.GetHicon();
        return Icon.FromHandle(handle);
    }

    private static GraphicsPath RoundedRectangle(RectangleF r, float radius)
    {
        var d = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(r.X, r.Y, d, d, 180, 90);
        path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    private static void DestroyIconHandle(Icon icon)
    {
        var handle = icon.Handle;
        icon.Dispose();
        NativeMethods.DestroyIcon(handle);
    }

    private static Icon LoadAppIcon()
    {
        using var stream = typeof(TrayIcons).Assembly.GetManifestResourceStream("IbaKeyMorph.Assets.keymorph.ico");
        return stream is null ? SystemIcons.Application : new Icon(stream);
    }
}
