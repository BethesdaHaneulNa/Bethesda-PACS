// Bethesda CD - reading a disc (or a folder of a USB stick) that another hospital made, to
// bring its images into the EMR: which exams are on it, whose they say they are, how many
// files and how large.
//
// Only DICOM files are looked at. With a DICOMDIR on the disc, the files it lists are the
// only ones touched. Without one, the folder is walked - and a file that is a program, a
// library or a document by its name (the other maker's viewer, its DLLs, AUTORUN.INF…) is
// not opened at all; the others are opened for their header only, and counted as "not an
// image" when they do not carry the DICM mark. Nothing on the disc is ever run.
//
// The reading itself is the viewer's (src\viewer\Dicom.cs, Disc.cs), compiled into this
// program too.
using System;
using System.Collections.Generic;
using System.IO;
using Bethesda.Viewer;

namespace Bethesda.Cd {
  public class ImportFile { public string Path = ""; public long Bytes; public bool Seen; }      // Seen: its own header was read and is of this exam

  // One exam of the disc, as the disc's files describe it.
  public class ImportStudy {
    public string Uid = "", Date = "", Description = "", Modality = "", Accession = "", Institution = "";
    public string PatientId = "", PatientName = "", BirthDate = "", Sex = "";                   // PatientName: as written (FAMILY^Given)
    public List<ImportFile> Files = new List<ImportFile>();
    // What the EMR said of it (the check), or what this program found: "" = can be brought in.
    public string State = "", ImportedAt = "";
    public long Bytes { get { long n = 0; foreach (ImportFile f in Files) n += f.Bytes; return n; } }
    public long LargestFile { get { long n = 0; foreach (ImportFile f in Files) if (f.Bytes > n) n = f.Bytes; return n; } }
    public string DateShown { get { return Date.Length == 8 ? Date.Substring(0, 4) + "-" + Date.Substring(4, 2) + "-" + Date.Substring(6, 2) : Date; } }
    public string PatientShown { get { return ImportDisc.NameShown(PatientName); } }
    public string PatientKey { get { return PatientId + "\n" + PatientName; } }
  }

  public class ImportSource {
    public string Folder = ""; public List<ImportStudy> Studies = new List<ImportStudy>();
    public bool FromDicomdir, Stopped;
    public int NotImages;                                  // files opened that are not DICOM images
    public int FileCount { get { int n = 0; foreach (ImportStudy s in Studies) n += s.Files.Count; return n; } }
  }

  public static class ImportDisc {
    public const int MaxFiles = 100000;                    // what the EMR takes for one exam; a walk stops there
    const string DirectoryClass = "1.2.840.10008.1.3.10";  // a DICOMDIR is a DICOM file too - never an image
    // Not opened when the folder is walked: programs, libraries, scripts, documents, pictures.
    static readonly HashSet<string> NotOpened = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
      ".exe", ".dll", ".com", ".bat", ".cmd", ".msi", ".scr", ".sys", ".ocx", ".cpl", ".lnk", ".url", ".vbs", ".js", ".ps1", ".jar", ".class", ".app", ".dmg", ".pkg", ".so", ".dylib",
      ".inf", ".ini", ".cfg", ".config", ".manifest", ".xml", ".json", ".txt", ".htm", ".html", ".css", ".pdf", ".rtf", ".doc", ".docx", ".chm", ".hlp", ".log",
      ".jpg", ".jpeg", ".png", ".bmp", ".gif", ".ico", ".tif", ".tiff", ".zip", ".7z", ".rar", ".cab", ".iso", ".db", ".dat_old" };

    // "RAKOTO^Jean^^^" -> "RAKOTO Jean"; a name in two writings -> "Hong Gildong (홍 길동)".
    public static string NameShown(string raw) { return DicomText.PersonName(raw); }

    // The header of one file: null when it is not a DICOM image (no DICM mark, a DICOMDIR, cut short…).
    static DataSet Header(string file) {
      try {
        using (FileStream s = File.OpenRead(file)) {
          string ts; DataSet d = DicomReader.Open(s, true, out ts);
          if (d.Str(0x00020002) == DirectoryClass || d.Str(0x0020000D) == "") return null;
          return d;
        }
      } catch (Exception) { return null; }
    }
    static void Describe(ImportStudy st, DataSet d) {
      st.Uid = d.Str(0x0020000D); st.Date = d.Str(0x00080020); st.Description = d.Str(0x00081030); st.Accession = d.Str(0x00080050);
      st.Institution = d.Str(0x00080080); st.PatientId = d.Str(0x00100020); st.PatientName = d.Str(0x00100010);
      st.BirthDate = d.Str(0x00100030); st.Sex = d.Str(0x00100040);
    }
    static void AddModality(ImportStudy st, string m) {
      if (m == "") return;
      foreach (string have in st.Modality.Split('/')) if (have == m) return;
      st.Modality = st.Modality == "" ? m : st.Modality + "/" + m;
    }
    static long Size(string file) { try { return new FileInfo(file).Length; } catch (Exception) { return -1; } }

    // What is on the disc. `onFile(done, of)` is told as it goes (of = 0: not known yet) and
    // answers false to stop.
    public static ImportSource Read(string folder, Func<int, int, bool> onFile) {
      ImportSource src = new ImportSource { Folder = folder };
      Disc listed = null;
      try { listed = Disc.ListOnly(folder); } catch (Exception) { listed = null; }
      if (listed != null) ReadListed(src, listed, onFile); else Walk(src, folder, onFile);
      src.Studies.RemoveAll(delegate(ImportStudy s) { return s.Files.Count == 0 || s.Uid == ""; });
      src.Studies.Sort(delegate(ImportStudy a, ImportStudy b) { int c = string.CompareOrdinal(b.Date, a.Date); return c != 0 ? c : string.CompareOrdinal(a.Description, b.Description); });
      return src;
    }

    // With a DICOMDIR: its list of exams, series and files; one file of each series is opened
    // for what the DICOMDIR does not say (the hospital, the birth date) and to see that the
    // list tells the truth. The other files are opened when the exam is brought in (Verify).
    static void ReadListed(ImportSource src, Disc listed, Func<int, int, bool> onFile) {
      src.FromDicomdir = true;
      int series = 0, done = 0; foreach (Study s in listed.Studies) series += s.Series.Count;
      foreach (Study s in listed.Studies) {
        ImportStudy st = new ImportStudy(); bool described = false;
        foreach (Series se in s.Series) {
          if (onFile != null && !onFile(++done, series)) { src.Stopped = true; return; }
          bool opened = false;
          foreach (ImageRef im in se.Images) {
            long size = Size(im.File); if (size < 0) continue;                       // listed, but not on the disc
            ImportFile f = new ImportFile { Path = im.File, Bytes = size };
            if (!opened) {
              DataSet d = Header(im.File);
              if (d == null) { src.NotImages++; continue; }
              opened = true;
              if (!described) { Describe(st, d); described = true; }
              if (d.Str(0x0020000D) != st.Uid || d.Str(0x00100020) != st.PatientId) continue;     // not of this exam after all: left to Verify of its own exam - not counted here
              AddModality(st, d.Str(0x00080060)); f.Seen = true;
            }
            AddModality(st, se.Modality);
            if (st.Files.Count < MaxFiles) st.Files.Add(f);
          }
        }
        if (described) src.Studies.Add(st);
      }
    }

    // Without a DICOMDIR: every file under the folder that may be an image is opened for its header.
    static void Walk(ImportSource src, string folder, Func<int, int, bool> onFile) {
      Dictionary<string, ImportStudy> by = new Dictionary<string, ImportStudy>();
      List<string> files = new List<string>();
      try { foreach (string f in Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories)) { files.Add(f); if (files.Count >= MaxFiles) break; } } catch (Exception) { }
      int done = 0;
      foreach (string f in files) {
        if (onFile != null && !onFile(++done, files.Count)) { src.Stopped = true; return; }
        string name = Path.GetFileName(f);
        if (string.Equals(name, "DICOMDIR", StringComparison.OrdinalIgnoreCase) || NotOpened.Contains(Path.GetExtension(name))) continue;
        long size = Size(f); if (size < 140) continue;
        DataSet d = Header(f);
        if (d == null) { src.NotImages++; continue; }
        string key = d.Str(0x0020000D) + "\n" + d.Str(0x00100020);
        ImportStudy st;
        if (!by.TryGetValue(key, out st)) { st = new ImportStudy(); Describe(st, d); by[key] = st; src.Studies.Add(st); }
        AddModality(st, d.Str(0x00080060));
        st.Files.Add(new ImportFile { Path = f, Bytes = size, Seen = true });
      }
    }

    // Before an exam is brought in: every file of it that was only listed is opened for its
    // header. A file that is not a DICOM image of this exam and this patient is taken off the
    // list (the EMR would refuse it, and the count it is told must be the count it gets).
    // Returns how many were taken off; -1 when stopped.
    public static int Verify(ImportStudy st, Func<int, int, bool> onFile) {
      int off = 0, done = 0;
      for (int i = st.Files.Count - 1; i >= 0; i--) {
        ImportFile f = st.Files[i];
        if (onFile != null && !onFile(++done, st.Files.Count + off)) return -1;
        if (f.Seen) continue;
        DataSet d = Header(f.Path);
        if (d == null || d.Str(0x0020000D) != st.Uid || d.Str(0x00100020) != st.PatientId) { st.Files.RemoveAt(i); off++; continue; }
        AddModality(st, d.Str(0x00080060)); f.Seen = true;
      }
      return off;
    }

    // What the EMR is told of the exam's origin: the words of the disc as they are, cut to the lengths it takes.
    static string Cut(string s, int max) { s = (s ?? "").Trim(); return s.Length > max ? s.Substring(0, max) : s; }
    public static Dictionary<string, object> Origin(ImportStudy st) {
      return new Dictionary<string, object> {
        { "study_uid", st.Uid }, { "patient_id", Cut(st.PatientId, 64) }, { "patient_name", Cut(st.PatientName, 200) },
        { "birth_date", Cut(st.BirthDate, 10) }, { "sex", Cut(st.Sex, 4) }, { "accession", Cut(st.Accession, 64) },
        { "institution", Cut(st.Institution, 200) }, { "study_date", Cut(st.Date, 10) }, { "description", Cut(st.Description, 200) },
        { "modality", Cut(st.Modality, 16) } };
    }

    // Do the disc and the chart say the same day of birth / the same sex? "differs" only when
    // both say something and it is not the same; a side that says nothing decides nothing.
    public static bool BirthDiffers(string discDate, string chartDate) {
      string a = Digits(discDate), b = Digits(chartDate);
      return a.Length == 8 && b.Length == 8 && a != b;
    }
    public static bool SexDiffers(string discSex, string chartGender) {
      string a = (discSex ?? "").Trim().ToUpperInvariant(), b = (chartGender ?? "").Trim().ToUpperInvariant();
      return (a == "M" || a == "F") && (b == "M" || b == "F") && a != b;
    }
    static string Digits(string s) { System.Text.StringBuilder b = new System.Text.StringBuilder(); foreach (char c in s ?? "") if (c >= '0' && c <= '9') b.Append(c); return b.ToString(); }
  }
}
