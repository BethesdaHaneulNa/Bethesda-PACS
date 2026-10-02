// Bethesda CD - "is this the same patient?": what the disc says of the patient beside what
// the chart says, shown before anything is sent. The name is shown, never judged (every
// hospital writes it its own way); a day of birth or a sex that differs is shown in red,
// and the person must then say "all the same" in so many words. Nothing goes on without
// the tick.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace Bethesda.Cd {
  // What the window shows - and, once answered, what the EMR is told was seen.
  public class ConfirmInfo {
    public string DiscName = "", DiscId = "", DiscBirth = "", DiscSex = "", ChartName = "", ChartNo = "", ChartBirth = "", ChartSex = "";
    public bool BirthDiffers, SexDiffers; public List<string> Exams = new List<string>();
    public bool Differs { get { return BirthDiffers || SexDiffers; } }
  }

  public class ImportConfirmForm : Form {
    public readonly CheckBox Sure = new CheckBox(); public readonly Button Go = new Button(), Stop = new Button();

    public ImportConfirmForm(ConfirmInfo info) {
      Font font = new Font("Segoe UI", 10f), bold = new Font("Segoe UI", 10f, FontStyle.Bold);
      Text = Texts.Get("cfTitle"); Font = font; StartPosition = FormStartPosition.CenterParent; FormBorderStyle = FormBorderStyle.FixedDialog;
      MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = false; ClientSize = new Size(640, 100);
      int y = 16;
      Controls.Add(new Label { Text = Texts.Get("cfDisc"), Location = new Point(110, y), Size = new Size(220, 22), Font = bold });
      Controls.Add(new Label { Text = Texts.Get("cfChart"), Location = new Point(340, y), Size = new Size(190, 22), Font = bold });
      y += 28;
      y = Row(y, Texts.Get("cfName"), info.DiscName, info.ChartName, false, false, bold);
      y = Row(y, Texts.Get("cfNumber"), info.DiscId, info.ChartNo, false, false, bold);
      y = Row(y, Texts.Get("cfBirth"), info.DiscBirth, info.ChartBirth, true, info.BirthDiffers, bold);
      y = Row(y, Texts.Get("cfSex"), info.DiscSex, info.ChartSex, true, info.SexDiffers, bold);
      Controls.Add(new Label { Text = Texts.Get("cfNameNote"), Location = new Point(16, y + 2), Size = new Size(608, 20), ForeColor = Color.DimGray, Font = new Font("Segoe UI", 8.5f) });
      y += 30;
      List<string> lines = new List<string>(); lines.Add(Texts.Get("cfExams"));
      for (int i = 0; i < info.Exams.Count && i < 6; i++) lines.Add("   " + info.Exams[i]);
      if (info.Exams.Count > 6) lines.Add("   " + Texts.Get("cfMore", info.Exams.Count - 6));
      Controls.Add(new Label { Text = string.Join("\n", lines), Location = new Point(16, y), Size = new Size(608, 20 * lines.Count + 4), AutoEllipsis = true });
      y += 20 * lines.Count + 14;
      Sure.Text = Texts.Get(info.Differs ? "cfCheckDiffer" : "cfCheck"); Sure.Location = new Point(16, y); Sure.Size = new Size(608, info.Differs ? 46 : 26);
      Sure.CheckAlign = ContentAlignment.TopLeft; Sure.TextAlign = ContentAlignment.TopLeft; Sure.Font = bold;
      if (info.Differs) Sure.ForeColor = Color.Firebrick;
      Controls.Add(Sure);
      y += Sure.Height + 14;
      Stop.Text = Texts.Get("impCancel"); Stop.Location = new Point(364, y); Stop.Size = new Size(120, 34); Stop.DialogResult = DialogResult.Cancel;
      Go.Text = Texts.Get("cfGo"); Go.Location = new Point(494, y); Go.Size = new Size(130, 34); Go.Font = bold; Go.Enabled = false; Go.DialogResult = DialogResult.OK;
      Controls.Add(Stop); Controls.Add(Go);
      Sure.CheckedChanged += delegate { Go.Enabled = Sure.Checked; };
      CancelButton = Stop;                                 // Esc = no; Enter does nothing until the tick is there
      ClientSize = new Size(640, y + 50);
    }
    // One line: what the disc says, what the chart says, and - where the two are compared - whether they agree.
    int Row(int y, string label, string disc, string chart, bool compared, bool differs, Font bold) {
      Color ink = differs ? Color.Firebrick : Color.Black; Font f = differs ? bold : Font;
      Controls.Add(new Label { Text = label, Location = new Point(16, y), Size = new Size(90, 22), ForeColor = Color.DimGray });
      Controls.Add(new Label { Text = disc == "" ? "—" : disc, Location = new Point(110, y), Size = new Size(224, 22), ForeColor = ink, Font = f, AutoEllipsis = true });
      Controls.Add(new Label { Text = chart == "" ? "—" : chart, Location = new Point(340, y), Size = new Size(186, 22), ForeColor = ink, Font = f, AutoEllipsis = true });
      if (compared && disc != "" && chart != "")
        Controls.Add(new Label { Text = Texts.Get(differs ? "cfDiffer" : "cfSame"), Location = new Point(530, y), Size = new Size(100, 22), ForeColor = differs ? Color.Firebrick : Color.SeaGreen, Font = bold });
      return y + 24;
    }

    public static bool Ask(Form owner, ConfirmInfo info) {
      using (ImportConfirmForm f = new ImportConfirmForm(info)) return f.ShowDialog(owner) == DialogResult.OK && f.Sure.Checked;
    }
  }
}
