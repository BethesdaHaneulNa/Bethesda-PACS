// VIEWER.EXE - the small viewer that goes on every disc cd-export makes.
// This file: reading a DICOM file. Only what a viewer needs - the header, the few dozen
// attributes that say how to draw the picture, where the pixels are, and the list of a
// DICOMDIR. Little-endian files, explicit or implicit VR; anything else is refused with
// a reason (the disc is made so that it does not occur - see cd-mini-viewer-design.md).
//
// C# 5 only: it is compiled by the compiler that ships with Windows.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace Bethesda.Viewer {
  public class Element {
    public uint Tag; public string VR; public byte[] Value;
    public long Offset, Length;                       // where the value is in the file (the pixels are not kept in memory here)
    public List<DataSet> Items;                       // a sequence
    public List<long[]> Fragments;                    // compressed pixels: { offset, length } of each fragment
  }

  // The words of a DICOM file as people wrote them. A file says in (0008,0005) which character set
  // its words are in; discs from Korea, Japan and China also switch sets inside a value (ISO 2022
  // escape sequences), and many devices write Korean names without saying so at all.
  public static class DicomText {
    public static readonly Encoding Latin1 = Encoding.GetEncoding(28591);
    static Encoding Page(int page) { try { return Encoding.GetEncoding(page); } catch (Exception) { return Latin1; } }
    public static Encoding Korean { get { return Page(949); } }

    // `named`: the set the file names (Western Europe when it names none). `guess`: the file names
    // none, or Western Europe - then bytes that are plainly UTF-8 or Korean are read as such.
    public static string Decode(byte[] v, Encoding named, bool guess) {
      bool high = false, esc = false;
      for (int i = 0; i < v.Length; i++) { if (v[i] >= 0x80) high = true; else if (v[i] == 0x1B) esc = true; }
      if (esc) return Escaped(v, named);
      if (!high) return Latin1.GetString(v);
      if (guess || named.CodePage == 65001) {
        if (IsUtf8(v)) return Encoding.UTF8.GetString(v);
        if (IsHangul(v)) return Korean.GetString(v);
        if (named.CodePage == 65001) return Latin1.GetString(v);          // said to be UTF-8 and is not
      }
      return named.GetString(v);
    }

    // Well-formed UTF-8 with at least one character of several bytes. Western European text that
    // happens to be this is not met in practice (it would read like "Ã©").
    public static bool IsUtf8(byte[] v) {
      bool any = false;
      for (int i = 0; i < v.Length; ) {
        int b = v[i], n;
        if (b < 0x80) { i++; continue; }
        if (b >= 0xC2 && b <= 0xDF) n = 1; else if (b >= 0xE0 && b <= 0xEF) n = 2; else if (b >= 0xF0 && b <= 0xF4) n = 3; else return false;
        if (i + n > v.Length - 1) return false;
        for (int k = 1; k <= n; k++) if ((v[i + k] & 0xC0) != 0x80) return false;
        if (b == 0xE0 && v[i + 1] < 0xA0) return false;                    // (a longer form of a shorter character)
        if (b == 0xF0 && v[i + 1] < 0x90) return false;
        i += n + 1; any = true;
      }
      return any;
    }
    // Korean written as EUC-KR: every byte above ASCII belongs to a pair "Hangul syllable"
    // (B0..C8, then A1..FE) and none is left over. Kept this narrow on purpose: French names in
    // Western European bytes (é, è, É, ç...) are never such pairs - an accent is followed by a letter.
    public static bool IsHangul(byte[] v) {
      bool any = false;
      for (int i = 0; i < v.Length; ) {
        if (v[i] < 0x80) { i++; continue; }
        if (v[i] < 0xB0 || v[i] > 0xC8 || i + 1 >= v.Length || v[i + 1] < 0xA1 || v[i + 1] > 0xFE) return false;
        i += 2; any = true;
      }
      return any;
    }

    // A value with ISO 2022 escape sequences: each stretch is read in the set that was switched to.
    static string Escaped(byte[] v, Encoding initial) {
      StringBuilder sb = new StringBuilder(); Encoding g = initial; int pairs = 0, from = 0, i = 0;      // pairs: 1 = JIS X 0208, 2 = JIS X 0212 (two 7-bit bytes a character)
      while (i < v.Length) {
        if (v[i] != 0x1B) { i++; continue; }
        Stretch(sb, v, from, i, g, pairs);
        int j = i + 1; while (j < v.Length && v[j] >= 0x20 && v[j] <= 0x2F) j++;
        string seq = j < v.Length ? Latin1.GetString(v, i + 1, j - i) : "";
        i = Math.Min(v.Length, j + 1); from = i;
        switch (seq) {
          case "$)C": g = Korean; pairs = 0; break;                      // KS X 1001
          case "$)A": g = Page(936); pairs = 0; break;                   // GB 2312
          case "$B": case "$@": pairs = 1; break;                        // JIS X 0208
          case "$(D": pairs = 2; break;                                  // JIS X 0212
          case "(B": case "(J": pairs = 0; break;                        // ASCII, JIS Roman
          case ")I": g = Page(932); break;                               // half-width katakana
          case "-A": g = Latin1; break;
          case "-B": g = Page(28592); break;
          case "-C": g = Page(28593); break;
          case "-D": g = Page(28594); break;
          case "-L": g = Page(28595); break;
          case "-G": g = Page(28596); break;
          case "-F": g = Page(28597); break;
          case "-H": g = Page(28598); break;
          case "-M": g = Page(28599); break;
          case "-T": g = Page(874); break;
        }
      }
      Stretch(sb, v, from, v.Length, g, pairs);
      return sb.ToString();
    }
    static void Stretch(StringBuilder sb, byte[] v, int from, int to, Encoding g, int pairs) {
      if (to <= from) return;
      if (pairs == 0) { sb.Append(g.GetString(v, from, to - from)); return; }
      List<byte> euc = new List<byte>();                                   // 7-bit JIS pairs, read as EUC-JP
      for (int k = from; k + 1 < to; k += 2) { if (pairs == 2) euc.Add(0x8F); euc.Add((byte)(v[k] | 0x80)); euc.Add((byte)(v[k + 1] | 0x80)); }
      sb.Append(Page(51932).GetString(euc.ToArray()));
    }

    // A person's name as people write it: "RAKOTO^Jean^^^" -> "RAKOTO Jean". A name may come in up
    // to three writings, "Hong^Gildong=洪^吉洞=홍^길동" (Latin letters = ideographs = phonetic): the
    // first is shown, with the local writing beside it - "Hong Gildong (홍 길동)".
    public static string PersonName(string raw) {
      string[] groups = (raw ?? "").Split('='); List<string> shown = new List<string>();
      foreach (string g in groups) shown.Add(string.Join(" ", g.Split(new[] { '^' }, StringSplitOptions.RemoveEmptyEntries)).Trim());
      string first = shown[0], local = shown.Count > 2 && shown[2] != "" ? shown[2] : shown.Count > 1 ? shown[1] : "";
      if (first == "") return local;
      return local != "" && local != first ? first + " (" + local + ")" : first;
    }
  }

  public class DataSet : Dictionary<uint, Element> {
    public Encoding Text = DicomText.Latin1;          // the character set the file names
    public bool Guess = true;                         // it names none, or Western Europe: see DicomText.Decode
    public long At;                                   // an item of a sequence: where it starts in the file

    public bool Has(uint tag) { Element e; return TryGetValue(tag, out e) && e.Value != null && e.Value.Length > 0; }
    public string Str(uint tag) {
      Element e; if (!TryGetValue(tag, out e) || e.Value == null) return "";
      return DicomText.Decode(e.Value, Text, Guess).TrimEnd('\0', ' ').Trim();
    }
    // The first of several values ("40\\400" -> "40").
    public string First(uint tag) { string s = Str(tag); int i = s.IndexOf('\\'); return i < 0 ? s : s.Substring(0, i).Trim(); }
    public int Int(uint tag, int def) {
      Element e; if (!TryGetValue(tag, out e) || e.Value == null || e.Value.Length == 0) return def;
      if (e.VR == "US" || (e.VR == "UN" && e.Value.Length == 2)) return BitConverter.ToUInt16(e.Value, 0);
      if (e.VR == "UL" && e.Value.Length >= 4) return (int)BitConverter.ToUInt32(e.Value, 0);
      double v; return double.TryParse(First(tag), NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? (int)Math.Round(v) : def;
    }
    public double Num(uint tag, double def) {
      double v; string t = First(tag);
      return t.Length > 0 && double.TryParse(t, NumberStyles.Float, CultureInfo.InvariantCulture, out v) ? v : def;
    }
    // A person's name as people write it: "RAKOTO^Jean^^^" -> "RAKOTO Jean".
    public string Name(uint tag) { return DicomText.PersonName(Str(tag)); }
    // "20261001" -> "2026-10-01"
    public string Date(uint tag) {
      string s = Str(tag);
      return s.Length == 8 ? s.Substring(0, 4) + "-" + s.Substring(4, 2) + "-" + s.Substring(6, 2) : s;
    }
  }

  public static class DicomReader {
    static readonly HashSet<string> LongVR = new HashSet<string> { "OB", "OW", "OF", "OD", "OL", "OV", "SQ", "UT", "UN", "UC", "UR", "SV", "UV" };
    public const uint PixelData = 0x7FE00010;

    static uint Tag(byte[] b) { return (uint)((b[1] << 24) | (b[0] << 16) | (b[3] << 8) | b[2]); }
    static void Fill(Stream s, byte[] b, int n) { int got = 0; while (got < n) { int r = s.Read(b, got, n - got); if (r <= 0) throw new EndOfStreamException(); got += r; } }

    // The character set a data set names (0008,0005). Western Europe when it names none. Of several
    // ("\\ISO 2022 IR 149": ASCII, then Korean after a switch) the last is the one that tells.
    static void SetText(DataSet d) {
      Element e; if (!d.TryGetValue(0x00080005, out e) || e.Value == null) return;
      Encoding inherited = d.Text;
      d.Text = TextOf(e, inherited); d.Guess = d.Text.CodePage == 28591;
    }
    static Encoding TextOf(Element e, Encoding inherited) {
      string[] parts = Encoding.ASCII.GetString(e.Value).Split('\\'); string cs = parts[parts.Length - 1].Trim().Replace("ISO 2022 ", "ISO_");
      int page = cs == "ISO_IR 192" ? 65001 : cs == "ISO_IR 100" || cs == "" ? 28591 : cs == "ISO_IR 101" ? 28592 : cs == "ISO_IR 109" ? 28593
        : cs == "ISO_IR 110" ? 28594 : cs == "ISO_IR 144" ? 28595 : cs == "ISO_IR 127" ? 28596 : cs == "ISO_IR 126" ? 28597 : cs == "ISO_IR 138" ? 28598
        : cs == "ISO_IR 148" ? 28599 : cs == "ISO_IR 149" ? 949 : cs == "GB18030" ? 54936 : cs == "GBK" ? 936 : cs == "ISO_IR 13" || cs == "ISO_IR 87" ? 932 : 0;
      if (page == 0) return inherited;
      try { return Encoding.GetEncoding(page); } catch (Exception) { return inherited; }
    }

    // One data set. Values of up to `keep` bytes are kept, larger ones only by their place.
    // Reading stops before `stopAt` (the pixels, for a header-only read; 0 = read everything).
    // `headerGroup`: only the elements of group 0002 - the file's own header.
    public static DataSet Read(Stream s, long end, bool explicitVR, int keep, uint stopAt, Encoding text) { return Read(s, end, explicitVR, keep, stopAt, text, false); }
    static DataSet Read(Stream s, long end, bool explicitVR, int keep, uint stopAt, Encoding text, bool headerGroup) { return Read(s, end, explicitVR, keep, stopAt, text, headerGroup, true); }
    static DataSet Read(Stream s, long end, bool explicitVR, int keep, uint stopAt, Encoding text, bool headerGroup, bool guess) {
      DataSet d = new DataSet(); d.Text = text; d.Guess = guess; byte[] b = new byte[8];
      while (s.Position + 8 <= end) {
        Fill(s, b, 4); uint tag = Tag(b);
        if (tag == 0xFFFEE00D || tag == 0xFFFEE0DD) { Fill(s, b, 4); break; }          // the end of an item / of a sequence
        if ((stopAt != 0 && tag >= stopAt) || (headerGroup && (tag >> 16) != 0x0002)) { s.Position -= 4; break; }
        bool exp = explicitVR || (tag >> 16) == 0x0002;
        string vr = "UN"; long len;
        if (exp) {
          Fill(s, b, 2); vr = Encoding.ASCII.GetString(b, 0, 2);
          if (LongVR.Contains(vr)) { Fill(s, b, 2); Fill(s, b, 4); len = BitConverter.ToUInt32(b, 0); } else { Fill(s, b, 2); len = BitConverter.ToUInt16(b, 0); }
        } else { Fill(s, b, 4); len = BitConverter.ToUInt32(b, 0); if (len == 0xFFFFFFFF && tag != PixelData) vr = "SQ"; }
        Element e = new Element { Tag = tag, VR = vr, Offset = s.Position, Length = len };
        if (tag == PixelData && len == 0xFFFFFFFF) {
          e.Fragments = new List<long[]>();
          while (s.Position + 8 <= end) {
            Fill(s, b, 8); if (Tag(b) != 0xFFFEE000) break;
            long l = BitConverter.ToUInt32(b, 4); e.Fragments.Add(new long[] { s.Position, l }); s.Position += l;
          }
        } else if (vr == "SQ" || len == 0xFFFFFFFF) {
          // A sequence. One written with the VR "unknown" and no length (a private sequence a
          // device passed on) has its items in implicit VR, whatever the file's own.
          bool itemsExplicit = explicitVR && vr == "SQ";
          e.Items = new List<DataSet>();
          long seqEnd = len == 0xFFFFFFFF ? end : s.Position + len;
          while (s.Position + 8 <= seqEnd) {
            long at = s.Position; Fill(s, b, 8); uint it = Tag(b); long l = BitConverter.ToUInt32(b, 4);
            if (it != 0xFFFEE000) break;                                                // the sequence's own end mark
            long itemEnd = l == 0xFFFFFFFF ? seqEnd : s.Position + l;
            DataSet item = Read(s, itemEnd, itemsExplicit, keep, 0, d.Text, false, d.Guess); item.At = at; e.Items.Add(item);
            if (l != 0xFFFFFFFF) s.Position = itemEnd;
          }
          if (len != 0xFFFFFFFF) s.Position = seqEnd;
        } else if (len <= keep) { e.Value = new byte[len]; Fill(s, e.Value, (int)len); }
        else s.Position += len;
        d[tag] = e;
        if (tag == 0x00080005) SetText(d);
      }
      return d;
    }

    // A DICOM file: its header group and its data set in one. `transferSyntax` says how
    // the pixels are stored. Throws InvalidDataException when it is not a file we read.
    public static DataSet Open(Stream s, bool headerOnly, out string transferSyntax) {
      byte[] m = new byte[4];
      if (s.Length < 140) throw new InvalidDataException("not DICOM");
      s.Position = 128; Fill(s, m, 4);
      if (Encoding.ASCII.GetString(m) != "DICM") throw new InvalidDataException("not DICOM");
      Encoding latin = Encoding.GetEncoding(28591);
      // The header group: read while the tags are of group 0002 - the length it states is
      // not trusted (files are met where it is wrong).
      DataSet meta = Read(s, s.Length, true, 256, 0, latin, true);
      transferSyntax = meta.Str(0x00020010);
      if (transferSyntax == "") throw new InvalidDataException("no transfer syntax");
      if (transferSyntax == "1.2.840.10008.1.2.2" || transferSyntax == "1.2.840.10008.1.2.1.99") throw new InvalidDataException("unsupported transfer syntax");
      // (values are kept up to the size of the largest table of colours a picture may carry)
      DataSet d = Read(s, s.Length, transferSyntax != "1.2.840.10008.1.2", 131072, headerOnly ? PixelData : 0, latin);
      foreach (KeyValuePair<uint, Element> kv in meta) d[kv.Key] = kv.Value;
      return d;
    }
  }
}
