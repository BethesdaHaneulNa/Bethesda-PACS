# Put the images from the PACS backup disk back into Orthanc (Windows).
#
# Uploads every .dcm on the disk to Orthanc. Images Orthanc already has are
# answered "already stored", so running it twice, or on a PACS that still has
# most of its images, is safe. Use it after a disk failure, and to move the
# images to a new PC (install PACS -> restore the EMR backup -> pair-with-emr
# -> this). The StudyInstanceUIDs are unchanged, so EMR orders find their images.
#
#   .\restore-image-backup.ps1                 restore
#   .\restore-image-backup.ps1 -Verify         check the disk only (monthly drill)
#
# At the end it also counts EMR imaging orders recorded as "images arrived"
# whose study Orthanc does not have - the number that should be 0 afterwards.
param(
  [switch]$Verify,
  [string]$OrthancUrl = 'http://localhost:9090',
  [string]$EnvFile = (Join-Path $PSScriptRoot '.env'),
  [string[]]$SearchRoots = @(),
  [string]$EmrDbContainer = 'bethesda-emr-db',
  [int]$Sample = 20
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'image-backup-common.ps1')

$cfg = Read-PacsEnv $EnvFile
if (-not $cfg['ORTHANC_PASSWORD']) { Write-Host "ORTHANC_PASSWORD missing from $EnvFile"; exit 1 }
$headers = Get-OrthancHeaders $cfg['ORTHANC_PASSWORD']

$disks = @(Find-BackupDisks $SearchRoots)
if ($disks.Count -ne 1) { Write-Host ("Need exactly one backup disk plugged in; found " + $disks.Count + '.'); exit 2 }
$images = Join-Path $disks[0] "$BackupDirName\images"
$files = @(Get-ChildItem $images -Recurse -Filter '*.dcm' -ErrorAction SilentlyContinue)
Write-Host "Backup disk $($disks[0]): $($files.Count) image files."

function Get-OrthancCount {
  try { return [int](Invoke-RestMethod -Uri "$OrthancUrl/statistics" -Headers $headers -UseBasicParsing -ErrorAction Stop).CountInstances }
  catch { return -1 }
}

# EMR orders marked as arrived whose study Orthanc cannot find. Counts only.
function Show-EmrLinks {
  $running = (docker inspect -f '{{.State.Running}}' $EmrDbContainer 2>$null)
  if ($running -ne 'true') { Write-Host "(EMR database $EmrDbContainer not running here - skipped the order check.)"; return }
  $uids = @(docker exec $EmrDbContainer psql -U medconnect -d medconnect -tAc "SELECT COALESCE(image_study_uid, study_instance_uid) FROM worklist_log WHERE images_received_at IS NOT NULL" 2>$null |
    ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $missing = 0
  foreach ($u in $uids) {
    try {
      $found = Invoke-RestMethod -Method Post -Uri "$OrthancUrl/tools/find" -Headers $headers -UseBasicParsing -ContentType 'application/json' `
        -Body (@{ Level = 'Study'; Query = @{ StudyInstanceUID = $u } } | ConvertTo-Json) -ErrorAction Stop
      if (@($found).Count -eq 0) { $missing++ }
    } catch { $missing++ }
  }
  Write-Host "EMR imaging orders with images recorded: $($uids.Count); of those, missing from Orthanc: $missing"
}

if ($Verify) {
  $bad = 0
  foreach ($f in @($files | Get-Random -Count ([math]::Min($Sample, $files.Count)))) {
    # A DICOM file has 'DICM' at byte 128.
    try {
      $fs = [IO.File]::OpenRead($f.FullName); $buf = New-Object byte[] 132
      $n = $fs.Read($buf, 0, 132); $fs.Close()
      if ($n -lt 132 -or [Text.Encoding]::ASCII.GetString($buf, 128, 4) -ne 'DICM') { $bad++; Write-Host "  not a DICOM file: $($f.Name)" }
    } catch { $bad++; Write-Host "  unreadable: $($f.Name)" }
  }
  $inOrthanc = Get-OrthancCount
  Write-Host "Checked $([math]::Min($Sample, $files.Count)) files at random: $bad bad."
  if ($inOrthanc -ge 0) {
    Write-Host "Orthanc holds $inOrthanc images; the disk holds $($files.Count) (the disk keeps images Orthanc has deleted, so it may hold more)."
    if ($files.Count -lt $inOrthanc) { Write-Host "  WARNING: fewer on the disk than in Orthanc - last night's backup may not have run." -ForegroundColor Yellow; $bad++ }
  }
  Show-EmrLinks
  if ($bad -gt 0) { exit 1 } else { Write-Host 'VERIFIED'; exit 0 }
}

$before = Get-OrthancCount
$stored = 0; $already = 0; $failed = 0
foreach ($f in $files) {
  try {
    $r = Invoke-RestMethod -Method Post -Uri "$OrthancUrl/instances" -Headers $headers -UseBasicParsing `
      -ContentType 'application/dicom' -InFile $f.FullName -TimeoutSec 120 -ErrorAction Stop
    if ([string]$r.Status -eq 'AlreadyStored') { $already++ } else { $stored++ }
  } catch { $failed++; Write-Host "  could not upload $($f.Name): $($_.Exception.Message)" }
}
$after = Get-OrthancCount
Write-Host "Uploaded: $stored new, $already already there, $failed failed. Orthanc images: $before -> $after."
Show-EmrLinks
if ($failed -gt 0) { exit 1 }
exit 0
