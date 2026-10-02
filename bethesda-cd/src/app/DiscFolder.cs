// Bethesda CD - what goes on a disc, made in a working folder of this PC:
//   DICOMDIR      the standard index, made by the image server
//   IMAGES\IM0…   the original DICOM files, as the image server holds them
//   README.TXT    written here: whose images, which exams, how to read the disc
//   VIEWER.EXE    the small viewer this program carries inside itself
//   AUTORUN.INF   written here, when the viewer is on the disc: Windows offers to start it
// ... and the same content saved to a folder (a USB stick), read back and compared.
// No window and no question here, so that every step can be run and checked on its own.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace Bethesda.Cd {
  public class DiscFile { public string Path; public long Bytes; public string Sha256; }

  // How a step ended: Ok, or the reason (Code) and what goes with it.
  public class StepResult {
    public bool Ok; public string Code = "", Error = "", Path = "";
    public int Files, Items; public long Bytes, Need, Free; public bool Unpacked; public List<string> Bad = new List<string>();
    public string OrderItemId = "";
  }

  public static class DiscFolder {
    public const int Sector = 2048;
    public const int FileSystems = 3;                      // a disc image's file systems: ISO 9660 + Joliet - what imaging stations read
    public static readonly string TempRoot = Path.Combine(Path.GetTempPath(), "BethesdaCD");

    // ── sizes and names ──────────────────────────────────────────────────────
    public static string FormatSize(long bytes, string unit) {
      CultureInfo c = unit == "Mo" ? CultureInfo.GetCultureInfo("fr-FR") : CultureInfo.InvariantCulture;
      if (bytes >= 1073741824) return (bytes / 1073741824.0).ToString("0.00", c) + " " + "G" + unit.Substring(1);
      if (bytes >= 10485760) return Math.Round(bytes / 1048576.0).ToString("0", c) + " " + unit;
      if (bytes < 104858) return Math.Ceiling(bytes / 1024.0).ToString("0", c) + " " + "K" + unit.Substring(1);
      return (bytes / 1048576.0).ToString("0.0", c) + " " + unit;
    }
    // Letters that are safe in a folder name and in a disc label.
    public static string SafeName(string text, int max) {
      string s = Regex.Replace(text ?? "", "[^A-Za-z0-9_-]", "_").Trim('_');
      if (s.Length > max) s = s.Substring(0, max);
      return s == "" ? "X" : s;
    }
    public static string DiscLabel(string chartNo) { return ("IMG_" + SafeName(chartNo, 11).Replace('-', '_')).ToUpperInvariant(); }
    // Room the files take on a disc, a little over: each file rounded up to a sector, plus
    // the disc's own tables. The exact figure is the image's, once it is built.
    public static long Estimate(long bytes, int files) { return bytes + (long)(files + 40) * Sector + 2097152; }

    // ── the working folder on this PC ────────────────────────────────────────
    // Everything fetched is under %TEMP%\BethesdaCD and is removed when the copy is done,
    // failed or cancelled - and whatever an earlier run left behind is removed at start.
    public static string NewTemp() {
      string d = Path.Combine(TempRoot, Guid.NewGuid().ToString("N"));
      Directory.CreateDirectory(Path.Combine(d, "disc"));
      return d;
    }
    public static bool RemoveTemp(string dir) {
      string target = string.IsNullOrEmpty(dir) ? TempRoot : dir;
      if (target.StartsWith(TempRoot, StringComparison.OrdinalIgnoreCase)) {
        // a file still held for a moment (the disc image just let go of it): tried again
        for (int i = 0; i < 10 && Directory.Exists(target); i++) { try { Directory.Delete(target, true); } catch (Exception) { Thread.Sleep(300); } }
      }
      return !Directory.Exists(target);
    }

    // ── the bundle ───────────────────────────────────────────────────────────
    // Fetch the exams as the image server's ZIP and unpack it into <work>\disc.
    // Only DICOMDIR and IMAGES\<short name> are accepted from the ZIP - anything else, or a
    // count that differs from what the EMR announced, and nothing is kept.
    public static StepResult Bundle(EmrClient emr, IList<string> orderItemIds, string medium, string work, Action<long> onBytes) {
      string zip = Path.Combine(work, "bundle.zip");
      EmrAnswer r = emr.Call("GET", "/api/pacs/export/bundle?order_item_ids=" + string.Join(",", orderItemIds) + "&medium=" + medium, null, zip, onBytes, 120);
      if (!r.Ok) return new StepResult { Code = r.Code, Error = r.Error, OrderItemId = J.Str(r.Data, "order_item_id") };
      string disc = Path.Combine(work, "disc"); int count = 0; long bytes = 0; bool hasDir = false;
      try {
        using (ZipArchive z = ZipFile.OpenRead(zip)) {
          foreach (ZipArchiveEntry e in z.Entries) {
            string name = e.FullName.Replace('\\', '/'), dest; Match m;
            if (name == "DICOMDIR") { hasDir = true; dest = Path.Combine(disc, "DICOMDIR"); }
            else if ((m = Regex.Match(name, "^IMAGES/([A-Za-z0-9_]{1,16})$")).Success) { dest = Path.Combine(Path.Combine(disc, "IMAGES"), m.Groups[1].Value); count++; }
            else if (name == "IMAGES/") continue;
            else return new StepResult { Code = "BAD_BUNDLE", Error = name };
            Directory.CreateDirectory(Path.GetDirectoryName(dest));
            e.ExtractToFile(dest, true); bytes += e.Length;
          }
        }
      } catch (Exception e) { return new StepResult { Code = "BAD_BUNDLE", Error = e.Message }; }
      finally { try { File.Delete(zip); } catch (Exception) { } }
      int announced; int.TryParse(r.Header("X-Export-Items"), out announced);
      if (!hasDir || count == 0 || (announced > 0 && announced != count)) return new StepResult { Code = "BAD_BUNDLE", Error = count + " / " + announced };
      // (Unpacked: the image server was asked to decompress the images - see the EMR's /export/bundle)
      return new StepResult { Ok = true, Path = disc, Items = count, Bytes = bytes, Unpacked = r.Header("X-Export-Unpacked") == "1" };
    }

    // ── README.TXT ───────────────────────────────────────────────────────────
    // French first, then English: what the disc holds and how to read it. Saved as UTF-8
    // with its mark at the start, so that Windows Notepad shows the accents.
    public static void WriteReadme(string dir, Dictionary<string, object> patient, Dictionary<string, object> clinic, IList<Dictionary<string, object>> exams, bool withViewer, DateTime when) {
      string name = (J.Str(patient, "last_name") + " " + J.Str(patient, "first_name")).Trim();
      string fr = J.Str(clinic, "name_fr"); if (fr == "") fr = J.Str(clinic, "name");
      string en = J.Str(clinic, "name_en"); if (en == "") en = J.Str(clinic, "name");
      List<string> c = new List<string>(); if (J.Str(clinic, "address") != "") c.Add(J.Str(clinic, "address")); if (J.Str(clinic, "phone") != "") c.Add("Tel. " + J.Str(clinic, "phone"));
      string contact = string.Join(" - ", c), day = when.ToString("yyyy-MM-dd");
      List<string> rows = new List<string>();
      foreach (Dictionary<string, object> e in exams) rows.Add(string.Format("    {0}  {1,-3} {2} ({3})", J.Str(e, "exam_date"), J.Str(e, "modality"), J.Str(e, "order_name"), J.Str(e, "items")));
      List<string> L = new List<string>();
      L.Add((fr.ToUpper() + " - IMAGES MÉDICALES (DICOM)").Trim(' ', '-'));
      if (contact != "") L.Add(contact);
      L.Add("");
      L.Add("Patient    : " + name);
      L.Add("N° dossier : " + J.Str(patient, "chart_no"));
      L.Add("Examens (date, type, examen, nombre d'images) :");
      L.AddRange(rows);
      L.Add("Disque créé le " + day);
      L.Add("");
      L.Add("Ce disque contient des images médicales au format DICOM :");
      L.Add("  DICOMDIR  la liste des images (fichier standard)");
      L.Add("  IMAGES    les images d'origine");
      L.Add("Pour les voir : ouvrez ce disque avec votre logiciel d'imagerie (PACS ou");
      L.Add("visionneuse DICOM), fonction « importer un CD / ouvrir un DICOMDIR ».");
      if (withViewer) {
        L.Add("Sans logiciel d'imagerie : double-cliquez sur VIEWER.EXE (Windows). C'est");
        L.Add("une visionneuse de consultation, non destinée au diagnostic ; elle ne");
        L.Add("s'installe pas et ne laisse rien sur l'ordinateur.");
      }
      L.Add("Ce disque contient des données médicales personnelles : remettez-le au patient");
      L.Add("ou au médecin destinataire uniquement.");
      L.Add("");
      L.Add("------------------------------------------------------------------------");
      L.Add("");
      L.Add((en.ToUpper() + " - MEDICAL IMAGES (DICOM)").Trim(' ', '-'));
      L.Add("");
      L.Add("Patient  : " + name);
      L.Add("Chart no.: " + J.Str(patient, "chart_no"));
      L.Add("Exams (date, type, exam, number of images):");
      L.AddRange(rows);
      L.Add("Disc made on " + day);
      L.Add("");
      L.Add("This disc holds medical images in DICOM format:");
      L.Add("  DICOMDIR  the index of the images (standard file)");
      L.Add("  IMAGES    the original images");
      L.Add("To see them: open this disc with your imaging software (PACS or DICOM");
      L.Add("viewer), \"import a CD / open a DICOMDIR\".");
      if (withViewer) {
        L.Add("Without imaging software: double-click VIEWER.EXE (Windows). It is a");
        L.Add("viewer for reference, not for diagnosis; it installs nothing and leaves");
        L.Add("nothing on the computer.");
      }
      L.Add("This disc holds personal medical data: hand it to the patient or to the");
      L.Add("receiving doctor only.");
      File.WriteAllText(Path.Combine(dir, "README.TXT"), string.Join("\r\n", L) + "\r\n", new UTF8Encoding(true));
    }

    // ── the viewer on the disc ───────────────────────────────────────────────
    // A hospital reads the disc with its own imaging software; a patient has none. So every
    // disc carries the small viewer VIEWER.EXE. It is built once, with this program, and
    // carried inside it: every disc gets the very same file.
    public static bool HasViewer { get { return Assembly.GetExecutingAssembly().GetManifestResourceInfo("VIEWER.EXE") != null; } }
    public static StepResult AddViewer(string dir) {
      string exe = Path.Combine(dir, "VIEWER.EXE");
      try {
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("VIEWER.EXE")) {
          if (s == null) return new StepResult { Error = "not in this program" };
          using (FileStream f = File.Create(exe)) s.CopyTo(f);
        }
        return new StepResult { Ok = true, Path = exe, Bytes = new FileInfo(exe).Length };
      } catch (Exception e) {
        try { File.Delete(exe); } catch (Exception) { }
        return new StepResult { Error = e.Message };
      }
    }

    // ── AUTORUN.INF ──────────────────────────────────────────────────────────
    // With this file on a CD or DVD, Windows offers the viewer when the disc is put in
    // ("Run VIEWER.EXE", in its AutoPlay window) and shows the disc with the viewer's icon;
    // a double-click on the disc starts the viewer. Nothing starts by itself: Windows asks
    // first, and where AutoPlay is switched off nothing is offered at all. On a USB stick
    // Windows ignores the file (it has, since Windows 7) - there the viewer is started by a
    // double-click on VIEWER.EXE, as README.TXT says.
    // Written only when the viewer is on the disc: a file that points at a program that is
    // not there would be an error message for whoever puts the disc in.
    // Plain ASCII, as Windows reads this file; "action" is the line the AutoPlay window
    // shows where Windows uses it (French first, then English - no accents).
    public static readonly string[] AutorunLines = {
      "[autorun]",
      "open=VIEWER.EXE",
      "icon=VIEWER.EXE,0",
      "action=Voir les images / View the images",
    };
    public static bool WriteAutorun(string dir) {
      string file = Path.Combine(dir, "AUTORUN.INF");
      try {
        if (!File.Exists(Path.Combine(dir, "VIEWER.EXE"))) { if (File.Exists(file)) File.Delete(file); return false; }
        File.WriteAllText(file, string.Join("\r\n", AutorunLines) + "\r\n", Encoding.ASCII);
        return true;
      } catch (Exception) {
        try { File.Delete(file); } catch (Exception) { }        // a disc without it is still a good disc
        return false;
      }
    }

    // ── what is in the disc folder ───────────────────────────────────────────
    // Every file with its size and SHA-256, by its path from the top of the disc.
    public static List<DiscFile> Files(string dir) {
      string root = Path.GetFullPath(dir).TrimEnd('\\'); List<DiscFile> list = new List<DiscFile>();
      using (SHA256 sha = SHA256.Create())
        foreach (string f in Directory.GetFiles(root, "*", SearchOption.AllDirectories))
          list.Add(new DiscFile { Path = f.Substring(root.Length + 1), Bytes = new FileInfo(f).Length, Sha256 = Hash(sha, f) });
      return list;
    }
    static string Hash(SHA256 sha, string file) { using (FileStream s = File.OpenRead(file)) return BitConverter.ToString(sha.ComputeHash(s)).Replace("-", ""); }
    // The files of `files` that are missing or different under `root`.
    public static List<string> Compare(IList<DiscFile> files, string root) {
      List<string> bad = new List<string>();
      using (SHA256 sha = SHA256.Create())
        foreach (DiscFile f in files) {
          try { if (Hash(sha, Path.Combine(root, f.Path)) != f.Sha256) bad.Add(f.Path); } catch (Exception) { bad.Add(f.Path); }
        }
      return bad;
    }

    // ── saving to a folder (a USB stick, or a folder to burn from) ───────────
    // The disc's content goes into a new folder <baseDir>\<name>, which is then the "top
    // of the disc". Every file is read back and compared.
    public static StepResult SaveToFolder(string dir, string baseDir, string name, Action<int, int> onFile) {
      if (!Directory.Exists(baseDir)) return new StepResult { Code = "NO_FOLDER" };
      List<DiscFile> files = Files(dir); long need = 0; foreach (DiscFile f in files) need += f.Bytes;
      try {
        DriveInfo drive = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(baseDir)));
        if (drive.AvailableFreeSpace < need + 1048576) return new StepResult { Code = "NO_ROOM", Need = need, Free = drive.AvailableFreeSpace };
      } catch (Exception) { }                                // a network path: tried anyway
      string target = Path.Combine(baseDir, name);
      for (int i = 2; Directory.Exists(target) || File.Exists(target); i++) target = Path.Combine(baseDir, name + "_" + i);   // never into a folder that exists
      try {
        Directory.CreateDirectory(target); int n = 0;
        foreach (DiscFile f in files) {
          string to = Path.Combine(target, f.Path);
          Directory.CreateDirectory(Path.GetDirectoryName(to));
          File.Copy(Path.Combine(dir, f.Path), to, false);
          n++; if (onFile != null) onFile(n, files.Count);
        }
        List<string> bad = Compare(files, target);
        if (bad.Count > 0) return new StepResult { Code = "NOT_VERIFIED", Path = target, Bad = bad };
        return new StepResult { Ok = true, Path = target, Files = files.Count, Bytes = need };
      } catch (Exception e) { return new StepResult { Code = "WRITE_FAILED", Path = target, Error = e.Message }; }
    }
  }
}
