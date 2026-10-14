using IbaKeyMorph.UI;

namespace IbaKeyMorph;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(initiallyOwned: true, @"Local\IBA.KeyMorph.SingleInstance", out var isFirst);
        if (!isFirst)
        {
            MessageBox.Show("IBA KeyMorph уже запущен — значок находится в области уведомлений.", "IBA KeyMorph",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        Application.ThreadException += (_, e) => Log.Error("UI thread exception", e.Exception);
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Log.Error("Unhandled exception", e.ExceptionObject as Exception);
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApplicationContext());
    }
}
