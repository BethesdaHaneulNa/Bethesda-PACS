// VOIR.EXE - the part of the window the picture is drawn in: fitted or zoomed, moved
// with the mouse, with a line of text in each corner. It knows nothing about DICOM; the
// window tells it what to draw and is told what the mouse asks for.
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace Bethesda.Viewer {
  public class ImagePanel : Control {
    Bitmap picture; double aspectY = 1;
    bool fitted = true; double zoom = 1; PointF origin;          // where the picture's top-left corner is, in the panel
    Point last; MouseButtons held = MouseButtons.None;
    public string TopLeft = "", TopRight = "", BottomLeft = "", BottomRight = "", Message = "";

    public event Action<int, int> Windowing;                     // left button dragged: (dx, dy) in pixels of the screen
    public event Action<int> Step;                               // the wheel: -1 previous, +1 next
    public event Action ViewChanged;                             // the zoom changed

    public ImagePanel() {
      SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
      BackColor = Color.Black; ForeColor = Color.Gainsboro; TabStop = true;
    }

    public double Zoom { get { return zoom; } }
    public bool Fitted { get { return fitted; } }

    // A new picture (or none). `keepView` keeps the zoom and the place - the same picture drawn again.
    public void Show(Bitmap b, double aspect, bool keepView) {
      picture = b; aspectY = aspect <= 0 ? 1 : aspect;
      if (!keepView || fitted) Fit(); else Invalidate();
    }
    SizeF Shown { get { return picture == null ? SizeF.Empty : new SizeF((float)(picture.Width * zoom), (float)(picture.Height * aspectY * zoom)); } }

    public void Fit() {
      fitted = true;
      if (picture != null && ClientSize.Width > 0 && ClientSize.Height > 0) {
        zoom = Math.Min(ClientSize.Width / (double)picture.Width, ClientSize.Height / (picture.Height * aspectY));
        SizeF s = Shown; origin = new PointF((ClientSize.Width - s.Width) / 2, (ClientSize.Height - s.Height) / 2);
      }
      Invalidate(); if (ViewChanged != null) ViewChanged();
    }
    // Zoom by a factor, keeping the point under the mouse where it is.
    public void ZoomAt(Point at, double factor) {
      if (picture == null) return;
      double z = Math.Max(0.02, Math.Min(16, zoom * factor)); if (z == zoom) return;
      origin = new PointF((float)(at.X - (at.X - origin.X) * z / zoom), (float)(at.Y - (at.Y - origin.Y) * z / zoom));
      zoom = z; fitted = false; Invalidate(); if (ViewChanged != null) ViewChanged();
    }

    protected override void OnResize(EventArgs e) { base.OnResize(e); if (fitted) Fit(); }
    protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); Focus(); held = e.Button; last = e.Location; }
    protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); held = MouseButtons.None; }
    protected override void OnMouseMove(MouseEventArgs e) {
      base.OnMouseMove(e);
      int dx = e.X - last.X, dy = e.Y - last.Y; if (held == MouseButtons.None || (dx == 0 && dy == 0)) return;
      last = e.Location;
      if (held == MouseButtons.Left) { if (Windowing != null) Windowing(dx, dy); }
      else if (held == MouseButtons.Right || held == MouseButtons.Middle) { origin = new PointF(origin.X + dx, origin.Y + dy); fitted = false; Invalidate(); }
    }
    protected override void OnMouseWheel(MouseEventArgs e) {
      base.OnMouseWheel(e);
      if ((ModifierKeys & Keys.Control) != 0) ZoomAt(e.Location, e.Delta > 0 ? 1.25 : 0.8);
      else if (Step != null) Step(e.Delta > 0 ? -1 : 1);
    }
    protected override void OnMouseDoubleClick(MouseEventArgs e) { base.OnMouseDoubleClick(e); Fit(); }

    protected override void OnPaint(PaintEventArgs e) {
      Graphics g = e.Graphics; g.Clear(BackColor);
      if (picture != null) {
        // shrunk pictures are smoothed; enlarged ones show their own pixels
        g.InterpolationMode = zoom >= 2 ? InterpolationMode.NearestNeighbor : InterpolationMode.Bilinear;
        g.PixelOffsetMode = PixelOffsetMode.Half;
        SizeF s = Shown; g.DrawImage(picture, new RectangleF(origin.X, origin.Y, s.Width, s.Height));
      }
      using (Font f = new Font("Segoe UI", 9f)) using (SolidBrush ink = new SolidBrush(ForeColor)) using (SolidBrush shade = new SolidBrush(Color.FromArgb(150, 0, 0, 0))) {
        Corner(g, f, ink, shade, TopLeft, false, false); Corner(g, f, ink, shade, TopRight, true, false);
        Corner(g, f, ink, shade, BottomLeft, false, true); Corner(g, f, ink, shade, BottomRight, true, true);
        if (Message != "") {
          using (Font big = new Font("Segoe UI", 11f)) {
            SizeF m = g.MeasureString(Message, big, ClientSize.Width - 40);
            g.DrawString(Message, big, ink, new RectangleF((ClientSize.Width - m.Width) / 2, (ClientSize.Height - m.Height) / 2, m.Width + 2, m.Height + 2));
          }
        }
      }
    }
    void Corner(Graphics g, Font f, Brush ink, Brush shade, string text, bool right, bool bottom) {
      if (string.IsNullOrEmpty(text)) return;
      SizeF m = g.MeasureString(text, f, Math.Max(60, ClientSize.Width / 2 - 12));
      float x = right ? ClientSize.Width - m.Width - 8 : 8, y = bottom ? ClientSize.Height - m.Height - 6 : 6;
      g.FillRectangle(shade, x - 3, y - 2, m.Width + 6, m.Height + 4);
      using (StringFormat sf = new StringFormat { Alignment = right ? StringAlignment.Far : StringAlignment.Near })
        g.DrawString(text, f, ink, new RectangleF(x, y, m.Width + 1, m.Height + 1), sf);
    }
  }
}
