// VOIR.EXE - the window: the exams and their series on the left, the picture on the
// right, a few buttons and, always in sight, the line that says what this viewer is for.
//
// It reads the disc and nothing else: no settings are kept, no file is written, nothing
// is left on the computer it runs on.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Windows.Forms;

namespace Bethesda.Viewer {
  public class MainForm : Form {
    readonly Disc disc; readonly TreeView tree = new TreeView(); readonly ImagePanel panel = new ImagePanel();
    readonly Label where = new Label(), notice = new Label();
    readonly Button prev = new Button(), next = new Button(), fit = new Button(), invert = new Button(), reset = new Button(), help = new Button();

    Series series; int index = -1, frame; Picture picture;
    double center, width; bool inverted;

    // what a test (or a person) can ask
    public Disc Disc { get { return disc; } }
    public Picture Current { get { return picture; } }
    public Series CurrentSeries { get { return series; } }
    public int CurrentIndex { get { return index; } }
    public int CurrentFrame { get { return frame; } }
    public double WindowCenter { get { return center; } }
    public double WindowWidth { get { return width; } }
    public bool Inverted { get { return inverted; } }
    public ImagePanel Panel { get { return panel; } }
    public Bitmap CurrentBitmap { get { return picture == null || picture.Problem != "" ? null : picture.Render(frame, center, width, inverted); } }

    public MainForm(Disc d) {
      disc = d;
      Text = Texts.Get("app") + (disc.PatientName != "" ? " — " + disc.PatientName + (disc.PatientId != "" ? " · " + disc.PatientId : "") : "");
      Font = new Font("Segoe UI", 9.5f); ClientSize = new Size(1120, 720); MinimumSize = new Size(720, 480); StartPosition = FormStartPosition.CenterScreen;
      KeyPreview = true;

      // left: the exams and their series
      tree.Dock = DockStyle.Left; tree.Width = 270; tree.Font = new Font(Font, FontStyle.Bold); tree.HideSelection = false; tree.FullRowSelect = true; tree.ShowLines = false; tree.ShowRootLines = false; tree.ShowPlusMinus = false; tree.ItemHeight = 22;
      foreach (Study st in disc.Studies) {
        // (the list's own font is the bold one: a node given a bolder font than the list's is cut short)
        TreeNode sn = tree.Nodes.Add(st.Label == "" ? Texts.Get("exams") : st.Label); sn.Tag = st;
        foreach (Series se in st.Series) { TreeNode n = sn.Nodes.Add(se.Label); n.Tag = se; n.NodeFont = Font; }
      }
      tree.ExpandAll();
      tree.BeforeCollapse += delegate(object s, TreeViewCancelEventArgs e) { e.Cancel = true; };       // the whole list stays open
      tree.AfterSelect += delegate(object s, TreeViewEventArgs e) {
        Series se = e.Node.Tag as Series; if (se == null && e.Node.Nodes.Count > 0) se = e.Node.Nodes[0].Tag as Series;
        if (se != null && se != series) ShowSeries(se);
      };

      // bottom: the buttons, and under them the line that is always there
      Panel bar = new Panel { Dock = DockStyle.Bottom, Height = 40, Padding = new Padding(8, 6, 8, 6) };
      Setup(prev, Texts.Get("prev"), 84, delegate { StepImage(-1); }); Setup(next, Texts.Get("next"), 84, delegate { StepImage(1); });
      Setup(fit, Texts.Get("fit"), 84, delegate { panel.Fit(); }); Setup(invert, Texts.Get("invert"), 84, delegate { ToggleInvert(); });
      Setup(reset, Texts.Get("reset"), 104, delegate { ResetView(); }); Setup(help, Texts.Get("help"), 32, delegate { MessageBox.Show(this, Texts.Get("helpText"), Texts.Get("app"), MessageBoxButtons.OK, MessageBoxIcon.Information); });
      help.Dock = DockStyle.Right; reset.Dock = DockStyle.Right; invert.Dock = DockStyle.Right; fit.Dock = DockStyle.Right;
      prev.Dock = DockStyle.Left; next.Dock = DockStyle.Left;
      where.Dock = DockStyle.Fill; where.TextAlign = ContentAlignment.MiddleLeft; where.Padding = new Padding(10, 0, 0, 0); where.AutoEllipsis = true;
      bar.Controls.Add(where); bar.Controls.Add(next); bar.Controls.Add(prev); bar.Controls.Add(fit); bar.Controls.Add(invert); bar.Controls.Add(reset); bar.Controls.Add(help);
      notice.Dock = DockStyle.Bottom; notice.Height = 24; notice.TextAlign = ContentAlignment.MiddleLeft; notice.Padding = new Padding(8, 0, 0, 0);
      notice.Text = Texts.Get("notice"); notice.Font = new Font(Font, FontStyle.Bold); notice.BackColor = Color.FromArgb(255, 244, 214); notice.ForeColor = Color.FromArgb(90, 60, 0);

      panel.Dock = DockStyle.Fill;
      panel.Windowing += delegate(int dx, int dy) { DragWindow(dx, dy); };
      panel.Step += delegate(int by) { StepFrame(by); };
      panel.ViewChanged += delegate { Corners(); panel.Invalidate(); };
      Splitter split = new Splitter { Dock = DockStyle.Left, Width = 4 };
      Controls.Add(panel); Controls.Add(split); Controls.Add(tree); Controls.Add(bar); Controls.Add(notice);

      if (disc.ImageCount == 0) { panel.Message = Texts.Get("empty"); Buttons(); }
      else {
        // the first series that holds something to look at
        Series firstSeries = null;
        foreach (Study st in disc.Studies) { foreach (Series se in st.Series) if (se.Images.Count > 0) { firstSeries = se; break; } if (firstSeries != null) break; }
        Shown += delegate { if (firstSeries != null) Select(firstSeries); panel.Focus(); };
      }
    }
    void Setup(Button b, string text, int w, EventHandler click) { b.Text = text; b.Width = w; b.FlatStyle = FlatStyle.System; b.TabStop = false; b.Click += click; b.Margin = new Padding(3); }

    // ── what is shown ──────────────────────────────────────────────────────────
    public void Select(Series se) {
      foreach (TreeNode sn in tree.Nodes) foreach (TreeNode n in sn.Nodes) if (n.Tag == se) { tree.SelectedNode = n; return; }
    }
    void ShowSeries(Series se) { series = se; ShowImage(0); }
    public void ShowImage(int i) {
      if (series == null || series.Images.Count == 0) return;
      i = Math.Max(0, Math.Min(series.Images.Count - 1, i));
      // A large film takes seconds to come off a CD (8 s for 14 MB, measured): say so while
      // it is read - in the line under the picture, and in the picture area when it is empty.
      where.Text = Texts.Get("reading"); where.Refresh();
      if (picture == null) { panel.Message = Texts.Get("reading"); panel.Refresh(); }
      if (picture != null) picture.Dispose();
      index = i; frame = 0; picture = Picture.Open(series.Images[i].File); inverted = false;
      if (picture.Problem == "") {
        Cursor = Cursors.WaitCursor;
        try { picture.DefaultWindow(out center, out width); panel.Message = ""; panel.Show(picture.Render(0, center, width, inverted), picture.AspectY, false); }
        catch (Exception) { picture.Problem = "unreadable"; }
        Cursor = Cursors.Default;
      }
      if (picture.Problem != "") { panel.Message = Texts.Get(picture.Problem); panel.Show(null, 1, false); }
      Corners(); Buttons(); panel.Invalidate();
    }
    public void StepImage(int by) { if (series != null && index + by >= 0 && index + by < series.Images.Count) ShowImage(index + by); }
    // The wheel: through the frames of a file that holds several, then on to the next image.
    public void StepFrame(int by) {
      if (picture == null || picture.Problem != "" || frame + by < 0 || frame + by >= picture.Steps) { StepImage(by); return; }
      frame += by;
      try { panel.Show(picture.Render(frame, center, width, inverted), picture.AspectY, true); }
      catch (Exception) { picture.Problem = "unreadable"; panel.Message = Texts.Get(picture.Problem); panel.Show(null, 1, false); }
      Corners(); Buttons(); panel.Invalidate();
    }
    public void StepSeries(int by) {
      List<Series> all = new List<Series>(); foreach (Study st in disc.Studies) all.AddRange(st.Series);
      int i = all.IndexOf(series) + by; if (series != null && i >= 0 && i < all.Count) Select(all[i]);
    }

    // The window of grey levels, as the mouse drags it: sideways the width, up and down the centre.
    public void SetWindow(double c, double w) {
      if (picture == null || picture.Problem != "" || !picture.IsGrey) return;
      center = c; width = Math.Max(1, w); Redraw();
    }
    void DragWindow(int dx, int dy) {
      if (picture == null || picture.Problem != "" || !picture.IsGrey) return;
      double range = Math.Max(256, (picture.High - picture.Low) * picture.Slope), unit = range / 600.0;
      SetWindow(center + dy * unit, width + dx * unit);
    }
    public void ToggleInvert() { if (picture != null && picture.Problem == "") { inverted = !inverted; Redraw(); } }
    public void ResetView() {
      if (picture == null || picture.Problem != "") return;
      inverted = false; picture.DefaultWindow(out center, out width); Redraw(); panel.Fit();
    }
    void Redraw() { panel.Show(picture.Render(frame, center, width, inverted), picture.AspectY, true); Corners(); panel.Invalidate(); }

    // The four corners of the picture: whose it is, which exam, which image, how it is shown.
    void Corners() {
      if (picture == null) { panel.TopLeft = panel.TopRight = panel.BottomLeft = panel.BottomRight = ""; where.Text = ""; return; }
      string who = picture.PatientName != "" ? picture.PatientName : disc.PatientName, id = picture.PatientId != "" ? picture.PatientId : disc.PatientId;
      panel.TopLeft = (who + (id != "" ? "\n" + id : "")).Trim();
      panel.TopRight = (picture.StudyDescription + "\n" + picture.StudyDate + (picture.Orientation != "" ? "\n" + picture.Orientation : "")).Trim();
      string at = "S" + (series != null ? series.Number : picture.SeriesNumber) + " · " + Texts.Get("image", index + 1, series != null ? series.Images.Count : 1);
      panel.BottomLeft = at + (picture.SeriesDescription != "" ? "\n" + picture.SeriesDescription : "");
      string view = "";
      if (picture.Problem == "") {
        if (picture.IsGrey) view = Texts.Get("window", Math.Round(center).ToString(CultureInfo.InvariantCulture), Math.Round(width).ToString(CultureInfo.InvariantCulture)) + "\n";
        view += Texts.Get("zoom", Math.Round(panel.Zoom * 100));
      }
      panel.BottomRight = view;
      where.Text = at + (picture.Problem != "" || picture.Frames <= 1 ? "" : "   —   " + (picture.Steps > 1 ? Texts.Get("frame", frame + 1, picture.Steps) : Texts.Get("frames", picture.Frames)));
    }
    void Buttons() {
      bool can = picture != null && picture.Problem == "";
      prev.Enabled = series != null && index > 0; next.Enabled = series != null && index < series.Images.Count - 1;
      fit.Enabled = invert.Enabled = reset.Enabled = can;
    }

    protected override bool ProcessCmdKey(ref Message msg, Keys keyData) {
      switch (keyData) {
        case Keys.Left: StepImage(-1); return true;
        case Keys.Right: StepImage(1); return true;
        case Keys.Up: StepSeries(-1); return true;
        case Keys.Down: StepSeries(1); return true;
        case Keys.I: ToggleInvert(); return true;
        case Keys.R: ResetView(); return true;
      }
      return base.ProcessCmdKey(ref msg, keyData);
    }
    protected override void OnFormClosed(FormClosedEventArgs e) { if (picture != null) picture.Dispose(); base.OnFormClosed(e); }
  }
}
