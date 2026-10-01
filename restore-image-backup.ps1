# Put the images from the PACS backup disk back into Orthanc (Windows).
#
# Uploads every .dcm on the disk to Orthanc. Images Orthanc already has are
# answered "already stored", so running it twice, or on a PACS that still has
# most of its images, is safe. Use it after a disk failure, and to move the
# images to a new PC (install PACS -> restore the EMR backup -> pair-with-emr
# -> this). The StudyInstanceUIDs are unchanged, so EMR orders find their images.
#
#   .\restore-image-backup.ps1                 restore
#   .\restore-image-backup.ps1 -Verify         check the disk only (monthly drill),
#                                              including the EMR database backups on it
#
# The EMR database backups on the disk (BethesdaPACS\emr-backups) are NOT
# restored here: copy one into the EMR's backups folder and follow the EMR's
# DEPLOYMENT.md section 5b.
#
# At the end it also counts EMR imaging orders recorded as "images arrived"
# whose study Orthanc does not have - the number that should be 0 afterwards.
#
# Images a doctor put under another order in the EMR ("Corriger la demande..."): the
# files under the old study number must not come back. Those the nightly backup already
# set aside are in <disk>\BethesdaPACS\replaced and are never uploaded. For a disk that
# has not had a backup since the correction, the EMR is asked (it must be restored and
# running first - the usual order) and the files are set aside before the upload; any
# such image already in Orthanc is removed from it. A file is set aside (or an image
# removed) only when its replacement is there too: if the disk holds a picture only
# under its old study number - no backup ran after the correction - it is uploaded as
# it is, and said, rather than lost.
param(
  [switch]$Verify,
  [string]$OrthancUrl = 'http://localhost:9090',
  [string]$EnvFile = (Join-Path $PSScriptRoot '.env'),
  [string[]]$SearchRoots = @(),
  [string]$EmrDbContainer = 'bethesda-emr-db',
  [string]$EmrSupersededUrl = 'http://localhost:9080/api/pacs/superseded-images',
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
$base = Join-Path $disks[0] $BackupDirName
$images = Join-Path $base 'images'
$asideBefore = @(Get-ChildItem (Join-Path $base $ReplacedDirName) -Recurse -Filter '*.dcm' -ErrorAction SilentlyContinue).Count

# Images put under another order in the EMR since they were backed up (see the header).
$gone = Get-SupersededImages $EmrSupersededUrl $cfg['BRIDGE_TOKEN']
# A line put into the EMR by hand without image numbers ("every file under this study
# number") is left to the nightly backup, which asks Orthanc about each file. Here Orthanc
# is being rebuilt and cannot be asked, and that number may hold a later exam as well.
if ($null -ne $gone) {
  $byHand = @($gone | Where-Object { $_.all }).Count
  $gone = @($gone | Where-Object { -not $_.all })
  if ($byHand -gt 0 -and -not $Verify) { Write-Host "($byHand study number(s) registered by hand without image numbers: left as they are - the nightly backup handles them.)" }
}
if (-not $Verify) {
  if ($null -eq $gone) {
    Write-Host "WARNING: could not ask the EMR which images were put under another order ($EmrSupersededUrl)." -ForegroundColor Yellow
    Write-Host "  If any were since this disk's last backup, the old studies come back. Start the EMR and run this again: it removes them." -ForegroundColor Yellow
  } elseif ($gone.Count -gt 0) {
    $res = Move-SupersededFiles $base $gone $null
    if ($res.moved -gt 0) { Write-Host "Set aside $($res.moved) image file(s) whose images were put under another order in the EMR (kept in $ReplacedDirName, not uploaded)." }
    if ($res.kept -gt 0) {
      Write-Host "WARNING: $($res.kept) image(s) that were put under another order in the EMR are on this disk only under their OLD study number" -ForegroundColor Yellow
      Write-Host "  (no backup ran after the correction). They are uploaded as they are, so that the pictures are not lost. In the EMR," -ForegroundColor Yellow
      Write-Host "  the exam they were moved to will say the image server does not have its images: call for help (README, Image backup)." -ForegroundColor Yellow
    }
  }
}
$files = @(Get-ChildItem $images -Recurse -Filter '*.dcm' -ErrorAction SilentlyContinue)
Write-Host "Backup disk $($disks[0]): $($files.Count) image files$(if ($asideBefore) { " (+ $asideBefore set aside in $ReplacedDirName)" })."

# The listed images that Orthanc holds (uploaded by an earlier run that could not ask
# the EMR): removed from Orthanc. Only exact matches of study number and image number.
function Remove-SupersededFromOrthanc($items) {
  $removed = 0
  foreach ($it in @($items)) {
    $uid = [string]$it.study_uid
    if (-not (Test-Uid $uid)) { continue }
    try {
      $q = @{ Level = 'Instance'; Query = @{ StudyInstanceUID = $uid }; Expand = $true } | ConvertTo-Json
      # (Assigned first: Windows PowerShell hands a JSON array down the pipeline as ONE
      # object, so @(Invoke-RestMethod ...) would be a list of one list.)
      $found = Invoke-RestMethod -Method Post -Uri "$OrthancUrl/tools/find" -Headers $headers -UseBasicParsing -ContentType 'application/json' -Body $q -TimeoutSec 60 -ErrorAction Stop
    } catch { continue }
    foreach ($h in @($found)) {
      $sop = [string]$h.MainDicomTags.SOPInstanceUID
      if (-not $it.all -and (@($it.instances) -notcontains $sop)) { continue }
      # Only when the picture is in Orthanc under another study number too.
      try {
        if ($it.all) {
          $by = [string]$it.replaced_by
          if (-not (Test-Uid $by)) { continue }
          $q2 = @{ Level = 'Study'; Query = @{ StudyInstanceUID = $by } } | ConvertTo-Json
        } else {
          $q2 = @{ Level = 'Instance'; Query = @{ SOPInstanceUID = $sop } } | ConvertTo-Json
        }
        $others = Invoke-RestMethod -Method Post -Uri "$OrthancUrl/tools/find" -Headers $headers -UseBasicParsing -ContentType 'application/json' -Body $q2 -TimeoutSec 60 -ErrorAction Stop
        if (@($others).Count -lt $(if ($it.all) { 1 } else { 2 })) { continue }
      } catch { continue }
      try { Invoke-RestMethod -Method Delete -Uri "$OrthancUrl/instances/$($h.ID)" -Headers $headers -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop | Out-Null; $removed++ } catch { }
    }
  }
  return $removed
}

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
  # (Get-Random refuses -Count 0: a disk with no images yet has nothing to sample.)
  $picked = if ($files.Count -gt 0) { @($files | Get-Random -Count ([math]::Min($Sample, $files.Count))) } else { @() }
  foreach ($f in $picked) {
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
  # Files still under the study number of images that were since put under another order:
  # the next nightly backup (or a restore) sets them aside. Told, not counted as bad.
  if ($null -ne $gone -and $gone.Count -gt 0) {
    $left = 0
    foreach ($it in $gone) {
      $d = Join-Path $images ([string]$it.study_uid)
      if (-not (Test-Uid ([string]$it.study_uid)) -or -not (Test-Path $d)) { continue }
      if ($it.all) { $left += @(Get-ChildItem $d -Filter '*.dcm' -ErrorAction SilentlyContinue).Count }
      else { foreach ($s in @($it.instances)) { if ((Test-Uid ([string]$s)) -and (Test-Path (Join-Path $d ("$s.dcm")))) { $left++ } } }
    }
    if ($left -gt 0) { Write-Host "$left image file(s) on the disk belong to exams since put under another order in the EMR; the next backup sets them aside." }
  }
  # The EMR database backups copied by image-backup.ps1 (emr-backups). This script
  # does not restore them: copy the chosen file into the EMR's backups folder and
  # follow the EMR's DEPLOYMENT.md section 5b.
  $emrCopies = @(Get-EmrBackupFiles (Join-Path $disks[0] "$BackupDirName\$EmrBackupDirName"))
  if ($emrCopies.Count -eq 0) {
    Write-Host 'EMR database backups on the disk: none.' -ForegroundColor Yellow
  } else {
    $ok = Test-GzipFile $emrCopies[0].FullName
    Write-Host ("EMR database backups on the disk: $($emrCopies.Count); newest $($emrCopies[0].Name), written " + $emrCopies[0].LastWriteTime.ToString('yyyy-MM-dd HH:mm') + ' on this PC''s clock, ' + $(if ($ok) { 'reads as a complete gzip.' } else { 'DAMAGED - not a complete gzip.' }))
    if (-not $ok) { $bad++ }
    # Age by the file's own time, not its name: the name is written in the EMR
    # container's time zone (TZ, Indian/Antananarivo by default), which is not
    # this PC's when the PC is set to another zone. image-backup.ps1 gives each
    # copy the original's modification time, a real instant.
    if (((Get-Date) - $emrCopies[0].LastWriteTime).TotalHours -gt 36) { Write-Host '  WARNING: the newest EMR backup on the disk is more than 36 hours old.' -ForegroundColor Yellow; $bad++ }
  }
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
if ($null -ne $gone -and $gone.Count -gt 0) {
  $removed = Remove-SupersededFromOrthanc $gone
  if ($removed -gt 0) { Write-Host "Removed from Orthanc $removed image(s) that the EMR had put under another order (an earlier upload brought them back)." }
}
$after = Get-OrthancCount
Write-Host "Uploaded: $stored new, $already already there, $failed failed. Orthanc images: $before -> $after."
Show-EmrLinks
if ($failed -gt 0) { exit 1 }
exit 0
