// Bethesda CD - the window: sign in, look a patient up by chart number, then one of two
// things.
//   Copy out   tick the patient's exams, see their size, save them to a folder, to a disc
//              image, or burn them to the disc in the drive.
//   Bring in   choose a CD or a folder another hospital gave the patient, tick its exams,
//              confirm that they are this patient's, and send them to the EMR.
// What each step does is in DiscFolder.cs, Burner.cs, ImportDisc.cs and Emr.cs; this file
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
    public static Func<string, string> Folder = delegate(string start) { return Browse(start, "askFolder", true); };
    // The disc or folder to bring in: only looked at, so no "new folder" button.
    public static Func<string, string> Source = delegate(string start) { return Browse(start, "askSource", false); };
    static string Browse(string start, string words, bool mayCreate) {
      using (FolderBrowserDialog d = new FolderBrowserDialog { Description = Texts.Get(words), ShowNewFolderButton = mayCreate }) {
        if (!string.IsNullOrEmpty(start) && Directory.Exists(start)) d.SelectedPath = start;
        return d.ShowDialog(Owner) == DialogResult.OK ? d.SelectedPath : "";
      }
    }
    // (suggested file name, folder to start in) -> the .iso path, or ""
    public static Func<string, string, string> IsoFile = delegate(string name, string start) {
      using (SaveFileDialog d = new SaveFileDialog { Filter = "ISO (*.iso)|*.iso", FileName = name, OverwritePrompt = false }) {
        if (!string.IsNullOrEmpty(start) && Directory.Exists(start)) d.InitialDirectory = start;
        return d.ShowDialog(Owner) == DialogResult.OK ? d.FileName : "";
      }
    };
    // "Is this the same patient?" - true only when the person ticked the box and pressed the button.
    public static Func<ConfirmInfo, bool> SamePatient = delegate(ConfirmInfo info) { return ImportConfirmForm.Ask(Owner, info); };
  }

  public class ExportResult { public bool Ok; public string Code = "", Path = "", Verified = "", Error = ""; public int Files; public long Bytes; }
  // How bringing in ended: how many exams and images went into the chart, how many did not.
  public class ImportResult { public bool Ok, Cancelled; public string Code = ""; public int Imported, Images, Failed, Dropped; public List<string> Errors = new List<string>(), Undrawn = new List<string>(); }

  public class MainForm : Form {
    public readonly EmrClient Emr = new EmrClient(); public readonly Config Config;
    public Dictionary<string, object> Patient;                                  // the answer of /export/patient: patient, clinic, exams
    public Dictionary<string, object> ImportInfo;                               // the answer of /import/patient: patient, limits, what was brought in before
    public string ImportError = "";                                             // why bringing in is not possible for this patient ("" = it is)
    public string CheckError = "";                                              // why the EMR could not say what it knows of the disc's exams
    public ImportSource Source;                                                 // the disc or folder being brought in
    public BurnerInfo Burner; public bool Busy; public long Need;
    public string Mode = "export";                                              // export | import
    volatile bool stopAsked; bool canStop; string lastSource = "";

    // the controls, by name (a test fills them and reads them)
    public readonly Panel LoginPanel = new Panel(), MainPanel = new Panel(), ExportPanel = new Panel(), ImportPanel = new Panel();
    public readonly TextBox Url = new TextBox(), LoginBox = new TextBox(), Password = new TextBox(), Chart = new TextBox();
    public readonly Button SignIn = new Button(), SignOut = new Button(), SearchButton = new Button(), Burn = new Button(), Iso = new Button(), FolderButton = new Button();
    public readonly Button ModeExport = new Button(), ModeImport = new Button(), ChooseSource = new Button(), ImportButton = new Button(), StopButton = new Button();
    public readonly Label LoginMsg = new Label(), Who = new Label(), PatientLine = new Label(), Selection = new Label(), Drive = new Label(), Status = new Label();
    public readonly Label SourceLine = new Label(), DiscLine = new Label(), ImportSelection = new Label(), RoomLine = new Label();
    public readonly DataGridView Grid = new DataGridView(), ImportGrid = new DataGridView(); public readonly ProgressBar Progress = new ProgressBar();
    readonly System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer { Interval = 2000 };
    readonly Font plain = new Font("Segoe UI", 10f), bold = new Font("Segoe UI", 10f, FontStyle.Bold);
    // What the window showed while it worked (a test listens).
    public event Action<string, int> StatusShown;

    public MainForm(Config config) {
      Config = config; Ask.Owner = this;
      Text = Texts.Get("title"); Font = plain; StartPosition = FormStartPosition.CenterScreen;
      ClientSize = new Size(900, 620); MinimumSize = new Size(820, 560);
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
      // the two ways, side by side: the one in use is the one that looks pressed
      ModeExport.Text = Texts.Get("modeExport"); ModeExport.Location = new Point(14, 8); ModeExport.Size = new Size(190, 32);
      ModeImport.Text = Texts.Get("modeImport"); ModeImport.Location = new Point(208, 8); ModeImport.Size = new Size(250, 32);
      foreach (Button m in new[] { ModeExport, ModeImport }) { m.FlatStyle = FlatStyle.Flat; m.FlatAppearance.BorderColor = Color.FromArgb(150, 170, 200); }
      Who.Location = new Point(466, 14); Who.Size = new Size(262, 24); Who.TextAlign = ContentAlignment.MiddleRight; Who.AutoEllipsis = true; Who.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
      SignOut.Text = Texts.Get("signOut"); SignOut.Size = new Size(150, 28); SignOut.Location = new Point(736, 10); SignOut.Anchor = AnchorStyles.Top | AnchorStyles.Right;
      Label cl = new Label { Text = Texts.Get("chart"), Location = new Point(14, 52), Size = new Size(96, 24) };
      Chart.Location = new Point(112, 49); Chart.Size = new Size(150, 26);
      SearchButton.Text = Texts.Get("search"); SearchButton.Location = new Point(270, 47); SearchButton.Size = new Size(110, 29);
      PatientLine.Location = new Point(14, 86); PatientLine.Size = new Size(872, 24); PatientLine.Font = bold; PatientLine.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right; PatientLine.AutoEllipsis = true;

      // ── copy out ──
      ExportPanel.Location = new Point(0, 112); ExportPanel.Size = new Size(900, 440); ExportPanel.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
      Grid.Location = new Point(14, 4); Grid.Size = new Size(872, 330);
      string[] heads = { "colDate", "colType", "colExam", "colImages", "colSize", "colState" }; int[] weights = { 16, 9, 40, 11, 13, 34 };
      SetUpList(Grid, heads, weights);
      Grid.CellValueChanged += delegate { UpdateSelection(); };
      Selection.Location = new Point(14, 342); Selection.Size = new Size(872, 24); Selection.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right; Selection.Font = bold;
      Drive.Location = new Point(14, 368); Drive.Size = new Size(872, 24); Drive.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right; Drive.AutoEllipsis = true;
      Action<Button, string, int, int> place = delegate(Button b, string text, int x, int w) { b.Text = text; b.Location = new Point(x, 400); b.Size = new Size(w, 36); b.Anchor = AnchorStyles.Bottom | AnchorStyles.Left; };
      place(Burn, Texts.Get("burn"), 14, 190); Burn.Font = bold;
      place(Iso, Texts.Get("iso"), 214, 250);
      place(FolderButton, Texts.Get("folder"), 474, 270);
      ExportPanel.Controls.AddRange(new Control[] { Grid, Selection, Drive, Burn, Iso, FolderButton });

      // ── bring in ──
      ImportPanel.Location = ExportPanel.Location; ImportPanel.Size = ExportPanel.Size; ImportPanel.Anchor = ExportPanel.Anchor; ImportPanel.Visible = false;
      SourceLine.Location = new Point(14, 8); SourceLine.Size = new Size(622, 24); SourceLine.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right; SourceLine.AutoEllipsis = true;
      ChooseSource.Text = Texts.Get("impChoose"); ChooseSource.Location = new Point(646, 3); ChooseSource.Size = new Size(240, 30); ChooseSource.Anchor = AnchorStyles.Top | AnchorStyles.Right;
      ImportGrid.Location = new Point(14, 38); ImportGrid.Size = new Size(872, 270);
      SetUpList(ImportGrid, new[] { "colDate", "colType", "colExam", "colImages", "colSize", "colHospital", "colDiscPatient", "colState" }, new[] { 18, 8, 28, 11, 12, 18, 20, 32 });
      ImportGrid.CellValueChanged += delegate { UpdateImport(); };
      DiscLine.Location = new Point(14, 314); DiscLine.Size = new Size(872, 24); DiscLine.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right; DiscLine.AutoEllipsis = true;
      ImportSelection.Location = new Point(14, 340); ImportSelection.Size = new Size(872, 24); ImportSelection.Anchor = DiscLine.Anchor; ImportSelection.Font = bold; ImportSelection.AutoEllipsis = true;
      RoomLine.Location = new Point(14, 366); RoomLine.Size = new Size(872, 24); RoomLine.Anchor = DiscLine.Anchor; RoomLine.AutoEllipsis = true;
      place(ImportButton, Texts.Get("impButton"), 14, 190); ImportButton.Font = bold;
      place(StopButton, Texts.Get("impCancel"), 214, 130); StopButton.Enabled = false;
      ImportPanel.Controls.AddRange(new Control[] { SourceLine, ChooseSource, ImportGrid, DiscLine, ImportSelection, RoomLine, ImportButton, StopButton });

      Progress.Location = new Point(14, 562); Progress.Size = new Size(300, 20); Progress.Anchor = AnchorStyles.Bottom | AnchorStyles.Left; Progress.Visible = false; Progress.MarqueeAnimationSpeed = 30;
      Status.Location = new Point(324, 561); Status.Size = new Size(562, 24); Status.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right; Status.AutoEllipsis = true;
      MainPanel.Controls.AddRange(new Control[] { ModeExport, ModeImport, Who, SignOut, cl, Chart, SearchButton, PatientLine, ExportPanel, ImportPanel, Progress, Status });

      SignOut.Click += delegate { Logout(""); };
      SearchButton.Click += delegate { Search(); };
      Chart.KeyDown += delegate(object s, KeyEventArgs e) { if (e.KeyCode == Keys.Enter) { e.SuppressKeyPress = true; Search(); } };
      Burn.Click += delegate { Export("disc", ""); };
      Iso.Click += delegate { Export("iso", ""); };
      FolderButton.Click += delegate { Export("folder", ""); };
      ModeExport.Click += delegate { SetMode("export"); };
      ModeImport.Click += delegate { SetMode("import"); };
      ChooseSource.Click += delegate { LoadSource(""); };
      ImportButton.Click += delegate { Import(); };
      StopButton.Click += delegate { if (canStop) { stopAsked = true; StopButton.Enabled = false; } };

      Controls.Add(MainPanel); Controls.Add(LoginPanel);
      // looked at every two seconds while nothing is being copied: a disc put in is seen by itself.
      // Not while bringing in - the drive is then reading the other hospital's disc.
      timer.Tick += delegate { if (MainPanel.Visible && Mode == "export") UpdateDrive(); };
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
    // A list of exams with a tick in front: the same look and the same manners in both ways.
    void SetUpList(DataGridView g, string[] heads, int[] weights) {
      g.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
      g.AllowUserToAddRows = false; g.AllowUserToDeleteRows = false; g.AllowUserToResizeRows = false; g.RowHeadersVisible = false;
      g.SelectionMode = DataGridViewSelectionMode.FullRowSelect; g.MultiSelect = false; g.BackgroundColor = Color.White; g.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
      // the line the cursor is on is tinted, not painted over: what counts is the tick
      g.DefaultCellStyle.SelectionBackColor = Color.FromArgb(226, 236, 250); g.DefaultCellStyle.SelectionForeColor = Color.Black;
      g.Columns.Add(new DataGridViewCheckBoxColumn { HeaderText = "", FillWeight = 6 });
      for (int i = 0; i < heads.Length; i++) g.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = Texts.Get(heads[i]), FillWeight = weights[i], ReadOnly = true, SortMode = DataGridViewColumnSortMode.NotSortable });
      // a tick counts at once, not when the row is left; a click anywhere on the line ticks it
      g.CurrentCellDirtyStateChanged += delegate { if (g.IsCurrentCellDirty) g.CommitEdit(DataGridViewDataErrorContexts.CurrentCellChange); };
      g.CellClick += delegate(object s, DataGridViewCellEventArgs e) {
        if (e.RowIndex >= 0 && e.ColumnIndex > 0) { DataGridViewCell cell = g.Rows[e.RowIndex].Cells[0]; if (!cell.ReadOnly) cell.Value = !Equals(cell.Value, true); }
      };
    }

    void SetStatus(string text, int percent) {
      Status.Text = text;
      if (percent < 0) Progress.Style = ProgressBarStyle.Marquee; else { Progress.Style = ProgressBarStyle.Continuous; Progress.Value = Math.Max(0, Math.Min(100, percent)); }
      if (StatusShown != null) StatusShown(text, percent);
      Application.DoEvents();
    }
    void SetBusy(bool on) { SetBusy(on, false); }
    // `stoppable`: the work can be given up with the "Annuler" button of the bring-in panel.
    void SetBusy(bool on, bool stoppable) {
      Busy = on; canStop = on && stoppable; if (on) stopAsked = false;
      foreach (Control c in new Control[] { Chart, SearchButton, Grid, Burn, Iso, FolderButton, SignOut, ModeExport, ModeImport, ChooseSource, ImportGrid, ImportButton }) c.Enabled = !on;
      StopButton.Enabled = canStop;
      Progress.Visible = on;
      if (!on) { Status.Text = ""; Progress.Style = ProgressBarStyle.Continuous; Progress.Value = 0; UpdateSelection(); UpdateImport(); }
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
      // An account of the registration desk alone may bring in but not copy out: it is shown
      // the one way it has.
      ModeExport.Visible = Emr.CanExport; ModeImport.Left = Emr.CanExport ? 208 : 14;
      ClearPatient(); Source = null; SetMode(Emr.CanExport ? "export" : "import");
      Chart.Focus(); UpdateDrive();
      return true;
    }
    public void Logout(string message) {
      Emr.Logout(); ClearPatient(); Source = null; ImportGrid.Rows.Clear();
      MainPanel.Visible = false; LoginPanel.Visible = true;
      LoginMsg.Text = message ?? ""; LoginBox.Focus();
    }
    public void SetMode(string mode) {
      if (Busy) return;
      if (mode != "import" && !Emr.CanExport) mode = "import";
      Mode = mode == "import" ? "import" : "export";
      ExportPanel.Visible = Mode == "export"; ImportPanel.Visible = Mode == "import";
      foreach (Button m in new[] { ModeExport, ModeImport }) {
        bool on = (m == ModeImport) == (Mode == "import");
        m.Font = on ? bold : plain; m.BackColor = on ? Color.FromArgb(226, 236, 250) : SystemColors.Control;
      }
      if (Mode == "export") UpdateDrive(); else UpdateImport();
    }

    // ── the patient and the exams ────────────────────────────────────────────
    void ClearPatient() {
      Patient = null; ImportInfo = null; ImportError = ""; Chart.Text = ""; PatientLine.Text = Texts.Get("noPatientYet"); PatientLine.ForeColor = Color.DimGray;
      Grid.Rows.Clear(); UpdateSelection();
      if (Source != null) { CheckSource(); FillImportGrid(); } else UpdateImport();
    }
    // The patient as either answer gives it (the chart's own name, number, day of birth, sex).
    Dictionary<string, object> PatientRow() { return J.Dict(Patient != null ? Patient : ImportInfo, "patient"); }
    static string NameOf(Dictionary<string, object> p) { return (J.Str(p, "last_name") + " " + J.Str(p, "first_name")).Trim(); }
    static string SexShown(string g) { g = (g ?? "").Trim().ToUpperInvariant(); return g == "M" ? Texts.Get("male") : g == "F" ? Texts.Get("female") : g; }

    public bool Search() {
      string chart = Chart.Text.Trim(); if (chart == "") return false;
      SearchButton.Enabled = false; Application.DoEvents();
      // Two questions: the exams that can be copied out (for those who may copy out), and what
      // bringing in needs - the limits, what was brought in before. An EMR that does not yet
      // know the second one still serves the first.
      EmrAnswer r = Emr.CanExport ? Emr.Patient(chart) : null;
      EmrAnswer ri = r == null || r.Ok ? Emr.ImportPatient(chart) : null;
      SearchButton.Enabled = true;
      EmrAnswer bad = r != null && !r.Ok ? r : r == null && !ri.Ok ? ri : null;
      if ((bad != null && bad.Code == "LOGIN") || (ri != null && ri.Code == "LOGIN")) { Logout(Texts.Get("expired")); return false; }
      if (bad != null) {
        Patient = null; ImportInfo = null; ImportError = ""; Grid.Rows.Clear();
        PatientLine.Text = Texts.Error(bad.Code == "HTTP_404" && r == null ? "NO_IMPORT" : bad.Code, bad.Error); PatientLine.ForeColor = Color.Firebrick;
        UpdateSelection(); CheckSource(); FillImportGrid(); return false;
      }
      Patient = r != null ? r.Data : null;
      ImportInfo = ri.Ok ? ri.Data : null; ImportError = ri.Ok ? "" : ri.Code == "HTTP_404" ? "NO_IMPORT" : ri.Code;
      Dictionary<string, object> p = PatientRow();
      PatientLine.Text = Texts.Get("patient", NameOf(p) + "  ·  " + J.Str(p, "chart_no"), J.Str(p, "date_of_birth"), SexShown(J.Str(p, "gender"))).TrimEnd(' ', '—');
      PatientLine.ForeColor = Color.Black;
      Grid.Rows.Clear();
      foreach (Dictionary<string, object> e in J.List(Patient, "exams")) {
        string blocked = J.Str(e, "block"), state = blocked != "" ? Texts.Error(blocked, "") : "", size = "", items = "";
        if (blocked == "") { size = DiscFolder.FormatSize(J.Long(e, "bytes"), Texts.Unit); items = J.Str(e, "items"); }
        DataGridViewRow row = Grid.Rows[Grid.Rows.Add(false, J.Str(e, "exam_date"), J.Str(e, "modality"), J.Str(e, "order_name"), items, size, state)];
        row.Tag = e;
        if (blocked != "") { row.Cells[0].ReadOnly = true; row.DefaultCellStyle.ForeColor = Color.Gray; row.DefaultCellStyle.SelectionForeColor = Color.Gray; }
      }
      string server = J.Str(Patient != null ? Patient : ImportInfo, "server");
      if (server != "") { PatientLine.Text += "   —   " + Texts.Error(server, ""); PatientLine.ForeColor = Color.Firebrick; }
      UpdateSelection();
      CheckSource(); FillImportGrid();                     // a disc already read: what the EMR says of its exams for this patient
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
      Need = DiscFolder.Estimate(bytes, items + 3) + (DiscFolder.HasViewer ? 262144 : 0);           // (the viewer: well under this)
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
      if (sel.Count == 0 || Busy || !Emr.CanExport) return new ExportResult { Code = "NOTHING" };
      int max = (int)J.Long(Patient, "max_exams");
      if (max > 0 && sel.Count > max) { Ask.Message(Texts.Get("selMax", max), "warn"); return new ExportResult { Code = "TOO_MANY_EXAMS" }; }
      Dictionary<string, object> p = J.Dict(Patient, "patient");
      string name = NameOf(p), unit = Texts.Unit;
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

    // ── bringing in: the disc ────────────────────────────────────────────────
    // Reads the disc or folder (asked when `folder` is empty) and asks the EMR what it knows
    // of its exams. Nothing is sent yet.
    public bool LoadSource(string folder) {
      if (Busy) return false;
      if (string.IsNullOrEmpty(folder)) folder = Ask.Source(lastSource);
      if (string.IsNullOrEmpty(folder)) return false;
      if (!Directory.Exists(folder)) { Ask.Message(Texts.Error("NO_FOLDER", ""), "warn"); return false; }
      SetBusy(true, true);
      try {
        SetStatus(Texts.Get("impReading", 0, "…"), -1);
        ImportSource src = ImportDisc.Read(folder, delegate(int n, int of) {
          if (n == 1 || n % 10 == 0 || n == of) SetStatus(Texts.Get("impReading", n, of), of > 0 ? 100 * n / of : -1);
          return !stopAsked;
        });
        if (src.Stopped) return false;                      // given up: the list stays as it was
        Source = src; lastSource = folder;
        CheckSource();
      } catch (Exception e) {
        Ask.Message(Texts.Get("e_other", e.Message), "error"); return false;
      } finally { SetBusy(false); FillImportGrid(); }
      return true;
    }
    long Limit(string key) { return ImportInfo == null || J.IsNull(ImportInfo, key) ? -1 : J.Long(ImportInfo, key); }
    // What the EMR says of each exam of the disc, for the patient at the top of the window:
    // can be brought in, is here already, is another patient's… and what this program sees
    // itself (a file too large). Without a patient nothing is known yet.
    public void CheckSource() {
      CheckError = "";
      if (Source == null) return;
      long maxFile = Limit("max_file_bytes");
      List<ImportStudy> ask = new List<ImportStudy>();
      foreach (ImportStudy st in Source.Studies) {
        st.State = ""; st.ImportedAt = "";
        if (maxFile > 0 && st.LargestFile > maxFile) st.State = "TOO_BIG"; else ask.Add(st);
      }
      if (ImportInfo == null || J.Str(ImportInfo, "server") != "") return;
      for (int at = 0; at < ask.Count; at += 200) {
        List<ImportStudy> part = ask.GetRange(at, Math.Min(200, ask.Count - at));
        List<string> uids = new List<string>(); foreach (ImportStudy st in part) uids.Add(st.Uid);
        EmrAnswer r = Emr.Post("/api/pacs/import/check", new Dictionary<string, object> { { "patient_id", J.Long(J.Dict(ImportInfo, "patient"), "id") }, { "studies", uids } }, 60);
        if (!r.Ok) {
          if (r.Code == "LOGIN") { Logout(Texts.Get("expired")); return; }
          CheckError = r.Code; return;                    // nothing is ticked on a guess: the button stays off
        }
        Dictionary<string, Dictionary<string, object>> said = new Dictionary<string, Dictionary<string, object>>();
        foreach (Dictionary<string, object> s in J.List(r.Data, "studies")) said[J.Str(s, "study_uid")] = s;
        foreach (ImportStudy st in part) {
          Dictionary<string, object> s; if (!said.TryGetValue(st.Uid, out s)) continue;
          st.State = J.Str(s, "state"); st.ImportedAt = J.Str(s, "imported_at");
        }
      }
    }
    string StateShown(ImportStudy st) {
      if (st.State == "") return "";
      if (st.State == "HERE") return Texts.Get("s_HERE", st.ImportedAt.Length > 10 ? st.ImportedAt.Substring(0, 10) : st.ImportedAt).Trim();
      if (st.State == "TOO_BIG") return Texts.Get("s_TOO_BIG", DiscFolder.FormatSize(Math.Max(0, Limit("max_file_bytes")), Texts.Unit));
      return Texts.Has("s_" + st.State) ? Texts.Get("s_" + st.State) : st.State;
    }
    public void FillImportGrid() {
      ImportGrid.Rows.Clear();
      if (Source != null) foreach (ImportStudy st in Source.Studies) {
        string state = StateShown(st);
        DataGridViewRow row = ImportGrid.Rows[ImportGrid.Rows.Add(false, st.DateShown, st.Modality, st.Description, st.Files.Count, DiscFolder.FormatSize(st.Bytes, Texts.Unit), st.Institution, st.PatientShown, state)];
        row.Tag = st;
        if (st.State != "") { row.Cells[0].ReadOnly = true; row.DefaultCellStyle.ForeColor = Color.Gray; row.DefaultCellStyle.SelectionForeColor = Color.Gray; }
      }
      UpdateImport();
    }
    public List<ImportStudy> ChosenStudies() {
      List<ImportStudy> o = new List<ImportStudy>();
      foreach (DataGridViewRow row in ImportGrid.Rows) {
        ImportStudy st = row.Tag as ImportStudy;
        if (Equals(row.Cells[0].Value, true) && st != null && st.State == "") o.Add(st);
      }
      return o;
    }
    // The lines of the bring-in panel, and whether its button can be pressed.
    public void UpdateImport() {
      string unit = Texts.Unit;
      if (Source == null) { SourceLine.Text = Texts.Get("impNoSource"); DiscLine.Text = ""; }
      else {
        SourceLine.Text = Source.Studies.Count == 0 ? Texts.Get("impNothing", Source.Folder)
          : Texts.Get("impSource", Source.Folder, Source.Studies.Count, Source.FileCount) + (Source.NotImages > 0 ? Texts.Get("impSkipped", Source.NotImages) : "");
        // whose images the disc says they are - one line when the disc is one patient's
        List<string> keys = new List<string>(); ImportStudy first = null;
        foreach (ImportStudy st in Source.Studies) { if (!keys.Contains(st.PatientKey)) keys.Add(st.PatientKey); if (first == null) first = st; }
        DiscLine.Text = keys.Count == 0 ? "" : keys.Count > 1 ? Texts.Get("impDiscPatients", keys.Count)
          : Texts.Get("impDiscPatient", first.PatientShown == "" ? "—" : first.PatientShown, first.PatientId == "" ? "—" : first.PatientId, DateShown(first.BirthDate), SexShown(first.Sex) == "" ? "—" : SexShown(first.Sex));
        DiscLine.ForeColor = keys.Count > 1 ? Color.Firebrick : Color.Black;
      }
      List<ImportStudy> sel = ChosenStudies(); long bytes = 0; int items = 0;
      foreach (ImportStudy st in sel) { bytes += st.Bytes; items += st.Files.Count; }
      string server = ImportInfo == null ? "" : J.Str(ImportInfo, "server");
      bool can = ImportInfo != null && server == "" && ImportError == "" && CheckError == "";
      ImportSelection.ForeColor = Color.Black;
      if (ImportError != "" || CheckError != "") { ImportSelection.Text = Texts.Error(ImportError != "" ? ImportError : CheckError, ""); ImportSelection.ForeColor = Color.Firebrick; }
      else if (server != "") { ImportSelection.Text = Texts.Error(server, ""); ImportSelection.ForeColor = Color.Firebrick; }
      else if (ImportInfo == null) ImportSelection.Text = Texts.Get("impNeedPatient");
      else ImportSelection.Text = sel.Count > 0 ? Texts.Get("sel", sel.Count, items, DiscFolder.FormatSize(bytes, unit)) : Source != null && Source.Studies.Count > 0 ? Texts.Get("impSelNone") : "";
      // the image server's free room, when the EMR knows it: twice the size and a reserve must fit
      long free = Limit("free_bytes"), spare = Math.Max(0, Limit("spare_bytes")); bool room = true;
      if (can && free >= 0) {
        room = sel.Count == 0 || bytes * 2 + spare <= free;
        RoomLine.Text = Texts.Get("impRoom", DiscFolder.FormatSize(free, unit)) + (sel.Count == 0 ? "" : room ? "  ✔" : Texts.Get("impRoomNo"));
        RoomLine.ForeColor = room ? Color.Black : Color.Firebrick;
      } else RoomLine.Text = "";
      // what was brought in for this patient before (the EMR lists it with the limits)
      int had = ImportInfo == null ? 0 : J.List(ImportInfo, "imported").Count;
      if (had > 0) RoomLine.Text = (RoomLine.Text == "" ? "" : RoomLine.Text + "   ·   ") + Texts.Get("impBefore", had);
      if (!Busy) ImportButton.Enabled = can && room && sel.Count > 0;
    }
    static string DateShown(string d) { d = (d ?? "").Trim(); return d.Length == 8 ? d.Substring(0, 4) + "-" + d.Substring(4, 2) + "-" + d.Substring(6, 2) : d == "" ? "—" : d; }
    static string ExamShown(ImportStudy st) { return (st.DateShown + "  " + st.Modality + "  " + st.Description).Trim(); }

    // ── bringing in: sending ─────────────────────────────────────────────────
    // What a refusal means, in the window's words.
    string Refusal(EmrAnswer r) {
      string c = r.Code;
      if (c == "NO_ROOM") return Texts.Error("NO_ROOM_SERVER", "", DiscFolder.FormatSize(J.Long(r.Data, "needed_bytes"), Texts.Unit), DiscFolder.FormatSize(J.Long(r.Data, "free_bytes"), Texts.Unit));
      if (c == "TOO_BIG_FILE" || c == "HTTP_413") return Texts.Error("TOO_BIG_FILE", "", DiscFolder.FormatSize(J.Long(r.Data, "max_file_bytes") > 0 ? J.Long(r.Data, "max_file_bytes") : Math.Max(0, Limit("max_file_bytes")), Texts.Unit));
      if (c == "INCOMPLETE") return Texts.Error("INCOMPLETE", "", J.Str(r.Data, "on_server"), J.Str(r.Data, "announced"));
      if (c == "NOT_LOGGED") return Texts.Error("NOT_LOGGED_IMPORT", "");
      if (c == "BROKEN" || c == "NO_ANSWER" || c == "HTTP_502" || c == "HTTP_503" || c == "HTTP_504") return Texts.Error("BROKEN_IMPORT", "");
      if (c == "BAD_REQUEST") return Texts.Error("BAD_REQUEST", "", r.Error);
      if (Texts.Has("s_" + c)) return c == "HERE" ? Texts.Get("s_HERE", J.Str(r.Data, "imported_at")).Trim() : Texts.Get("s_" + c);
      return Texts.Error(c, r.Error);
    }
    static bool WorthAnotherTry(string code) { return code == "BROKEN" || code == "NO_ANSWER" || code == "UNREACHABLE" || code == "HTTP_502" || code == "HTTP_503" || code == "HTTP_504"; }
    // A pause in which the window goes on answering (the "Annuler" button too).
    void Pause(int ms) { DateTime until = DateTime.Now.AddMilliseconds(ms); while (DateTime.Now < until && !stopAsked) { Application.DoEvents(); Thread.Sleep(50); } }
    // The EMR is asked on another thread while this one goes on answering Windows. Without it the
    // window reads "not responding" during a long wait - the EMR closing a large exam takes minutes -
    // and the "Annuler" button cannot be pressed. `tick` runs on the window's thread between two looks.
    // Only used while the window is busy (its other buttons are off).
    EmrAnswer Wait(Func<EmrAnswer> call, Action tick) {
      EmrAnswer answer = null;
      Thread t = new Thread(delegate() { try { answer = call(); } catch (Exception e) { answer = new EmrAnswer { Code = "BROKEN", Error = e.Message }; } });
      t.IsBackground = true; t.Start();
      while (!t.Join(30)) { if (tick != null) tick(); Application.DoEvents(); }
      return answer;
    }
    EmrAnswer Wait(Func<EmrAnswer> call) { return Wait(call, null); }
    void GiveUp(string importId, string reason) {
      SetStatus(Texts.Get("impCancelling"), -1);
      Wait(delegate { return Emr.Post("/api/pacs/import/" + importId + "/cancel", new Dictionary<string, object> { { "reason", reason } }, 120); });
    }

    // The ticked exams of the disc go into the chart of the patient at the top of the window.
    public ImportResult Import() {
      ImportResult res = new ImportResult();
      List<ImportStudy> sel = ChosenStudies();
      if (sel.Count == 0 || Busy || ImportInfo == null || !Emr.CanImport) { res.Code = "NOTHING"; return res; }
      Dictionary<string, object> p = J.Dict(ImportInfo, "patient"); string unit = Texts.Unit;
      // the image server is not there (or the EMR could not say what it knows of the disc): no question
      // is asked of the person for something that cannot be done - the button is off for the same reason
      string why = J.Str(ImportInfo, "server") != "" ? J.Str(ImportInfo, "server") : ImportError != "" ? ImportError : CheckError;
      if (why != "") { Ask.Message(Texts.Error(why, ""), "error"); res.Code = why; return res; }
      foreach (ImportStudy st in sel) if (st.PatientKey != sel[0].PatientKey) { Ask.Message(Texts.Get("impOnePatient"), "warn"); res.Code = "SEVERAL_PATIENTS"; return res; }
      long bytes = 0; foreach (ImportStudy st in sel) bytes += st.Bytes;
      long free = Limit("free_bytes"), spare = Math.Max(0, Limit("spare_bytes")), warn = Limit("warn_bytes");
      if (free >= 0 && bytes * 2 + spare > free) {
        Ask.Message(Texts.Error("NO_ROOM_SERVER", "", DiscFolder.FormatSize(bytes * 2 + spare, unit), DiscFolder.FormatSize(free, unit)), "error"); res.Code = "NO_ROOM"; return res;
      }
      foreach (ImportStudy st in sel) if (warn > 0 && st.Bytes > warn && !Ask.Confirm(Texts.Get("impWarnBig", ExamShown(st), DiscFolder.FormatSize(st.Bytes, unit)))) { res.Code = "CANCELLED_BY_USER"; return res; }

      SetBusy(true, true);
      try {
        // every file that was only listed is opened once: what is told to the EMR must be what it gets
        for (int i = 0; i < sel.Count; i++) {
          ImportStudy st = sel[i];
          int off = ImportDisc.Verify(st, delegate(int n, int of) { if (n == 1 || n % 10 == 0 || n == of) SetStatus(Texts.Get("impVerify", n, of), of > 0 ? 100 * n / of : -1); return !stopAsked; });
          if (off < 0) { res.Cancelled = true; res.Code = "CANCELLED_BY_USER"; return res; }
          res.Dropped += off;
        }
        List<ImportStudy> empty = sel.FindAll(delegate(ImportStudy s) { return s.Files.Count == 0; });
        foreach (ImportStudy st in empty) { res.Failed++; res.Errors.Add(Texts.Get("impFailed", ExamShown(st), Texts.Get("impEmpty"))); sel.Remove(st); }
        if (sel.Count == 0) { res.Code = "NOTHING_READABLE"; SetBusy(false); Ask.Message(string.Join("\n\n", res.Errors.ToArray()), "error"); return res; }

        // the question that must be answered before anything is sent
        ConfirmInfo info = new ConfirmInfo {
          DiscName = sel[0].PatientShown, DiscId = sel[0].PatientId, DiscBirth = DateShown(sel[0].BirthDate) == "—" ? "" : DateShown(sel[0].BirthDate), DiscSex = SexShown(sel[0].Sex),
          ChartName = NameOf(p), ChartNo = J.Str(p, "chart_no"), ChartBirth = J.Str(p, "date_of_birth"), ChartSex = SexShown(J.Str(p, "gender")),
          BirthDiffers = ImportDisc.BirthDiffers(sel[0].BirthDate, J.Str(p, "date_of_birth")), SexDiffers = ImportDisc.SexDiffers(sel[0].Sex, J.Str(p, "gender")) };
        foreach (ImportStudy st in sel) info.Exams.Add((st.Institution == "" ? "" : st.Institution + " — ") + ExamShown(st) + " — " + Texts.Get("cfImages", st.Files.Count) + " · " + DiscFolder.FormatSize(st.Bytes, unit));
        SetStatus("", 0);
        if (!Ask.SamePatient(info)) { res.Code = "CANCELLED_BY_USER"; return res; }

        for (int i = 0; i < sel.Count; i++) {
          ImportStudy st = sel[i]; bool stopAll;
          string err = SendStudy(st, i + 1, sel.Count, p, info, res, out stopAll);
          if (err == "") { res.Imported++; continue; }
          if (err == "CANCELLED") { res.Cancelled = true; break; }
          if (err == "LOGIN") { SetBusy(false); Logout(Texts.Get("expired")); res.Code = "LOGIN"; return res; }
          res.Failed++; string said = Texts.Get("impFailed", ExamShown(st), err); res.Errors.Add(said);
          SetStatus("", 0);
          if (stopAll || i == sel.Count - 1) { Ask.Message(said, "error"); break; }
          if (!Ask.Confirm(said + Texts.Get("impContinue"))) break;
        }
      } catch (Exception e) {
        res.Code = "ERROR"; res.Errors.Add(e.Message); Ask.Message(Texts.Get("e_other", e.Message), "error");
      } finally { if (Busy) SetBusy(false); }

      // the chart has changed: what the EMR says of this disc now (the exams brought in read "déjà importé")
      EmrAnswer again = Emr.ImportPatient(J.Str(p, "chart_no"));
      if (again.Ok) ImportInfo = again.Data; else if (again.Code == "LOGIN") { Logout(Texts.Get("expired")); res.Ok = res.Imported > 0; if (res.Code == "") res.Code = "LOGIN"; return res; }
      CheckSource(); FillImportGrid();

      res.Ok = res.Imported > 0 && res.Failed == 0 && !res.Cancelled && res.Code == "";
      if (res.Imported > 0) {
        string done = Texts.Get("impDone", res.Imported, res.Images, NameOf(p) + " (" + J.Str(p, "chart_no") + ")");
        if (res.Failed > 0) done += Texts.Get("impNotAll", res.Failed);
        if (res.Cancelled) done += "\n\n" + Texts.Get("impCancelled");
        if (res.Undrawn.Count > 0) done += Texts.Get("impUndrawn", string.Join(", ", res.Undrawn.ToArray()));
        if (res.Dropped > 0) done += Texts.Get("impDropped", res.Dropped);
        Ask.Message(done, res.Failed > 0 || res.Cancelled ? "warn" : "info");
      } else if (res.Cancelled) Ask.Message(Texts.Get("impCancelled"), "warn");
      if (res.Code == "" && !res.Ok) res.Code = res.Cancelled ? "CANCELLED_BY_USER" : "FAILED";
      return res;
    }

    // One exam: begin, every file, finish. "" = it is in the chart; "CANCELLED" / "LOGIN"; or
    // the words that say why not (then nothing of it is in the chart, and what was sent has
    // been taken back - or will be, by the EMR itself). stopAll: the next exams would fail too.
    string SendStudy(ImportStudy st, int index, int of, Dictionary<string, object> p, ConfirmInfo info, ImportResult res, out bool stopAll) {
      stopAll = false;
      SetStatus(Texts.Get("impSending", index, of, 0, st.Files.Count), 0);
      Dictionary<string, object> announce = new Dictionary<string, object> {
        { "patient_id", J.Long(p, "id") }, { "files", st.Files.Count }, { "bytes", st.Bytes }, { "source", ImportDisc.Origin(st) },
        { "confirm", new Dictionary<string, object> { { "birth_differs", info.BirthDiffers }, { "sex_differs", info.SexDiffers } } } };
      EmrAnswer b = Wait(delegate { return Emr.Post("/api/pacs/import/begin", announce, 120); });
      if (!b.Ok) {
        if (b.Code == "LOGIN") return "LOGIN";
        if (Texts.Has("s_" + b.Code)) { st.State = b.Code; st.ImportedAt = J.Str(b.Data, "imported_at"); }
        stopAll = b.Code == "NO_ROOM" || b.Code == "UNREACHABLE" || b.Code == "NOT_PAIRED" || WorthAnotherTry(b.Code);
        return Refusal(b);
      }
      string id = J.Str(b.Data, "import_id"), path = "/api/pacs/import/" + id + "/instance";
      long total = Math.Max(1, st.Bytes), sent = 0;
      for (int n = 0; n < st.Files.Count; n++) {
        ImportFile f = st.Files[n]; EmrAnswer r = null;
        for (int attempt = 1; attempt <= 3; attempt++) {
          if (stopAsked) { GiveUp(id, "cancelled by the user"); return "CANCELLED"; }
          string words = Texts.Get(attempt == 1 ? "impSending" : "impRetry", index, of, n + 1, st.Files.Count); long before = sent;
          SetStatus(words, (int)(100 * before / total));
          long now = 0, drawn = 0;                         // the sending thread says how far it is; the window's thread draws it
          r = Wait(delegate { return Emr.PutFile(path, f.Path, delegate(long done) { Interlocked.Exchange(ref now, done); }, delegate { return stopAsked; }, 900); },
            delegate { long d = Interlocked.Read(ref now); if (d != drawn) { drawn = d; SetStatus(words, (int)(100 * (before + d) / total)); } });
          if (r.Ok || !WorthAnotherTry(r.Code) || attempt == 3) break;
          Pause(2000);                                     // a network hiccup, or the image server coming back: the same file again is safe
        }
        if (!r.Ok) {
          if (r.Code == "CANCELLED") { GiveUp(id, "cancelled by the user"); return "CANCELLED"; }
          if (r.Code == "LOGIN") return "LOGIN";             // (the EMR tidies up what was sent)
          if (r.Code != "NOT_FOUND" && r.Code != "CLOSED" && r.Code != "NOT_YOURS") GiveUp(id, r.Code);
          stopAll = WorthAnotherTry(r.Code) || r.Code == "NOT_PAIRED" || r.Code == "UNREADABLE";
          return Refusal(r);
        }
        sent += f.Bytes;
      }
      EmrAnswer fin = null;
      for (int attempt = 1; attempt <= 3; attempt++) {
        SetStatus(Texts.Get("impFinishing"), -1);
        fin = Wait(delegate { return Emr.Post("/api/pacs/import/" + id + "/finish", null, 600); });
        if (fin.Ok || !(WorthAnotherTry(fin.Code) || fin.Code == "NOT_PAIRED" || fin.Code == "NOT_LOGGED") || attempt == 3) break;
        Pause(3000);
        if (stopAsked) break;
      }
      if (!fin.Ok) {
        if (fin.Code == "LOGIN") return "LOGIN";
        if (fin.Code != "NOT_FOUND" && fin.Code != "CLOSED" && fin.Code != "NOT_YOURS") GiveUp(id, fin.Code);
        if (stopAsked) return "CANCELLED";
        stopAll = WorthAnotherTry(fin.Code) || fin.Code == "NOT_PAIRED";
        return Refusal(fin);
      }
      res.Images += (int)J.Long(fin.Data, "images");
      res.Undrawn.AddRange(J.Strings(fin.Data, "undrawn"));
      return "";
    }
  }
}
