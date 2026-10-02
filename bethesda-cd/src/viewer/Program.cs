// VOIR.EXE - started by a double-click on the disc: it shows the images of the disc it
// is on. Given a folder as its argument, it shows that folder instead. When there is
// nothing to show where it stands, it asks for the folder.
using System;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("VOIR - Bethesda CD viewer")]
[assembly: AssemblyDescription("Shows the images of the disc it is on. For reference - not for diagnosis.")]

namespace Bethesda.Viewer {
  static class Program {
    [STAThread]
    static void Main(string[] args) {
      Application.EnableVisualStyles();
      Application.SetCompatibleTextRenderingDefault(false);
      Application.ThreadException += delegate(object s, System.Threading.ThreadExceptionEventArgs e) {
        MessageBox.Show(e.Exception.Message, Texts.Get("app"), MessageBoxButtons.OK, MessageBoxIcon.Warning);
      };
      string folder = args.Length > 0 && Directory.Exists(args[0]) ? args[0] : AppDomain.CurrentDomain.BaseDirectory;
      Disc disc = Disc.Open(folder);
      if (disc.ImageCount == 0 && args.Length == 0) {
        using (FolderBrowserDialog f = new FolderBrowserDialog { Description = Texts.Get("choose"), ShowNewFolderButton = false }) {
          if (f.ShowDialog() != DialogResult.OK) return;
          disc = Disc.Open(f.SelectedPath);
        }
      }
      Application.Run(new MainForm(disc));
    }
  }
}
