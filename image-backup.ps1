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
# Exit: 0 done, 1 failed (see message), 2 no backup disk found.
param(
  [string]$OrthancUrl = 'http://localhost:9090',
  [string]$EmrReportUrl = 'http://localhost:9080/api/pacs/image-backup-report',
  [string]$EnvFile = (Join-Path $PSScriptRoot '.env'),
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

# Tell the EMR (status screen) and leave the same news beside the PACS for the
# server status window, which reads it even when the EMR is down. Counts only -
# no patient data in either.
function Finish([bool]$ok, [bool]$diskFound, [int]$copied, [int]$failed, [string]$err, [int]$code) {
  $space = if ($script:root) { Get-FreeSpace $script:root } else { @{ free = [int64]0; total = [int64]0 } }
  $report = [ordered]@{
    ok = $ok; disk_found = $diskFound; copied = $copied; failed = $failed
    total_files = $script:totalFiles
    free_gb = [math]::Round($space.free / 1GB, 1); total_gb = [math]::Round($space.total / 1GB, 1)
    error = $err
  }
  $status = [ordered]@{ at = (Get-Date).ToString('o') }
  foreach ($k in $report.Keys) { $status[$k] = $report[$k] }
  Write-JsonAtomically (Join-Path $logDir 'image-backup-status.json') $status
  if (-not $NoReport -and $cfg['BRIDGE_TOKEN']) {
    try {
      Invoke-RestMethod -Method Post -Uri $EmrReportUrl -ContentType 'application/json' -UseBasicParsing `
        -Headers @{ 'X-Bridge-Token' = $cfg['BRIDGE_TOKEN'] } -Body ($report | ConvertTo-Json) -TimeoutSec 15 -ErrorAction Stop | Out-Null
    } catch { Log ('could not report to the EMR: ' + $_.Exception.Message) }
  }
  Log ("finished: ok=$ok copied=$copied failed=$failed" + $(if ($err) { " error=$err" } else { '' }))
  exit $code
}

$script:root = $null
$script:totalFiles = 0

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
Log "start: disk $($script:root), from change $seq"

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
      $failed++; Log "could not copy instance $id : $($_.Exception.Message)"
    }
  }

  # The position moves on only once a whole page has been copied: a failure
  # leaves it where it was, so tonight's gap is retried tomorrow.
  if ($failed -gt 0) { break }
  $seq = [int64]$page.Last
  Write-JsonAtomically $statePath ([ordered]@{
    last_seq = $seq; total_files = $script:totalFiles
    last_success = (Get-Date).ToString('o')
    note = 'Written by image-backup.ps1. last_seq = Orthanc change already copied.'
  })
  if ($page.Done) { break }
}

if ($failed -gt 0) { Finish $false $true $copied $failed "$failed image(s) could not be copied; will retry next run" 1 }
$space = Get-FreeSpace $script:root
if ($space.total -gt 0 -and ($space.free / $space.total) -lt 0.10) {
  Finish $true $true $copied 0 ('backup disk almost full - ' + [math]::Round($space.free / 1GB, 1) + ' GB free') 0
}
Finish $true $true $copied 0 '' 0
