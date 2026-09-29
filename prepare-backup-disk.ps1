# Make an external disk the PACS image backup disk (run once per disk).
#
# Writes the marker file image-backup.ps1 looks for, so the disk is found
# whatever drive letter Windows gives it. Refuses a disk that already holds
# other files unless -Force, so the wrong disk is not picked by mistake.
#
#   .\prepare-backup-disk.ps1 -Target E:\
#   .\prepare-backup-disk.ps1 -Target E:\ -Force
param(
  [Parameter(Mandatory = $true)][string]$Target,
  [switch]$Force
)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'image-backup-common.ps1')

if (-not (Test-Path $Target)) { Write-Host "No such drive or folder: $Target"; exit 1 }
$root = (Resolve-Path $Target).Path
if ($root -match '^[A-Za-z]:\\?$' -and $root.Substring(0, 1).ToUpper() -eq $env:SystemDrive.Substring(0, 1).ToUpper()) {
  Write-Host "$root is the system disk. Use an external disk."; exit 1
}
if (Test-Path (Join-Path $root $MarkerName)) { Write-Host "$root is already a PACS backup disk - nothing to do."; exit 0 }

$others = @(Get-ChildItem -Force $root -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -notin @('System Volume Information', '$RECYCLE.BIN') })
if ($others.Count -gt 0 -and -not $Force) {
  Write-Host "$root is not empty ($($others.Count) items). If this really is the disk for PACS image backups, run again with -Force."
  exit 1
}

New-Item -ItemType Directory -Force -Path (Join-Path $root "$BackupDirName\images") | Out-Null
$marker = @(
  'Bethesda PACS image backup disk',
  'disk_id=' + [guid]::NewGuid().ToString(),
  'created=' + (Get-Date -Format 'yyyy-MM-dd HH:mm'),
  'Do not delete this file: the nightly backup finds this disk by it.'
)
Set-Content -Path (Join-Path $root $MarkerName) -Value $marker -Encoding ascii -ErrorAction Stop
Write-Host "Ready: $root is now the PACS image backup disk."
exit 0
