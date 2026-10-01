# What cd-export.ps1 does, without its window: talking to the EMR, fetching the exams,
# laying out the disc, saving it to a folder or a disc image, burning and checking.
# Dot-sourced by cd-export.ps1; no window and no question is asked here, so that every
# step can be run and checked on its own.
#
# The program talks to the EMR only (login, GET /api/pacs/export/patient, GET
# /api/pacs/export/bundle) - never to the image server, whose password it does not have.
# The EMR checks who may copy what and writes the change-log line.
#
# What goes on a disc:
#   DICOMDIR      the standard index, made by the image server
#   IMAGES\IM0…   the original DICOM files, as the image server holds them
#   README.TXT    written here: whose images, which exams, how to read the disc
# Nothing is installed and no system setting is changed: burning uses Windows' own
# burning component (IMAPI2), the window is Windows' own (WinForms).

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:CdxEmr = @{ Url = ''; Token = ''; User = $null }
$script:TempRoot = Join-Path ([IO.Path]::GetTempPath()) 'BethesdaCD'
$SECTOR = 2048

# ── settings beside the program (never a secret) ─────────────────────────────
function Read-ExportConfig([string]$Path) {
  $cfg = @{ emr_url = 'http://localhost:9080'; last_folder = '' }
  if (Test-Path -LiteralPath $Path) {
    foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
      if ($line -match '^\s*([a-z_]+)\s*=\s*(.*?)\s*$' -and $cfg.ContainsKey($Matches[1])) { $cfg[$Matches[1]] = $Matches[2] }
    }
  }
  return $cfg
}
function Save-ExportConfig([string]$Path, [hashtable]$Cfg) {
  $lines = @('# Bethesda - image copy to CD. The address of the EMR, and the last folder a copy was saved in.',
    ('emr_url=' + $Cfg.emr_url), ('last_folder=' + $Cfg.last_folder))
  try { [IO.File]::WriteAllLines($Path, $lines, (New-Object Text.UTF8Encoding($false))) } catch { }   # a read-only folder: asked again next time
}

# ── the EMR ──────────────────────────────────────────────────────────────────
# One request. Returns @{ ok; status; data; code; error; headers }. status 0 = no answer.
# -SaveTo streams the body to a file (the bundle); -OnBytes is called with the bytes so far.
function Invoke-Emr {
  param([string]$Method = 'GET', [string]$Path, $Body = $null, [string]$SaveTo = '', [scriptblock]$OnBytes = $null, [int]$TimeoutSec = 30)
  $out = @{ ok = $false; status = 0; data = $null; code = ''; error = ''; headers = @{} }
  try {
    $req = [Net.HttpWebRequest]::Create($script:CdxEmr.Url.TrimEnd('/') + $Path)
    $req.Method = $Method
    $req.Timeout = $TimeoutSec * 1000
    $req.ReadWriteTimeout = 120000                      # two minutes without a byte: given up
    $req.AllowAutoRedirect = $false
    $req.Proxy = [Net.GlobalProxySelection]::GetEmptyWebProxy()   # the EMR is on the clinic's own network
    $req.UserAgent = 'bethesda-cd-export'
    if ($script:CdxEmr.Token) { $req.Headers['Authorization'] = 'Bearer ' + $script:CdxEmr.Token }
    if ($null -ne $Body) {
      $bytes = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Compress -Depth 6))
      $req.ContentType = 'application/json; charset=utf-8'
      $req.ContentLength = $bytes.Length
      $s = $req.GetRequestStream(); try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Close() }
    }
    $resp = $null
    try { $resp = $req.GetResponse() }
    catch {
      $ex = $_.Exception
      while ($ex -and -not ($ex -is [Net.WebException])) { $ex = $ex.InnerException }
      if ($ex -and $ex.Response) { $resp = $ex.Response } else { $out.code = 'NO_ANSWER'; $out.error = $_.Exception.Message; return $out }
    }
    try {
      $out.status = [int]$resp.StatusCode
      foreach ($k in $resp.Headers.AllKeys) { $out.headers[$k] = $resp.Headers[$k] }
      $in = $resp.GetResponseStream()
      if ($SaveTo -and $out.status -eq 200) {
        $file = [IO.File]::Create($SaveTo)
        try {
          $buf = New-Object byte[] 262144; $total = [long]0; $told = [long]0
          while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            $file.Write($buf, 0, $n); $total += $n
            if ($OnBytes -and ($total - $told) -ge 1048576) { $told = $total; & $OnBytes $total }
          }
          if ($OnBytes) { & $OnBytes $total }
          $out.data = $total; $out.ok = $true
        } finally { $file.Close() }
      } else {
        $reader = New-Object IO.StreamReader($in, [Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        try { $out.data = $text | ConvertFrom-Json } catch { $out.data = $null }
        $out.ok = ($out.status -ge 200 -and $out.status -lt 300 -and $null -ne $out.data)
        if (-not $out.ok) {
          if ($out.data -and $out.data.code) { $out.code = [string]$out.data.code }
          elseif ($out.status -eq 401) { $out.code = 'LOGIN' }
          elseif ($out.status -eq 403) { $out.code = 'FORBIDDEN' }
          else { $out.code = 'HTTP_' + $out.status }
          if ($out.data -and $out.data.error) { $out.error = [string]$out.data.error }
        }
      }
    } finally { $resp.Close() }
  } catch {
    # the connection broke while the body was being read: a bundle cut short is never kept as if whole
    $out.ok = $false; if (-not $out.code) { $out.code = 'BROKEN' }; $out.error = $_.Exception.Message
    if ($SaveTo -and (Test-Path -LiteralPath $SaveTo)) { Remove-Item -LiteralPath $SaveTo -Force -ErrorAction SilentlyContinue }
  }
  return $out
}

# Sign in with an EMR account. The token is kept in memory only, for as long as the
# program runs; the password is not kept at all.
function Connect-Emr([string]$Url, [string]$Login, [string]$Password) {
  $script:CdxEmr.Url = $Url.Trim(); $script:CdxEmr.Token = ''; $script:CdxEmr.User = $null
  if ($script:CdxEmr.Url -notmatch '^https?://[^/\s]+') { return @{ ok = $false; code = 'BAD_URL' } }
  $r = Invoke-Emr -Method POST -Path '/api/auth/login' -Body @{ login_id = $Login; password = $Password }
  if ($r.ok -and $r.data.token) {
    $script:CdxEmr.Token = [string]$r.data.token; $script:CdxEmr.User = $r.data.user
    $perms = @($r.data.user.permissions)
    if (-not ($perms -contains 'consultation' -or $perms -contains 'payment')) {
      $script:CdxEmr.Token = ''; $script:CdxEmr.User = $null
      return @{ ok = $false; code = 'FORBIDDEN' }
    }
    return @{ ok = $true; user = $r.data.user }
  }
  if ($r.status -eq 401 -or $r.status -eq 400) { return @{ ok = $false; code = 'WRONG_LOGIN' } }
  if ($r.status -eq 0) { return @{ ok = $false; code = 'NO_ANSWER'; error = $r.error } }
  # an address that answers but is not the EMR
  return @{ ok = $false; code = 'NOT_EMR'; error = ('HTTP ' + $r.status) }
}
function Disconnect-Emr { $script:CdxEmr.Token = ''; $script:CdxEmr.User = $null }

function Get-ExportPatient([string]$ChartNo) {
  return Invoke-Emr -Path ('/api/pacs/export/patient?chart_no=' + [Uri]::EscapeDataString($ChartNo.Trim()))
}

# ── sizes and names ──────────────────────────────────────────────────────────
function Format-Size([long]$Bytes, [string]$Unit = 'Mo') {
  $c = [Globalization.CultureInfo]::GetCultureInfo('fr-FR')
  if ($Unit -ne 'Mo') { $c = [Globalization.CultureInfo]::InvariantCulture }
  if ($Bytes -ge 1073741824) { return ($Bytes / 1073741824).ToString('0.00', $c) + ' ' + ($Unit -replace '^M', 'G') }
  if ($Bytes -ge 10485760) { return [Math]::Round($Bytes / 1048576).ToString('0', $c) + ' ' + $Unit }
  if ($Bytes -lt 104858) { return [Math]::Ceiling($Bytes / 1024).ToString('0', $c) + ' ' + ($Unit -replace '^M', 'K') }
  return ($Bytes / 1048576).ToString('0.0', $c) + ' ' + $Unit
}
# Letters that are safe in a folder name and in a disc label.
function Get-SafeName([string]$Text, [int]$Max = 40) {
  $s = ($Text -replace '[^A-Za-z0-9_-]', '_').Trim('_')
  if ($s.Length -gt $Max) { $s = $s.Substring(0, $Max) }
  if (-not $s) { $s = 'X' }
  return $s
}
function Get-DiscLabel([string]$ChartNo) { return ('IMG_' + ((Get-SafeName $ChartNo 11) -replace '-', '_')).ToUpper() }

# ── the working folder on this PC ────────────────────────────────────────────
# Everything fetched is under %TEMP%\BethesdaCD and is removed when the copy is done,
# failed or cancelled - and whatever an earlier run left behind is removed at start.
function New-ExportTemp {
  $d = Join-Path $script:TempRoot ([Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path (Join-Path $d 'disc') | Out-Null
  return $d
}
function Remove-ExportTemp([string]$Dir = '') {
  $target = $script:TempRoot
  if ($Dir) { $target = $Dir }
  if ($target -and $target.StartsWith($script:TempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    # a file still held for a moment (the disc image just let go of it): tried again
    for ($i = 0; $i -lt 10 -and (Test-Path -LiteralPath $target); $i++) {
      try { [IO.Directory]::Delete($target, $true) } catch { Start-Sleep -Milliseconds 300 }
    }
  }
  return (-not (Test-Path -LiteralPath $target))
}

# ── the bundle ───────────────────────────────────────────────────────────────
# Fetch the exams as the image server's ZIP and unpack it into <Work>\disc.
# Only DICOMDIR and IMAGES\<short name> are accepted from the ZIP - anything else, or a
# count that differs from what the EMR announced, and nothing is kept.
function Get-ExportBundle {
  param([int[]]$OrderItemIds, [string]$Medium, [string]$Work, [scriptblock]$OnBytes = $null)
  $zip = Join-Path $Work 'bundle.zip'
  $r = Invoke-Emr -Path ('/api/pacs/export/bundle?order_item_ids=' + ($OrderItemIds -join ',') + '&medium=' + $Medium) -SaveTo $zip -OnBytes $OnBytes -TimeoutSec 120
  if (-not $r.ok) { return @{ ok = $false; code = $r.code; error = $r.error; order_item_id = $(if ($r.data -and $r.data.order_item_id) { $r.data.order_item_id } else { $null }) } }
  $disc = Join-Path $Work 'disc'
  $count = 0; $bytes = [long]0; $hasDir = $false
  try {
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
      foreach ($e in $z.Entries) {
        $name = $e.FullName -replace '\\', '/'
        if ($name -ceq 'DICOMDIR') { $hasDir = $true; $dest = Join-Path $disc 'DICOMDIR' }
        elseif ($name -cmatch '^IMAGES/([A-Za-z0-9_]{1,16})$') { $dest = Join-Path (Join-Path $disc 'IMAGES') $Matches[1]; $count++ }
        elseif ($name -ceq 'IMAGES/') { continue }
        else { return @{ ok = $false; code = 'BAD_BUNDLE'; error = $name } }
        $parent = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
        $bytes += $e.Length
      }
    } finally { $z.Dispose() }
  } catch { return @{ ok = $false; code = 'BAD_BUNDLE'; error = $_.Exception.Message } }
  finally { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
  $announced = 0; [void][int]::TryParse([string]$r.headers['X-Export-Items'], [ref]$announced)
  if (-not $hasDir -or $count -eq 0 -or ($announced -gt 0 -and $announced -ne $count)) { return @{ ok = $false; code = 'BAD_BUNDLE'; error = "$count / $announced" } }
  return @{ ok = $true; dir = $disc; items = $count; bytes = $bytes }
}

# ── README.TXT ───────────────────────────────────────────────────────────────
# French first, then English: what the disc holds and how to read it. Saved as UTF-8
# with its mark at the start, so that Windows Notepad shows the accents.
function Write-DiscReadme {
  param([string]$Dir, $Patient, $Clinic, [object[]]$Exams, [bool]$WithViewer = $false, [datetime]$When = (Get-Date))
  $name = (([string]$Patient.last_name) + ' ' + ([string]$Patient.first_name)).Trim()
  $fr = [string]$Clinic.name_fr; if (-not $fr) { $fr = [string]$Clinic.name }
  $en = [string]$Clinic.name_en; if (-not $en) { $en = [string]$Clinic.name }
  $contact = (@([string]$Clinic.address, $(if ($Clinic.phone) { 'Tel. ' + [string]$Clinic.phone } else { '' })) | Where-Object { $_ }) -join ' - '
  $day = $When.ToString('yyyy-MM-dd')
  $rows = @(foreach ($e in $Exams) { '    {0}  {1,-3} {2} ({3})' -f [string]$e.exam_date, [string]$e.modality, [string]$e.order_name, [string]$e.items })
  $L = New-Object Collections.Generic.List[string]
  $L.Add(($fr.ToUpper() + ' - IMAGES MÉDICALES (DICOM)').Trim(' -'))
  if ($contact) { $L.Add($contact) }
  $L.Add('')
  $L.Add('Patient    : ' + $name)
  $L.Add('N° dossier : ' + [string]$Patient.chart_no)
  $L.Add('Examens (date, type, examen, nombre d''images) :')
  foreach ($r in $rows) { $L.Add($r) }
  $L.Add('Disque créé le ' + $day)
  $L.Add('')
  $L.Add('Ce disque contient des images médicales au format DICOM :')
  $L.Add('  DICOMDIR  la liste des images (fichier standard)')
  $L.Add('  IMAGES    les images d''origine')
  $L.Add('Pour les voir : ouvrez ce disque avec votre logiciel d''imagerie (PACS ou')
  $L.Add('visionneuse DICOM), fonction « importer un CD / ouvrir un DICOMDIR ».')
  if ($WithViewer) {
    $L.Add('Sans logiciel d''imagerie : double-cliquez sur VOIR.BAT (Windows 64 bits).')
    $L.Add('Le démarrage depuis un disque est lent. La visionneuse fournie (Weasis,')
    $L.Add('dossier VIEWER) n''est pas un dispositif médical certifié.')
  }
  $L.Add('Ce disque contient des données médicales personnelles : remettez-le au patient')
  $L.Add('ou au médecin destinataire uniquement.')
  $L.Add('')
  $L.Add('------------------------------------------------------------------------')
  $L.Add('')
  $L.Add(($en.ToUpper() + ' - MEDICAL IMAGES (DICOM)').Trim(' -'))
  $L.Add('')
  $L.Add('Patient  : ' + $name)
  $L.Add('Chart no.: ' + [string]$Patient.chart_no)
  $L.Add('Exams (date, type, exam, number of images):')
  foreach ($r in $rows) { $L.Add($r) }
  $L.Add('Disc made on ' + $day)
  $L.Add('')
  $L.Add('This disc holds medical images in DICOM format:')
  $L.Add('  DICOMDIR  the index of the images (standard file)')
  $L.Add('  IMAGES    the original images')
  $L.Add('To see them: open this disc with your imaging software (PACS or DICOM')
  $L.Add('viewer), "import a CD / open a DICOMDIR".')
  if ($WithViewer) {
    $L.Add('Without imaging software: double-click VOIR.BAT (64-bit Windows). Starting')
    $L.Add('from a disc is slow. The viewer provided (Weasis, folder VIEWER) is not a')
    $L.Add('certified medical device.')
  }
  $L.Add('This disc holds personal medical data: hand it to the patient or to the')
  $L.Add('receiving doctor only.')
  [IO.File]::WriteAllText((Join-Path $Dir 'README.TXT'), (($L -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($true)))
}

# ── what is in the disc folder ───────────────────────────────────────────────
# Every file with its size and SHA-256, by its path from the top of the disc.
function Get-DiscFiles([string]$Dir, [scriptblock]$OnFile = $null) {
  $root = (Resolve-Path -LiteralPath $Dir).Path.TrimEnd('\')
  $sha = [Security.Cryptography.SHA256]::Create()
  $list = New-Object Collections.Generic.List[object]
  try {
    foreach ($f in [IO.Directory]::GetFiles($root, '*', [IO.SearchOption]::AllDirectories)) {
      $s = [IO.File]::OpenRead($f)
      try { $h = [BitConverter]::ToString($sha.ComputeHash($s)) -replace '-', '' } finally { $s.Close() }
      $list.Add([pscustomobject]@{ path = $f.Substring($root.Length + 1); bytes = (New-Object IO.FileInfo($f)).Length; sha256 = $h })
      if ($OnFile) { & $OnFile $list.Count }
    }
  } finally { $sha.Dispose() }
  return $list.ToArray()
}
# Room the files take on a disc, a little over: each file rounded up to a sector, plus
# the disc's own tables. The exact figure is the image's, once it is built.
function Get-DiscEstimate([long]$Bytes, [int]$Files) {
  return [long]($Bytes + ($Files + 40) * $SECTOR + 2097152)
}

# ── saving to a folder (a USB stick, or a folder to burn from) ───────────────
# The disc's content goes into a new folder <Base>\<name>, which is then the "top of the
# disc". Every file is read back and compared. Returns @{ ok; path; files; bytes }.
function Save-DiscToFolder {
  param([string]$Dir, [string]$Base, [string]$Name, [scriptblock]$OnFile = $null)
  if (-not (Test-Path -LiteralPath $Base -PathType Container)) { return @{ ok = $false; code = 'NO_FOLDER' } }
  $files = Get-DiscFiles $Dir
  $need = ($files | Measure-Object -Property bytes -Sum).Sum
  try {
    $drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Base).Path))
    if ($drive.AvailableFreeSpace -lt ($need + 1048576)) { return @{ ok = $false; code = 'NO_ROOM'; need = $need; free = $drive.AvailableFreeSpace } }
  } catch { }                                           # a network path: tried anyway
  $target = Join-Path $Base $Name
  $i = 2
  while (Test-Path -LiteralPath $target) { $target = Join-Path $Base ($Name + '_' + $i); $i++ }   # never into a folder that exists
  try {
    New-Item -ItemType Directory -Path $target | Out-Null
    $n = 0
    foreach ($f in $files) {
      $to = Join-Path $target $f.path
      $parent = Split-Path -Parent $to
      if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
      [IO.File]::Copy((Join-Path $Dir $f.path), $to, $false)
      $n++; if ($OnFile) { & $OnFile $n $files.Count }
    }
    $bad = Compare-DiscFiles $files $target
    if ($bad.Count) { return @{ ok = $false; code = 'NOT_VERIFIED'; path = $target; bad = $bad } }
    return @{ ok = $true; path = $target; files = $files.Count; bytes = $need }
  } catch { return @{ ok = $false; code = 'WRITE_FAILED'; path = $target; error = $_.Exception.Message } }
}
# The files of `Files` (Get-DiscFiles) that are missing or different under `Root`.
function Compare-DiscFiles([object[]]$Files, [string]$Root) {
  $bad = New-Object Collections.Generic.List[string]
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    foreach ($f in $Files) {
      $p = Join-Path $Root $f.path
      try {
        $s = [IO.File]::OpenRead($p)
        try { $h = [BitConverter]::ToString($sha.ComputeHash($s)) -replace '-', '' } finally { $s.Close() }
        if ($h -ne $f.sha256) { $bad.Add($f.path) }
      } catch { $bad.Add($f.path) }
    }
  } finally { $sha.Dispose() }
  return , $bad.ToArray()
}

# ── the disc image and the burner (Windows' IMAPI2) ──────────────────────────
# The image is built and written on a thread of its own, so that the window goes on
# answering; the window asks how far it is (DoneBytes / TotalBytes).
#   StartIso   the image saved as a file - works without any drive
#   StartBurn  the image written to the disc in a recorder, closed (nothing can be added),
#              checked by the burner where it can
# IMAPI reads the image through CountingStream, which is how progress is known.
if (-not ('Bethesda.DiscJob' -as [type])) {
  Add-Type -ReferencedAssemblies 'Microsoft.CSharp' -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace Bethesda {
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
    public int State { get { return Thread.VolatileRead(ref state); } }          // 0 not started, 1 working, 2 done, 3 failed
    public long TotalBytes { get { return Interlocked.Read(ref total); } }
    public long DoneBytes { get { CountingStream c = counter; return c != null ? c.BytesRead : Interlocked.Read(ref written); } }

    private static object Make(string progId) { return Activator.CreateInstance(Type.GetTypeFromProgID(progId, true)); }

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
        counter = new CountingStream(s);
        Step = "write";
        fmt.Write(new UnknownWrapper(counter));
        Step = "done";
        if (eject) { try { rec.EjectMedia(); } catch (Exception) { } }
      });
    }
  }
}
'@
}

$MEDIA_NAMES = @{ 1 = 'CD-ROM'; 2 = 'CD-R'; 3 = 'CD-RW'; 4 = 'DVD-ROM'; 5 = 'DVD-RAM'; 6 = 'DVD+R'; 7 = 'DVD+RW'; 8 = 'DVD+R DL'; 9 = 'DVD-R'; 10 = 'DVD-RW'; 11 = 'DVD-R DL'; 13 = 'DVD+RW DL'; 18 = 'BD-R'; 19 = 'BD-RE' }
$MEDIA_REWRITABLE = @(3, 5, 7, 10, 13, 19)

# The recorders of this PC and what is in each (nothing is written, the tray is not moved):
#   state  'none'   no disc            'blank'  an empty disc that can be written
#          'used'   a disc that already holds something (never written to, never erased)
#          'other'  a disc this drive cannot write
function Get-Burners {
  $out = New-Object Collections.Generic.List[object]
  try { $master = New-Object -ComObject IMAPI2.MsftDiscMaster2 } catch { return , $out.ToArray() }
  foreach ($id in $master) {
    $b = [pscustomobject]@{ id = $id; letter = ''; name = ''; state = 'none'; media = ''; rewritable = $false; freeBytes = [long]0 }
    try {
      $rec = New-Object -ComObject IMAPI2.MsftDiscRecorder2
      $rec.InitializeDiscRecorder($id)
      $b.name = (([string]$rec.VendorId).Trim() + ' ' + ([string]$rec.ProductId).Trim()).Trim()
      $b.letter = ([string](@($rec.VolumePathNames)[0])).TrimEnd('\')
      $fmt = New-Object -ComObject IMAPI2.MsftDiscFormat2Data
      if ($fmt.IsRecorderSupported($rec)) {
        $fmt.Recorder = $rec; $fmt.ClientName = 'BethesdaCdExport'
        try {
          $type = [int]$fmt.CurrentPhysicalMediaType
          $b.media = $MEDIA_NAMES[$type]; if (-not $b.media) { $b.media = 'disc' }
          $b.rewritable = $MEDIA_REWRITABLE -contains $type
          if (-not $fmt.IsCurrentMediaSupported($rec)) { $b.state = 'other' }
          elseif ($fmt.MediaHeuristicallyBlank) { $b.state = 'blank'; $b.freeBytes = [long]$fmt.FreeSectorsOnMedia * $SECTOR }
          else { $b.state = 'used' }
        } catch { $b.state = 'none' }                    # no disc: the questions about it fail
      }
    } catch { }
    $out.Add($b)
  }
  return , $out.ToArray()
}

# After a burn: wait for Windows to show the new disc, then compare every file with
# what was meant to be written. 'unread' = the disc did not show up in time.
function Test-BurnedDisc([string]$Letter, [object[]]$Files, [int]$WaitSec = 45, [scriptblock]$OnWait = $null) {
  $root = $Letter.TrimEnd('\') + '\'
  $until = (Get-Date).AddSeconds($WaitSec)
  while ((Get-Date) -lt $until) {
    if (Test-Path -LiteralPath (Join-Path $root 'DICOMDIR')) {
      $bad = Compare-DiscFiles $Files $root
      if ($bad.Count) { return @{ result = 'different'; bad = $bad } }
      return @{ result = 'same' }
    }
    if ($OnWait) { & $OnWait }
    Start-Sleep -Milliseconds 500
  }
  return @{ result = 'unread' }
}
function Open-DiscTray([string]$RecorderId) {
  try { $rec = New-Object -ComObject IMAPI2.MsftDiscRecorder2; $rec.InitializeDiscRecorder($RecorderId); $rec.EjectMedia() } catch { }
}
