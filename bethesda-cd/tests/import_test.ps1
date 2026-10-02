# Bethesda CD - "bring in a CD / USB stick", driven without a person and without the EMR:
# this script writes a made-up "other hospital's disc" (DICOM files of its own making, with
# a viewer program, a library and other files that are not images beside them), starts a
# stand-in for the EMR on this PC (an HTTP listener that answers the import calls as the
# EMR's document says - wiki reference/external-images-import-api.md), loads the built
# Bethesda-CD.exe, fills its boxes, calls what its buttons call, answers its questions, and
# checks what was sent.
#
#   .\import_test.ps1                          (nothing to prepare: made in %TEMP% and removed)
#   .\import_test.ps1 -Sample D:\some\disc     also reads a real disc folder that has a DICOMDIR
#                                              (read only; nothing of it is sent anywhere)
#
# Nothing leaves this PC: the stand-in listens on 127.0.0.1 only. What it cannot show is
# what the real EMR does with the files - that is checked against a test EMR.
param([string]$Exe = '', [string]$Sample = '', [ValidateSet('fr', 'ko', 'en')][string]$Lang = 'fr', [string]$Shots = '')
$ErrorActionPreference = 'Stop'
if (-not $Exe) { $Exe = Join-Path $PSScriptRoot '..\build\Bethesda-CD.exe' }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[void][Reflection.Assembly]::LoadFrom($Exe)

# ── made-up DICOM files (written here; the program only reads them) ──────────────────────
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
  // One image: 8 x 8 pixels (or more, to make a file of a given size), explicit VR little endian, Latin-1 words.
  public static void Write(string path, string study, string series, string sop, string patientId, string patientName, string birth, string sex,
      string institution, string date, string description, string modality, string accession, int pixelBytes) {
    MemoryStream meta = new MemoryStream(), ds = new MemoryStream();
    El(meta, 2, 1, "OB", new byte[] { 0, 1 }); S(meta, 2, 2, "UI", "1.2.840.10008.5.1.4.1.1.7"); S(meta, 2, 3, "UI", sop); S(meta, 2, 0x10, "UI", "1.2.840.10008.1.2.1"); S(meta, 2, 0x12, "UI", "1.2.826.0.1.3680043.8.498.1");
    S(ds, 8, 5, "CS", "ISO_IR 100"); S(ds, 8, 0x16, "UI", "1.2.840.10008.5.1.4.1.1.7"); S(ds, 8, 0x18, "UI", sop);
    S(ds, 8, 0x20, "DA", date); S(ds, 8, 0x50, "SH", accession); S(ds, 8, 0x60, "CS", modality); S(ds, 8, 0x80, "LO", institution); S(ds, 8, 0x1030, "LO", description);
    S(ds, 0x10, 0x10, "PN", patientName); S(ds, 0x10, 0x20, "LO", patientId); S(ds, 0x10, 0x30, "DA", birth); S(ds, 0x10, 0x40, "CS", sex);
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

$script:res = @(); $script:said = New-Object Collections.Generic.List[string]; $script:answer = $true; $script:same = $true; $script:asked = $null
function Check([string]$label, $good, [string]$extra = '') { $script:res += [bool]$good; '{0} {1} {2}' -f $(if ($good) { 'PASS' } else { 'FAIL' }), $label, $extra }
function Sha([string]$file) { (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }

$work = Join-Path $env:TEMP ('bethesda-cd-import-test-' + [Guid]::NewGuid().ToString('N'))
$disc = Join-Path $work 'disc'; $two = Join-Path $work 'two-patients'; $empty = Join-Path $work 'no-images'
New-Item -ItemType Directory -Path $disc, $two, $empty | Out-Null
$name = "$([char]0xC9)SSAI^H$([char]0xE9)l$([char]0xE8)ne"                 # accents, as a French hospital writes them
$A = '1.2.826.0.1.3680043.8.498.7001'; $B = '1.2.826.0.1.3680043.8.498.7002'
foreach ($i in 1..3) { [FakeDicom]::Write((Join-Path $disc "DICOM\ST1\IM$i"), $A, "$A.1", "$A.1.$i", 'H-00340406', $name, '19850412', 'F', 'HJRA', '20260814', 'ABDOMEN AVEC CONTRASTE', 'CT', 'ACC-A', 40000 + 3000 * $i) }
foreach ($i in 1..2) { [FakeDicom]::Write((Join-Path $disc "DICOM\ST2\IM$i.dcm"), $B, "$B.1", "$B.1.$i", 'H-00340406', $name, '19850412', 'F', 'HJRA', '20250311', 'THORAX', 'CR', 'ACC-B', 20000) }
# what else lies on such a disc: another maker's viewer, its library, its autorun, a note, a picture, a file that is nothing
[IO.File]::WriteAllBytes((Join-Path $disc 'VIEWER.EXE'), [byte[]](0x4D, 0x5A) + (New-Object byte[] 4000))
[IO.File]::WriteAllBytes((Join-Path $disc 'DICOM\codec.dll'), [byte[]](0x4D, 0x5A) + (New-Object byte[] 4000))
[IO.File]::WriteAllText((Join-Path $disc 'AUTORUN.INF'), "[autorun]`r`nopen=VIEWER.EXE`r`n")
[IO.File]::WriteAllText((Join-Path $disc 'README.TXT'), 'read me')
[IO.File]::WriteAllBytes((Join-Path $disc 'DICOM\cover.jpg'), (New-Object byte[] 500))
[IO.File]::WriteAllBytes((Join-Path $disc 'DICOM\NOTHING'), (New-Object byte[] 900))
$before = @{}; Get-ChildItem -LiteralPath $disc -Recurse -File | ForEach-Object { $before[$_.FullName] = Sha $_.FullName }
[FakeDicom]::Write((Join-Path $two 'P1\IM1'), '1.2.826.0.1.3680043.8.498.7101', '1.2.826.0.1.3680043.8.498.7101.1', '1.2.826.0.1.3680043.8.498.7101.1.1', 'X-1', 'UN^Patient', '19700101', 'M', 'CHU', '20260101', 'GENOU', 'CR', '', 9000)
[FakeDicom]::Write((Join-Path $two 'P2\IM1'), '1.2.826.0.1.3680043.8.498.7102', '1.2.826.0.1.3680043.8.498.7102.1', '1.2.826.0.1.3680043.8.498.7102.1.1', 'X-2', 'DEUX^Patient', '19800202', 'F', 'CHU', '20260102', 'MAIN', 'CR', '', 9000)
[IO.File]::WriteAllText((Join-Path $empty 'notes.txt'), 'nothing here')

# ── the stand-in for the EMR ─────────────────────────────────────────────────────────────
$tcp = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0); $tcp.Start(); $port = $tcp.LocalEndpoint.Port; $tcp.Stop()
$S = [hashtable]::Synchronized(@{ port = $port; stop = $false; ready = $false; error = ''
    calls = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList)); bodies = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList))
    puts = [Collections.ArrayList]::Synchronized((New-Object Collections.ArrayList)); imports = [hashtable]::Synchronized(@{}); nextId = 11; putCount = 0
    perms = @('registration'); expire = $false; noImport = $false; server = ''; free = 500GB; maxFile = 1GB; warn = 2GB
    birth = '1985-04-12'; gender = 'F'; states = [hashtable]::Synchronized(@{}); failPut = 0; failCode = ''; cutPut = 0; slow = 0; done = [hashtable]::Synchronized(@{}) })
$serverScript = {
  param($S)
  function Send($ctx, [int]$status, $obj) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Depth 8 -Compress))
    $ctx.Response.StatusCode = $status; $ctx.Response.ContentType = 'application/json; charset=utf-8'; $ctx.Response.ContentLength64 = $bytes.Length
    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length); $ctx.Response.Close()
  }
  try {
    $l = New-Object Net.HttpListener; $l.Prefixes.Add("http://127.0.0.1:$($S.port)/"); $l.Start(); $S.ready = $true
    $sha = [Security.Cryptography.SHA256]::Create()
    while (-not $S.stop) {
      $task = $l.GetContextAsync()
      while (-not $task.Wait(150)) { if ($S.stop) { break } }
      if ($S.stop) { break }
      $ctx = $task.Result; $req = $ctx.Request; $path = $req.Url.AbsolutePath; $m = $req.HttpMethod
      [void]$S.calls.Add("$m $path")
      try {
      $ms = New-Object IO.MemoryStream
      if ($m -eq 'PUT' -and $S.cutPut -gt 0 -and ($S.putCount + 1) -eq $S.cutPut) { $S.cutPut = 0; [void]$S.calls.Add('(connection cut)'); $ctx.Response.Abort(); continue }
      $req.InputStream.CopyTo($ms); $raw = $ms.ToArray()
      $json = $null
      if ($m -eq 'POST' -and $raw.Length) { $text = [Text.Encoding]::UTF8.GetString($raw); [void]$S.bodies.Add(@{ path = $path; text = $text }); try { $json = $text | ConvertFrom-Json } catch { } }
      if ($path -eq '/api/auth/login') {
        if ($json.password -ne 'right') { Send $ctx 401 @{ error = 'Invalid credentials' }; continue }
        Send $ctx 200 @{ token = 'T'; user = @{ id = 5; name = 'Test Accueil'; permissions = @($S.perms) } }; continue
      }
      if ($S.expire -or $req.Headers['Authorization'] -ne 'Bearer T') { Send $ctx 401 @{ error = 'Invalid token' }; continue }
      if ($path -eq '/api/pacs/export/patient') {
        if ($req.QueryString['chart_no'] -ne '26-00001') { Send $ctx 404 @{ ok = $false; code = 'NO_PATIENT'; error = 'No such patient' }; continue }
        Send $ctx 200 @{ ok = $true; patient = @{ id = 1; chart_no = '26-00001'; last_name = 'RAKOTO'; first_name = 'Jean'; gender = $S.gender; date_of_birth = $S.birth }; clinic = @{ name = 'Test' }; exams = @(); server = ''; max_exams = 20 }; continue
      }
      if ($path -like '/api/pacs/import/*' -and $S.noImport) { Send $ctx 404 @{ error = 'Not found' }; continue }
      if ($path -eq '/api/pacs/import/patient') {
        if ($req.QueryString['chart_no'] -ne '26-00001') { Send $ctx 404 @{ ok = $false; code = 'NO_PATIENT'; error = 'No such patient' }; continue }
        Send $ctx 200 @{ ok = $true; patient = @{ id = 1; chart_no = '26-00001'; last_name = 'RAKOTO'; first_name = 'Jean'; gender = $S.gender; date_of_birth = $S.birth }
          server = $S.server; free_bytes = $S.free; spare_bytes = 5GB; max_file_bytes = $S.maxFile; warn_bytes = $S.warn; imported = @() }; continue
      }
      if ($path -eq '/api/pacs/import/check') {
        $out = @(foreach ($u in $json.studies) { $st = [string]$S.states[$u]; if ($S.done[$u]) { $st = 'HERE' }; if ($st -eq 'HERE') { @{ study_uid = $u; state = 'HERE'; imported_at = '2026-09-30' } } else { @{ study_uid = $u; state = $st } } })
        Send $ctx 200 @{ ok = $true; studies = $out }; continue
      }
      if ($path -eq '/api/pacs/import/begin') {
        $u = [string]$json.source.study_uid
        if ($S.done[$u]) { Send $ctx 409 @{ ok = $false; code = 'HERE'; error = 'Already imported'; state = 'HERE'; imported_at = '2026-10-02' }; continue }
        $id = $S.nextId; $S.nextId = $id + 1
        $S.imports["$id"] = @{ uid = $u; files = [int]$json.files; received = 0; state = 'started'; sops = @{} }
        Send $ctx 200 @{ ok = $true; import_id = $id; study_uid = "1.2.826.0.1.3680043.9.7308.$id"; accession_no = "EXT-$id" }; continue
      }
      if ($path -match '^/api/pacs/import/(\d+)/(instance|finish|cancel)$') {
        $imp = $S.imports[$Matches[1]]; $what = $Matches[2]
        if (-not $imp) { Send $ctx 404 @{ ok = $false; code = 'NOT_FOUND'; error = 'No such import' }; continue }
        if ($imp.state -ne 'started') { Send $ctx 409 @{ ok = $false; code = 'CLOSED'; error = 'Closed'; state = $imp.state }; continue }
        if ($what -eq 'instance') {
          $S.putCount = $S.putCount + 1
          if ($S.slow) { Start-Sleep -Milliseconds $S.slow }
          $dicm = $raw.Length -gt 132 -and [Text.Encoding]::ASCII.GetString($raw, 128, 4) -eq 'DICM'
          $hash = [BitConverter]::ToString($sha.ComputeHash($raw)).Replace('-', '')
          [void]$S.puts.Add(@{ id = $Matches[1]; bytes = $raw.Length; sha = $hash; dicm = $dicm; type = $req.ContentType; length = $req.ContentLength64 })
          if ($S.failPut -gt 0 -and $S.putCount -eq $S.failPut) { $S.failPut = 0; Send $ctx 409 @{ ok = $false; code = $S.failCode; error = 'refused by the test' }; continue }
          if (-not $dicm) { Send $ctx 409 @{ ok = $false; code = 'NOT_DICOM'; error = 'Not DICOM' }; continue }
          if ([Text.Encoding]::ASCII.GetString($raw).IndexOf($imp.uid) -lt 0) { Send $ctx 409 @{ ok = $false; code = 'NOT_OF_STUDY'; error = 'Not of this study' }; continue }
          $again = [bool]$imp.sops[$hash]; if (-not $again) { $imp.sops[$hash] = $true; $imp.received = $imp.received + 1 }
          Send $ctx 200 @{ ok = $true; received = $imp.received; again = $again }; continue
        }
        if ($what -eq 'finish') {
          if ($imp.received -ne $imp.files) { Send $ctx 409 @{ ok = $false; code = 'INCOMPLETE'; error = 'Count differs'; on_server = $imp.received; received = $imp.received; announced = $imp.files }; continue }
          $imp.state = 'done'; $S.done[$imp.uid] = $true
          Send $ctx 200 @{ ok = $true; import_id = [int]$Matches[1]; images = $imp.received; undrawn = @() }; continue
        }
        $imp.state = 'rolled-back'; Send $ctx 200 @{ ok = $true; state = 'rolled-back' }; continue
      }
      Send $ctx 404 @{ error = 'Not found' }
      } catch { [void]$S.calls.Add('(request broken off)'); try { $ctx.Response.Abort() } catch { } }
    }
  } catch { $S.error = "$_" }
  finally { try { $l.Stop(); $l.Close() } catch { } }
}
$rs = [runspacefactory]::CreateRunspace(); $rs.Open()
$ps = [powershell]::Create(); $ps.Runspace = $rs; [void]$ps.AddScript($serverScript).AddArgument($S); $handle = $ps.BeginInvoke()
$until = (Get-Date).AddSeconds(10); while (-not $S.ready -and -not $S.error -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 50 }
if (-not $S.ready) { throw "the stand-in EMR did not start: $($S.error)" }
$Emr = "http://127.0.0.1:$port"
function Calls([string]$like) { @($S.calls | Where-Object { $_ -like $like }).Count }
function Reset { $S.calls.Clear(); $S.bodies.Clear(); $S.puts.Clear(); $script:said.Clear(); $script:asked = $null }
function Body([string]$path) { $b = @($S.bodies | Where-Object { $_.path -eq $path }); if ($b.Count) { $b[$b.Count - 1].text | ConvertFrom-Json } }

# the person at the window, played by the test
[Bethesda.Cd.Ask]::Message = [Action[string, string]] { param($text, $kind) $script:said.Add("[$kind] $text") }
[Bethesda.Cd.Ask]::Confirm = [Func[string, bool]] { param($text) $script:said.Add("[ask] $text"); [bool]$script:answer }
[Bethesda.Cd.Ask]::Source = [Func[string, string]] { param($start) '' }
[Bethesda.Cd.Ask]::SamePatient = [Func[Bethesda.Cd.ConfirmInfo, bool]] { param($info) $script:asked = $info; [bool]$script:same }
[Bethesda.Cd.Texts]::Lang = $Lang
$ini = Join-Path $work 'test.ini'
$form = $null
try {
  $form = New-Object Bethesda.Cd.MainForm([Bethesda.Cd.Config]::Read($ini)); $form.Show(); [Windows.Forms.Application]::DoEvents()
  function Shot([string]$name) {
    if (-not $Shots) { return }
    [Windows.Forms.Application]::DoEvents()
    $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height); $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bmp.Save((Join-Path $Shots "bethesda-cd-import-$Lang-$name.png"), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  }
  function SignIn { $form.Url.Text = $Emr; $form.LoginBox.Text = 'accueil'; $form.Password.Text = 'right'; $form.Login() }
  function Row([string]$uid) { foreach ($r in $form.ImportGrid.Rows) { if ($r.Tag.Uid -eq $uid) { return $r } } }
  function Tick([string]$uid) { (Row $uid).Cells[0].Value = $true; [Windows.Forms.Application]::DoEvents(); $form.UpdateImport() }

  '1. who may do what'
  $S.perms = @('lab'); $ok = SignIn
  Check '  an account without Consultation, Payment or Registration: not let in' (-not $ok -and $form.LoginPanel.Visible -and $form.LoginMsg.Text.Length -gt 5) $form.LoginMsg.Text
  $S.perms = @('registration'); $ok = SignIn
  Check '  a registration account: let in, and shown only "bring in"' ($ok -and $form.MainPanel.Visible -and $form.Mode -eq 'import' -and -not $form.ModeExport.Visible -and $form.ImportPanel.Visible -and -not $form.ExportPanel.Visible)
  $form.SetMode('export')
  Check '  ... it cannot switch to "copy out"' ($form.Mode -eq 'import')
  Shot 'empty'
  $form.Logout(''); $S.perms = @('consultation'); $ok = SignIn
  Check '  a consultation account: both ways, "copy out" first' ($ok -and $form.Mode -eq 'export' -and $form.ModeExport.Visible -and $form.ExportPanel.Visible)
  Shot 'both-ways'
  $form.SetMode('import')
  Check '  ... and "bring in" at a click' ($form.Mode -eq 'import' -and $form.ImportPanel.Visible -and -not $form.ExportPanel.Visible)
  $form.Logout(''); $S.perms = @('registration'); [void](SignIn)

  '2. the patient'
  Check '  before a chart number: the button is off and the window says what to do first' (-not $form.ImportButton.Enabled -and $form.ImportSelection.Text.Length -gt 5) $form.ImportSelection.Text
  Reset; $form.Chart.Text = 'no-such-chart'; $ok = $form.Search()
  Check '  unknown chart number: said in the patient line' (-not $ok -and $form.PatientLine.Text.Length -gt 5 -and $null -eq $form.ImportInfo) $form.PatientLine.Text
  Reset; $form.Chart.Text = '26-00001'; $ok = $form.Search()
  Check '  found: the patient line; the copy-out question is not asked for a registration account' ($ok -and $form.PatientLine.Text -match 'RAKOTO' -and (Calls 'GET /api/pacs/import/patient') -eq 1 -and (Calls '*export*') -eq 0) $form.PatientLine.Text

  '3. the disc'
  Reset; $ok = $form.LoadSource($disc)
  $src = $form.Source
  Check '  two exams, five images; the most recent first' ($ok -and $src.Studies.Count -eq 2 -and $src.FileCount -eq 5 -and $src.Studies[0].Uid -eq $A -and $src.Studies[0].Files.Count -eq 3) "$($src.Studies.Count) exams, $($src.FileCount) files"
  Check '  the viewer program, its library, AUTORUN.INF, the note and the picture are not opened; the one stray file is counted as "not an image"' ($src.NotImages -eq 1) "$($src.NotImages)"
  $a0 = $src.Studies[0]
  Check '  what the disc says of the patient - accents kept - and of the exam' ($a0.PatientShown -eq "$([char]0xC9)SSAI H$([char]0xE9)l$([char]0xE8)ne" -and $a0.PatientId -eq 'H-00340406' -and $a0.BirthDate -eq '19850412' -and $a0.Sex -eq 'F' -and $a0.Institution -eq 'HJRA' -and $a0.Modality -eq 'CT' -and $a0.Description -eq 'ABDOMEN AVEC CONTRASTE' -and $a0.DateShown -eq '2026-08-14') "$($a0.PatientShown) $($a0.Institution) $($a0.Modality)"
  $sum = 0; Get-ChildItem (Join-Path $disc 'DICOM\ST1') -File | ForEach-Object { $sum += $_.Length }
  Check '  its size is the size of its files' ($a0.Bytes -eq $sum) "$($a0.Bytes)"
  $chk = Body '/api/pacs/import/check'
  Check '  the EMR is asked about both exams, for this patient' ((Calls 'POST /api/pacs/import/check') -eq 1 -and $chk.patient_id -eq 1 -and @($chk.studies).Count -eq 2 -and $chk.studies -contains $A -and $chk.studies -contains $B)
  Check '  the lines: the source, whose disc it is; both exams can be ticked' ($form.SourceLine.Text -match '2' -and $form.DiscLine.Text -match 'H-00340406' -and $form.DiscLine.Text -match '1985-04-12' -and $form.ImportGrid.Rows.Count -eq 2 -and -not (Row $A).Cells[0].ReadOnly -and -not (Row $B).Cells[0].ReadOnly) $form.DiscLine.Text
  $S.states[$B] = 'HERE'; $form.CheckSource(); $form.FillImportGrid()
  Check '  an exam the EMR already has for this patient: cannot be ticked, and says since when' ((Row $B).Cells[0].ReadOnly -and [string](Row $B).Cells[8].Value -match '2026-09-30') ([string](Row $B).Cells[8].Value)
  (Row $B).Cells[0].Value = $true; Tick $A
  Check '  one ticked (a tick forced on the refused one does not count): 3 images, the button is on, the room is shown' ($form.ChosenStudies().Count -eq 1 -and $form.ImportSelection.Text -match '(?<!\d)3(?!\d)' -and $form.ImportButton.Enabled -and $form.RoomLine.Text.Length -gt 5) "$($form.ImportSelection.Text) | $($form.RoomLine.Text)"
  (Row $B).Cells[0].Value = $false                    # (the picture shows the window as a person sees it)
  Shot 'chosen'

  '4. the question, answered no'
  Reset; $script:same = $false; $r = $form.Import()
  Check '  asked, with the disc beside the chart; nothing is sent' (-not $r.Ok -and $r.Code -eq 'CANCELLED_BY_USER' -and $script:asked -and $script:asked.ChartName -eq 'RAKOTO Jean' -and $script:asked.DiscId -eq 'H-00340406' -and $script:asked.Exams.Count -eq 1 -and (Calls '*begin') -eq 0 -and (Calls 'PUT*') -eq 0 -and -not $form.Busy)
  Check '  the same day of birth and sex: not marked as different' (-not $script:asked.BirthDiffers -and -not $script:asked.SexDiffers -and -not $script:asked.Differs)

  '5. brought in'
  Reset; $script:same = $true; Tick $A
  $shown = New-Object Collections.Generic.List[string]; $form.add_StatusShown([Action[string, int]] { param($text, $percent) $shown.Add($text) })
  $r = $form.Import()
  $bg = Body '/api/pacs/import/begin'
  Check '  the exam is announced as it is on the disc: files, size, whose, where from' ($bg.patient_id -eq 1 -and $bg.files -eq 3 -and $bg.bytes -eq $sum -and $bg.source.study_uid -eq $A -and $bg.source.patient_id -eq 'H-00340406' -and $bg.source.patient_name -eq $name -and $bg.source.birth_date -eq '19850412' -and $bg.source.sex -eq 'F' -and $bg.source.institution -eq 'HJRA' -and $bg.source.study_date -eq '20260814' -and $bg.source.modality -eq 'CT' -and $bg.source.accession -eq 'ACC-A' -and $bg.source.description -eq 'ABDOMEN AVEC CONTRASTE') ($bg.source.patient_name)
  Check '  ... with what the person confirmed' ($bg.confirm.birth_differs -eq $false -and $bg.confirm.sex_differs -eq $false)
  $sent = @($S.puts); $hashes = @(Get-ChildItem (Join-Path $disc 'DICOM\ST1') -File | ForEach-Object { Sha $_.FullName })
  Check '  three files sent, each as it is on the disc - byte for byte, as application/dicom, with its length' ($sent.Count -eq 3 -and @($sent | Where-Object { $_.dicm -and $_.type -eq 'application/dicom' -and $_.length -eq $_.bytes -and $hashes -contains $_.sha }).Count -eq 3 -and @($sent | ForEach-Object { $_.sha } | Sort-Object -Unique).Count -eq 3)
  Check '  one after the other: begin, the files, finish - and no cancel' ((($S.calls | Where-Object { $_ -match 'begin|instance|finish|cancel' }) -join ' ') -match '^POST \S+begin( PUT \S+instance){3} POST \S+finish$')
  Check '  it ends well: 1 exam, 3 images, said once; nothing left busy' ($r.Ok -and $r.Imported -eq 1 -and $r.Images -eq 3 -and $r.Failed -eq 0 -and -not $form.Busy -and $script:said.Count -eq 1 -and $script:said[0] -match '^\[info\]' -and $script:said[0] -match '(?<!\d)3(?!\d)' -and $script:said[0] -match 'RAKOTO') $script:said[0]
  Check '  while it worked the window said how far it was' (@($shown | Where-Object { $_ -match '3' }).Count -ge 3) "$($shown.Count) lines"
  Check '  afterwards the list reads the exam as already here; nothing is ticked' ((Row $A).Cells[0].ReadOnly -and $form.ChosenStudies().Count -eq 0 -and -not $form.ImportButton.Enabled) ([string](Row $A).Cells[8].Value)
  Shot 'done'

  '6. a day of birth and a sex that differ'
  $S.done.Clear(); $S.states.Clear(); $S.birth = '1990-01-01'; $S.gender = 'M'
  Reset; [void]$form.Search(); Tick $A; $r = $form.Import()
  $bg = Body '/api/pacs/import/begin'
  Check '  shown as different in the question, and the EMR is told the person said "all the same"' ($r.Ok -and $script:asked.BirthDiffers -and $script:asked.SexDiffers -and $script:asked.ChartBirth -eq '1990-01-01' -and $script:asked.DiscBirth -eq '1985-04-12' -and $bg.confirm.birth_differs -eq $true -and $bg.confirm.sex_differs -eq $true)
  $S.birth = '1985-04-12'; $S.gender = 'F'

  '7. the real question window'
  $info = New-Object Bethesda.Cd.ConfirmInfo; $info.DiscName = 'X'; $info.ChartName = 'Y'; $info.DiscBirth = '1985-04-12'; $info.ChartBirth = '1990-01-01'; $info.BirthDiffers = $true; $info.Exams.Add('HJRA - CT')
  $dlg = New-Object Bethesda.Cd.ImportConfirmForm($info); $dlg.Show(); [Windows.Forms.Application]::DoEvents()
  $off = -not $dlg.Go.Enabled; $red = $dlg.Sure.ForeColor.ToArgb() -eq [Drawing.Color]::Firebrick.ToArgb(); $dlg.Sure.Checked = $true; [Windows.Forms.Application]::DoEvents()
  Check '  its button is off until the box is ticked; with a difference the sentence is the "all the same" one, in red' ($off -and $dlg.Go.Enabled -and $red -and $dlg.Sure.Text -eq [Bethesda.Cd.Texts]::Get('cfCheckDiffer') -and $dlg.Sure.Text -ne [Bethesda.Cd.Texts]::Get('cfCheck')) $dlg.Sure.Text
  if ($Shots) { $bmp = New-Object Drawing.Bitmap($dlg.Width, $dlg.Height); $dlg.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $dlg.Width, $dlg.Height))); $bmp.Save((Join-Path $Shots "bethesda-cd-import-$Lang-confirm.png"), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose() }
  $dlg.Close()

  '8. a file the EMR refuses'
  $S.done.Clear(); Reset; [void]$form.Search(); Tick $A
  $S.putCount = 0; $S.failPut = 2; $S.failCode = 'NOT_OF_STUDY'; $r = $form.Import()
  $cancel = Body ('/api/pacs/import/' + ($S.nextId - 1) + '/cancel')
  Check '  the exam is given up and taken back (cancel, with the reason); said; not in the chart' (-not $r.Ok -and $r.Imported -eq 0 -and $r.Failed -eq 1 -and (Calls '*cancel') -eq 1 -and (Calls '*finish') -eq 0 -and $cancel.reason -eq 'NOT_OF_STUDY' -and $script:said.Count -eq 1 -and $script:said[0] -match '^\[error\]' -and -not $form.Busy) $script:said[0]

  '9. the connection cut once'
  Reset; [void]$form.Search(); Tick $A
  $S.putCount = 0; $S.cutPut = 2; $r = $form.Import()
  Check '  the file is sent again and the exam goes in' ($r.Ok -and $r.Images -eq 3 -and (Calls '(connection cut)') -eq 1 -and (Calls 'PUT*') -eq 4 -and (Calls '*cancel') -eq 0) "$(Calls 'PUT*') PUTs"

  '10. cancelled by the person'
  $S.done.Clear(); Reset; [void]$form.Search(); Tick $A
  $S.slow = 150; $script:pressed = $false
  $press = [Action[string, int]] { param($text, $percent) if (-not $script:pressed -and @($S.puts).Count -ge 1) { $script:pressed = $true; $form.StopButton.PerformClick() } }
  $form.add_StatusShown($press); $r = $form.Import(); $form.remove_StatusShown($press); $S.slow = 0
  $cancel = Body ('/api/pacs/import/' + ($S.nextId - 1) + '/cancel')
  Check '  the button stops the sending; the EMR is told to take back what it got; said; nothing in the chart' ($script:pressed -and $r.Cancelled -and -not $r.Ok -and $r.Imported -eq 0 -and (Calls '*cancel') -eq 1 -and (Calls '*finish') -eq 0 -and @($S.puts).Count -lt 3 -and $cancel.reason -match 'user' -and $script:said.Count -eq 1 -and -not $form.Busy -and -not $form.StopButton.Enabled) "$(@($S.puts).Count) file(s) had gone; $($script:said[0])"

  '11. limits the EMR gives'
  $S.maxFile = 45000; Reset; [void]$form.Search()
  Check '  an exam with a file over the limit cannot be ticked, and says the limit; the other one can' ((Row $A).Cells[0].ReadOnly -and [string](Row $A).Cells[8].Value -match '\d' -and -not (Row $B).Cells[0].ReadOnly) ([string](Row $A).Cells[8].Value)
  $S.maxFile = 1GB; $S.free = 5GB + 100000; Reset; [void]$form.Search(); Tick $A
  Check '  not enough room on the image server (twice the size and the reserve): the button is off, the line says so' (-not $form.ImportButton.Enabled -and $form.RoomLine.ForeColor.ToArgb() -eq [Drawing.Color]::Firebrick.ToArgb()) $form.RoomLine.Text
  $r = $form.Import()
  Check '  ... and nothing is sent even if asked' (-not $r.Ok -and $r.Code -eq 'NO_ROOM' -and (Calls '*begin') -eq 0)
  $S.free = 500GB; $S.warn = 1000; Reset; [void]$form.Search(); Tick $A; $script:answer = $false; $r = $form.Import()
  Check '  a large exam: a warning first; answered no, nothing is sent' ($r.Code -eq 'CANCELLED_BY_USER' -and $script:said.Count -eq 1 -and $script:said[0] -match '^\[ask\]' -and (Calls '*begin') -eq 0) $script:said[0]
  $S.warn = 2GB; $script:answer = $true
  $S.server = 'UNREACHABLE'; Reset; [void]$form.Search(); Tick $A
  Check '  the image server does not answer: said, the button is off, the EMR is not asked about the exams' (-not $form.ImportButton.Enabled -and $form.ImportSelection.ForeColor.ToArgb() -eq [Drawing.Color]::Firebrick.ToArgb() -and (Calls '*check') -eq 0) $form.ImportSelection.Text
  $script:said.Clear(); $r = $form.Import()
  Check '  ... and asked anyway: said, no question about the patient, nothing sent' (-not $r.Ok -and $r.Code -eq 'UNREACHABLE' -and $null -eq $script:asked -and $script:said.Count -eq 1 -and (Calls '*begin') -eq 0) $script:said[0]
  $S.server = ''

  '12. a disc of two patients, a folder without images'
  Reset; [void]$form.Search(); $ok = $form.LoadSource($two)
  Check '  two patients on the disc: said in red' ($ok -and $form.Source.Studies.Count -eq 2 -and $form.DiscLine.ForeColor.ToArgb() -eq [Drawing.Color]::Firebrick.ToArgb() -and $form.DiscLine.Text -match '2')  $form.DiscLine.Text
  foreach ($row in $form.ImportGrid.Rows) { $row.Cells[0].Value = $true }; [Windows.Forms.Application]::DoEvents(); $form.UpdateImport()
  $script:said.Clear(); $r = $form.Import()
  Check '  both ticked: refused before the question - one patient at a time' (-not $r.Ok -and $r.Code -eq 'SEVERAL_PATIENTS' -and (Calls '*begin') -eq 0 -and $script:said.Count -eq 1) $script:said[0]
  $ok = $form.LoadSource($empty)
  Check '  a folder with no DICOM image: said, nothing to tick' ($ok -and $form.Source.Studies.Count -eq 0 -and $form.ImportGrid.Rows.Count -eq 0 -and $form.SourceLine.Text.Length -gt 10 -and -not $form.ImportButton.Enabled) $form.SourceLine.Text

  '13. a file that can no longer be read'
  $copy = Join-Path $work 'usb'; Copy-Item -LiteralPath $disc -Destination $copy -Recurse
  $S.done.Clear(); Reset; [void]$form.Search(); [void]$form.LoadSource($copy); Tick $A
  Remove-Item -LiteralPath (Join-Path $copy 'DICOM\ST1\IM2')                    # the stick is pulled out, the disc is scratched
  $r = $form.Import()
  Check '  said, the exam is taken back, nothing in the chart' (-not $r.Ok -and $r.Imported -eq 0 -and (Calls '*cancel') -eq 1 -and (Calls '*finish') -eq 0 -and $script:said[0] -match '^\[error\]') $script:said[0]

  '14. an EMR that cannot bring in yet, a session that has ended'
  $S.noImport = $true; Reset; $ok = $form.Search()
  Check '  an older EMR: the window says it cannot bring in' (-not $ok -and $form.PatientLine.Text.Length -gt 10 -and -not $form.ImportButton.Enabled) $form.PatientLine.Text
  $S.noImport = $false; [void]$form.Search(); [void]$form.LoadSource($disc); $S.done.Clear(); $form.CheckSource(); $form.FillImportGrid(); Tick $A
  $S.expire = $true; Reset; $r = $form.Import()
  Check '  a token the EMR no longer accepts: back to the sign-in panel, saying so' (-not $r.Ok -and $r.Code -eq 'LOGIN' -and $form.LoginPanel.Visible -and $form.LoginMsg.Text.Length -gt 5 -and -not $form.Busy) $form.LoginMsg.Text
  $S.expire = $false

  if ($Sample) {
    '15. a disc folder with a DICOMDIR'
    [void](SignIn); $form.Chart.Text = '26-00001'; [void]$form.Search(); Reset; $ok = $form.LoadSource($Sample)
    $n = @(Get-ChildItem -LiteralPath (Join-Path $Sample 'IMAGES') -File).Count
    Check '  listed from its DICOMDIR: the exams, every image file, whose they are' ($ok -and $form.Source.FromDicomdir -and $form.Source.Studies.Count -ge 1 -and $form.Source.FileCount -eq $n -and $form.Source.Studies[0].PatientId -ne '') "$($form.Source.Studies.Count) exam(s), $($form.Source.FileCount) of $n files, $($form.Source.Studies[0].PatientShown)"
    foreach ($row in $form.ImportGrid.Rows) { if (-not $row.Cells[0].ReadOnly) { $row.Cells[0].Value = $true } }; [Windows.Forms.Application]::DoEvents(); $form.UpdateImport()
    $r = $form.Import()
    Check '  brought in: every file of it sent, each a DICOM file' ($r.Ok -and $r.Images -eq $n -and @($S.puts | Where-Object { $_.dicm }).Count -eq $n) "$($r.Images) images"
  }

  'at the end'
  $after = @{}; Get-ChildItem -LiteralPath $disc -Recurse -File | ForEach-Object { $after[$_.FullName] = Sha $_.FullName }
  Check '  the disc is as it was: no file added, changed or removed' ($after.Count -eq $before.Count -and @($before.Keys | Where-Object { $after[$_] -ne $before[$_] }).Count -eq 0)
  $t = [Bethesda.Cd.DiscFolder]::TempRoot
  Check '  nothing of the patient was written to this PC by the program' (-not (Test-Path $t) -or @(Get-ChildItem $t).Count -eq 0)
  Check '  the settings file holds no password' (-not (Test-Path $ini) -or -not ((Get-Content $ini -Raw) -match 'right'))
} finally {
  if ($form) { $form.Close(); [Windows.Forms.Application]::DoEvents() }
  $S.stop = $true; try { [void]$ps.EndInvoke($handle) } catch { }; $ps.Dispose(); $rs.Dispose()
  if ($S.error) { "the stand-in EMR failed: $($S.error)"; $script:res += $false }
  for ($i = 0; $i -lt 10 -and (Test-Path -LiteralPath $work); $i++) { try { [IO.Directory]::Delete($work, $true) } catch { Start-Sleep -Milliseconds 300 } }
}
Check 'nothing of the test is left on this PC' (-not (Test-Path -LiteralPath $work))
if ($script:res -contains $false) { "SOME FAILED $($script:res.Count)"; exit 1 } else { "ALL PASS $($script:res.Count)" }
