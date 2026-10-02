// VOIR.EXE - RLE, the simple lossless compression some machines use (DICOM PS3.5
// annex G). A frame is cut into "segments" - one for each byte of each sample, the
// high byte first - and each segment is run-length coded (PackBits): a count byte, then
// either that many bytes as they are, or one byte to repeat.
using System;
using System.IO;

namespace Bethesda.Viewer {
  public static class Rle {
    public const string Syntax = "1.2.840.10008.1.2.5";

    // One frame: its samples, pixel after pixel. `bytes`: 1 or 2 to a sample.
    // Throws when the frame is not what the image says it is, or ends early.
    public static ushort[] Decode(byte[] f, int count, int samples, int bytes) {
      if (f.Length < 64) throw new EndOfStreamException();
      int n = BitConverter.ToInt32(f, 0);
      if (n != samples * bytes) throw new InvalidDataException("RLE segments");
      ushort[] v = new ushort[count * samples]; byte[] plane = new byte[count];
      for (int s = 0; s < n; s++) {
        long from = BitConverter.ToUInt32(f, 4 + s * 4), to = s + 1 < n ? (long)BitConverter.ToUInt32(f, 8 + s * 4) : f.Length;
        if (from < 64 || to > f.Length || from > to) throw new InvalidDataException("RLE offsets");
        int p = (int)from, o = 0;
        while (o < count && p < to) {
          int c = (sbyte)f[p++];
          if (c >= 0) {                                   // c + 1 bytes as they are
            c = Math.Min(c + 1, count - o); if (p + c > to) throw new EndOfStreamException();
            Buffer.BlockCopy(f, p, plane, o, c); p += c; o += c;
          } else if (c != -128) {                         // the next byte, 1 - c times
            if (p >= to) throw new EndOfStreamException();
            c = Math.Min(1 - c, count - o); byte b = f[p++];
            for (int k = 0; k < c; k++) plane[o++] = b;
          }
        }
        if (o < count) throw new EndOfStreamException();
        int sample = s / bytes, shift = bytes == 2 && s % 2 == 0 ? 8 : 0;
        for (int i = 0; i < count; i++) v[i * samples + sample] |= (ushort)(plane[i] << shift);
      }
      return v;
    }
  }
}
