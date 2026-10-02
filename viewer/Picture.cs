// VOIR.EXE - one image of the disc: what the file says about it, its pixels, and the
// picture drawn from them the way the file asks (grey scale turned over for
// MONOCHROME1, rescaled, shown through a window of grey levels).
//
// What is shown is the stored picture: it is never turned or flipped.
using System;
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

    DataSet d; Element px;
    ushort[] grey; int[] colour; int loadedFrame = -1;
    Bitmap bitmap; int[] argb;

    public const string Uncompressed = "1.2.840.10008.1.2.1", Implicit = "1.2.840.10008.1.2";
    public bool IsGrey { get { return Samples == 1; } }

    public static Picture Open(string path) {
      Picture p = new Picture(); p.File = path;
      try {
        using (FileStream s = System.IO.File.OpenRead(path)) { string ts; p.d = DicomReader.Open(s, false, out ts); p.TransferSyntax = ts; }
      } catch (Exception) { p.Problem = "unreadable"; return p; }
      DataSet d = p.d;
      p.Rows = d.Int(0x00280010, 0); p.Cols = d.Int(0x00280011, 0); p.Frames = Math.Max(1, d.Int(0x00280008, 1));
      p.Samples = d.Int(0x00280002, 1); p.Photometric = d.Str(0x00280004);
      p.BitsAllocated = d.Int(0x00280100, 8); p.BitsStored = d.Int(0x00280101, p.BitsAllocated); p.HighBit = d.Int(0x00280102, p.BitsStored - 1);
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
      else if (p.px.Fragments != null || (p.TransferSyntax != Uncompressed && p.TransferSyntax != Implicit)) p.Problem = "compressed";
      else if (p.BitsAllocated != 8 && p.BitsAllocated != 16) p.Problem = "unsupported";
      else if (p.Samples == 1 && p.Photometric != "MONOCHROME1" && p.Photometric != "MONOCHROME2") p.Problem = "unsupported";
      else if (p.Samples == 3 && (p.Photometric != "RGB" || p.BitsAllocated != 8)) p.Problem = "unsupported";
      else if (p.Samples != 1 && p.Samples != 3) p.Problem = "unsupported";
      else if (p.px.Length < (long)p.Rows * p.Cols * p.Samples * (p.BitsAllocated / 8)) p.Problem = "unreadable";
      return p;
    }

    // The pixels of one frame, read from the disc when first asked.
    void Load(int frame) {
      if (loadedFrame == frame) return;
      int bytes = BitsAllocated / 8, count = Rows * Cols;
      byte[] raw = new byte[count * Samples * bytes];
      using (FileStream s = System.IO.File.OpenRead(File)) {
        s.Position = px.Offset + (long)frame * raw.Length;
        int got = 0; while (got < raw.Length) { int r = s.Read(raw, got, raw.Length - got); if (r <= 0) break; got += r; }
      }
      if (Samples == 3) {
        colour = new int[count];
        for (int i = 0; i < count; i++) {
          int r = Planar ? raw[i] : raw[i * 3], g = Planar ? raw[count + i] : raw[i * 3 + 1], b = Planar ? raw[2 * count + i] : raw[i * 3 + 2];
          colour[i] = unchecked((int)0xFF000000) | (r << 16) | (g << 8) | b;
        }
      } else {
        // only the bits that carry the picture: BitsStored of them, ending at HighBit
        int shift = Math.Max(0, HighBit - BitsStored + 1), mask = (1 << BitsStored) - 1, sign = 1 << (BitsStored - 1);
        grey = new ushort[count]; long lo = long.MaxValue, hi = long.MinValue;
        for (int i = 0; i < count; i++) {
          int v = bytes == 1 ? raw[i] : (raw[i * 2] | (raw[i * 2 + 1] << 8));
          v = (v >> shift) & mask; grey[i] = (ushort)v;
          if (Signed && (v & sign) != 0) v -= (1 << BitsStored);
          if (v < lo) lo = v; if (v > hi) hi = v;
        }
        Low = lo; High = hi;
        if (!HasWindow) {
          // no window written in the image: an 8-bit picture is shown as it is, a deeper one over its whole range
          if (BitsStored <= 8) { Center = 128 * Slope + Intercept; Width = 256 * Slope; }
          else { Center = (lo + hi) / 2.0 * Slope + Intercept + 0.5; Width = Math.Max(1, (hi - lo) * Slope + 1); }
        }
      }
      loadedFrame = frame;
    }

    // The window the picture starts with (after its pixels were read at least once).
    public void DefaultWindow(out double center, out double width) { if (Problem == "") Load(Math.Max(0, loadedFrame)); center = Center; width = Width; }

    // Frame `frame` drawn through the window (centre, width), turned over when asked.
    // The bitmap is this object's own: it is drawn into again at the next call.
    public Bitmap Render(int frame, double center, double width, bool invert) {
      if (Problem != "") return null;
      Load(frame);
      int count = Rows * Cols;
      if (argb == null) argb = new int[count];
      if (Samples == 3) {
        if (invert) { for (int i = 0; i < count; i++) argb[i] = colour[i] ^ 0x00FFFFFF; } else Array.Copy(colour, argb, count);
      } else {
        // every stored value -> a grey of the screen, once; then one look-up a pixel
        int n = 1 << BitsStored, sign = 1 << (BitsStored - 1); int[] lut = new int[n];
        bool turned = (Photometric == "MONOCHROME1") != invert;
        double lo = center - 0.5 - (width - 1) / 2, hi = center - 0.5 + (width - 1) / 2;
        for (int v = 0; v < n; v++) {
          int x = Signed && (v & sign) != 0 ? v - n : v;
          double val = x * Slope + Intercept, y;
          if (width <= 1) y = val <= center - 0.5 ? 0 : 255;
          else if (val <= lo) y = 0; else if (val > hi) y = 255; else y = ((val - (center - 0.5)) / (width - 1) + 0.5) * 255;
          int g = (int)Math.Round(y); if (g < 0) g = 0; if (g > 255) g = 255; if (turned) g = 255 - g;
          lut[v] = unchecked((int)0xFF000000) | (g << 16) | (g << 8) | g;
        }
        for (int i = 0; i < count; i++) argb[i] = lut[grey[i]];
      }
      if (bitmap == null) bitmap = new Bitmap(Cols, Rows, PixelFormat.Format32bppRgb);
      BitmapData bd = bitmap.LockBits(new Rectangle(0, 0, Cols, Rows), ImageLockMode.WriteOnly, PixelFormat.Format32bppRgb);
      for (int y = 0; y < Rows; y++) Marshal.Copy(argb, y * Cols, IntPtr.Add(bd.Scan0, y * bd.Stride), Cols);
      bitmap.UnlockBits(bd);
      return bitmap;
    }

    // Let go of the pixels (the picture is no longer on the screen).
    public void Dispose() { if (bitmap != null) bitmap.Dispose(); bitmap = null; argb = null; grey = null; colour = null; loadedFrame = -1; }
  }
}
