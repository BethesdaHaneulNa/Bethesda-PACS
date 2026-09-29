# Shared by the image-backup scripts (dot-sourced; not run on its own).
#
# The backup disk is recognised by a marker file at its root, never by drive
# letter: a USB disk's letter changes with whatever else is plugged in.

$MarkerName = 'BETHESDA-PACS-BACKUP.id'
$BackupDirName = 'BethesdaPACS'

# Read KEY=VALUE pairs from the PACS .env. Values are returned, never printed.
function Read-PacsEnv([string]$path) {
  $vals = @{}
  if (Test-Path $path) {
    foreach ($line in (Get-Content $path)) {
      if ($line -match '^\s*([A-Z_][A-Z0-9_]*)\s*=(.*)$') { $vals[$Matches[1]] = $Matches[2].Trim() }
    }
  }
  return $vals
}

function Get-OrthancHeaders([string]$password) {
  $pair = [Text.Encoding]::ASCII.GetBytes('admin:' + $password)
  return @{ Authorization = 'Basic ' + [Convert]::ToBase64String($pair) }
}

# Every drive (or the roots given) that carries the marker file, as full paths.
# Always call it as @(Find-BackupDisks ...): PowerShell unwraps a one-item list
# returned from a function, and $disks[0] would then be the first letter.
function Find-BackupDisks([string[]]$roots) {
  if (-not $roots -or $roots.Count -eq 0) {
    $roots = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName })
  }
  $found = New-Object System.Collections.ArrayList
  foreach ($r in $roots) {
    if ($r -and (Test-Path (Join-Path $r $MarkerName))) { [void]$found.Add([IO.Path]::GetFullPath($r)) }
  }
  return $found.ToArray()
}

function Get-FreeSpace([string]$root) {
  try {
    $d = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot((Resolve-Path $root).Path))
    return @{ free = $d.AvailableFreeSpace; total = $d.TotalSize }
  } catch { return @{ free = [int64]0; total = [int64]0 } }
}

# UIDs are digits and dots; anything else never becomes part of a path.
function Test-Uid([string]$u) { return ($u -match '^[0-9.]{1,64}$') }

# ── EMR database backups on the same disk (decision: one external disk for both) ──
#
# The EMR writes bethesda_YYYY-MM-DD_HHMM.sql.gz nightly at 02:00 into its own
# backups folder (or BACKUP_PATH from the EMR's .env). Those files are copied to
# <disk>\BethesdaPACS\emr-backups. The EMR's own folder and settings are never
# touched, so an unplugged disk cannot affect the EMR.
$EmrBackupDirName = 'emr-backups'
$EmrBackupMinKeep = 7            # same rule as the EMR (backend/src/services/backup.js)

# The EMR folder: the one given, else a Bethesda-EMR* folder beside the PACS
# folder that holds the EMR's docker-compose.yml. With several, the one with the
# newest backup. $null when none.
function Find-EmrFolder([string]$given, [string]$pacsDir) {
  if ($given) { if (Test-Path (Join-Path $given 'docker-compose.yml')) { return [IO.Path]::GetFullPath($given) } else { return $null } }
  $parent = Split-Path -Parent $pacsDir
  $cands = @(Get-ChildItem $parent -Directory -Filter 'Bethesda-EMR*' -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'docker-compose.yml') })
  if ($cands.Count -eq 0) { return $null }
  $best = $cands | Sort-Object { $n = @(Get-EmrBackupFiles (Get-EmrBackupDir $_.FullName)) | Select-Object -First 1; if ($n) { $n.LastWriteTime } else { [datetime]::MinValue } } -Descending | Select-Object -First 1
  return $best.FullName
}

# Where that EMR writes its backups: BACKUP_PATH in its .env when set (a path
# relative to the EMR folder is taken from there), else <EMR>\backups.
function Get-EmrBackupDir([string]$emr) {
  $bp = (Read-PacsEnv (Join-Path $emr '.env'))['BACKUP_PATH']
  if ($bp) { $bp = $bp.Trim('"', "'"); if ([IO.Path]::IsPathRooted($bp)) { return $bp } else { return (Join-Path $emr $bp) } }
  return (Join-Path $emr 'backups')
}

# Finished EMR backups in a folder, newest first. Only the top level: a dump
# still being written sits in .inprogress and never counts.
function Get-EmrBackupFiles([string]$dir) {
  if (-not $dir -or -not (Test-Path $dir)) { return @() }
  return @(Get-ChildItem $dir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(bethesda|medconnect)_[A-Za-z0-9_.-]*\.sql\.gz$' -and $_.Length -gt 0 } |
    Sort-Object { Get-EmrBackupDate $_ } -Descending)
}

# The date a backup was taken: from its name (bethesda_2026-09-29_0200.sql.gz),
# else the file's time. By name, because a copy may carry a new file time.
function Get-EmrBackupDate($file) {
  if ($file.Name -match '_(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})\.sql\.gz$') {
    return (Get-Date -Year $Matches[1] -Month $Matches[2] -Day $Matches[3] -Hour $Matches[4] -Minute $Matches[5] -Second 0 -Millisecond 0)
  }
  return $file.LastWriteTime
}

# Does the whole file decompress to the length its trailer records? Windows
# PowerShell's GZipStream stops quietly at the end of a truncated file, so the
# decompressed byte count is compared with the gzip trailer (ISIZE, the last 4
# bytes: the original length mod 2^32). A cut-off file fails here.
function Test-GzipFile([string]$path) {
  $fs = $null; $gz = $null
  try {
    $fs = [IO.File]::OpenRead($path)
    if ($fs.Length -lt 20) { return $false }
    $head = New-Object byte[] 2; [void]$fs.Read($head, 0, 2)
    if ($head[0] -ne 0x1f -or $head[1] -ne 0x8b) { return $false }
    $fs.Seek(-4, [IO.SeekOrigin]::End) | Out-Null
    $tail = New-Object byte[] 4; [void]$fs.Read($tail, 0, 4)
    $isize = [BitConverter]::ToUInt32($tail, 0)
    $fs.Seek(0, [IO.SeekOrigin]::Begin) | Out-Null
    $gz = New-Object IO.Compression.GZipStream ($fs, [IO.Compression.CompressionMode]::Decompress)
    $buf = New-Object byte[] 65536; [int64]$n = 0
    while (($k = $gz.Read($buf, 0, $buf.Length)) -gt 0) { $n += $k }
    return (($n % 4294967296) -eq $isize)
  } catch { return $false } finally { if ($gz) { $gz.Dispose() }; if ($fs) { $fs.Dispose() } }
}

function Write-JsonAtomically([string]$path, $obj) {
  $path = [IO.Path]::GetFullPath($path)
  $tmp = $path + '.tmp'
  [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
  # [NullString]::Value, not $null: PowerShell passes $null to a .NET string
  # parameter as "", which File.Replace rejects as a backup path.
  if (Test-Path $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
}
