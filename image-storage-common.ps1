# Shared by setup.ps1, move-image-storage.ps1 and the backup scripts (dot-sourced; not run
# on its own): where the image server keeps its images, and how that place is recognised.
#
# The place is one line of .env:
#     ORTHANC_STORAGE_PATH=D:/Bethesda-PACS-images
# Not set (or empty) = the folder "storage" inside the PACS folder, as before.
# docker-compose.yml mounts that place into the image server.
#
# The place carries a marker file, BETHESDA-PACS-STORAGE.id. The image server refuses to
# start on a folder that has neither the marker nor an image index: when the drive is not
# there (unplugged, another letter) Docker Desktop quietly makes an EMPTY folder of that
# name, and an image server started on it would look healthy and hold nothing - devices
# would send into it, and the real images would seem to be gone. See README.

$StorageMarkerName = 'BETHESDA-PACS-STORAGE.id'
$StorageEnvKey = 'ORTHANC_STORAGE_PATH'

function Format-Size([double]$bytes) {
  if ($bytes -ge 1GB) { return ('{0:N0} GB' -f ($bytes / 1GB)) }
  if ($bytes -ge 1MB) { return ('{0:N0} MB' -f ($bytes / 1MB)) }
  return ('{0:N0} KB' -f ($bytes / 1KB))
}

# KEY=VALUE lines of a .env; values are returned, never printed.
function Read-EnvFile([string]$path) {
  $vals = @{}
  if (Test-Path $path) {
    foreach ($line in (Get-Content $path)) {
      if ($line -match '^\s*([A-Z_][A-Z0-9_]*)\s*=(.*)$') { $vals[$Matches[1]] = $Matches[2].Trim() }
    }
  }
  return $vals
}

# Sets one KEY=VALUE line of a .env (replaced where it stands, or added at the end). Every
# other line is kept as it is. Plain ASCII, like the file setup writes.
function Set-EnvValue([string]$path, [string]$key, [string]$value) {
  $lines = @()
  if (Test-Path $path) { $lines = @(Get-Content $path) }
  $done = $false
  $out = foreach ($line in $lines) {
    if ($line -match ('^\s*' + [regex]::Escape($key) + '\s*=')) { if (-not $done) { "$key=$value"; $done = $true } }
    else { $line }
  }
  $out = @($out)
  if (-not $done) {
    $out += ''
    $out += '# Where the image server keeps the images (image-storage-common.ps1). Not set = .\storage'
    $out += "$key=$value"
  }
  Set-Content -Path $path -Value $out -Encoding ascii -ErrorAction Stop
}

# The place as a full Windows path. A relative value is taken from the PACS folder.
function Get-ImageStoragePath([string]$pacsRoot, [string]$envFile) {
  $v = (Read-EnvFile $envFile)[$StorageEnvKey]
  if (-not $v) { return (Join-Path $pacsRoot 'storage') }
  $v = $v.Trim('"').Trim("'").Replace('/', '\')
  if (-not [IO.Path]::IsPathRooted($v)) { $v = Join-Path $pacsRoot $v }
  return [IO.Path]::GetFullPath($v)
}

# What is known of the drive a path is on. Nothing here changes anything.
#   ready   the drive is there
#   kind    Fixed / Removable / Network / ...        format  NTFS / exFAT / FAT32 / ...
#   usb     a USB disk (by its bus, or "Removable")  system  the Windows disk
#   disk    the physical disk's number (-1 = not known)
function Get-DriveFacts([string]$path) {
  $f = @{ root = ''; ready = $false; free = [int64]0; total = [int64]0; kind = ''; format = ''; usb = $false; system = $false; disk = -1; bus = '' }
  try { $f.root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($path)) } catch { return $f }
  if ($f.root -notmatch '^[A-Za-z]:\\$') { $f.kind = 'Network'; return $f }
  try {
    $d = New-Object IO.DriveInfo $f.root
    if ($d.IsReady) { $f.ready = $true; $f.free = $d.AvailableFreeSpace; $f.total = $d.TotalSize; $f.format = $d.DriveFormat }
    $f.kind = "$($d.DriveType)"
  } catch { }
  $f.system = ($f.root.Substring(0, 1).ToUpper() -eq "$env:SystemDrive".Substring(0, 1).ToUpper())
  try {
    $p = Get-Partition -DriveLetter $f.root.Substring(0, 1) -ErrorAction Stop | Select-Object -First 1
    $f.disk = [int]$p.DiskNumber
    $f.bus = "$((Get-Disk -Number $p.DiskNumber -ErrorAction Stop).BusType)"
  } catch { }
  $f.usb = ($f.bus -eq 'USB' -or $f.kind -eq 'Removable')
  return $f
}

# What stands at the place:
#   store    the marker or an image index is there - it is an image store
#   empty    a folder with nothing in it
#   foreign  a folder that holds other things
#   missing  no such folder          nodrive  no such drive
function Test-ImageStorage([string]$path) {
  $facts = Get-DriveFacts $path
  if (-not $facts.ready) { return 'nodrive' }
  if (-not (Test-Path -LiteralPath $path -PathType Container)) { return 'missing' }
  if ((Test-Path -LiteralPath (Join-Path $path $StorageMarkerName)) -or (Test-Path -LiteralPath (Join-Path $path 'index'))) { return 'store' }
  $n = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Select-Object -First 1).Count
  if ($n -eq 0) { return 'empty' }
  return 'foreign'
}

function Set-ImageStorageMarker([string]$path) {
  $file = Join-Path $path $StorageMarkerName
  if (Test-Path -LiteralPath $file) { return }
  $text = @(
    'Bethesda PACS image store',
    'store_id=' + [guid]::NewGuid().ToString(),
    'created=' + (Get-Date -Format 'yyyy-MM-dd HH:mm'),
    'Do not delete this file or anything in this folder: the image server keeps the images here',
    'and will not start without this file.'
  )
  Set-Content -LiteralPath $file -Value $text -Encoding ascii -ErrorAction Stop
}

# One line about a drive, for a person choosing.
function Format-DriveLine($facts) {
  if (-not $facts.ready) { return "$($facts.root)  not there" }
  $notes = @()
  if ($facts.system) { $notes += 'the Windows disk' }
  if ($facts.usb) { $notes += 'USB - can be unplugged, may go to sleep' }
  if ($facts.kind -eq 'Network') { $notes += 'network drive' }
  if ($facts.format -and $facts.format -ne 'NTFS') { $notes += "$($facts.format), not NTFS" }
  $line = '{0}  {1} free of {2}' -f $facts.root, (Format-Size $facts.free), (Format-Size $facts.total)
  if ($notes.Count) { $line += '  (' + ($notes -join '; ') + ')' }
  return $line
}

# Why a place cannot be the image store ('' = it can). `warn` collects what a person
# should know but that does not forbid it.
function Test-ImageStorageChoice([string]$path, [string]$pacsRoot, [ref]$warn) {
  $w = @()
  if (-not [IO.Path]::IsPathRooted($path) -or $path -notmatch '^[A-Za-z]:[\\/]') { return 'Give a full path with a drive letter, for example D:\Bethesda-PACS-images.' }
  $full = [IO.Path]::GetFullPath($path)
  if ($full -match '^[A-Za-z]:\\?$') { return 'Give a folder, not the drive itself - for example ' + $full.TrimEnd('\') + '\Bethesda-PACS-images.' }
  $facts = Get-DriveFacts $full
  if ($facts.kind -eq 'Network') { return 'A network drive cannot hold the image store.' }
  if ($facts.kind -eq 'CDRom') { return 'That is a CD/DVD drive.' }
  if (-not $facts.ready) { return "Drive $($facts.root) is not there." }
  $state = Test-ImageStorage $full
  if ($state -eq 'foreign') { return 'That folder already holds other files. Choose an empty folder (or a new one).' }
  if ($facts.usb) { $w += 'This is a USB disk: if it is unplugged or goes to sleep, the image server stops. An internal disk is better.' }
  if ($facts.format -and $facts.format -ne 'NTFS') { $w += "This drive is $($facts.format), not NTFS: the free space the EMR sees can be wrong and large files may fail. Format it as NTFS first." }
  if ($facts.system) { $w += 'This is the Windows disk: when the images fill it, Windows and the EMR stop too.' }
  if ($state -eq 'store') { $w += 'An image store is already in that folder: it will be used as it is.' }
  $warn.Value = $w
  return ''
}

# Asks where the images go (first installation, a person at the keyboard). Returns the full
# path chosen; Enter keeps the default.
function Read-ImageStorageChoice([string]$default, [string]$pacsRoot) {
  Write-Host ''
  Write-Host 'Where should the image server keep the images?'
  Write-Host '  They take far more room than anything else: an ultrasound image about 1.5 MB,'
  Write-Host '  an X-ray film 10-30 MB. A large internal disk of its own is best.'
  Write-Host ''
  foreach ($d in [IO.DriveInfo]::GetDrives()) {
    if ("$($d.DriveType)" -in @('CDRom', 'Network')) { continue }
    Write-Host ('    ' + (Format-DriveLine (Get-DriveFacts $d.Name)))
  }
  Write-Host ''
  Write-Host "  Press Enter to keep them here:  $default"
  Write-Host '  or type a folder on another drive, for example  D:\Bethesda-PACS-images'
  while ($true) {
    $raw = Read-Host '  Folder'
    if ($null -eq $raw) { return $default }               # no keyboard after all: the default
    $answer = "$raw".Trim().Trim('"')
    if (-not $answer) { return $default }
    $warn = @()
    $why = Test-ImageStorageChoice $answer $pacsRoot ([ref]$warn)
    if ($why) { Write-Host "  $why" -ForegroundColor Yellow; continue }
    foreach ($w in $warn) { Write-Host "  Note: $w" -ForegroundColor Yellow }
    if ($warn.Count) {
      $yes = "$(Read-Host '  Use this folder anyway? (y/N)')".Trim()
      if ($yes -notmatch '^[yYoO]') { continue }
    }
    return [IO.Path]::GetFullPath($answer)
  }
}

# First installation: decides the place (given, asked, or the default), makes the folder,
# puts the marker in it and writes the line to .env when it is not the default.
# Throws with a sentence a person can read when the place cannot be used.
function Initialize-ImageStorage([string]$pacsRoot, [string]$envFile, [string]$storagePath, [bool]$ask) {
  $default = Join-Path $pacsRoot 'storage'
  $path = $default
  if ($storagePath) {
    $warn = @()
    $why = Test-ImageStorageChoice $storagePath $pacsRoot ([ref]$warn)
    if ($why) { throw $why }
    foreach ($w in $warn) { Write-Host "Note: $w" -ForegroundColor Yellow }
    $path = [IO.Path]::GetFullPath($storagePath)
  } elseif ($ask) {
    $path = Read-ImageStorageChoice $default $pacsRoot
  }
  New-Item -ItemType Directory -Force -Path $path -ErrorAction Stop | Out-Null
  Set-ImageStorageMarker $path
  if ($path.TrimEnd('\') -ne $default.TrimEnd('\')) { Set-EnvValue $envFile $StorageEnvKey ($path.Replace('\', '/')) }
  return $path
}

# Before the image server is started: is the place there, and is it an image store?
# Returns '' when it is (an existing store without the marker gets its marker), or the
# sentences to show. Never creates the folder: a missing place is a thing to be told.
function Confirm-ImageStorage([string]$pacsRoot, [string]$envFile) {
  $path = Get-ImageStoragePath $pacsRoot $envFile
  $state = Test-ImageStorage $path
  if ($state -eq 'store') {
    try { Set-ImageStorageMarker $path } catch { }
    return ''
  }
  $lines = @("The image store is not where it should be: $path")
  if ($state -eq 'nodrive') { $lines += "Drive $([IO.Path]::GetPathRoot($path)) is not there. Is the disk connected? Has its letter changed?" }
  elseif ($state -eq 'missing') { $lines += 'The folder does not exist on that drive. Has the drive letter moved to another disk?' }
  elseif ($state -eq 'empty') { $lines += 'The folder is there but empty: this is not the disk that holds the images (or they were deleted).' }
  else { $lines += 'The folder holds other files and no image store.' }
  $lines += 'The image server is NOT started: on an empty folder it would look healthy and hold no images.'
  $lines += 'Connect the disk (or give it back its letter), then run start.bat again.'
  $lines += "If the images really live somewhere else now, set $StorageEnvKey in .env to that folder."
  return ($lines -join "`n")
}

# True when two paths are on the same physical disk (two partitions of one disk are the
# same disk: one failure takes both). $null when Windows does not say.
function Test-SamePhysicalDisk([string]$a, [string]$b) {
  $fa = Get-DriveFacts $a; $fb = Get-DriveFacts $b
  if ($fa.disk -lt 0 -or $fb.disk -lt 0) {
    if ($fa.root -and $fa.root -eq $fb.root) { return $true }
    return $null
  }
  return ($fa.disk -eq $fb.disk)
}
