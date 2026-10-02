// VIEWER.EXE - one image of the disc: what the file says about it, its pixels, and the
// picture drawn from them the way the file asks (grey scale turned over for
// MONOCHROME1, rescaled, shown through a window of grey levels; colours as RGB, as
// luminance and chroma, or through the file's own palette).
//
// The pixels are read as they are stored: uncompressed, RLE (Rle.cs), or JPEG -
// lossless JPEG by Jpeg.cs, lossy JPEG of 8 bits by Windows. Any other compression is
// said to be "not shown here" (the disc is made so that it does not occur: the EMR has
// the image server unpack such images when it makes the bundle).
//
// What is shown is the stored picture: it is never turned or flipped.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace Bethesda.Viewer {
  public class Picture : IDisposable {
    public string File, TransferSyntax, Photometric = "", Modality = "", SeriesDescription = "", StudyDescription = "", StudyDate = "", PatientName = "", PatientId = "", Institution = "", Orientation = "";
    public int Rows, Cols, Frames = 1, Samples = 1, BitsAllocated = 8, BitsStored = 8, HighBit = 7, InstanceNumber, SeriesNumber;
    public bool Signed, Planar, HasWindow;
    public double Slope = 1, Intercept, Center, Width, AspectY = 1;      // the window the picture starts with
    public string Problem = "";                                          // why it cannot be shown ("" = it can): a key of Texts
    public long Low, High;                                               // the range of its values (grey pictures)
    public string Coding = "raw";                                        // how its pixels are stored: raw, rle, lossless (JPEG, read here), windows (JPEG, read by Windows)
    public int Steps = 1;                                                // how many of its frames can be shown, one after the other

    DataSet d; Element px;
    ushort[] grey; int[] colour; int loadedFrame = -1;
    Bitmap bitmap; int[] argb;
    Bitmap quick; int[] quickArgb, quickX;                               // the same picture at the size it has on the screen: drawn while the mouse drags
    int[] lut;                                                           // stored value -> what the screen shows (kept: made anew it is large enough to stall the program)
    int[] starts;                                                        // compressed, several frames: the fragment each frame begins at
    int[][] palette; int paletteFirst;                                   // PALETTE COLOR: the red, green, blue of every stored value

    public const string Uncompressed = "1.2.840.10008.1.2.1", Implicit = "1.2.840.10008.1.2";
    // JPEG: baseline, extended, lossless, lossless with first-order prediction
    static readonly string[] JpegSyntaxes = { "1.2.840.10008.1.2.4.50", "1.2.840.10008.1.2.4.51", "1.2.840.10008.1.2.4.57", "1.2.840.10008.1.2.4.70" };
    public bool IsGrey { get { return Samples == 1 && Photometric != "PALETTE COLOR"; } }
    long FrameSize { get { return Photometric == "YBR_FULL_422" && Samples == 3 ? (long)Rows * Cols * 2 : (long)Rows * Cols * Samples * (BitsAllocated / 8); } }

    public static Picture Open(string path) {
      Picture p = new Picture(); p.File = path;
      try {
        using (FileStream s = System.IO.File.OpenRead(path)) { string ts; p.d = DicomReader.Open(s, false, out ts); p.TransferSyntax = ts; }
      } catch (Exception) { p.Problem = "unreadable"; return p; }
      DataSet d = p.d;
      p.Rows = d.Int(0x00280010, 0); p.Cols = d.Int(0x00280011, 0); p.Frames = Math.Max(1, d.Int(0x00280008, 1));
      p.Samples = d.Int(0x00280002, 1); p.Photometric = d.Str(0x00280004);
      p.BitsAllocated = d.Int(0x00280100, 8); p.BitsStored = d.Int(0x00280101, p.BitsAllocated); p.HighBit = d.Int(0x00280102, p.BitsStored - 1);
      if (p.BitsStored < 1 || p.BitsStored > p.BitsAllocated) p.BitsStored = p.BitsAllocated;
      if (p.HighBit < p.BitsStored - 1 || p.HighBit >= p.BitsAllocated) p.HighBit = p.BitsStored - 1;
      p.Signed = d.Int(0x00280103, 0) == 1; p.Planar = d.Int(0x00280006, 0) == 1;
      p.Slope = d.Num(0x00281053, 1); p.Intercept = d.Num(0x00281052, 0); if (p.Slope == 0) p.Slope = 1;
      p.Modality = d.Str(0x00080060); p.SeriesDescription = d.Str(0x0008103E); p.StudyDescription = d.Str(0x00081030); p.StudyDate = d.Date(0x00080020);
      p.PatientName = d.Name(0x00100010); p.PatientId = d.Str(0x00100020); p.Institution = d.Str(0x00080080);
      p.InstanceNumber = d.Int(0x00200013, 0); p.SeriesNumber = d.Int(0x00200011, 0);
      p.Orientation = d.Str(0x00200020).Replace("\\", " / "); string lat = d.Str(0x00200062); if (lat == "") lat = d.Str(0x00200060);
      if (lat != "") p.Orientation = (p.Orientation + "  " + lat).Trim();
      // pixels wider than tall or the other way round (0028,0034: vertical \ horizontal)
      string[] ar = d.Str(0x00280034).Split('\\'); double av, ah;
      if (ar.Length == 2 && double.TryParse(ar[0], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out av)
          && double.TryParse(ar[1], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out ah) && av > 0 && ah > 0) p.AspectY = av / ah;
      p.HasWindow = d.Has(0x00281050) && d.Has(0x00281051) && d.Num(0x00281051, 0) >= 1;
      if (p.HasWindow) { p.Center = d.Num(0x00281050, 0); p.Width = d.Num(0x00281051, 1); }

      d.TryGetValue(DicomReader.PixelData, out p.px);
      if (p.px == null || p.Rows <= 0 || p.Cols <= 0) p.Problem = "noPicture";
      else { try { p.Problem = p.Check(); } catch (Exception) { p.Problem = "unreadable"; } }
      return p;
    }

    // Can it be shown here? "" or the reason; also settles how its pixels are read.
    string Check() {
      if (px.Fragments != null) {
        bool rle = TransferSyntax == Rle.Syntax;
        if (!rle && Array.IndexOf(JpegSyntaxes, TransferSyntax) < 0) return "compressed";
        if (px.Fragments.Count < 2) return "unreadable";
        Steps = Splits() ? Frames : 1;
        if (rle) Coding = "rle";
        else {
          // what the JPEG stream says of itself decides who reads it
          int process, bits, w, h, comps;
          if (!Jpeg.Header(FrameBytes(0, 65536), out process, out bits, out w, out h, out comps) || w != Cols || h != Rows || comps != Samples) return "unreadable";
          if (process == 3 && bits <= BitsAllocated) Coding = "lossless";
          else if (process <= 2 && bits == 8) Coding = "windows";
          else return "compressed";
        }
      } else if (TransferSyntax != Uncompressed && TransferSyntax != Implicit) return "compressed";
      if (BitsAllocated != 8 && BitsAllocated != 16) return "unsupported";
      if (Samples == 1) {
        if (Photometric == "PALETTE COLOR") { if (Coding == "windows" || !ReadPalette()) return "unsupported"; }
        else if (Photometric != "MONOCHROME1" && Photometric != "MONOCHROME2") return "unsupported";
      } else if (Samples == 3) {
        // a lossy JPEG comes out of its decoder as red, green, blue whatever it was stored as
        if (BitsAllocated != 8) return "unsupported";
        if (Coding != "windows" && Photometric != "RGB" && Photometric != "YBR_FULL" && !(Photometric == "YBR_FULL_422" && Coding == "raw")) return "unsupported";
      } else return "unsupported";
      if (Coding == "raw") {
        if (px.Length < FrameSize) return "unreadable";
        Steps = (int)Math.Max(1, Math.Min(Frames, px.Length / FrameSize));
      }
      return "";
    }

    // Compressed, several frames: can one frame be told from the next? Yes when every
    // frame is one fragment, or when the table in front of the fragments says where each begins.
    bool Splits() {
      List<long[]> f = px.Fragments;
      if (Frames <= 1 || f.Count - 1 == Frames) return true;
      if (f[0][1] != 4L * Frames) return false;
      byte[] t = new byte[4 * Frames];
      using (FileStream s = System.IO.File.OpenRead(File)) { s.Position = f[0][0]; int got = 0; while (got < t.Length) { int r = s.Read(t, got, t.Length - got); if (r <= 0) return false; got += r; } }
      int[] st = new int[Frames]; long zero = f[1][0] - 8;
      for (int k = 0; k < Frames; k++) {
        long at = zero + BitConverter.ToUInt32(t, k * 4); st[k] = -1;
        for (int i = 1; i < f.Count; i++) if (f[i][0] - 8 == at) { st[k] = i; break; }
        if (st[k] < 0) return false;
      }
      starts = st; return true;
    }

    // The bytes of one frame of a compressed picture (at most `max` of them).
    byte[] FrameBytes(int frame, int max) {
      List<long[]> f = px.Fragments; int first = 1, last = f.Count - 1;
      if (Frames > 1 && f.Count - 1 == Frames) first = last = frame + 1;
      else if (Frames > 1 && starts != null) { first = starts[frame]; last = frame + 1 < Frames ? starts[frame + 1] - 1 : f.Count - 1; }
      long total = 0; for (int i = first; i <= last; i++) total += f[i][1];
      byte[] o = new byte[(int)Math.Min(total, max)]; int got = 0;
      using (FileStream s = System.IO.File.OpenRead(File)) {
        for (int i = first; i <= last && got < o.Length; i++) {
          s.Position = f[i][0]; int want = (int)Math.Min(f[i][1], o.Length - got);
          while (want > 0) { int r = s.Read(o, got, want); if (r <= 0) throw new EndOfStreamException(); got += r; want -= r; }
        }
      }
      return o;
    }

    // The file's own table of colours (0028,1101-1103 say how it is laid out, 1201-1203 hold it).
    bool ReadPalette() {
      palette = new int[3][];
      for (int c = 0; c < 3; c++) {
        Element how, data;
        if (!d.TryGetValue((uint)(0x00281101 + c), out how) || how.Value == null || how.Value.Length < 6) return false;
        if (!d.TryGetValue((uint)(0x00281201 + c), out data) || data.Value == null) return false;
        int n = BitConverter.ToUInt16(how.Value, 0), bits = BitConverter.ToUInt16(how.Value, 4); if (n == 0) n = 65536;
        if (c == 0) paletteFirst = BitConverter.ToUInt16(how.Value, 2);
        int[] t = new int[n];
        if (data.Value.Length >= n * 2) for (int i = 0; i < n; i++) { int v = BitConverter.ToUInt16(data.Value, i * 2); t[i] = bits > 8 ? v >> 8 : v & 0xFF; }
        else if (data.Value.Length >= n) for (int i = 0; i < n; i++) t[i] = data.Value[i];
        else return false;
        palette[c] = t;
      }
      return true;
    }

    // The stored samples of one frame of an uncompressed picture, pixel after pixel.
    ushort[] Raw(int frame) {
      int count = Rows * Cols; byte[] raw = new byte[FrameSize];
      using (FileStream s = System.IO.File.OpenRead(File)) {
        s.Position = px.Offset + (long)frame * raw.Length;
        int got = 0; while (got < raw.Length) { int r = s.Read(raw, got, raw.Length - got); if (r <= 0) throw new EndOfStreamException(); got += r; }
      }
      ushort[] v = new ushort[count * Samples];
      if (Samples == 1) { if (BitsAllocated == 8) for (int i = 0; i < count; i++) v[i] = raw[i]; else Buffer.BlockCopy(raw, 0, v, 0, count * 2); }
      else if (Photometric == "YBR_FULL_422") {
        // two pixels share their chroma: Y1 Y2 Cb Cr
        for (int i = 0; i + 1 < count; i += 2) { int q = i * 2, o = i * 3; v[o] = raw[q]; v[o + 3] = raw[q + 1]; v[o + 1] = v[o + 4] = raw[q + 2]; v[o + 2] = v[o + 5] = raw[q + 3]; }
      }
      else if (Planar) for (int i = 0; i < count; i++) { v[i * 3] = raw[i]; v[i * 3 + 1] = raw[count + i]; v[i * 3 + 2] = raw[2 * count + i]; }
      else for (int i = 0; i < v.Length; i++) v[i] = raw[i];
      return v;
    }

    // The pixels of one frame, read from the disc when first asked.
    void Load(int frame) {
      if (loadedFrame == frame) return;
      int count = Rows * Cols, w, h;
      if (Coding == "windows") {
        int[] rgb = Jpeg.ByWindows(FrameBytes(frame, int.MaxValue), Samples != 3 ? "" : Photometric == "RGB" ? "rgb" : "ybr", out w, out h);
        if (w != Cols || h != Rows) throw new InvalidDataException("size");
        if (Samples == 3) { colour = rgb; Center = 128; Width = 256; } else { ushort[] g = new ushort[count]; for (int i = 0; i < count; i++) g[i] = (ushort)(rgb[i] & 0xFF); Grey(g); }
      } else {
        ushort[] v;
        if (Coding == "lossless") { int c, b; v = Jpeg.Lossless(FrameBytes(frame, int.MaxValue), out w, out h, out c, out b); if (w != Cols || h != Rows || c != Samples) throw new InvalidDataException("size"); }
        else if (Coding == "rle") v = Rle.Decode(FrameBytes(frame, int.MaxValue), count, Samples, BitsAllocated / 8);
        else v = Raw(frame);
        if (Samples == 1) Grey(v); else Colour(v);
      }
      loadedFrame = frame;
    }

    // Grey values: only the bits that carry the picture (BitsStored of them, ending at HighBit).
    void Grey(ushort[] v) {
      int shift = Math.Max(0, HighBit - BitsStored + 1), mask = (1 << BitsStored) - 1, sign = 1 << (BitsStored - 1); long lo = long.MaxValue, hi = long.MinValue;
      for (int i = 0; i < v.Length; i++) {
        int x = (v[i] >> shift) & mask; v[i] = (ushort)x;
        if (Signed && (x & sign) != 0) x -= (1 << BitsStored);
        if (x < lo) lo = x; if (x > hi) hi = x;
      }
      Low = lo; High = hi;
      if (palette != null) {
        colour = new int[v.Length];
        for (int i = 0; i < v.Length; i++) {
          int k = v[i] - paletteFirst;
          colour[i] = unchecked((int)0xFF000000) | (Entry(0, k) << 16) | (Entry(1, k) << 8) | Entry(2, k);
        }
        Center = 128; Width = 256;
        return;
      }
      grey = v;
      if (!HasWindow) {
        // no window written in the image: an 8-bit picture is shown as it is, a deeper one over its whole range
        if (BitsStored <= 8) { Center = 128 * Slope + Intercept; Width = 256 * Slope; }
        else { Center = (lo + hi) / 2.0 * Slope + Intercept + 0.5; Width = Math.Max(1, (hi - lo) * Slope + 1); }
      }
    }
    int Entry(int c, int k) { int[] t = palette[c]; return t[k < 0 ? 0 : k >= t.Length ? t.Length - 1 : k]; }

    // Colours: stored as red, green, blue, or as luminance and two chroma values.
    void Colour(ushort[] v) {
      int count = Rows * Cols; colour = new int[count]; bool ybr = Photometric.StartsWith("YBR");
      for (int i = 0; i < count; i++) {
        int r = v[i * 3], g = v[i * 3 + 1], b = v[i * 3 + 2];
        if (ybr) {
          double y = r, cb = g - 128.0, cr = b - 128.0;
          r = Byte(y + 1.402 * cr); g = Byte(y - 0.344136 * cb - 0.714136 * cr); b = Byte(y + 1.772 * cb);
        }
        colour[i] = unchecked((int)0xFF000000) | (r << 16) | (g << 8) | b;
      }
      // A colour picture has no window of its own: 128 / 256 shows it as it is, and moving
      // that window makes it brighter or darker, harder or softer - the same for red, green and blue.
      Center = 128; Width = 256;
    }
    static int Byte(double x) { int n = (int)Math.Round(x); return n < 0 ? 0 : n > 255 ? 255 : n; }

    // The window the picture starts with (after its pixels were read at least once).
    public void DefaultWindow(out double center, out double width) { if (Problem == "") Load(Math.Max(0, loadedFrame)); center = Center; width = Width; }

    // Frame `frame` drawn through the window (centre, width), turned over when asked.
    // The bitmap is this object's own: it is drawn into again at the next call.
    public Bitmap Render(int frame, double center, double width, bool invert) { return Render(frame, center, width, invert, 0, 0); }

    // (outW, outH) given: the picture made at once in that size - the size it has on the
    // screen - by taking the nearest pixel. It is quick to make and needs no scaling to be
    // put on the screen: for the moments the mouse is dragging the window. (0, 0): in full.
    public Bitmap Render(int frame, double center, double width, bool invert, int outW, int outH) {
      if (Problem != "") return null;
      Load(frame);
      bool whole = outW <= 0 || outH <= 0;
      int w = whole ? Cols : outW, h = whole ? Rows : outH; int[] to;
      if (whole) { if (argb == null) argb = new int[Rows * Cols]; to = argb; }
      else {
        if (quick == null || quick.Width != w || quick.Height != h) {
          if (quick != null) quick.Dispose();
          quick = new Bitmap(w, h, PixelFormat.Format32bppRgb); quickArgb = new int[w * h]; quickX = new int[w];
          for (int x = 0; x < w; x++) quickX[x] = Math.Min(Cols - 1, (int)((x + 0.5) * Cols / w));
        }
        to = quickArgb;
      }
      // every stored value -> what the screen shows, once; then one look-up a pixel
      bool isGrey = IsGrey; int n = isGrey ? 1 << BitsStored : 256, sign = 1 << (BitsStored - 1);
      if (lut == null || lut.Length != n) lut = new int[n];
      bool turned = isGrey ? (Photometric == "MONOCHROME1") != invert : invert;
      double lo = center - 0.5 - (width - 1) / 2, hi = center - 0.5 + (width - 1) / 2;
      for (int v = 0; v < n; v++) {
        int s = isGrey && Signed && (v & sign) != 0 ? v - n : v;
        double val = isGrey ? s * Slope + Intercept : s, shown;
        if (width <= 1) shown = val <= center - 0.5 ? 0 : 255;
        else if (val <= lo) shown = 0; else if (val > hi) shown = 255; else shown = ((val - (center - 0.5)) / (width - 1) + 0.5) * 255;
        int g = (int)Math.Round(shown); if (g < 0) g = 0; if (g > 255) g = 255; if (turned) g = 255 - g;
        lut[v] = isGrey ? unchecked((int)0xFF000000) | (g << 16) | (g << 8) | g : g;
      }
      int[] t = lut, xs = quickX; const int opaque = unchecked((int)0xFF000000);
      if (isGrey) {
        ushort[] src = grey;
        if (whole) { int count = Rows * Cols; for (int i = 0; i < count; i++) to[i] = t[src[i]]; }
        else for (int y = 0, k = 0; y < h; y++) { int row = Math.Min(Rows - 1, (int)((y + 0.5) * Rows / h)) * Cols; for (int x = 0; x < w; x++) to[k++] = t[src[row + xs[x]]]; }
      } else {
        int[] src = colour;
        if (whole) { int count = Rows * Cols; for (int i = 0; i < count; i++) { int c = src[i]; to[i] = opaque | (t[(c >> 16) & 255] << 16) | (t[(c >> 8) & 255] << 8) | t[c & 255]; } }
        else for (int y = 0, k = 0; y < h; y++) {
          int row = Math.Min(Rows - 1, (int)((y + 0.5) * Rows / h)) * Cols;
          for (int x = 0; x < w; x++) { int c = src[row + xs[x]]; to[k++] = opaque | (t[(c >> 16) & 255] << 16) | (t[(c >> 8) & 255] << 8) | t[c & 255]; }
        }
      }
      Bitmap b;
      if (whole) { if (bitmap == null) bitmap = new Bitmap(Cols, Rows, PixelFormat.Format32bppRgb); b = bitmap; } else b = quick;
      BitmapData bd = b.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppRgb);
      if (bd.Stride == w * 4) Marshal.Copy(to, 0, bd.Scan0, w * h);
      else for (int y = 0; y < h; y++) Marshal.Copy(to, y * w, IntPtr.Add(bd.Scan0, y * bd.Stride), w);
      b.UnlockBits(bd);
      return b;
    }

    // Let go of the pixels (the picture is no longer on the screen).
    public void Dispose() { if (bitmap != null) bitmap.Dispose(); if (quick != null) quick.Dispose(); bitmap = quick = null; argb = quickArgb = quickX = null; lut = null; grey = null; colour = null; loadedFrame = -1; }
  }
}
