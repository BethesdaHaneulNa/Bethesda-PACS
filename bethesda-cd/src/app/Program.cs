// Bethesda CD - copy a patient's exams to a CD (or a folder, or a disc image).
//
// A separate program, as hospitals have beside their PACS: sign in with an EMR account,
// type the patient's chart number, tick the exams, see how large they are; with a blank
// disc in the drive, "burn this CD?" - burn, check, eject.
//
// It talks to the EMR only - the EMR decides who may copy what, refuses exams that must
// not leave and writes one line in its change log per copy. It can run on any PC that
// reaches the EMR. Nothing is installed and no system setting is changed: the window is
// Windows' own (WinForms), burning uses Windows' own burning component (IMAPI2). The
// images fetched are kept under %TEMP%\BethesdaCD while the copy is made and removed
// afterwards.
//
//   Bethesda-CD.exe                 the language of Bethesda-CD.ini (French when none)
//   Bethesda-CD.exe -Lang ko        Korean (en: English) for this run
//   Bethesda-CD.exe -ConfigPath x   another settings file
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Bethesda CD")]
[assembly: AssemblyDescription("Copies a patient's imaging exams from the Bethesda EMR to a CD, a disc image or a folder")]

namespace Bethesda.Cd {
  // The settings beside the program - never a secret: the address of the EMR, the last
  // folder a copy was saved in, the language.
  public class Config {
    public string File = "", EmrUrl = "http://localhost:9080", LastFolder = "", Lang = "";
    public static Config Read(string path) {
      Config c = new Config { File = path };
      string from = System.IO.File.Exists(path) ? path : Path.Combine(Path.GetDirectoryName(path) ?? "", "cd-export.ini");     // the settings of the earlier cd-export.bat, read once
      if (System.IO.File.Exists(from)) {
        foreach (string line in System.IO.File.ReadAllLines(from, Encoding.UTF8)) {
          int eq = line.IndexOf('='); if (eq <= 0 || line.TrimStart().StartsWith("#")) continue;
          string key = line.Substring(0, eq).Trim(), value = line.Substring(eq + 1).Trim();
          if (key == "emr_url") c.EmrUrl = value; else if (key == "last_folder") c.LastFolder = value; else if (key == "lang") c.Lang = value;
        }
      }
      return c;
    }
    public void Save() {
      List<string> lines = new List<string> { "# Bethesda CD. The address of the EMR, the last folder a copy was saved in, the language (fr, ko, en).", "emr_url=" + EmrUrl, "last_folder=" + LastFolder };
      if (Lang != "") lines.Add("lang=" + Lang);
      try { System.IO.File.WriteAllLines(File, lines.ToArray(), new UTF8Encoding(false)); } catch (Exception) { }    // a read-only folder: asked again next time
    }
  }

  static class Program {
    [STAThread]
    static int Main(string[] args) {
      Application.EnableVisualStyles();
      Application.SetCompatibleTextRenderingDefault(false);
      try {
        string lang = "", path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Bethesda-CD.ini");
        for (int i = 0; i + 1 < args.Length; i++) {
          string a = args[i].TrimStart('-', '/').ToLowerInvariant();
          if (a == "lang") lang = args[i + 1].ToLowerInvariant(); else if (a == "configpath") path = args[i + 1];
        }
        Config config = Config.Read(path);
        Texts.Lang = Texts.Known(lang) ? lang : Texts.Known(config.Lang) ? config.Lang : "fr";
        DiscFolder.RemoveTemp("");                           // what an interrupted run left behind
        Application.Run(new MainForm(config));
        return 0;
      } catch (Exception e) {
        MessageBox.Show(Product.Name + ": " + e.Message, Product.Name, MessageBoxButtons.OK, MessageBoxIcon.Error);
        return 1;
      }
    }
  }
}
