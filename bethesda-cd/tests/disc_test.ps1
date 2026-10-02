# Bethesda CD - what goes on a disc, checked without the EMR and without a person: the
# viewer, AUTORUN.INF and README.TXT put into a disc folder, the folder saved (a USB
# stick), and the disc image written - then, with -Mount, the image put in a Windows
# virtual drive and read back file by file.
#
#   .\disc_test.ps1                       (nothing to prepare: made in %TEMP% and removed)
#   .\disc_test.ps1 -Mount                also mounts the image (and always takes it out again)
#   .\disc_test.ps1 -Sample D:\some\disc  DICOMDIR and IMAGES taken from a disc folder (read only)
#                                         instead of made-up bytes - then the viewer's own
#                                         reading of the disc is checked too
#   .\disc_test.ps1 -Keep D:\folder       the image is left there as disc_test.iso (to look at)
#
# Nothing is burnt: the burner takes the very folder the image is made from.
param([string]$Exe = '', [switch]$Mount, [string]$Sample = '', [string]$Keep = '')
$ErrorActionPreference = 'Stop'
if (-not $Exe) { $Exe = Join-Path $PSScriptRoot '..\build\Bethesda-CD.exe' }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[void][Reflection.Assembly]::LoadFrom($Exe)
$script:res = @()
function Check([string]$label, $good, [string]$extra = '') { $script:res += [bool]$good; '{0} {1} {2}' -f $(if ($good) { 'PASS' } else { 'FAIL' }), $label, $extra }
function Top([string]$dir) { (Get-ChildItem -LiteralPath $dir -Name | Sort-Object) -join ',' }

$work = Join-Path $env:TEMP ('bethesda-cd-disc-test-' + [Guid]::NewGuid().ToString('N'))
$disc = Join-Path $work 'disc'; $bare = Join-Path $work 'bare'; $usb = Join-Path $work 'usb'
New-Item -ItemType Directory -Path (Join-Path $disc 'IMAGES'), $bare, $usb | Out-Null
$iso = Join-Path $work 'disc_test.iso'; $mounted = $false
try {
  # the images of the disc: a sample disc's, or made-up bytes (nothing here reads them as DICOM)
  if ($Sample) {
    Copy-Item -LiteralPath (Join-Path $Sample 'DICOMDIR') -Destination $disc
    Get-ChildItem -LiteralPath (Join-Path $Sample 'IMAGES') -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $disc 'IMAGES') }
  } else {
    $rnd = New-Object Random 7
    $bytes = New-Object byte[] 4096; $rnd.NextBytes($bytes); [IO.File]::WriteAllBytes((Join-Path $disc 'DICOMDIR'), $bytes)
    foreach ($i in 0..2) { $bytes = New-Object byte[] (200000 + 1000 * $i); $rnd.NextBytes($bytes); [IO.File]::WriteAllBytes((Join-Path $disc "IMAGES\IM$i"), $bytes) }
  }
  $images = @(Get-ChildItem -LiteralPath (Join-Path $disc 'IMAGES') -File).Count

  '1. the viewer and AUTORUN.INF'
  Check '  the program carries the viewer' ([Bethesda.Cd.DiscFolder]::HasViewer)
  Check '  no viewer on the disc: no AUTORUN.INF is written' (-not [Bethesda.Cd.DiscFolder]::WriteAutorun($disc) -and -not (Test-Path (Join-Path $disc 'AUTORUN.INF')))
  $v = [Bethesda.Cd.DiscFolder]::AddViewer($disc)
  $built = Join-Path (Split-Path -Parent $Exe) 'VIEWER.EXE'
  Check '  the viewer is put on the disc as VIEWER.EXE, byte for byte the one built with the program' ($v.Ok -and (Test-Path $built) -and (Get-FileHash (Join-Path $disc 'VIEWER.EXE')).Hash -eq (Get-FileHash $built).Hash) "$($v.Bytes) bytes"
  $wrote = [Bethesda.Cd.DiscFolder]::WriteAutorun($disc)
  $raw = [IO.File]::ReadAllBytes((Join-Path $disc 'AUTORUN.INF')); $text = [Text.Encoding]::ASCII.GetString($raw)
  $lines = $text -split "`r`n"
  Check '  with the viewer: AUTORUN.INF, plain ASCII, lines ended as Windows ends them' ($wrote -and @($raw | Where-Object { $_ -gt 126 -or ($_ -lt 32 -and $_ -ne 13 -and $_ -ne 10) }).Count -eq 0 -and $text.EndsWith("`r`n") -and -not ($text -replace "`r`n", '').Contains("`n")) "$($raw.Length) bytes"
  Check '  it names the viewer to start and the viewer''s icon, and nothing else to run' ($lines[0] -eq '[autorun]' -and $lines -contains 'open=VIEWER.EXE' -and $lines -contains 'icon=VIEWER.EXE,0' -and @($lines | Where-Object { $_ -match '^(open|shellexecute|shell\\)' }).Count -eq 1 -and @($lines | Where-Object { $_ -match '^action=.+' }).Count -eq 1) ($lines -join ' | ')
  [IO.File]::WriteAllText((Join-Path $bare 'AUTORUN.INF'), "[autorun]`r`nopen=VIEWER.EXE`r`n")
  Check '  a folder whose viewer is gone: an AUTORUN.INF left there is taken away' (-not [Bethesda.Cd.DiscFolder]::WriteAutorun($bare) -and -not (Test-Path (Join-Path $bare 'AUTORUN.INF')))

  '2. README.TXT'
  $patient = New-Object 'Collections.Generic.Dictionary[string,object]'; $patient['last_name'] = 'ESSAI'; $patient['first_name'] = 'Helene'; $patient['chart_no'] = '00-00000'
  $clinic = New-Object 'Collections.Generic.Dictionary[string,object]'; $clinic['name'] = 'Clinique Exemple'
  $exam = New-Object 'Collections.Generic.Dictionary[string,object]'; $exam['exam_date'] = '2026-10-01'; $exam['modality'] = 'US'; $exam['order_name'] = 'Abdomen'; $exam['items'] = $images
  $exams = New-Object 'Collections.Generic.List[Collections.Generic.Dictionary[string,object]]'; $exams.Add($exam)
  [Bethesda.Cd.DiscFolder]::WriteReadme($disc, $patient, $clinic, $exams, $true, (Get-Date))
  $readme = [IO.File]::ReadAllText((Join-Path $disc 'README.TXT'))
  Check '  it tells, in French and in English, to double-click VIEWER.EXE' ((($readme -split 'VIEWER\.EXE').Count - 1) -eq 2 -and $readme -notmatch 'VOIR\.EXE')
  Check '  the top of the disc: AUTORUN.INF, DICOMDIR, IMAGES, README.TXT, VIEWER.EXE' ((Top $disc) -eq 'AUTORUN.INF,DICOMDIR,IMAGES,README.TXT,VIEWER.EXE') (Top $disc)
  $files = [Bethesda.Cd.DiscFolder]::Files($disc)

  '3. saved to a folder (a USB stick)'
  $r = [Bethesda.Cd.DiscFolder]::SaveToFolder($disc, $usb, 'COPY', $null)
  Check '  every file of the disc is there, read back and the same' ($r.Ok -and $r.Files -eq ($images + 4) -and (Top $r.Path) -eq (Top $disc) -and [Bethesda.Cd.DiscFolder]::Compare($files, $r.Path).Count -eq 0) "$($r.Files) files"

  '4. the disc image'
  $job = New-Object Bethesda.Cd.DiscJob
  $job.StartIso($disc, 'IMG_00_00000', [Bethesda.Cd.DiscFolder]::FileSystems, $iso)
  $until = (Get-Date).AddSeconds(120); while ($job.State -lt 2 -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 100 }
  Check '  the image is written whole' ($job.State -eq 2 -and (Test-Path $iso) -and (Get-Item $iso).Length -eq $job.TotalBytes) "$((Get-Item $iso).Length) bytes $($job.Error)"
  # the names as they stand in the image itself (ISO 9660 keeps them in capitals, as written)
  $head = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($iso))
  Check '  the image names AUTORUN.INF and VIEWER.EXE' ($head.Contains('AUTORUN.INF') -and $head.Contains('VIEWER.EXE'))
  if ($Keep) { Copy-Item -LiteralPath $iso -Destination (Join-Path $Keep 'disc_test.iso') -Force }

  if ($Mount) {
    '5. the image in a Windows virtual drive'
    $img = Mount-DiskImage -ImagePath $iso -PassThru; $mounted = $true
    $letter = $null; $until = (Get-Date).AddSeconds(30)
    while (-not $letter -and (Get-Date) -lt $until) { $letter = ($img | Get-Volume).DriveLetter; if (-not $letter) { Start-Sleep -Milliseconds 300 } }
    if (-not $letter) { Check '  the image got a drive letter' $false }
    else {
      $rootDir = "${letter}:\"; $vol = Get-Volume -DriveLetter $letter
      Check '  Windows sees a CD: its label, its file system' ($vol.DriveType -eq 'CD-ROM' -and $vol.FileSystemLabel -eq 'IMG_00_00000') "$($vol.DriveType) $($vol.FileSystemLabel) $($vol.FileSystem)"
      Check '  the top of the disc as Windows lists it' ((Top $rootDir) -eq 'AUTORUN.INF,DICOMDIR,IMAGES,README.TXT,VIEWER.EXE') (Top $rootDir)
      Check '  every file read from the disc is the one that was put on it' ([Bethesda.Cd.DiscFolder]::Compare($files, $rootDir).Count -eq 0)
      Check '  AUTORUN.INF on the disc reads as it was written' ([IO.File]::ReadAllText((Join-Path $rootDir 'AUTORUN.INF')) -eq $text)
    }
  }
} finally {
  if ($mounted) { Dismount-DiskImage -ImagePath $iso | Out-Null; if ((Get-DiskImage -ImagePath $iso).Attached) { "FAIL the image is still mounted: $iso"; $script:res += $false } }
  for ($i = 0; $i -lt 10 -and (Test-Path -LiteralPath $work); $i++) { try { [IO.Directory]::Delete($work, $true) } catch { Start-Sleep -Milliseconds 300 } }
}
Check 'nothing of the test is left on this PC' (-not (Test-Path -LiteralPath $work))
if ($script:res -contains $false) { "SOME FAILED $($script:res.Count)"; exit 1 } else { "ALL PASS $($script:res.Count)" }
