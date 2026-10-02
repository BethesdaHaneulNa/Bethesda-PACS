# Bethesda CD - tests: made-up DICOM files. Dot-sourced by import_test.ps1 and
# import_real_test.ps1; it only defines [FakeDicom]::Write, which writes one small image
# (secondary capture, explicit VR little endian, Latin-1 words) of a patient who does not exist.
Add-Type -TypeDefinition @'
using System; using System.IO; using System.Text;
public static class FakeDicom {
  static void El(MemoryStream m, int g, int e, string vr, byte[] val) {
    if (val.Length % 2 == 1) { Array.Resize(ref val, val.Length + 1); val[val.Length - 1] = (byte)(vr == "UI" ? 0 : 32); }
    m.Write(BitConverter.GetBytes((ushort)g), 0, 2); m.Write(BitConverter.GetBytes((ushort)e), 0, 2); m.Write(Encoding.ASCII.GetBytes(vr), 0, 2);
    if (vr == "OB" || vr == "OW") { m.Write(new byte[2], 0, 2); m.Write(BitConverter.GetBytes((uint)val.Length), 0, 4); }
    else m.Write(BitConverter.GetBytes((ushort)val.Length), 0, 2);
    m.Write(val, 0, val.Length);
  }
  static void S(MemoryStream m, int g, int e, string vr, string text) { El(m, g, e, vr, Encoding.GetEncoding(28591).GetBytes(text)); }
  static void U(MemoryStream m, int g, int e, int n) { El(m, g, e, "US", BitConverter.GetBytes((ushort)n)); }
  // For names in other alphabets: the bytes of the patient's name as a device would write them
  // (null = the name given, in Western European bytes), and what the file says its character set is
  // (null = "ISO_IR 100"; "" = the file says nothing).
  public static byte[] NameBytes; public static string Charset;
  // One image: 8 x 8 pixels (or more, to make a file of a given size), explicit VR little endian, Latin-1 words.
  public static void Write(string path, string study, string series, string sop, string patientId, string patientName, string birth, string sex,
      string institution, string date, string description, string modality, string accession, int pixelBytes) {
    MemoryStream meta = new MemoryStream(), ds = new MemoryStream();
    El(meta, 2, 1, "OB", new byte[] { 0, 1 }); S(meta, 2, 2, "UI", "1.2.840.10008.5.1.4.1.1.7"); S(meta, 2, 3, "UI", sop); S(meta, 2, 0x10, "UI", "1.2.840.10008.1.2.1"); S(meta, 2, 0x12, "UI", "1.2.826.0.1.3680043.8.498.1");
    if (Charset == null) S(ds, 8, 5, "CS", "ISO_IR 100"); else if (Charset != "") S(ds, 8, 5, "CS", Charset);
    S(ds, 8, 0x16, "UI", "1.2.840.10008.5.1.4.1.1.7"); S(ds, 8, 0x18, "UI", sop);
    S(ds, 8, 0x20, "DA", date); S(ds, 8, 0x50, "SH", accession); S(ds, 8, 0x60, "CS", modality); S(ds, 8, 0x80, "LO", institution); S(ds, 8, 0x1030, "LO", description);
    if (NameBytes != null) El(ds, 0x10, 0x10, "PN", (byte[])NameBytes.Clone()); else S(ds, 0x10, 0x10, "PN", patientName); S(ds, 0x10, 0x20, "LO", patientId); S(ds, 0x10, 0x30, "DA", birth); S(ds, 0x10, 0x40, "CS", sex);
    S(ds, 0x20, 0xD, "UI", study); S(ds, 0x20, 0xE, "UI", series); S(ds, 0x20, 0x11, "IS", "1"); S(ds, 0x20, 0x13, "IS", "1");
    int side = (int)Math.Ceiling(Math.Sqrt(Math.Max(64, pixelBytes))); if (side % 2 == 1) side++;
    U(ds, 0x28, 2, 1); S(ds, 0x28, 4, "CS", "MONOCHROME2"); U(ds, 0x28, 0x10, side); U(ds, 0x28, 0x11, side); U(ds, 0x28, 0x100, 8); U(ds, 0x28, 0x101, 8); U(ds, 0x28, 0x102, 7); U(ds, 0x28, 0x103, 0);
    byte[] px = new byte[side * side]; new Random(sop.GetHashCode()).NextBytes(px); El(ds, 0x7FE0, 0x10, "OW", px);
    Directory.CreateDirectory(Path.GetDirectoryName(path));
    using (FileStream f = File.Create(path)) {
      f.Write(new byte[128], 0, 128); f.Write(Encoding.ASCII.GetBytes("DICM"), 0, 4);
      f.Write(new byte[] { 2, 0, 0, 0, (byte)'U', (byte)'L', 4, 0 }, 0, 8); f.Write(BitConverter.GetBytes((uint)meta.Length), 0, 4); meta.WriteTo(f); ds.WriteTo(f);
    }
  }
}
'@
