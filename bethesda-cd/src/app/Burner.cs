// Bethesda CD - the disc image and the burner, through Windows' own burning component
// (IMAPI2): nothing is installed. Its objects are used by name (dynamic), so that no
// Windows SDK is needed to build this.
//
// The image is built and written on a thread of its own, so that the window goes on
// answering; the window asks how far it is (DoneBytes / TotalBytes).
//   StartIso   the image saved as a file - works without any drive
//   StartBurn  the image written to the disc in a recorder, closed (nothing can be added),
//              at the slowest speed the drive offers, checked by the burner where it can
// IMAPI reads the image through CountingStream, which is how progress is known.
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Threading;

namespace Bethesda.Cd {
  [ComImport, Guid("D2FFD834-958B-426D-8470-2A13879C6A91"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface IBurnVerification {
    void put_BurnVerificationLevel(int value);
    int get_BurnVerificationLevel();
  }

  public class CountingStream : IStream {
    private readonly IStream inner; private long read;
    public CountingStream(IStream s) { inner = s; }
    public long BytesRead { get { return Interlocked.Read(ref read); } }
    public void Read(byte[] pv, int cb, IntPtr pcbRead) {
      IntPtr got = pcbRead == IntPtr.Zero ? Marshal.AllocHGlobal(sizeof(int)) : pcbRead;
      try { inner.Read(pv, cb, got); Interlocked.Add(ref read, Marshal.ReadInt32(got)); }
      finally { if (pcbRead == IntPtr.Zero) Marshal.FreeHGlobal(got); }
    }
    public void Write(byte[] pv, int cb, IntPtr pcbWritten) { inner.Write(pv, cb, pcbWritten); }
    public void Seek(long dlibMove, int dwOrigin, IntPtr plibNewPosition) { inner.Seek(dlibMove, dwOrigin, plibNewPosition); }
    public void SetSize(long libNewSize) { inner.SetSize(libNewSize); }
    public void CopyTo(IStream pstm, long cb, IntPtr pcbRead, IntPtr pcbWritten) { inner.CopyTo(pstm, cb, pcbRead, pcbWritten); }
    public void Commit(int grfCommitFlags) { inner.Commit(grfCommitFlags); }
    public void Revert() { inner.Revert(); }
    public void LockRegion(long libOffset, long cb, int dwLockType) { inner.LockRegion(libOffset, cb, dwLockType); }
    public void UnlockRegion(long libOffset, long cb, int dwLockType) { inner.UnlockRegion(libOffset, cb, dwLockType); }
    public void Stat(out System.Runtime.InteropServices.ComTypes.STATSTG pstatstg, int grfStatFlag) { inner.Stat(out pstatstg, grfStatFlag); }
    public void Clone(out IStream ppstm) { inner.Clone(out ppstm); }
  }

  public class DiscJob {
    private int state; private long total; private CountingStream counter; private long written;
    private object fsiRef, resultRef, streamRef, recorderRef, formatRef;
    public string Error = ""; public string Step = ""; public bool CheckedByBurner = false; public int HResult = 0;
    public int WriteSpeed = 0;                                                    // sectors a second asked of the drive (0 = its own choice)
    public int State { get { return Thread.VolatileRead(ref state); } }          // 0 not started, 1 working, 2 done, 3 failed
    public long TotalBytes { get { return Interlocked.Read(ref total); } }
    public long DoneBytes { get { CountingStream c = counter; return c != null ? c.BytesRead : Interlocked.Read(ref written); } }

    internal static object Make(string progId) { return Activator.CreateInstance(Type.GetTypeFromProgID(progId, true)); }

    // The image of `dir` as a disc: ISO 9660 + Joliet names (+ UDF when asked).
    private IStream Build(string dir, string volume, int fileSystems, object recorder) {
      Step = "image";
      dynamic fsi = Make("IMAPI2FS.MsftFileSystemImage"); fsiRef = fsi;
      if (recorder != null) fsi.ChooseImageDefaults(recorder);     // the size of the disc in the drive: a tree too large is refused here
      else fsi.FreeMediaBlocks = 0;                                // an image file: no disc to fit (the default is a 650 MB CD)
      fsi.FileSystemsToCreate = fileSystems;
      fsi.VolumeName = volume;
      fsi.Root.AddTree(dir, false);
      dynamic result = fsi.CreateResultImage(); resultRef = result;
      Interlocked.Exchange(ref total, (long)(int)result.TotalBlocks * (long)(int)result.BlockSize);
      IStream stream = (IStream)result.ImageStream; streamRef = stream;
      return stream;
    }

    // The image keeps every file of the folder open for as long as it lives: let go of it
    // as soon as the work is over, so that the folder (a patient's images) can be removed.
    private void Release() {
      counter = null;
      foreach (object o in new object[] { streamRef, resultRef, fsiRef, formatRef, recorderRef }) {
        try { if (o != null && Marshal.IsComObject(o)) Marshal.FinalReleaseComObject(o); } catch (Exception) { }
      }
      streamRef = resultRef = fsiRef = formatRef = recorderRef = null;
      GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
    }

    private void Run(ThreadStart work) {
      Thread.VolatileWrite(ref state, 1);
      Thread t = new Thread(delegate() {
        int end = 2;
        try { work(); }
        catch (Exception e) {
          Exception x = e; while (x.InnerException != null) x = x.InnerException;
          Error = x.Message; HResult = Marshal.GetHRForException(x);
          end = 3;
        }
        long done = DoneBytes;
        Release();
        Interlocked.Exchange(ref written, done);          // what the window reads once the image is let go
        Thread.VolatileWrite(ref state, end);
      });
      t.SetApartmentState(ApartmentState.STA); t.IsBackground = true; t.Start();
    }

    public void StartIso(string dir, string volume, int fileSystems, string isoPath) {
      Run(delegate() {
        IStream s = Build(dir, volume, fileSystems, null);
        Step = "write";
        byte[] buf = new byte[1 << 20]; IntPtr got = Marshal.AllocHGlobal(sizeof(int));
        try {
          using (FileStream f = new FileStream(isoPath, FileMode.CreateNew, FileAccess.Write)) {
            while (true) { s.Read(buf, buf.Length, got); int n = Marshal.ReadInt32(got); if (n <= 0) break; f.Write(buf, 0, n); Interlocked.Add(ref written, n); }
          }
        } finally { Marshal.FreeHGlobal(got); }
        if (Interlocked.Read(ref written) != TotalBytes) throw new IOException("image cut short");
      });
    }

    public void StartBurn(string dir, string volume, int fileSystems, string recorderId, string clientName, bool eject) {
      Run(delegate() {
        dynamic rec = Make("IMAPI2.MsftDiscRecorder2"); recorderRef = rec;
        rec.InitializeDiscRecorder(recorderId);
        dynamic fmt = Make("IMAPI2.MsftDiscFormat2Data"); formatRef = fmt;
        fmt.Recorder = rec; fmt.ClientName = clientName;
        if (!(bool)fmt.MediaHeuristicallyBlank) throw new InvalidOperationException("the disc is not blank");
        IStream s = Build(dir, volume, fileSystems, (object)rec);
        fmt.ForceMediaToBeClosed = true;                 // a finished disc: nothing can be added later
        try { ((IBurnVerification)(object)fmt).put_BurnVerificationLevel(2); CheckedByBurner = true; } catch (Exception) { CheckedByBurner = false; }
        // The slowest speed the drive offers for this disc: a few minutes more at most, and
        // kinder to cheap discs and to slim drives fed by a USB port.
        try {
          int slowest = int.MaxValue;
          foreach (object v in (IEnumerable)fmt.SupportedWriteSpeeds) { int sp = Convert.ToInt32(v); if (sp > 0 && sp < slowest) slowest = sp; }
          if (slowest != int.MaxValue) { fmt.SetWriteSpeed(slowest, false); WriteSpeed = slowest; }
        } catch (Exception) { }
        counter = new CountingStream(s);
        Step = "write";
        fmt.Write(new UnknownWrapper(counter));
        Step = "done";
        if (eject) { try { rec.EjectMedia(); } catch (Exception) { } }
      });
    }
  }

  // A recorder of this PC and what is in it:
  //   State  "none"   no disc            "blank"  an empty disc that can be written
  //          "used"   a disc that already holds something (never written to, never erased)
  public class BurnerInfo { public string Id = "", Letter = "", Name = "", State = "none", Media = ""; public bool Rewritable; public long FreeBytes; }

  public static class Burners {
    public const string ClientName = "BethesdaCD";
    static readonly Dictionary<int, string> MediaNames = new Dictionary<int, string> {
      { 1, "CD-ROM" }, { 2, "CD-R" }, { 3, "CD-RW" }, { 4, "DVD-ROM" }, { 5, "DVD-RAM" }, { 6, "DVD+R" }, { 7, "DVD+RW" }, { 8, "DVD+R DL" },
      { 9, "DVD-R" }, { 10, "DVD-RW" }, { 11, "DVD-R DL" }, { 13, "DVD+RW DL" }, { 18, "BD-R" }, { 19, "BD-RE" } };
    static readonly int[] Rewritable = { 3, 5, 7, 10, 13, 19 };
    static void Free(object o) { try { if (o != null && Marshal.IsComObject(o)) Marshal.ReleaseComObject(o); } catch (Exception) { } }

    // The recorders and their discs. Nothing is written, the tray is not moved.
    public static List<BurnerInfo> List() {
      List<BurnerInfo> list = new List<BurnerInfo>(); dynamic master;
      try { master = DiscJob.Make("IMAPI2.MsftDiscMaster2"); } catch (Exception) { return list; }
      List<string> ids = new List<string>();
      try { foreach (object id in (IEnumerable)master) ids.Add(Convert.ToString(id)); } catch (Exception) { }
      Free(master);
      foreach (string id in ids) {
        BurnerInfo b = new BurnerInfo { Id = id }; dynamic rec = null, fmt = null;
        try {
          rec = DiscJob.Make("IMAPI2.MsftDiscRecorder2"); rec.InitializeDiscRecorder(id);
          b.Name = (Convert.ToString(rec.VendorId).Trim() + " " + Convert.ToString(rec.ProductId).Trim()).Trim();
          foreach (object p in (IEnumerable)rec.VolumePathNames) { b.Letter = Convert.ToString(p).TrimEnd('\\'); break; }
          fmt = DiscJob.Make("IMAPI2.MsftDiscFormat2Data");
          if ((bool)fmt.IsRecorderSupported(rec)) {
            fmt.Recorder = rec; fmt.ClientName = ClientName;
            try {
              int type = (int)fmt.CurrentPhysicalMediaType;
              if (type > 0) {                               // (0 or less: no disc, or the tray is open - the drive names no kind of disc)
                string media; b.Media = MediaNames.TryGetValue(type, out media) ? media : "disc";
                b.Rewritable = Array.IndexOf(Rewritable, type) >= 0;
                // Nothing more can be written to a pressed disc or to a recordable one that was
                // closed - a CD-R this program burnt comes back named "CD-ROM" by the drive.
                // Either way it is "not blank" to the person at the window.
                if (!(bool)fmt.IsCurrentMediaSupported(rec)) b.State = "used";
                else if ((bool)fmt.MediaHeuristicallyBlank) { b.State = "blank"; b.FreeBytes = (long)(int)fmt.FreeSectorsOnMedia * DiscFolder.Sector; }
                else b.State = "used";
              }
            } catch (Exception) { b.State = "none"; }       // no disc: the questions about it fail
          }
        } catch (Exception) { }
        Free(fmt); Free(rec);
        list.Add(b);
      }
      return list;
    }

    // After a burn: wait for Windows to show the new disc, then compare every file with
    // what was meant to be written. "unread" = the disc did not show up in time.
    public static string Check(string letter, IList<DiscFile> files, int waitSec, Action onWait, out List<string> bad) {
      string root = letter.TrimEnd('\\') + "\\"; bad = new List<string>();
      DateTime until = DateTime.Now.AddSeconds(waitSec);
      while (DateTime.Now < until) {
        if (File.Exists(Path.Combine(root, "DICOMDIR"))) { bad = DiscFolder.Compare(files, root); return bad.Count > 0 ? "different" : "same"; }
        if (onWait != null) onWait();
        Thread.Sleep(500);
      }
      return "unread";
    }
    public static void OpenTray(string recorderId) {
      dynamic rec = null;
      try { rec = DiscJob.Make("IMAPI2.MsftDiscRecorder2"); rec.InitializeDiscRecorder(recorderId); rec.EjectMedia(); } catch (Exception) { }
      Free(rec);
    }
  }
}
