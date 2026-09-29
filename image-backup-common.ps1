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

function Write-JsonAtomically([string]$path, $obj) {
  $path = [IO.Path]::GetFullPath($path)
  $tmp = $path + '.tmp'
  [IO.File]::WriteAllText($tmp, ($obj | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding $false))
  # [NullString]::Value, not $null: PowerShell passes $null to a .NET string
  # parameter as "", which File.Replace rejects as a backup path.
  if (Test-Path $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
}
