# Bethesda CD - "bring in a CD / USB stick" against a TEST installation of the EMR that has
# its image server (never the one the clinic works on): this script writes a made-up disc
# (a patient who does not exist, two small exams of its own making), loads the built
# Bethesda-CD.exe, signs in, brings one exam in for real, tries to bring it in again, stops
# the second one half-way, and reads back from the EMR what is in the chart.
#
#   .\import_real_test.ps1 -Emr http://127.0.0.1:9188 -Login someone -Chart 26-00001
#
# The password comes from the environment variable BETHESDA_CD_TEST_PASSWORD (it is never
# written to a file by this script, and not printed). The account needs Registration,
# Consultation or Payment.
#
# WHAT IT LEAVES BEHIND, and only in that test EMR: one external exam of three small images
# in the chart given (made-up patient "ESSAI Import", hospital "TEST-BCD"). The script says
# which one at the end. Take it out in the EMR (Imaging - External imaging) or reset the test
# installation. Each run uses new exam numbers, so it can be run again without that.
# On this PC nothing is left: the disc is made in %TEMP% and removed.
#
#   -RealDisc D:\a\disc  also brings in the exams of that disc folder (read only) - those that the EMR
#                does not have yet, of the first patient on it. They stay in the test EMR too.
#   -OverLimit   also sends one file that is larger than the EMR allows (the window itself never
#                would: it greys such an exam), to see how the refusal arrives. It writes a file of
#                that size (zeros) in %TEMP% for the time of the test - 1 GB with the usual limit.
param(
  [Parameter(Mandatory = $true)][string]$Emr, [Parameter(Mandatory = $true)][string]$Login, [Parameter(Mandatory = $true)][string]$Chart,
  [string]$Exe = '', [ValidateSet('fr', 'ko', 'en')][string]$Lang = 'fr', [string]$Shots = '', [switch]$OverLimit, [string]$RealDisc = ''
)
$ErrorActionPreference = 'Stop'
if (-not $Exe) { $Exe = Join-Path $PSScriptRoot '..\build\Bethesda-CD.exe' }
$pw = $env:BETHESDA_CD_TEST_PASSWORD
if (-not $pw) { throw 'Set BETHESDA_CD_TEST_PASSWORD to the test account''s password first.' }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[void][Reflection.Assembly]::LoadFrom($Exe)
. (Join-Path $PSScriptRoot 'quiet_window.ps1')
. (Join-Path $PSScriptRoot 'fake_dicom.ps1')

$script:res = @(); $script:said = New-Object Collections.Generic.List[string]; $script:answer = $true; $script:same = $true; $script:asked = $null
function Check([string]$label, $good, [string]$extra = '') { $script:res += [bool]$good; '{0} {1} {2}' -f $(if ($good) { 'PASS' } else { 'FAIL' }), $label, $extra }
function Sha([string]$file) { (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }

# the made-up disc: exam A (3 small images) is brought in; exam B (8 images of 1 MB) is stopped half-way
$work = Join-Path $env:TEMP ('bethesda-cd-import-real-' + [Guid]::NewGuid().ToString('N'))
$disc = Join-Path $work 'disc'; New-Item -ItemType Directory -Path $disc | Out-Null
$run = Get-Date -Format 'yyyyMMddHHmmss'                               # new exam numbers every run
$A = "1.2.826.0.1.3680043.8.498.$run.1"; $B = "1.2.826.0.1.3680043.8.498.$run.2"
$name = 'ESSAI^Import'; $discId = 'BCD-TEST'; $birth = '19010203'
foreach ($i in 1..3) { [FakeDicom]::Write((Join-Path $disc "DICOM\ST1\IM$i"), $A, "$A.1", "$A.1.$i", $discId, $name, $birth, 'O', 'TEST-BCD', '20260814', "ESSAI BETHESDA CD $run", 'OT', "T$run", 40000 + 3000 * $i) }
foreach ($i in 1..8) { [FakeDicom]::Write((Join-Path $disc "DICOM\ST2\IM$i"), $B, "$B.1", "$B.1.$i", $discId, $name, $birth, 'O', 'TEST-BCD', '20250311', "ESSAI BETHESDA CD $run (2)", 'OT', '', 1MB) }
[IO.File]::WriteAllBytes((Join-Path $disc 'VIEWER.EXE'), [byte[]](0x4D, 0x5A) + (New-Object byte[] 4000))        # what else lies on such a disc
[IO.File]::WriteAllText((Join-Path $disc 'AUTORUN.INF'), "[autorun]`r`nopen=VIEWER.EXE`r`n")
$before = @{}; Get-ChildItem -LiteralPath $disc -Recurse -File | ForEach-Object { $before[$_.FullName] = Sha $_.FullName }
$sumA = 0; Get-ChildItem (Join-Path $disc 'DICOM\ST1') -File | ForEach-Object { $sumA += $_.Length }

# the person at the window, played by the test
[Bethesda.Cd.Ask]::Message = [Action[string, string]] { param($text, $kind) $script:said.Add("[$kind] $text") }
[Bethesda.Cd.Ask]::Confirm = [Func[string, bool]] { param($text) $script:said.Add("[ask] $text"); [bool]$script:answer }
[Bethesda.Cd.Ask]::Source = [Func[string, string]] { param($start) '' }
[Bethesda.Cd.Ask]::SamePatient = [Func[Bethesda.Cd.ConfirmInfo, bool]] { param($info) $script:asked = $info; [bool]$script:same }
[Bethesda.Cd.Texts]::Lang = $Lang
$ini = Join-Path $work 'test.ini'
$form = $null; $left = @()
try {
  $form = New-Object Bethesda.Cd.MainForm([Bethesda.Cd.Config]::Read($ini)); Show-Quietly $form
  function Shot([string]$name) {
    if (-not $Shots) { return }
    [Windows.Forms.Application]::DoEvents()
    $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height); $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bmp.Save((Join-Path $Shots "bethesda-cd-import-real-$Lang-$name.png"), [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
  }
  function Row([string]$uid) { foreach ($r in $form.ImportGrid.Rows) { if ($r.Tag.Uid -eq $uid) { return $r } } }
  function Tick([string]$uid) { (Row $uid).Cells[0].Value = $true; [Windows.Forms.Application]::DoEvents(); $form.UpdateImport() }
  function Brought { @($form.ImportInfo['imported']) }                       # what the EMR says was brought in for this patient
  function Ours { @(Brought | Where-Object { $_['description'] -eq "ESSAI BETHESDA CD $run" }) }
  $v = [Diagnostics.FileVersionInfo]::GetVersionInfo($Exe)
  "$($v.ProductName) $($v.ProductVersion)  ($Exe)  ->  $Emr"

  '1. signing in'
  $form.Url.Text = $Emr; $form.LoginBox.Text = $Login; $form.Password.Text = $pw
  $ok = $form.Login()
  Check '  let in' ($ok -and $form.MainPanel.Visible) $form.LoginMsg.Text
  if (-not $ok) { throw 'not signed in - nothing else can be checked' }
  "  this account: copy out = $($form.Emr.CanExport), bring in = $($form.Emr.CanImport)"
  $form.SetMode('import')
  Check '  the "bring in" way is shown' ($form.Mode -eq 'import' -and $form.ImportPanel.Visible)

  '2. the patient and the image server'
  $form.Chart.Text = $Chart; $ok = $form.Search()
  Check '  the chart is found' ($ok -and $null -ne $form.ImportInfo -and $form.PatientLine.Text -match [regex]::Escape($Chart)) $form.PatientLine.Text
  if (-not $ok -or $null -eq $form.ImportInfo) { throw 'no patient - nothing else can be checked' }
  $server = [Bethesda.Cd.J]::Str($form.ImportInfo, 'server')
  Check '  the image server answers and is the EMR''s own' ($server -eq '' -and $form.ImportError -eq '') "server='$server' $($form.ImportError)"
  if ($server -ne '') { throw 'this test EMR has no image server to bring images into' }
  $had = @(Brought).Count
  "  brought in before for this patient: $had"

  '3. the disc'
  $ok = $form.LoadSource($disc)
  Check '  two exams, eleven images; the program beside them is not counted' ($ok -and $form.Source.Studies.Count -eq 2 -and $form.Source.FileCount -eq 11 -and $form.Source.NotImages -eq 0) "$($form.Source.Studies.Count) exams, $($form.Source.FileCount) files"
  Check '  the EMR knows neither: both can be ticked' ($form.CheckError -eq '' -and -not (Row $A).Cells[0].ReadOnly -and -not (Row $B).Cells[0].ReadOnly) "$($form.CheckError) A='$((Row $A).Tag.State)' B='$((Row $B).Tag.State)'"
  Tick $A
  Check '  one ticked: the button is on, the room on the image server is shown' ($form.ChosenStudies().Count -eq 1 -and $form.ImportButton.Enabled -and $form.RoomLine.Text.Length -gt 5) "$($form.ImportSelection.Text) | $($form.RoomLine.Text)"
  Shot 'chosen'

  '4. one exam brought in'
  $shown = New-Object Collections.Generic.List[string]; $note = [Action[string, int]] { param($text, $percent) $shown.Add($text) }
  $form.add_StatusShown($note); $script:said.Clear(); $r = $form.Import(); $form.remove_StatusShown($note)
  Check '  the person was asked whether it is the same patient, with the disc beside the chart' ($null -ne $script:asked -and $script:asked.DiscId -eq $discId -and $script:asked.ChartNo -eq $Chart) "birth differs: $($script:asked.BirthDiffers), sex differs: $($script:asked.SexDiffers)"
  Check '  it ends well: 1 exam, 3 images; nothing left busy' ($r.Ok -and $r.Imported -eq 1 -and $r.Images -eq 3 -and $r.Failed -eq 0 -and -not $form.Busy) "$($r.Code) $($r.Errors -join ' | ') $($script:said -join ' | ')"
  "  the window said: $($script:said -join ' | ')"
  if ($r.Undrawn.Count) { "  images the EMR could not draw: $($r.Undrawn -join ', ')" }
  [void]$form.Search(); $mine = @(Ours)
  Check '  the EMR lists it for this patient: 3 images, the size of the files, where it came from' (@(Brought).Count -eq $had + 1 -and $mine.Count -eq 1 -and [int]$mine[0]['image_count'] -eq 3 -and [long]$mine[0]['bytes'] -eq $sumA -and $mine[0]['institution'] -eq 'TEST-BCD' -and $mine[0]['came_as']['patient_id'] -eq $discId) "$(@(Brought).Count) listed; ours: $($mine.Count)"
  if ($mine.Count) {
    $left += "import $($mine[0]['id']), '$($mine[0]['description'])', study $A"
    Check '  ... with what the person confirmed about the day of birth and the sex' ([bool]$mine[0]['birth_differed'] -eq [bool]$script:asked.BirthDiffers -and [bool]$mine[0]['sex_differed'] -eq [bool]$script:asked.SexDiffers) "birth_differed=$($mine[0]['birth_differed']) sex_differed=$($mine[0]['sex_differed'])"
  }
  Shot 'done'

  '5. the same exam again'
  $form.CheckSource(); $form.FillImportGrid()
  Check '  it cannot be ticked, and the list says since when' ((Row $A).Cells[0].ReadOnly -and (Row $A).Tag.State -eq 'HERE' -and [string](Row $A).Cells[8].Value -match '\d{4}-\d{2}-\d{2}') ([string](Row $A).Cells[8].Value)
  (Row $A).Cells[0].Value = $true; [Windows.Forms.Application]::DoEvents(); $form.UpdateImport()
  Check '  a tick forced on it does not count' ($form.ChosenStudies().Count -eq 0 -and -not $form.ImportButton.Enabled)
  $again = $form.Emr.Post('/api/pacs/import/begin', @{ patient_id = [int][Bethesda.Cd.J]::Long([Bethesda.Cd.J]::Dict($form.ImportInfo, 'patient'), 'id'); files = 3; bytes = $sumA; source = [Bethesda.Cd.ImportDisc]::Origin((Row $A).Tag); confirm = @{ birth_differs = $false; sex_differs = $false } }, 30)
  Check '  asked all the same (without the window): the EMR refuses it' (-not $again.Ok -and $again.Code -eq 'HERE') "$($again.Status) $($again.Code)"
  (Row $A).Cells[0].Value = $false

  '6. stopped by the person half-way'
  Tick $B; $script:said.Clear(); $script:pressed = $false; $script:sentWhenPressed = ''; $script:asked = $null
  # pressed once the question has been answered and at least one of the eight files has gone (12 % a file)
  $press = [Action[string, int]] { param($text, $percent) if (-not $script:pressed -and $null -ne $script:asked -and $percent -ge 12) { $script:pressed = $true; $script:sentWhenPressed = "$text ($percent %)"; $form.StopButton.PerformClick() } }
  $form.add_StatusShown($press); $r = $form.Import(); $form.remove_StatusShown($press)
  Check '  the button stops the sending; nothing is counted as brought in; said' ($script:pressed -and $r.Cancelled -and -not $r.Ok -and $r.Imported -eq 0 -and -not $form.Busy -and $script:said.Count -eq 1) "pressed at: $($script:sentWhenPressed) | $($r.Code) | $($script:said -join ' | ')"
  [void]$form.Search(); $form.CheckSource(); $form.FillImportGrid()
  Check '  the EMR took back what it had got: not in the chart, and the exam can be brought in again' (@(Brought).Count -eq $had + 1 -and (Row $B).Tag.State -eq '' -and -not (Row $B).Cells[0].ReadOnly) "listed: $(@(Brought).Count); state of the stopped exam: '$((Row $B).Tag.State)'"

  if ($OverLimit) {
    '7. a file over the limit, sent all the same'
    $max = [Bethesda.Cd.J]::Long($form.ImportInfo, 'max_file_bytes'); $room = (Get-PSDrive ($work.Substring(0, 1))).Free
    if ($max -le 0 -or $max -gt 4GB -or $room -lt ($max + 2GB)) { "  skipped: limit $max bytes, free on this PC's temp drive $room bytes" }
    else {
      $big = Join-Path $work 'over.bin'; $fs = [IO.File]::Create($big); $fs.SetLength($max + 1MB); $fs.Close()
      $pid0 = [int][Bethesda.Cd.J]::Long([Bethesda.Cd.J]::Dict($form.ImportInfo, 'patient'), 'id')
      $bg = $form.Emr.Post('/api/pacs/import/begin', @{ patient_id = $pid0; files = (Row $B).Tag.Files.Count; bytes = (Row $B).Tag.Bytes; source = [Bethesda.Cd.ImportDisc]::Origin((Row $B).Tag); confirm = @{ birth_differs = $true; sex_differs = $false } }, 120)
      if (-not $bg.Ok) { Check '  (an import could be opened for it)' $false "$($bg.Status) $($bg.Code)" }
      else {
        $id = [Bethesda.Cd.J]::Str($bg.Data, 'import_id'); $watch = [Diagnostics.Stopwatch]::StartNew()
        $put = $form.Emr.PutFile("/api/pacs/import/$id/instance", $big, $null, $null, 900); $watch.Stop()
        Check '  the EMR refuses it, and the program hears why (not "the connection broke")' (-not $put.Ok -and ($put.Code -eq 'TOO_BIG_FILE' -or $put.Code -eq 'HTTP_413')) "$($put.Status) $($put.Code) after $([int]$watch.Elapsed.TotalSeconds) s, $($put.Bytes) bytes sent | $($put.Error)"
        $cn = $form.Emr.Post("/api/pacs/import/$id/cancel", @{ reason = 'test: a file over the limit' }, 120)
        [void]$form.Search(); $form.CheckSource(); $form.FillImportGrid()
        Check '  the import is taken back; the exam can be brought in again' ($cn.Ok -and @(Brought).Count -eq $had + 1 -and (Row $B).Tag.State -eq '') "cancel: $($cn.Status) $($cn.Code); state: '$((Row $B).Tag.State)'"
      }
      [IO.File]::Delete($big)
    }
  }

  if ($RealDisc) {
    '8. a disc folder that was not made by this test'
    $ids = @(Brought | ForEach-Object { [int]$_['id'] })
    $ok = $form.LoadSource($RealDisc); $src = $form.Source
    Check '  read: its exams, whose they are, what the EMR knows of them' ($ok -and $src.Studies.Count -ge 1 -and $form.CheckError -eq '') "$($src.Studies.Count) exam(s), $($src.FileCount) file(s), from its DICOMDIR: $($src.FromDicomdir) | $($form.DiscLine.Text)"
    foreach ($r in $form.ImportGrid.Rows) { "    $($r.Tag.DateShown) $($r.Tag.Modality) '$($r.Tag.Description)' $($r.Tag.Files.Count) file(s) $($r.Tag.Bytes) bytes  state='$($r.Tag.State)'" }
    $free = @($form.ImportGrid.Rows | Where-Object { $_.Tag.State -eq '' -and $_.Tag.PatientKey -eq $src.Studies[0].PatientKey })
    if ($free.Count -eq 0) { '  nothing of it can be brought in (the EMR has it already, or refuses it) - nothing sent' }
    else {
      $want = 0; foreach ($r in $free) { $r.Cells[0].Value = $true; $want += $r.Tag.Files.Count }
      [Windows.Forms.Application]::DoEvents(); $form.UpdateImport(); $script:said.Clear(); $script:asked = $null
      $r = $form.Import()
      "  the question: disc '$($script:asked.DiscName)' $($script:asked.DiscBirth) $($script:asked.DiscSex) / chart '$($script:asked.ChartName)' $($script:asked.ChartBirth) $($script:asked.ChartSex) - birth differs: $($script:asked.BirthDiffers), sex differs: $($script:asked.SexDiffers)"
      Check "  brought in: $($free.Count) exam(s), $want image(s)" ($r.Ok -and $r.Imported -eq $free.Count -and $r.Images -eq $want -and $r.Failed -eq 0) "$($r.Code) imported=$($r.Imported) images=$($r.Images) failed=$($r.Failed) dropped=$($r.Dropped) | $($r.Errors -join ' | ')"
      if ($r.Undrawn.Count) { "  images the EMR could not draw: $($r.Undrawn -join ', ')" } else { '  the EMR could draw every image' }
      [void]$form.Search()
      $new = @(Brought | Where-Object { $ids -notcontains [int]$_['id'] })
      Check '  the EMR lists them for this patient' ($new.Count -eq $r.Imported) "$($new.Count) new in the list"
      foreach ($e in $new) { $left += "import $($e['id']), $($e['modality']) $($e['study_date']) '$($e['description'])', $($e['image_count']) image(s)" }
      $form.CheckSource(); $form.FillImportGrid()
      Check '  afterwards every one of them reads as already here' (@($form.ImportGrid.Rows | Where-Object { $_.Tag.State -eq '' -and $_.Tag.PatientKey -eq $src.Studies[0].PatientKey }).Count -eq 0)
    }
  }

  'at the end'
  $after = @{}; Get-ChildItem -LiteralPath $disc -Recurse -File | ForEach-Object { $after[$_.FullName] = Sha $_.FullName }
  Check '  the disc is as it was: no file added, changed or removed' ($after.Count -eq $before.Count -and @($before.Keys | Where-Object { $after[$_] -ne $before[$_] }).Count -eq 0)
  $t = [Bethesda.Cd.DiscFolder]::TempRoot
  Check '  nothing of the patient was written to this PC by the program' (-not (Test-Path $t) -or @(Get-ChildItem $t).Count -eq 0)
  Check '  the settings file holds no password' (-not (Test-Path $ini) -or -not ((Get-Content $ini -Raw) -match [regex]::Escape($pw)))
} catch {
  "STOPPED: $($_.Exception.Message)"; $script:res += $false
} finally {
  if ($form) { $form.Close(); [Windows.Forms.Application]::DoEvents() }
  for ($i = 0; $i -lt 10 -and (Test-Path -LiteralPath $work); $i++) { try { [IO.Directory]::Delete($work, $true) } catch { Start-Sleep -Milliseconds 300 } }
}
Check 'nothing of the test is left on this PC' (-not (Test-Path -LiteralPath $work))
if ($left.Count) { "LEFT IN THE TEST EMR (chart $Chart) - take them out in the EMR, or reset the test installation:"; $left | ForEach-Object { "  $_" } } else { 'Nothing was brought into the test EMR.' }
if ($script:res -contains $false) { "SOME FAILED $($script:res.Count)"; exit 1 } else { "ALL PASS $($script:res.Count)" }
