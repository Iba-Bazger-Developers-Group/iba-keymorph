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

        using (var about = new AboutForm())
        {
            Save(about, Path.Combine(directory, "about.png"));
        }

        using (var picker = new AppPickerForm(Array.Empty<string>()))
        {
            Save(picker, Path.Combine(directory, "picker.png"));
        }
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
