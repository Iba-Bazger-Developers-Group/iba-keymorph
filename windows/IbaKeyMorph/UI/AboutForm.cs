using System.Diagnostics;

namespace IbaKeyMorph.UI;

internal sealed class AboutForm : Form
{
    private const string ProjectUrl = "https://github.com/Iba-Bazger-Developers-Group/iba-keymorph";

    public AboutForm()
    {
        var version = typeof(AboutForm).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
        Text = "О программе IBA KeyMorph";
        Icon = TrayIcons.AppIcon;
        Font = Theme.Font(9.5f);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(520, 520);
        Padding = new Padding(28, 24, 28, 24);
        Theme.ApplyChrome(this);

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, BackColor = Theme.Background };
        layout.Controls.Add(new PictureBox
        {
            Image = Theme.Panda,
            SizeMode = PictureBoxSizeMode.Zoom,
            Size = new Size(120, 120),
            Anchor = AnchorStyles.None,
            Margin = new Padding(0, 0, 0, 12),
        });
        var title = new FlowLayoutPanel { AutoSize = true, WrapContents = false, BackColor = Theme.Background, Anchor = AnchorStyles.None };
        title.Controls.Add(new Label
        {
            Text = "IBA KeyMorph",
            AutoSize = true,
            Font = Theme.Font(19f, FontStyle.Bold),
            ForeColor = Theme.Text,
            Margin = new Padding(0, 0, 4, 0),
        });
        // The orange dot of the IBA mark.
        title.Controls.Add(new Dot(Theme.Orange, 9) { Margin = new Padding(0, 24, 0, 0) });
        layout.Controls.Add(title);
        layout.Controls.Add(Centered(Theme.MutedText($"Версия {version} · переключатель раскладки клавиатуры, EN ⇄ RU", 460)));

        var card = new CardTable
        {
            ColumnCount = 1,
            AutoSize = true,
            Dock = DockStyle.Fill,
            Padding = new Padding(16, 12, 16, 12),
            Margin = new Padding(0, 18, 0, 18),
        };
        card.Controls.Add(Theme.SectionCaption("Горячие клавиши"));
        foreach (var line in new[]
                 {
                     "Pause или Shift Shift — исправить / отменить последнее слово",
                     "Shift+Pause — исправить выделенный текст",
                     "Двойной щелчок по значку в трее — настройки",
                 })
        {
            card.Controls.Add(new Label { Text = line, AutoSize = true, ForeColor = Theme.Text, Margin = new Padding(0, 3, 0, 3) });
        }

        layout.Controls.Add(card);

        var link = new LinkLabel
        {
            Text = "Проект на GitHub",
            AutoSize = true,
            LinkColor = Theme.Accent,
            ActiveLinkColor = Theme.AccentHover,
            VisitedLinkColor = Theme.Accent,
            Anchor = AnchorStyles.None,
        };
        link.LinkClicked += (_, _) => Process.Start(new ProcessStartInfo(ProjectUrl) { UseShellExecute = true });
        layout.Controls.Add(link);

        var close = new IbaButton("Закрыть", ButtonKind.Primary)
        {
            Width = 140,
            DialogResult = DialogResult.OK,
            Anchor = AnchorStyles.None,
            Margin = new Padding(0, 16, 0, 0),
        };
        AcceptButton = close;
        CancelButton = close;
        layout.Controls.Add(close);
        layout.Controls.Add(Centered(new Label { Text = "© IBA", AutoSize = true, ForeColor = Theme.Muted, Margin = new Padding(0, 12, 0, 0) }));
        Controls.Add(layout);
    }

    private static Control Centered(Control control)
    {
        control.Anchor = AnchorStyles.None;
        return control;
    }
}
