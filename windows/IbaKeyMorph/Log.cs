using IbaKeyMorph.Settings;

namespace IbaKeyMorph;

/// <summary>Tiny append-only log in %APPDATA%\IBA\KeyMorph\keymorph.log (errors only, no keystrokes).</summary>
internal static class Log
{
    private const long MaxSize = 512 * 1024;
    private static readonly object Gate = new();

    public static string FilePath => Path.Combine(AppSettings.Directory, "keymorph.log");

    public static void Error(string message, Exception? ex = null) => Write("ERROR", $"{message}{(ex is null ? string.Empty : ": " + ex)}");

    public static void Info(string message) => Write("INFO", message);

    private static void Write(string level, string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(AppSettings.Directory);
                var file = new FileInfo(FilePath);
                if (file.Exists && file.Length > MaxSize)
                {
                    File.Move(FilePath, FilePath + ".old", overwrite: true);
                }

                File.AppendAllText(FilePath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {level} {message}{Environment.NewLine}");
            }
        }
        catch (IOException)
        {
            // Logging must never take the app down.
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
