// VOIR.EXE - JPEG, the compression ultrasound machines send their pictures in.
//
// Lossless JPEG (the hospital's own machine: "JPEG Lossless, first-order prediction")
// is read here, by the standard's own rule (ITU T.81 annex H): every sample is its
// neighbours' prediction plus a difference, and the differences are Huffman-coded.
// Nothing is approximated - the picture comes out as the machine made it, and it does
// not depend on what the receiver's Windows can decode.
//
// Lossy JPEG of 8 bits is left to the decoder that is part of every Windows (GDI+).
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace Bethesda.Viewer {
  public static class Jpeg {
    static bool IsFrame(int m) { return m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC; }

    // What the stream says of itself: its process (the n of SOFn - 0, 1, 2 lossy, 3 lossless),
    // the bits of a sample, its size, its components. False when no frame header is found
    // (`j` may be only the beginning of the stream).
    public static bool Header(byte[] j, out int process, out int bits, out int width, out int height, out int comps) {
      process = bits = width = height = comps = 0;
      if (j.Length < 4 || j[0] != 0xFF || j[1] != 0xD8) return false;
      int i = 2;
      while (i + 4 <= j.Length) {
        if (j[i] != 0xFF) return false;
        int m = j[i + 1]; if (m == 0xFF) { i++; continue; }
        if (m == 0xDA || m == 0xD9) return false;
        if (IsFrame(m)) {
          if (i + 10 > j.Length) return false;
          process = m - 0xC0; bits = j[i + 4]; height = (j[i + 5] << 8) | j[i + 6]; width = (j[i + 7] << 8) | j[i + 8]; comps = j[i + 9];
          return true;
        }
        i += 2 + ((j[i + 2] << 8) | j[i + 3]);
      }
      return false;
    }

    // A lossless JPEG picture: its samples, pixel after pixel (component after component
    // within a pixel). Throws when the stream is not one, or is damaged.
    public static ushort[] Lossless(byte[] j, out int width, out int height, out int comps, out int bits) {
      width = height = comps = bits = 0;
      if (j.Length < 4 || j[0] != 0xFF || j[1] != 0xD8) throw new InvalidDataException("not JPEG");
      ushort[][] tables = new ushort[4][]; int[] ids = null; ushort[] o = null; int restart = 0, pt = 0, i = 2;
      while (i + 4 <= j.Length) {
        if (j[i] != 0xFF) throw new InvalidDataException("JPEG marker");
        int m = j[i + 1]; if (m == 0xFF) { i++; continue; }
        if (m == 0xD9) break;
        int p = i + 4, end = i + 2 + ((j[i + 2] << 8) | j[i + 3]);
        if (end > j.Length) throw new EndOfStreamException();
        if (m == 0xC3) {
          bits = j[p]; height = (j[p + 1] << 8) | j[p + 2]; width = (j[p + 3] << 8) | j[p + 4]; comps = j[p + 5];
          if (bits < 2 || bits > 16 || width <= 0 || height <= 0 || comps < 1 || comps > 4 || (long)width * height * comps > 400000000) throw new InvalidDataException("JPEG frame");
          ids = new int[comps];
          for (int c = 0; c < comps; c++) { ids[c] = j[p + 6 + c * 3]; if (j[p + 7 + c * 3] != 0x11) throw new InvalidDataException("JPEG sampling"); }
          o = new ushort[width * height * comps];
        } else if (IsFrame(m)) throw new InvalidDataException("not lossless JPEG");
        else if (m == 0xC4) {
          // Huffman tables: for every 16 bits that may come next, the length of the code they begin with and what it stands for
          while (p + 17 <= end) {
            int id = j[p] & 15; if (id > 3) throw new InvalidDataException("JPEG table");
            ushort[] t = new ushort[65536]; int code = 0, k = p + 17;
            for (int len = 1; len <= 16; len++) {
              for (int n = 0; n < j[p + len]; n++) {
                if (k >= end) throw new InvalidDataException("JPEG table");
                int from = code << (16 - len), to = Math.Min(65536, (code + 1) << (16 - len)); ushort v = (ushort)((len << 8) | j[k++]);
                for (int x = from; x < to; x++) t[x] = v;
                code++;
              }
              code <<= 1;
            }
            tables[id] = t; p = k;
          }
        } else if (m == 0xDD) restart = (j[p] << 8) | j[p + 1];
        else if (m == 0xDA) {
          if (o == null) throw new InvalidDataException("JPEG scan");
          int ns = j[p]; int[] of = new int[ns]; ushort[][] tb = new ushort[ns][];
          for (int s = 0; s < ns; s++) {
            of[s] = Array.IndexOf(ids, (int)j[p + 1 + s * 2]); int td = j[p + 2 + s * 2] >> 4;
            if (of[s] < 0 || td > 3 || tables[td] == null) throw new InvalidDataException("JPEG scan");
            tb[s] = tables[td];
          }
          int predictor = j[p + 1 + ns * 2]; pt = j[p + 3 + ns * 2] & 15;
          if (predictor < 1 || predictor > 7 || pt >= bits) throw new InvalidDataException("JPEG scan");
          i = Scan(j, end, o, width, height, comps, of, tb, predictor, bits - pt, restart);
          continue;
        }
        i = end;
      }
      if (o == null) throw new InvalidDataException("no JPEG frame");
      if (pt > 0) for (int x = 0; x < o.Length; x++) o[x] <<= pt;
      return o;
    }

    // One scan of a lossless picture, from `pos`; answers where it ends.
    static int Scan(byte[] j, int pos, ushort[] o, int w, int h, int nf, int[] of, ushort[][] tb, int predictor, int precision, int restart) {
      // The bits read ahead. stop: the data ended (a marker), zeros follow - `zeros` of them.
      // A damaged file is told by its length: the bits of an intact one end where its samples do.
      ulong buf = 0; int cnt = 0, zeros = 0; bool stop = false;
      int ns = of.Length, first = 0, row = w * nf; long done = 0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          if (restart > 0 && done > 0 && done % restart == 0) {
            // a restart: the bits up to the byte boundary are dropped, the RSTn marker is passed, prediction starts again
            if (!stop || cnt < zeros || cnt - zeros >= 8) throw new InvalidDataException("JPEG data");
            buf = 0; cnt = 0; zeros = 0; stop = false;
            while (pos + 1 < j.Length && !(j[pos] == 0xFF && j[pos + 1] >= 0xD0 && j[pos + 1] <= 0xD7)) pos++;
            pos += 2; first = y;
          }
          for (int s = 0; s < ns; s++) {
            while (cnt <= 48) {
              int b = 0;
              if (!stop && pos < j.Length) {
                b = j[pos];
                if (b != 0xFF) pos++; else if (pos + 1 < j.Length && j[pos + 1] == 0) pos += 2; else { stop = true; b = 0; }
              } else stop = true;
              if (stop) zeros += 8;
              buf = (buf << 8) | (uint)b; cnt += 8;
            }
            int e = tb[s][(int)((buf >> (cnt - 16)) & 0xFFFF)], len = e >> 8, cat = e & 0xFF, diff = 0;
            if (len == 0 || cat > 16) throw new InvalidDataException("JPEG code");
            cnt -= len;
            if (cat == 16) diff = 32768;
            else if (cat > 0) { int v = (int)((buf >> (cnt - cat)) & ((1UL << cat) - 1)); cnt -= cat; diff = v < (1 << (cat - 1)) ? v - (1 << cat) + 1 : v; }
            int at = (y * w + x) * nf + of[s], pred;
            if (y == first) pred = x == 0 ? 1 << (precision - 1) : o[at - nf];
            else if (x == 0) pred = o[at - row];
            else {
              int ra = o[at - nf], rb = o[at - row], rc = o[at - row - nf];
              switch (predictor) {
                case 1: pred = ra; break;
                case 2: pred = rb; break;
                case 3: pred = rc; break;
                case 4: pred = ra + rb - rc; break;
                case 5: pred = ra + ((rb - rc) >> 1); break;
                case 6: pred = rb + ((ra - rc) >> 1); break;
                default: pred = (ra + rb) >> 1; break;
              }
            }
            o[at] = (ushort)(pred + diff);
          }
          done++;
        }
      }
      if (!stop || cnt < zeros || cnt - zeros >= 8) throw new InvalidDataException("JPEG data");
      // the scan ends at the next marker that is not a restart
      while (pos + 1 < j.Length && !(j[pos] == 0xFF && j[pos + 1] != 0 && !(j[pos + 1] >= 0xD0 && j[pos + 1] <= 0xD7))) pos++;
      return pos;
    }

    // A lossy JPEG picture of 8 bits, by the decoder that is part of Windows: its pixels
    // as 0xFFRRGGBB (a grey picture has the three alike). `colours`: what the three
    // components of a colour picture are, as the DICOM file says it - "rgb" (red, green,
    // blue as they are), "ybr" (luminance and two chroma values), "" for a grey picture.
    public static int[] ByWindows(byte[] j, string colours, out int width, out int height) {
      if (colours != "") j = SayColours(j, colours == "rgb");
      using (MemoryStream ms = new MemoryStream(j)) using (Bitmap b = new Bitmap(ms)) {
        width = b.Width; height = b.Height; int[] o = new int[width * height];
        BitmapData bd = b.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.ReadOnly, PixelFormat.Format32bppRgb);
        try { for (int y = 0; y < height; y++) Marshal.Copy(IntPtr.Add(bd.Scan0, y * bd.Stride), o, y * width, width); } finally { b.UnlockBits(bd); }
        for (int k = 0; k < o.Length; k++) o[k] |= unchecked((int)0xFF000000);
        return o;
      }
    }

    // A decoder left to itself guesses what the three components are, and guesses
    // "luminance and chroma" for most streams - also for those a machine filled with red,
    // green and blue. The DICOM file knows; it is told to the decoder in the one way every
    // JPEG decoder listens to: an "Adobe" segment whose last byte is 0 (as they are) or 1
    // (luminance and chroma), put in the place of the stream's own JFIF / Adobe segments.
    static byte[] SayColours(byte[] j, bool rgb) {
      MemoryStream o = new MemoryStream(j.Length + 16); o.Write(j, 0, 2);
      o.Write(new byte[] { 0xFF, 0xEE, 0, 14, (byte)'A', (byte)'d', (byte)'o', (byte)'b', (byte)'e', 0, 100, 0, 0, 0, 0, (byte)(rgb ? 0 : 1) }, 0, 16);
      int i = 2;
      while (i + 4 <= j.Length && j[i] == 0xFF && j[i + 1] != 0xDA && j[i + 1] != 0xFF) {
        int m = j[i + 1], len = 2 + ((j[i + 2] << 8) | j[i + 3]); if (i + len > j.Length) break;
        if (m != 0xE0 && m != 0xEE) o.Write(j, i, len);
        i += len;
      }
      o.Write(j, i, j.Length - i); return o.ToArray();
    }
  }
}
