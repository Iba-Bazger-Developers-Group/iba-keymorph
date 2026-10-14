using System.Runtime.InteropServices;
using IbaKeyMorph.Core;
using IbaKeyMorph.Native;
using static IbaKeyMorph.Native.NativeMethods;

namespace IbaKeyMorph;

/// <summary>
/// Shift+Pause: copies the selection, re-types it in the other layout via paste and restores the
/// user's clipboard afterwards. Runs on the UI (STA) thread.
/// </summary>
internal static class SelectionConverter
{
    private static readonly TimeSpan CopyTimeout = TimeSpan.FromMilliseconds(600);

    /// <summary>Returns the layout the text was converted to, or null if nothing happened.</summary>
    public static async Task<IKeyboardLayout?> ConvertAsync(IReadOnlyList<IKeyboardLayout> layouts)
    {
        var backup = ClipboardBackup.Capture();
        try
        {
            var sequence = GetClipboardSequenceNumber();
            new InputSender().ReleaseHeldModifiers().Chord(VK_CONTROL, VK_C).Flush();

            var deadline = DateTime.UtcNow + CopyTimeout;
            while (GetClipboardSequenceNumber() == sequence && DateTime.UtcNow < deadline)
            {
                await Task.Delay(20);
            }

            if (GetClipboardSequenceNumber() == sequence)
            {
                return null; // nothing selected
            }

            var text = await Retry(() => Clipboard.ContainsText() ? Clipboard.GetText() : string.Empty);
            if (string.IsNullOrEmpty(text) || TextConverter.PickConversion(text, layouts) is not { } conversion)
            {
                return null;
            }

            var converted = TextConverter.Convert(text, conversion.From, conversion.To);
            await Retry(() =>
            {
                Clipboard.SetText(converted);
                return true;
            });
            new InputSender().Chord(VK_CONTROL, VK_V).Flush();

            // Give the target application time to read the clipboard before restoring it.
            await Task.Delay(400);
            return conversion.To;
        }
        finally
        {
            backup.Restore();
        }
    }

    private static async Task<T> Retry<T>(Func<T> action)
    {
        for (var attempt = 0; ; attempt++)
        {
            try
            {
                return action();
            }
            catch (ExternalException) when (attempt < 5)
            {
                // Another process holds the clipboard open.
                await Task.Delay(50);
            }
        }
    }

    private sealed class ClipboardBackup
    {
        private readonly DataObject? _data;

        private ClipboardBackup(DataObject? data) => _data = data;

        public static ClipboardBackup Capture()
        {
            try
            {
                var current = Clipboard.GetDataObject();
                if (current is null)
                {
                    return new ClipboardBackup(null);
                }

                var copy = new DataObject();
                foreach (var format in current.GetFormats(autoConvert: false))
                {
                    try
                    {
                        if (current.GetData(format, autoConvert: false) is { } value)
                        {
                            copy.SetData(format, autoConvert: false, value);
                        }
                    }
                    catch (Exception ex) when (ex is ExternalException or OutOfMemoryException or InvalidOperationException)
                    {
                        // Some formats (delayed rendering, metafiles) cannot be copied; skip them.
                    }
                }

                return new ClipboardBackup(copy);
            }
            catch (ExternalException)
            {
                return new ClipboardBackup(null);
            }
        }

        public void Restore()
        {
            try
            {
                if (_data is null)
                {
                    Clipboard.Clear();
                }
                else
                {
                    Clipboard.SetDataObject(_data, copy: true);
                }
            }
            catch (ExternalException ex)
            {
                Log.Error("Could not restore clipboard", ex);
            }
        }
    }
}
