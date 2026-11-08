namespace IbaKeyMorph.UI;

/// <summary>The tray context menu in the IBA style. Also built by --render-ui with empty actions.</summary>
internal sealed class TrayMenu
{
    public TrayMenu(
        Action about, Action toggleEnabled, Action toggleAutoSwitch, Action convertSelection, Action settings,
        Action openLog, Action toggleDiagnostics, Action exit)
    {
        Enabled = new ToolStripMenuItem("Включено", null, (_, _) => toggleEnabled()) { CheckOnClick = false };
        AutoSwitch = new ToolStripMenuItem("Автоматическое переключение", null, (_, _) => toggleAutoSwitch());
        Diagnostics = new ToolStripMenuItem("Подробная диагностика (пишет слова в журнал)", null, (_, _) => toggleDiagnostics());
        Strip = new ContextMenuStrip
        {
            Renderer = new BrandMenuRenderer(),
            BackColor = Theme.Surface,
            ForeColor = Theme.Text,
            Font = Theme.Font(9.5f),
            ShowImageMargin = true,
        };
        Strip.Items.Add(new ToolStripMenuItem("IBA KeyMorph", Theme.Panda, (_, _) => about()) { Font = Theme.Font(9.5f, FontStyle.Bold) });
        Strip.Items.Add(new ToolStripSeparator());
        Strip.Items.Add(Enabled);
        Strip.Items.Add(AutoSwitch);
        Strip.Items.Add(new ToolStripMenuItem("Исправить выделенный текст", null, (_, _) => convertSelection())
        {
            ShortcutKeyDisplayString = "Shift+Pause",
        });
        Strip.Items.Add(new ToolStripSeparator());
        Strip.Items.Add(new ToolStripMenuItem("Настройки…", null, (_, _) => settings()));
        Strip.Items.Add(new ToolStripMenuItem("О программе", null, (_, _) => about()));
        Strip.Items.Add(new ToolStripMenuItem("Открыть журнал", null, (_, _) => openLog()));
        Strip.Items.Add(Diagnostics);
        Strip.Items.Add(new ToolStripSeparator());
        Strip.Items.Add(new ToolStripMenuItem("Выход", null, (_, _) => exit()));
    }

    public ContextMenuStrip Strip { get; }

    public ToolStripMenuItem Enabled { get; }

    public ToolStripMenuItem AutoSwitch { get; }

    public ToolStripMenuItem Diagnostics { get; }
}
