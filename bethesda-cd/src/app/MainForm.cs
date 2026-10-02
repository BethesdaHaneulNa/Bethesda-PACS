// Bethesda CD - the window: sign in, look a patient up by chart number, tick exams, see
// their size, then save them to a folder, to a disc image, or burn them to the disc in
// the drive. What each step does is in DiscFolder.cs, Burner.cs and Emr.cs; this file
// only shows and asks.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace Bethesda.Cd {
  // What is asked of the person at the window - one place, so that a test can answer for them.
  public static class Ask {
    public static Form Owner;
    public static Action<string, string> Message = delegate(string text, string kind) {
      MessageBox.Show(Owner, text, Texts.Get("title"), MessageBoxButtons.OK, kind == "error" ? MessageBoxIcon.Error : kind == "warn" ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
    };
    public static Func<string, bool> Confirm = delegate(string text) {
      return MessageBox.Show(Owner, text, Texts.Get("title"), MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) == DialogResult.Yes;
    };
    public static Func<string, string> Folder = delegate(string start) {
      using (FolderBrowserDialog d = new FolderBrowserDialog { Description = Texts.Get("askFolder"), ShowNewFolderButton = true }) {
        if (!string.IsNullOrEmpty(start) && Directory.Exists(start)) d.SelectedPath = start;
        return d.ShowDialog(Owner) == DialogResult.OK ? d.SelectedPath : "";
      }
    };
    // (suggested file name, folder to start in) -> the .iso path, or ""
    public static Func<string, string, string> IsoFile = delegate(string name, string start) {
      using (SaveFileDialog d = new SaveFileDialog { Filter = "ISO (*.iso)|*.iso", FileName = name, OverwritePrompt = false }) {
        if (!string.IsNullOrEmpty(start) && Directory.Exists(start)) d.InitialDirectory = start;
        return d.ShowDialog(Owner) == DialogResult.OK ? d.FileName : "";
      }
    };
  }

  public class ExportResult { public bool Ok; public string Code = "", Path = "", Verified = "", Error = ""; public int Files; public long Bytes; }

  public class MainForm : Form {
    public readonly EmrClient Emr = new EmrClient(); public readonly Config Config;
    public Dictionary<string, object> Patient;                                  // the answer of /export/patient: patient, clinic, exams
    public BurnerInfo Burner; public bool Busy; public long Need;

    // the controls, by name (a test fills them and reads them)
    public readonly Panel LoginPanel = new Panel(), MainPanel = new Panel();
    public readonly TextBox Url = new TextBox(), LoginBox = new TextBox(), Password = new TextBox(), Chart = new TextBox();
    public readonly Button SignIn = new Button(), SignOut = new Button(), SearchButton = new Button(), Burn = new Button(), Iso = new Button(), FolderButton = new Button();
    public readonly Label LoginMsg = new Label(), Who = new Label(), PatientLine = new Label(), Selection = new Label(), Drive = new Label(), Status = new Label();
    public readonly DataGridView Grid = new DataGridView(); public readonly ProgressBar Progress = new ProgressBar();
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer { Interval = 2000 };
    // What the window showed while it worked (a test listens).
    public event Action<string, int> StatusShown;

    public MainForm(Config config) {
      Config = config; Ask.Owner = this;
      Font font = new Font("Segoe UI", 10f), bold = new Font("Segoe UI", 10f, FontStyle.Bold);
      Text = Texts.Get("title"); Font = font; StartPosition = FormStartPosition.CenterScreen;
      ClientSize = new Size(900, 620); MinimumSize = new Size(760, 520);
      try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }

      // sign-in
      LoginPanel.Dock = DockStyle.Fill;
      Label hint = new Label { Text = Texts.Get("loginHint"), Location = new Point(250, 150), Size = new Size(520, 24), Font = bold };
      LoginPanel.Controls.Add(hint);
      Field(Texts.Get("emrUrl"), 190, Url); Url.Text = Config.EmrUrl;
      Field(Texts.Get("login"), 226, LoginBox);
      Field(Texts.Get("password"), 262, Password); Password.UseSystemPasswordChar = true;
      SignIn.Text = Texts.Get("signIn"); SignIn.Location = new Point(395, 302); SignIn.Size = new Size(160, 32);
      LoginMsg.Location = new Point(250, 346); LoginMsg.Size = new Size(560, 60); LoginMsg.ForeColor = Color.Firebrick;
      Label version = new Label { Text = Product.Name + " " + Product.Version, Location = new Point(250, 420), Size = new Size(300, 20), ForeColor = Color.Gray, Font = new Font("Segoe UI", 8.5f) };
      LoginPanel.Controls.Add(SignIn); LoginPanel.Controls.Add(LoginMsg); LoginPanel.Controls.Add(version);
      SignIn.Click += delegate { Login(); };
      Password.KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Login(); } };

      // the main panel. It has the window's size before anything is put on it: what is
      // anchored to its right and bottom edges keeps its place from there.
      MainPanel.Size = ClientSize; MainPanel.Dock = DockStyle.Fill; MainPanel.Visible = false;
      Who.Location = new Point(14, 14); Who.Size = new Size(600, 24);
      SignOut.Text = Texts.Get("signOut"); SignOut.Size = new Size(150, 28); SignOut.Location = new Point(736, 10); SignOut.Anchor = AnchorStyles.Top | AnchorStyles.Right;
      Label cl = new Label { Text = Texts.Get("chart"), Location = new Point(14, 52), Size = new Size(96, 24) };
      Chart.Location = new Point(112, 49); Chart.Size = new Size(150, 26);
      SearchButton.Text = Texts.Get("search"); SearchButton.Location = new Point(270, 47); SearchButton.Size = new Size(110, 29);
      PatientLine.Location = new Point(14, 86); PatientLine.Size = new Size(872, 24); PatientLine.Font = bold; PatientLine.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right; PatientLine.AutoEllipsis = true;

      Grid.Location = new Point(14, 116); Grid.Size = new Size(872, 330); Grid.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
      Grid.AllowUserToAddRows = false; Grid.AllowUserToDeleteRows = false; Grid.AllowUserToResizeRows = false; Grid.RowHeadersVisible = false;
      Grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect; Grid.MultiSelect = false; Grid.BackgroundColor = Color.White; Grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
      // the line the cursor is on is tinted, not painted over: what counts is the tick
      Grid.DefaultCellStyle.SelectionBackColor = Color.FromArgb(226, 236, 250); Grid.DefaultCellStyle.SelectionForeColor = Color.Black;
      Grid.Columns.Add(new DataGridViewCheckBoxColumn { HeaderText = "", FillWeight = 6 });
      string[] heads = { "colDate", "colType", "colExam", "colImages", "colSize", "colState" }; int[] weights = { 16, 9, 40, 11, 13, 34 };
      for (int i = 0; i < heads.Length; i++) Grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = Texts.Get(heads[i]), FillWeight = weights[i], ReadOnly = true, SortMode = DataGridViewColumnSortMode.NotSortable });
      // a tick counts at once, not when the row is left; a click anywhere on the line ticks it
      Grid.CurrentCellDirtyStateChanged += delegate { if (Grid.IsCurrentCellDirty) Grid.CommitEdit(DataGridViewDataErrorContexts.CurrentCellChange); };
      Grid.CellValueChanged += delegate { UpdateSelection(); };
      Grid.CellClick += delegate(object s, DataGridViewCellEventArgs e) {
        if (e.RowIndex >= 0 && e.ColumnIndex > 0) { DataGridViewCell cell = Grid.Rows[e.RowIndex].Cells[0]; if (!cell.ReadOnly) cell.Value = !Equals(cell.Value, true); }
      };

      Selection.Location = new Point(14, 454); Selection.Size = new Size(872, 24); Selection.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right; Selection.Font = bold;
      Drive.Location = new Point(14, 480); Drive.Size = new Size(872, 24); Drive.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right; Drive.AutoEllipsis = true;
      Action<Button, string, int, int> place = delegate(Button b, string text, int x, int w) { b.Text = text; b.Location = new Point(x, 512); b.Size = new Size(w, 36); b.Anchor = AnchorStyles.Bottom | AnchorStyles.Left; };
      place(Burn, Texts.Get("burn"), 14, 190); Burn.Font = bold;
      place(Iso, Texts.Get("iso"), 214, 250);
      place(FolderButton, Texts.Get("folder"), 474, 270);
      Progress.Location = new Point(14, 562); Progress.Size = new Size(300, 20); Progress.Anchor = AnchorStyles.Bottom | AnchorStyles.Left; Progress.Visible = false; Progress.MarqueeAnimationSpeed = 30;
      Status.Location = new Point(324, 561); Status.Size = new Size(562, 24); Status.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
      MainPanel.Controls.AddRange(new Control[] { Who, SignOut, cl, Chart, SearchButton, PatientLine, Grid, Selection, Drive, Burn, Iso, FolderButton, Progress, Status });

      SignOut.Click += delegate { Logout(""); };
      SearchButton.Click += delegate { Search(); };
      Chart.KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Search(); } };
      Burn.Click += delegate { Export("disc", ""); };
      Iso.Click += delegate { Export("iso", ""); };
      FolderButton.Click += delegate { Export("folder", ""); };

      Controls.Add(MainPanel); Controls.Add(LoginPanel);
      // looked at every two seconds while nothing is being copied: a disc put in is seen by itself
      timer.Tick += delegate { if (MainPanel.Visible) UpdateDrive(); };
      Shown += delegate { timer.Start(); if (Url.Text != "") LoginBox.Focus(); };
      FormClosing += delegate(object s, FormClosingEventArgs e) {
        if (Busy) { e.Cancel = true; Ask.Message(Texts.Get("busyClose"), "warn"); return; }
        timer.Stop(); Emr.Logout(); DiscFolder.RemoveTemp("");
      };
      ClearPatient();
    }
    void Field(string text, int y, TextBox box) {
      LoginPanel.Controls.Add(new Label { Text = text, Location = new Point(250, y + 3), Size = new Size(140, 24) });
      box.Location = new Point(395, y); box.Size = new Size(260, 26); LoginPanel.Controls.Add(box);
    }

    void SetStatus(string text, int percent) {
      Status.Text = text;
      if (percent < 0) Progress.Style = ProgressBarStyle.Marquee; else { Progress.Style = ProgressBarStyle.Continuous; Progress.Value = Math.Max(0, Math.Min(100, percent)); }
      if (StatusShown != null) StatusShown(text, percent);
      Application.DoEvents();
    }
    void SetBusy(bool on) {
      Busy = on;
      foreach (Control c in new Control[] { Chart, SearchButton, Grid, Burn, Iso, FolderButton, SignOut }) c.Enabled = !on;
      Progress.Visible = on;
      if (!on) { Status.Text = ""; Progress.Style = ProgressBarStyle.Continuous; Progress.Value = 0; UpdateSelection(); }
      Application.DoEvents();
    }

    // ── signing in and out ───────────────────────────────────────────────────
    public bool Login() {
      string url = Url.Text.Trim();
      LoginMsg.Text = ""; SignIn.Enabled = false; Application.DoEvents();
      EmrAnswer r = Emr.Login(url, LoginBox.Text.Trim(), Password.Text);
      Password.Text = "";                                  // the password is not kept, even in its box
      SignIn.Enabled = true;
      if (!r.Ok) { LoginMsg.Text = Texts.Error(r.Code, r.Error); return false; }
      if (Config.EmrUrl != url) { Config.EmrUrl = url; Config.Save(); }
      Who.Text = Texts.Get("connected", J.Str(Emr.User, "name"));
      LoginPanel.Visible = false; MainPanel.Visible = true;
      ClearPatient(); Chart.Focus(); UpdateDrive();
      return true;
    }
    public void Logout(string message) {
      Emr.Logout(); ClearPatient();
      MainPanel.Visible = false; LoginPanel.Visible = true;
      LoginMsg.Text = message ?? ""; LoginBox.Focus();
    }

    // ── the patient and the exams ────────────────────────────────────────────
    void ClearPatient() {
      Patient = null; Chart.Text = ""; PatientLine.Text = Texts.Get("noPatientYet"); PatientLine.ForeColor = Color.DimGray;
      Grid.Rows.Clear(); UpdateSelection();
    }
    public bool Search() {
      string chart = Chart.Text.Trim(); if (chart == "") return false;
      SearchButton.Enabled = false; Application.DoEvents();
      EmrAnswer r = Emr.Patient(chart);
      SearchButton.Enabled = true;
      if (!r.Ok) {
        if (r.Code == "LOGIN") { Logout(Texts.Get("expired")); return false; }
        Patient = null; Grid.Rows.Clear();
        PatientLine.Text = Texts.Error(r.Code, r.Error); PatientLine.ForeColor = Color.Firebrick;
        UpdateSelection(); return false;
      }
      Patient = r.Data; Dictionary<string, object> p = J.Dict(r.Data, "patient");
      string gender = J.Str(p, "gender"), sex = gender == "M" ? Texts.Get("male") : gender == "F" ? Texts.Get("female") : "";
      PatientLine.Text = Texts.Get("patient", (J.Str(p, "last_name") + " " + J.Str(p, "first_name")).Trim() + "  ·  " + J.Str(p, "chart_no"), J.Str(p, "date_of_birth"), sex).TrimEnd(' ', '—');
      PatientLine.ForeColor = Color.Black;
      Grid.Rows.Clear();
      foreach (Dictionary<string, object> e in J.List(r.Data, "exams")) {
        string blocked = J.Str(e, "block"), state = blocked != "" ? Texts.Error(blocked, "") : "", size = "", items = "";
        if (blocked == "") { size = DiscFolder.FormatSize(J.Long(e, "bytes"), Texts.Unit); items = J.Str(e, "items"); }
        DataGridViewRow row = Grid.Rows[Grid.Rows.Add(false, J.Str(e, "exam_date"), J.Str(e, "modality"), J.Str(e, "order_name"), items, size, state)];
        row.Tag = e;
        if (blocked != "") { row.Cells[0].ReadOnly = true; row.DefaultCellStyle.ForeColor = Color.Gray; row.DefaultCellStyle.SelectionForeColor = Color.Gray; }
      }
      if (J.Str(r.Data, "server") != "") { PatientLine.Text += "   —   " + Texts.Error(J.Str(r.Data, "server"), ""); PatientLine.ForeColor = Color.Firebrick; }
      UpdateSelection();
      return true;
    }
    public List<Dictionary<string, object>> Chosen() {
      List<Dictionary<string, object>> o = new List<Dictionary<string, object>>();
      foreach (DataGridViewRow row in Grid.Rows) {
        Dictionary<string, object> e = row.Tag as Dictionary<string, object>;
        if (Equals(row.Cells[0].Value, true) && e != null && J.Str(e, "block") == "") o.Add(e);
      }
      return o;
    }
    // The line under the list, the line about the drive, and which buttons can be pressed.
    public void UpdateSelection() {
      List<Dictionary<string, object>> sel = Chosen(); long bytes = 0; int items = 0;
      foreach (Dictionary<string, object> e in sel) { bytes += J.Long(e, "bytes"); items += (int)J.Long(e, "items"); }
      Need = DiscFolder.Estimate(bytes, items + 2) + (DiscFolder.HasViewer ? 262144 : 0);           // (the viewer: well under this)
      Selection.Text = sel.Count > 0 ? Texts.Get("sel", sel.Count, items, DiscFolder.FormatSize(bytes, Texts.Unit)) : Texts.Get("selNone");
      string line = Texts.Get("noBurner"); bool canBurn = false; BurnerInfo b = Burner;
      if (b != null) {
        if (b.State == "used") line = Texts.Get("discUsed", b.Letter);
        else if (b.State == "blank") {
          line = Texts.Get("discBlank", b.Letter, b.Media, DiscFolder.FormatSize(b.FreeBytes, Texts.Unit));
          if (sel.Count > 0) {
            if (Need <= b.FreeBytes) { line += Texts.Get("fits"); canBurn = true; }
            else line += Texts.Get("tooBig", DiscFolder.FormatSize(Need - b.FreeBytes, Texts.Unit));
          }
        } else line = Texts.Get("noDisc", b.Letter);
      }
      Drive.Text = line;
      if (!Busy) { Burn.Enabled = canBurn; Iso.Enabled = sel.Count > 0; FolderButton.Enabled = sel.Count > 0; }
    }
    public void UpdateDrive() {
      if (Busy) return;
      List<BurnerInfo> all = Burners.List(); BurnerInfo pick = null;
      foreach (BurnerInfo b in all) if (b.State == "blank") { pick = b; break; }
      if (pick == null && all.Count > 0) pick = all[0];
      Burner = pick; UpdateSelection();
    }

    // ── the copy ─────────────────────────────────────────────────────────────
    void Wait(DiscJob job, string key) {
      DateTime t0 = DateTime.Now;
      while (job.State == 1) {
        if (job.Step == "image" || job.TotalBytes <= 0) SetStatus(Texts.Get("stImage"), -1);
        else {
          int pct = (int)(100 * job.DoneBytes / job.TotalBytes); TimeSpan el = DateTime.Now - t0;
          string clock = string.Format("{0:00}:{1:00}", (int)Math.Floor(el.TotalMinutes), el.Seconds);
          // The whole image has been handed over: the burner is closing the disc and reading it
          // back - that takes a while and has no figure of its own.
          if (pct >= 100) SetStatus(Texts.Get("stCheck") + "   " + clock, -1); else SetStatus(Texts.Get(key, pct, clock), pct);
        }
        Thread.Sleep(150);
      }
    }
    // medium: folder | iso | disc. target: the base folder or the .iso path (asked when empty).
    public ExportResult Export(string medium, string target) {
      List<Dictionary<string, object>> sel = Chosen();
      if (sel.Count == 0 || Busy) return new ExportResult { Code = "NOTHING" };
      int max = (int)J.Long(Patient, "max_exams");
      if (max > 0 && sel.Count > max) { Ask.Message(Texts.Get("selMax", max), "warn"); return new ExportResult { Code = "TOO_MANY_EXAMS" }; }
      Dictionary<string, object> p = J.Dict(Patient, "patient");
      string name = (J.Str(p, "last_name") + " " + J.Str(p, "first_name")).Trim(), unit = Texts.Unit;
      string stamp = DiscFolder.SafeName(J.Str(p, "chart_no"), 40) + "_" + DateTime.Now.ToString("yyyyMMdd_HHmm");
      long bytes = 0; foreach (Dictionary<string, object> e in sel) bytes += J.Long(e, "bytes");
      BurnerInfo burner = Burner;

      if (medium == "folder") {
        if (string.IsNullOrEmpty(target)) target = Ask.Folder(Config.LastFolder);
        if (string.IsNullOrEmpty(target)) return new ExportResult { Code = "CANCELLED_BY_USER" };
      } else if (medium == "iso") {
        if (string.IsNullOrEmpty(target)) target = Ask.IsoFile(stamp + ".iso", Config.LastFolder);
        if (string.IsNullOrEmpty(target)) return new ExportResult { Code = "CANCELLED_BY_USER" };
        if (File.Exists(target)) { Ask.Message(Texts.Error("EXISTS", ""), "warn"); return new ExportResult { Code = "EXISTS" }; }
      } else if (medium == "disc") {
        if (burner == null || burner.State != "blank" || Need > burner.FreeBytes) { UpdateSelection(); return new ExportResult { Code = "NO_DISC" }; }
        if (!Ask.Confirm(Texts.Get("askBurn", sel.Count, DiscFolder.FormatSize(bytes, unit), name, burner.Letter))) return new ExportResult { Code = "CANCELLED_BY_USER" };
      } else return new ExportResult { Code = "BAD_MEDIUM" };

      SetBusy(true);
      string work = DiscFolder.NewTemp();
      try {
        SetStatus(Texts.Get("stFetch", ""), -1);
        List<string> ids = new List<string>(); foreach (Dictionary<string, object> e in sel) ids.Add(J.Str(e, "id"));
        StepResult b = DiscFolder.Bundle(Emr, ids, medium, work, delegate(long n) { SetStatus(Texts.Get("stFetch", DiscFolder.FormatSize(n, unit)), -1); });
        if (!b.Ok) {
          if (b.Code == "LOGIN") { SetBusy(false); Logout(Texts.Get("expired")); return new ExportResult { Code = "LOGIN" }; }
          Ask.Message(Texts.Error(b.Code, b.Error), "error");
          return new ExportResult { Code = b.Code };
        }
        SetStatus(Texts.Get("stReadme"), -1);
        // the small viewer goes on every disc; a disc without it is still a good disc, and says so
        string note = ""; bool withViewer = false;
        if (DiscFolder.HasViewer) {
          SetStatus(Texts.Get("stViewer"), -1);
          StepResult v = DiscFolder.AddViewer(b.Path);
          if (v.Ok) withViewer = true; else note = Texts.Get("noViewer", v.Error);
        }
        DiscFolder.WriteAutorun(b.Path);                    // only when the viewer is there; the same folder goes to a folder, an image or a disc
        if (b.Unpacked) note += Texts.Get("unpacked");
        DiscFolder.WriteReadme(b.Path, p, J.Dict(Patient, "clinic"), sel, withViewer, DateTime.Now);
        string label = DiscFolder.DiscLabel(J.Str(p, "chart_no"));

        if (medium == "folder") {
          StepResult r = DiscFolder.SaveToFolder(b.Path, target, stamp, delegate(int n, int of) { SetStatus(Texts.Get("stCopy", n, of), 100 * n / of); });
          if (!r.Ok) {
            string msg = r.Code == "NO_ROOM" ? Texts.Error("NO_ROOM", "", DiscFolder.FormatSize(r.Need, unit), DiscFolder.FormatSize(r.Free, unit))
              : r.Code == "NOT_VERIFIED" ? Texts.Error("NOT_VERIFIED", "", r.Bad.Count, r.Path)
              : r.Code == "WRITE_FAILED" ? Texts.Error("WRITE_FAILED", "", r.Error) : Texts.Error(r.Code, "");
            Ask.Message(msg, "error");
            return new ExportResult { Code = r.Code, Path = r.Path };
          }
          Config.LastFolder = target; Config.Save();
          SetBusy(false);
          Ask.Message(Texts.Get("doneFolder", r.Path, r.Files, DiscFolder.FormatSize(r.Bytes, unit)) + note, "info");
          return new ExportResult { Ok = true, Path = r.Path, Files = r.Files, Bytes = r.Bytes };
        }

        if (medium == "iso") {
          DiscJob job = new DiscJob();
          job.StartIso(b.Path, label, DiscFolder.FileSystems, target);
          Wait(job, "stIso");
          if (job.State != 2) {
            try { File.Delete(target); } catch (Exception) { }                 // a half-written image is not left behind
            Ask.Message(Texts.Error("ISO", "", job.Error), "error");
            return new ExportResult { Code = "ISO", Error = job.Error };
          }
          Config.LastFolder = Path.GetDirectoryName(target); Config.Save();
          SetBusy(false);
          long size = new FileInfo(target).Length;
          Ask.Message(Texts.Get("doneIso", target, DiscFolder.FormatSize(size, unit)) + note, "info");
          return new ExportResult { Ok = true, Path = target, Bytes = size };
        }

        // the disc in the drive
        List<DiscFile> files = DiscFolder.Files(b.Path);
        DiscJob burn = new DiscJob();
        burn.StartBurn(b.Path, label, DiscFolder.FileSystems, burner.Id, Burners.ClientName, false);
        Wait(burn, "stBurn");
        if (burn.State != 2) {
          Burners.OpenTray(burner.Id);
          Ask.Message(Texts.Get("badBurn", burn.Error), "error");
          return new ExportResult { Code = "BURN", Error = burn.Error };
        }
        SetStatus(Texts.Get("stCheck"), -1);
        List<string> bad; string seen = Burners.Check(burner.Letter, files, 45, delegate { Application.DoEvents(); }, out bad);
        Burners.OpenTray(burner.Id);
        SetBusy(false);
        if (seen == "different") { Ask.Message(Texts.Get("badVerify", bad.Count), "error"); return new ExportResult { Code = "VERIFY" }; }
        if (seen == "same") { Ask.Message(Texts.Get("doneBurn") + note, "info"); return new ExportResult { Ok = true, Verified = "read" }; }
        if (burn.CheckedByBurner) { Ask.Message(Texts.Get("doneBurnDrive") + note, "info"); return new ExportResult { Ok = true, Verified = "burner" }; }
        Ask.Message(Texts.Get("doneBurnUnread"), "warn");
        return new ExportResult { Ok = true, Verified = "no" };
      } catch (Exception e) {
        Ask.Message(Texts.Get("e_other", e.Message), "error");
        return new ExportResult { Code = "ERROR", Error = e.Message };
      } finally {
        DiscFolder.RemoveTemp(work);                         // what was fetched does not stay on this PC
        if (Busy) SetBusy(false);
        UpdateDrive();
      }
    }
  }
}
