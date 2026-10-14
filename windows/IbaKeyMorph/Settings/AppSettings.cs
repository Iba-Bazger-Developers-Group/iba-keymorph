using System.Text.Json;

namespace IbaKeyMorph.Settings;

internal sealed class AppSettings
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    public static string Directory { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "IBA", "KeyMorph");

    private static string FilePath => Path.Combine(Directory, "settings.json");

    /// <summary>Master switch: when off, KeyMorph ignores the keyboard completely.</summary>
    public bool Enabled { get; set; } = true;

    public bool AutoSwitch { get; set; } = true;

    public bool CorrectPreviousShortWord { get; set; } = true;

    public bool FixCapsLock { get; set; } = true;

    /// <summary>Pause: convert last word; Shift+Pause: convert selection.</summary>
    public bool PauseHotkeys { get; set; } = true;

    public bool DoubleShiftHotkey { get; set; } = true;

    public bool PlaySound { get; set; }

    public bool FirstRun { get; set; } = true;

    /// <summary>Words that are never corrected (normalised: lower case, ё → е).</summary>
    public SortedSet<string> Exceptions { get; set; } = new(StringComparer.Ordinal);

    /// <summary>Process names (without .exe) where automatic correction is off.</summary>
    public SortedSet<string> ExcludedApps { get; set; } = new(StringComparer.OrdinalIgnoreCase)
    {
        "windowsterminal",
        "putty",
        "mstsc",
        "vmconnect",
        "keepass",
        "keepassxc",
        "1password",
        "bitwarden",
    };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var loaded = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), JsonOptions);
                if (loaded is not null)
                {
                    loaded.Exceptions = new SortedSet<string>(loaded.Exceptions, StringComparer.Ordinal);
                    loaded.ExcludedApps = new SortedSet<string>(loaded.ExcludedApps, StringComparer.OrdinalIgnoreCase);
                    return loaded;
                }
            }
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            Log.Error("Failed to load settings, using defaults", ex);
        }

        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            var temp = FilePath + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(this, JsonOptions));
            File.Move(temp, FilePath, overwrite: true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Log.Error("Failed to save settings", ex);
        }
    }
}
