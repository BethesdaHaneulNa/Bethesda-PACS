# Nightly PACS image backup to an external disk (Windows). Decision 41.
#
# Copies every image Orthanc has received since the last run onto the disk that
# carries BETHESDA-PACS-BACKUP.id, as the original DICOM files, then tells the
# EMR how it went so the status screen can warn. Run by the scheduled task that
# install-image-backup.ps1 registers; safe to run by hand, and safe to re-run.
#
# Why not copy the storage folder: Orthanc's index is a SQLite file in use, and
# that folder's layout belongs to one Orthanc version. Asking Orthanc for its
# files gives only what it has fully stored, needs no downtime, and restores
# into any DICOM server.
#
# What is new comes from Orthanc's change log (/changes, NewInstance). The last
# change handled is kept ON THE DISK (state.json), so a fresh disk simply gets
# everything. Nothing on the disk is ever deleted, even if Orthanc deletes it.
#
# One thing is moved, not deleted: when a doctor put the images of an exam under another
# order in the EMR, the files under the old study number go to <disk>\BethesdaPACS\replaced
# (see image-backup-common.ps1) so that a restore does not bring the wrong study back.
#
# The same run also copies the EMR's nightly database backups (*.sql.gz) to
# <disk>\BethesdaPACS\emr-backups - one external disk for both. That part is
# reported separately (emr_backup*): it never turns the image result red, and an
# image failure does not stop it.
#
# Exit: 0 done, 1 failed (see message), 2 no backup disk found. The exit code
# is the images' result.
param(
  [string]$OrthancUrl = 'http://localhost:9090',
  [string]$EmrReportUrl = 'http://localhost:9080/api/pacs/image-backup-report',
  [string]$EmrSupersededUrl = '',    # default: the same EMR, .../superseded-images
  [string]$EnvFile = (Join-Path $PSScriptRoot '.env'),
  [string]$EmrPath = '',             # the EMR folder; default: Bethesda-EMR* beside this folder
  [string[]]$SearchRoots = @(),       # tests: folders to treat as disks
  [int]$ReserveMb = 1024,            # stop before the disk is this close to full
  [switch]$NoReport                  # tests: do not tell the EMR
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'image-backup-common.ps1')

$cfg = Read-PacsEnv $EnvFile
$headers = Get-OrthancHeaders $cfg['ORTHANC_PASSWORD']
$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir 'image-backup.log'
$started = Get-Date

function Log([string]$m) {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
  Write-Host $line
  Add-Content -Path $logFile -Value $line -Encoding utf8
}

# Copy the EMR's finished database backups that the disk does not have yet, then
# prune the disk's copies by the EMR's own rule. Returns what the report carries:
#   emr_backup  ok | not_found (no EMR folder) | none (EMR folder, no backup in it)
#               | failed | no_disk
#   emr_backup_ok, emr_backup_copied, emr_backup_count (on the disk),
#   emr_backup_newest (date in the newest name on the disk), emr_backup_error
function Copy-EmrBackups([string]$diskRoot) {
  $r = [ordered]@{ emr_backup = 'failed'; emr_backup_ok = $false; emr_backup_copied = 0; emr_backup_count = 0; emr_backup_newest = ''; emr_backup_error = '' }
  if (-not $diskRoot) { $r.emr_backup = 'no_disk'; $r.emr_backup_error = $(if ($script:unplugged) { $UnpluggedMsg } else { 'no single backup disk plugged in' }); return $r }
  if (-not (Test-Path (Join-Path $diskRoot $MarkerName))) { $r.emr_backup = 'no_disk'; $r.emr_backup_error = $UnpluggedMsg; return $r }
  $dest = Join-Path (Join-Path $diskRoot $BackupDirName) $EmrBackupDirName
  $emr = Find-EmrFolder $EmrPath $PSScriptRoot
  $failedNames = @()
  # The EMR's own retention (its .env BACKUP_RETENTION_DAYS, default 30).
  $days = 30
  if ($emr) { $rd = (Read-PacsEnv (Join-Path $emr '.env'))['BACKUP_RETENTION_DAYS']; if ($rd -match '^\d+$' -and [int]$rd -gt 0) { $days = [int]$rd } }
  $cutoff = (Get-Date).AddDays(-$days)
  if (-not $emr) {
    $r.emr_backup = 'not_found'; $r.emr_backup_error = 'EMR folder not found (use -EmrPath)'
    Log 'EMR backups: EMR folder not found - skipped'
  } else {
    $src = Get-EmrBackupDir $emr
    $files = @(Get-EmrBackupFiles $src)
    Log "EMR backups: $($files.Count) in $src"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem $dest -Filter '*.part' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    # A file the pruning below would remove at once is not copied at all.
    $youngest = @($files | Select-Object -First $EmrBackupMinKeep | ForEach-Object { $_.Name })
    foreach ($f in $files) {
      if ((Get-EmrBackupDate $f) -lt $cutoff -and $youngest -notcontains $f.Name) { continue }
      $final = Join-Path $dest $f.Name
      if ((Test-Path $final) -and (Get-Item $final).Length -eq $f.Length) { continue }
      $space = Get-FreeSpace $diskRoot
      if ($space.free -lt ($f.Length + [int64]$ReserveMb * 1MB)) { $failedNames += $f.Name; $r.emr_backup_error = 'backup disk is full'; break }
      $part = $final + '.part'
      try {
        Copy-Item $f.FullName $part -Force -ErrorAction Stop
        # Same bytes as the EMR's file, and a gzip that reads to the end.
        if ((Get-FileHash $part -Algorithm SHA256).Hash -ne (Get-FileHash $f.FullName -Algorithm SHA256).Hash) { throw 'copy differs from the original' }
        if (-not (Test-GzipFile $part)) { throw 'not a complete gzip file (the EMR copy may be damaged too)' }
        if (Test-Path $final) { Remove-Item $final -Force }
        Rename-Item $part $f.Name -ErrorAction Stop
        (Get-Item $final).LastWriteTime = $f.LastWriteTime
        $r.emr_backup_copied++
      } catch {
        Remove-Item $part -Force -ErrorAction SilentlyContinue
        $failedNames += $f.Name; $r.emr_backup_error = "could not copy $($f.Name): $($_.Exception.Message)"
        Log "EMR backups: $($r.emr_backup_error)"
        if (-not (Test-Path (Join-Path $diskRoot $MarkerName))) { $r.emr_backup = 'no_disk'; $r.emr_backup_error = $UnpluggedMsg; Log "EMR backups: $UnpluggedMsg"; return $r }
      }
    }
    if ($failedNames.Count -eq 0) { $r.emr_backup = if ($files.Count -gt 0) { 'ok' } else { 'none' } }
    if ($files.Count -eq 0 -and -not $r.emr_backup_error) { $r.emr_backup_error = 'no EMR backup in ' + (Split-Path -Leaf $src) }
  }

  # Prune the disk's copies like the EMR does: older than its retention days, and
  # never below the newest seven. Only after a run without copy errors.
  $onDisk = @(Get-EmrBackupFiles $dest)
  if ($emr -and $failedNames.Count -eq 0 -and $onDisk.Count -gt $EmrBackupMinKeep) {
    for ($i = $onDisk.Count - 1; $i -ge $EmrBackupMinKeep; $i--) {
      if ((Get-EmrBackupDate $onDisk[$i]) -lt $cutoff) { Remove-Item $onDisk[$i].FullName -Force -ErrorAction SilentlyContinue; Log "EMR backups: removed old copy $($onDisk[$i].Name)" }
    }
    $onDisk = @(Get-EmrBackupFiles $dest)
  }
  $r.emr_backup_count = $onDisk.Count
  if ($onDisk.Count -gt 0) { $r.emr_backup_newest = (Get-EmrBackupDate $onDisk[0]).ToString('yyyy-MM-dd HH:mm') }
  $r.emr_backup_ok = ($r.emr_backup -eq 'ok')
  Log "EMR backups: $($r.emr_backup) copied=$($r.emr_backup_copied) on disk=$($r.emr_backup_count) newest=$($r.emr_backup_newest)"
  return $r
}

# Tell the EMR (status screen) and leave the same news beside the PACS for the
# server status window, which reads it even when the EMR is down. Counts only -
# no patient data in either.
function Finish([bool]$ok, [bool]$diskFound, [int]$copied, [int]$failed, [string]$err, [int]$code) {
  try { $emrPart = Copy-EmrBackups $script:root }
  catch { $emrPart = [ordered]@{ emr_backup = 'failed'; emr_backup_ok = $false; emr_backup_copied = 0; emr_backup_count = 0; emr_backup_newest = ''; emr_backup_error = $_.Exception.Message }; Log "EMR backups: $($_.Exception.Message)" }
  $space = if ($script:root) { Get-FreeSpace $script:root } else { @{ free = [int64]0; total = [int64]0 } }
  $report = [ordered]@{
    ok = $ok; disk_found = $diskFound; copied = $copied; failed = $failed
    total_files = $script:totalFiles
    free_gb = [math]::Round($space.free / 1GB, 1); total_gb = [math]::Round($space.total / 1GB, 1)
    error = $err
  }
  foreach ($k in $emrPart.Keys) { $report[$k] = $emrPart[$k] }
  $status = [ordered]@{ at = (Get-Date).ToString('o') }
  foreach ($k in $report.Keys) { $status[$k] = $report[$k] }
  Write-JsonAtomically (Join-Path $logDir 'image-backup-status.json') $status
  if (-not $NoReport -and $cfg['BRIDGE_TOKEN']) {
    try {
      Invoke-RestMethod -Method Post -Uri $EmrReportUrl -ContentType 'application/json' -UseBasicParsing `
        -Headers @{ 'X-Bridge-Token' = $cfg['BRIDGE_TOKEN'] } -Body ($report | ConvertTo-Json) -TimeoutSec 15 -ErrorAction Stop | Out-Null
    } catch { Log ('could not report to the EMR: ' + $_.Exception.Message) }
  }
  Log ("finished: ok=$ok copied=$copied failed=$failed" + $(if ($err) { " error=$err" } else { '' }) + " emr_backup=$($report.emr_backup)")
  exit $code
}

$script:root = $null
$script:totalFiles = 0
$script:unplugged = $false
$UnpluggedMsg = 'backup disk was unplugged during the backup - plug it back in; the next run continues'

if (-not $cfg['ORTHANC_PASSWORD']) { Finish $false $false 0 0 'ORTHANC_PASSWORD missing from .env' 1 }

$disks = @(Find-BackupDisks $SearchRoots)
if ($disks.Count -eq 0) { Finish $false $false 0 0 'backup disk not found (is it plugged in?)' 2 }
if ($disks.Count -gt 1) { Finish $false $true 0 0 ('more than one backup disk plugged in: ' + ($disks -join ', ')) 1 }
$script:root = $disks[0]
$base = Join-Path $script:root $BackupDirName
$images = Join-Path $base 'images'
New-Item -ItemType Directory -Force -Path $images | Out-Null
$statePath = Join-Path $base 'state.json'

# A run that was cut off can leave half-written files; they never had their
# final name, so they are just removed.
Get-ChildItem $images -Recurse -Filter '*.part' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$state = if (Test-Path $statePath) { Get-Content $statePath -Raw | ConvertFrom-Json } else { $null }
$seq = if ($state -and $state.last_seq) { [int64]$state.last_seq } else { [int64]0 }
$script:totalFiles = if ($state -and $state.total_files) { [int]$state.total_files } else { 0 }
$lastChange = if ($state -and $state.last_change) { [string]$state.last_change } else { '' }

# Is the position on the disk this Orthanc's? Change numbers belong to one
# Orthanc database: a disk carried to a new server (decision 35), or an Orthanc
# rebuilt from the image backup, starts again from 1, and a position left by the
# old one could skip the new one's first images for good. The change at the
# saved position must still be there, with the same ID and time; if not, start
# again from 0 - images already on the disk are recognised by size and skipped.
function Get-ChangeMark($c) { return ('' + $c.Seq + '|' + $c.ChangeType + '|' + $c.ID + '|' + $c.Date) }
if ($seq -gt 0) {
  try {
    $probe = Invoke-RestMethod -Uri "$OrthancUrl/changes?since=$($seq - 1)&limit=1" -Headers $headers -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    $at = @($probe.Changes) | Select-Object -First 1
    $same = $at -and ([int64]$at.Seq -eq $seq) -and (-not $lastChange -or (Get-ChangeMark $at) -eq $lastChange)
    if (-not $same) {
      Log "the disk's position (change $seq) is not this Orthanc's - another server, or a rebuilt one. Starting again from 0; images already on the disk are skipped."
      $seq = [int64]0; $lastChange = ''
    } elseif (-not $lastChange) { $lastChange = Get-ChangeMark $at }   # a disk from before this check: mark it now
  } catch { Finish $false $true 0 0 ('could not ask Orthanc for changes: ' + $_.Exception.Message) 1 }
}
Log "start: disk $($script:root), from change $seq"

function Save-State {
  Write-JsonAtomically $statePath ([ordered]@{
    last_seq = $seq; last_change = $lastChange; total_files = $script:totalFiles
    last_success = (Get-Date).ToString('o')
    note = 'Written by image-backup.ps1. last_seq = Orthanc change already copied; last_change = that change (seq|type|id|date), to tell this Orthanc from another.'
  })
}

$copied = 0; $failed = 0
while ($true) {
  try {
    $page = Invoke-RestMethod -Uri "$OrthancUrl/changes?since=$seq&limit=200" -Headers $headers -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
  } catch { Finish $false $true $copied $failed ('could not ask Orthanc for changes: ' + $_.Exception.Message) 1 }

  foreach ($c in @($page.Changes)) {
    if ($c.ChangeType -ne 'NewInstance') { continue }
    $id = $c.ID
    try {
      $info = Invoke-RestMethod -Uri "$OrthancUrl/instances/$id" -Headers $headers -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
      $study = Invoke-RestMethod -Uri "$OrthancUrl/instances/$id/study" -Headers $headers -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    } catch {
      # Deleted from Orthanc since it arrived: nothing left to copy.
      if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { continue }
      $failed++; Log "could not read instance $id : $($_.Exception.Message)"; continue
    }
    $studyUid = [string]$study.MainDicomTags.StudyInstanceUID
    $sopUid = [string]$info.MainDicomTags.SOPInstanceUID
    if (-not (Test-Uid $studyUid) -or -not (Test-Uid $sopUid)) { $studyUid = 'orthanc-' + $study.ID; $sopUid = 'orthanc-' + $id }
    $dir = Join-Path $images $studyUid
    $final = Join-Path $dir ($sopUid + '.dcm')
    $size = [int64]$info.FileSize
    # Unplugged half way: say so, rather than reading 0 GB free as "disk full".
    if (-not (Test-Path (Join-Path $script:root $MarkerName))) { $script:root = $null; $script:unplugged = $true; Finish $false $false $copied $failed $UnpluggedMsg 1 }
    if ((Test-Path $final) -and (Get-Item $final).Length -eq $size) { continue }

    $space = Get-FreeSpace $script:root
    if ($space.free -lt ($size + [int64]$ReserveMb * 1MB)) {
      Finish $false $true $copied $failed ('backup disk is full - ' + [math]::Round($space.free / 1GB, 1) + ' GB free. Replace or clear it.') 1
    }

    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $part = $final + '.part'
    try {
      Invoke-WebRequest -Uri "$OrthancUrl/instances/$id/file" -Headers $headers -UseBasicParsing -OutFile $part -TimeoutSec 120 -ErrorAction Stop
      if ((Get-Item $part).Length -ne $size) { throw "size $((Get-Item $part).Length) instead of $size" }
      if (Test-Path $final) { Remove-Item $final -Force }
      Rename-Item $part ([IO.Path]::GetFileName($final)) -ErrorAction Stop
      $copied++; $script:totalFiles++
    } catch {
      Remove-Item $part -Force -ErrorAction SilentlyContinue
      if (-not (Test-Path (Join-Path $script:root $MarkerName))) { $script:root = $null; $script:unplugged = $true; Finish $false $false $copied ($failed + 1) $UnpluggedMsg 1 }
      $failed++; Log "could not copy instance $id : $($_.Exception.Message)"
    }
  }

  # The position moves on only once a whole page has been copied: a failure
  # leaves it where it was, so tonight's gap is retried tomorrow.
  if ($failed -gt 0) { break }
  $pageChanges = @($page.Changes)
  if ($pageChanges.Count -gt 0) {
    $seq = [int64]$pageChanges[-1].Seq; $lastChange = Get-ChangeMark $pageChanges[-1]
  }
  Save-State
  if ($page.Done) { break }
}

# Images put under another order in the EMR: the files under the old study number are
# set aside (never deleted). The EMR says which; Orthanc is asked once more for each, and
# a file whose image it still has under that number stays. An EMR that cannot be asked
# changes nothing tonight - the next run does it. Tests (-NoReport) ask only when told where.
if ($failed -eq 0 -and $script:root -and (Test-Path (Join-Path $script:root $MarkerName))) {
  $supUrl = if ($EmrSupersededUrl) { $EmrSupersededUrl } elseif (-not $NoReport) { $EmrReportUrl -replace 'image-backup-report$', 'superseded-images' } else { '' }
  if ($supUrl) {
    $gone = Get-SupersededImages $supUrl $cfg['BRIDGE_TOKEN']
    if ($null -eq $gone) { Log 'could not ask the EMR which images were put under another order; nothing set aside this run' }
    elseif ($gone.Count -gt 0) {
      $inOrthanc = {
        param($uid, $sop)
        try {
          $hit = Invoke-RestMethod -Method Post -Uri "$OrthancUrl/tools/find" -Headers $headers -UseBasicParsing -ContentType 'application/json' -TimeoutSec 30 -ErrorAction Stop `
            -Body (@{ Level = 'Instance'; Query = @{ StudyInstanceUID = $uid; SOPInstanceUID = $sop } } | ConvertTo-Json)
          return (@($hit).Count -gt 0)
        } catch { return $true }      # cannot tell: leave the file where it is
      }
      $aside = (Move-SupersededFiles $base $gone $inOrthanc).moved
      if ($aside -gt 0) {
        $script:totalFiles = [math]::Max(0, $script:totalFiles - $aside)
        Save-State
        Log "set aside $aside image file(s) whose images were put under another order in the EMR (in $ReplacedDirName, not deleted)"
      }
    }
  }
}

if ($failed -gt 0) { Finish $false $true $copied $failed "$failed image(s) could not be copied; will retry next run" 1 }
$space = Get-FreeSpace $script:root
if ($space.total -gt 0 -and ($space.free / $space.total) -lt 0.10) {
  Finish $true $true $copied 0 ('backup disk almost full - ' + [math]::Round($space.free / 1GB, 1) + ' GB free') 0
}
Finish $true $true $copied 0 '' 0
