// VOIR.EXE - what is on the disc: the patient, the exams, their series and images, as
// the DICOMDIR at the top of the disc lists them. That one small file gives the whole
// list; then the header of one image of each series is read, for its words - the
// DICOMDIR the image server writes loses the accents ("Vsicule" for "Vésicule").
// A folder without a DICOMDIR is listed by opening the files in it.
using System;
using System.Collections.Generic;
using System.IO;

namespace Bethesda.Viewer {
  public class ImageRef { public string File, TransferSyntax = "", SopClass = ""; public int Number; }
  public class Series {
    public string Modality = "", Description = "", Uid = ""; public int Number; public List<ImageRef> Images = new List<ImageRef>();
    public bool NamedByImage;                          // its description was checked against an image of its own
    public string Label { get { return ("S" + Number + "  " + (Description != "" ? Description : Modality)).Trim() + "  (" + Images.Count + ")"; } }
  }
  public class Study {
    public string Date = "", Description = "", Accession = "", Uid = ""; public List<Series> Series = new List<Series>();
    public string Label { get { return (Date + "  " + Description).Trim(); } }
  }

  public class Disc {
    public string Folder, PatientName = "", PatientId = ""; public List<Study> Studies = new List<Study>();
    public int ImageCount { get { int n = 0; foreach (Study st in Studies) foreach (Series se in st.Series) n += se.Images.Count; return n; } }

    public static Disc Open(string folder) {
      Disc disc = new Disc(); disc.Folder = folder;
      string dir = Path.Combine(folder, "DICOMDIR");
      if (System.IO.File.Exists(dir)) { try { disc.ReadDicomdir(dir); } catch (Exception) { disc.Studies.Clear(); } }
      if (disc.ImageCount == 0) disc.Scan(folder); else disc.NameByImages();
      disc.Sort();
      return disc;
    }

    // The directory records are linked by their places in the file: each names the next
    // one of its level and the first one of the level below.
    void ReadDicomdir(string path) {
      DataSet d;
      using (FileStream s = System.IO.File.OpenRead(path)) { string ts; d = DicomReader.Open(s, false, out ts); }
      Element seq; if (!d.TryGetValue(0x00041220, out seq) || seq.Items == null) return;
      Dictionary<long, DataSet> at = new Dictionary<long, DataSet>();
      foreach (DataSet r in seq.Items) at[r.At] = r;
      long first = d.Int(0x00041200, 0);
      if (!at.ContainsKey(first)) { ReadInOrder(seq.Items); return; }
      for (DataSet p = Get(at, first); p != null; p = Get(at, p.Int(0x00041400, 0))) {
        if (p.Str(0x00041430) != "PATIENT") continue;
        if (PatientName == "") { PatientName = p.Name(0x00100010); PatientId = p.Str(0x00100020); }
        for (DataSet st = Get(at, p.Int(0x00041420, 0)); st != null; st = Get(at, st.Int(0x00041400, 0))) {
          if (st.Str(0x00041430) != "STUDY") continue;
          Study study = NewStudy(st); Studies.Add(study);
          for (DataSet se = Get(at, st.Int(0x00041420, 0)); se != null; se = Get(at, se.Int(0x00041400, 0))) {
            if (se.Str(0x00041430) != "SERIES") continue;
            Series series = NewSeries(se); study.Series.Add(series);
            for (DataSet im = Get(at, se.Int(0x00041420, 0)); im != null; im = Get(at, im.Int(0x00041400, 0))) AddImage(series, im);
          }
        }
      }
    }
    static DataSet Get(Dictionary<long, DataSet> at, long offset) { DataSet r; return offset > 0 && at.TryGetValue(offset, out r) ? r : null; }

    // The same list from the order of the records alone (a DICOMDIR whose links cannot be followed).
    void ReadInOrder(List<DataSet> records) {
      Study study = null; Series series = null;
      foreach (DataSet r in records) {
        string type = r.Str(0x00041430);
        if (type == "PATIENT") { if (PatientName == "") { PatientName = r.Name(0x00100010); PatientId = r.Str(0x00100020); } }
        else if (type == "STUDY") { study = NewStudy(r); Studies.Add(study); series = null; }
        else if (type == "SERIES" && study != null) { series = NewSeries(r); study.Series.Add(series); }
        else if (series != null) AddImage(series, r);
      }
    }
    static Study NewStudy(DataSet r) { return new Study { Date = r.Date(0x00080020), Description = r.Str(0x00081030), Accession = r.Str(0x00080050), Uid = r.Str(0x0020000D) }; }
    static Series NewSeries(DataSet r) { return new Series { Modality = r.Str(0x00080060), Description = r.Str(0x0008103E), Uid = r.Str(0x0020000E), Number = r.Int(0x00200011, 0) }; }
    void AddImage(Series series, DataSet r) {
      string id = r.Str(0x00041500); if (id == "") return;                     // a record that names no file
      string file = Path.Combine(Folder, id.Replace('\\', Path.DirectorySeparatorChar));
      series.Images.Add(new ImageRef { File = file, Number = r.Int(0x00200013, 0), TransferSyntax = r.Str(0x00041512), SopClass = r.Str(0x00041510) });
    }

    // The names as the images themselves give them: the first image of every series.
    void NameByImages() {
      bool patient = false;
      foreach (Study st in Studies) {
        bool named = false;
        foreach (Series se in st.Series) {
          if (se.Images.Count == 0) continue;
          DataSet d; string ts;
          try { using (FileStream s = System.IO.File.OpenRead(se.Images[0].File)) d = DicomReader.Open(s, true, out ts); } catch (Exception) { continue; }
          se.NamedByImage = true;
          string t = d.Str(0x0008103E); if (t != "") se.Description = t;
          if (!named) { t = d.Str(0x00081030); if (t != "") st.Description = t; named = true; }
          if (!patient) { t = d.Name(0x00100010); if (t != "") PatientName = t; patient = true; }
        }
      }
    }

    // No DICOMDIR: every DICOM file under the folder, by what its own header says.
    void Scan(string folder) {
      Dictionary<string, Study> studies = new Dictionary<string, Study>(); Dictionary<string, Series> seriesBy = new Dictionary<string, Series>();
      string[] files;
      try { files = Directory.GetFiles(folder, "*", SearchOption.AllDirectories); } catch (Exception) { return; }
      int seen = 0;
      foreach (string f in files) {
        if (++seen > 5000) break;
        string name = Path.GetFileName(f).ToUpperInvariant();
        if (name == "DICOMDIR" || name.EndsWith(".EXE") || name.EndsWith(".TXT") || name.EndsWith(".BAT")) continue;
        DataSet d; string ts;
        try { using (FileStream s = System.IO.File.OpenRead(f)) d = DicomReader.Open(s, true, out ts); } catch (Exception) { continue; }
        if (PatientName == "") { PatientName = d.Name(0x00100010); PatientId = d.Str(0x00100020); }
        string su = d.Str(0x0020000D), eu = su + "|" + d.Str(0x0020000E);
        Study study; if (!studies.TryGetValue(su, out study)) { study = NewStudy(d); studies[su] = study; Studies.Add(study); }
        Series series; if (!seriesBy.TryGetValue(eu, out series)) { series = NewSeries(d); seriesBy[eu] = series; study.Series.Add(series); }
        series.Images.Add(new ImageRef { File = f, Number = d.Int(0x00200013, 0), TransferSyntax = ts, SopClass = d.Str(0x00080016) }); series.NamedByImage = true;
      }
    }

    // The most recent exam first; series and images in the order of the device.
    void Sort() {
      Studies.Sort(delegate(Study a, Study b) { int c = string.CompareOrdinal(b.Date, a.Date); return c != 0 ? c : string.CompareOrdinal(a.Description, b.Description); });
      foreach (Study st in Studies) {
        st.Series.Sort(delegate(Series a, Series b) { int c = a.Number.CompareTo(b.Number); return c != 0 ? c : string.CompareOrdinal(a.Uid, b.Uid); });
        foreach (Series se in st.Series) se.Images.Sort(delegate(ImageRef a, ImageRef b) { int c = a.Number.CompareTo(b.Number); return c != 0 ? c : string.CompareOrdinal(a.File, b.File); });
      }
    }
  }
}
