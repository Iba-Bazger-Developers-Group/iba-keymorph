using IbaKeyMorph.Settings;

namespace IbaKeyMorph.UI;

/// <summary>
/// `IbaKeyMorph.exe --render-ui &lt;dir&gt;` draws the windows into PNG files and exits; CI uses it to
/// review the UI without a person at the screen. No hooks are installed.
/// </summary>
internal static class UiSnapshots
{
    public static void Render(string directory)
    {
        Directory.CreateDirectory(directory);
        var settings = new AppSettings();
        using var service = new KeyMorphService(settings, new WindowsFormsSynchronizationContext());

        using (var form = new SettingsForm(settings, service))
        {
            for (var page = 0; page < 3; page++)
            {
                form.ShowPage(page);
                Save(form, Path.Combine(directory, $"settings-{page + 1}.png"));
            }
        }

        // Empty program list: the empty-state message instead of a blank box.
        var emptySettings = new AppSettings { ExcludedApps = new SortedSet<string>(StringComparer.OrdinalIgnoreCase) };
        using (var form = new SettingsForm(emptySettings, service))
        {
            form.ShowPage(2);
            Save(form, Path.Combine(directory, "settings-3-empty.png"));
        }

        SaveTrayIcons(Path.Combine(directory, "tray-icons.png"));

        using (var about = new AboutForm())
        {
            Save(about, Path.Combine(directory, "about.png"));
        }

        using (var picker = new AppPickerForm(Array.Empty<string>()))
        {
            Save(picker, Path.Combine(directory, "picker.png"));
        }
    }

    /// <summary>Tray badges (EN, RU, other layout, switched off) magnified 8x on the tray background colours.</summary>
    private static void SaveTrayIcons(string path)
    {
        using var icons = new TrayIcons();
        var items = new[] { ("EN", true), ("RU", true), ("UK", true), ("EN", false) };
        var cell = SystemInformation.SmallIconSize.Width * 8;
        using var sheet = new Bitmap(cell * items.Length + 16 * (items.Length + 1), cell + 32);
        using (var g = Graphics.FromImage(sheet))
        {
            g.Clear(Color.FromArgb(32, 32, 32));
            g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.NearestNeighbor;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.Half;
            for (var i = 0; i < items.Length; i++)
            {
                using var bitmap = icons.For(items[i].Item1, items[i].Item2).ToBitmap();
                g.DrawImage(bitmap, 16 + i * (cell + 16), 16, cell, cell);
            }
        }

        sheet.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }

    private static void Save(Form form, string path)
    {
        form.StartPosition = FormStartPosition.Manual;
        form.Location = new Point(40, 40);
        form.Show();
        for (var i = 0; i < 5; i++)
        {
            Application.DoEvents();
            Thread.Sleep(50);
        }

        using var bitmap = new Bitmap(form.Width, form.Height);
        form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, form.Size));
        bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        form.Hide();
    }
}
