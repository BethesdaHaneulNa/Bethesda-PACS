# Moves the image store to another folder - usually another drive (Windows).
#
#   .\move-image-storage.ps1 -To D:\Bethesda-PACS-images          do it
#   .\move-image-storage.ps1 -To D:\Bethesda-PACS-images -Check   only say what would be done
#
# What it does, in this order:
#   1. asks the image server how much it holds (studies, images, bytes)
#   2. stops the image server and the worklist bridge   <- devices cannot send meanwhile
#   3. copies the whole store to the new folder (robocopy) and compares every file's size;
#      the index and a sample of the image files are also compared byte for byte
#      (-FullVerify: every file)
#   4. writes the new place into .env and starts the two again
#   5. asks the image server again: the three numbers must be what they were
#   6. renames the old folder to "<name>.moved-<date>" - it is NOT deleted. Delete it by
#      hand later, once the nightly backup has run and the images open as usual.
# If anything fails before step 6, .env is put back and the image server is started on the
# old place, which was never changed. What was copied to the new folder is left there.
#
# Nothing is asked of the EMR: it reaches the image server at the same address as before.
# Exit: 0 moved (or -Check found nothing against it), 1 not moved (the reason is said).
param(
  [Parameter(Mandatory = $true)][string]$To,
  [switch]$Check,
  [switch]$FullVerify,
  [switch]$AllowUsb,                                   # a USB disk as the image store: only when said so
  [string]$OrthancUrl = 'http://localhost:9090',
  [string]$EnvFile = '',                               # default: .env in this folder
  [int]$SampleFiles = 200
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
# ($PSScriptRoot is still empty while the parameters above get their defaults - a script
# with a mandatory parameter - so the default is given here.)
if (-not $EnvFile) { $EnvFile = Join-Path $PSScriptRoot '.env' }
Set-Location $PSScriptRoot
. (Join-Path $PSScriptRoot 'image-storage-common.ps1')

$logDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logFile = Join-Path $logDir 'move-image-storage.log'
function Say([string]$m, [string]$color = '') {
  $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $m
  if ($color) { Write-Host $m -ForegroundColor $color } else { Write-Host $m }
  Add-Content -Path $logFile -Value $line -Encoding utf8
}
function Stop-Here([string]$m) { Say $m 'Red'; exit 1 }

# What the image server holds, or $null when it does not answer.
function Get-Holdings {
  $cfg = Read-EnvFile $EnvFile
  $pair = [Text.Encoding]::ASCII.GetBytes('admin:' + $cfg['ORTHANC_PASSWORD'])
  $h = @{ Authorization = 'Basic ' + [Convert]::ToBase64String($pair) }
  try {
    $s = Invoke-RestMethod -Uri ($OrthancUrl.TrimEnd('/') + '/statistics') -Headers $h -TimeoutSec 15 -ErrorAction Stop
    return @{ studies = [int64]$s.CountStudies; images = [int64]$s.CountInstances; bytes = [int64]$s.TotalDiskSize }
  } catch { return $null }
}
function Wait-Holdings([int]$seconds) {
  $until = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $until) { $h = Get-Holdings; if ($h) { return $h }; Start-Sleep -Seconds 3 }
  return $null
}
function Same-Holdings($a, $b) { return ($a -and $b -and $a.studies -eq $b.studies -and $a.images -eq $b.images -and $a.bytes -eq $b.bytes) }
function Text-Holdings($h) { return "$($h.studies) studies, $($h.images) images, $(Format-Size $h.bytes)" }

# Every file under a folder as "relative path -> length".
function Get-FileTable([string]$root) {
  $t = @{}
  $n = $root.TrimEnd('\').Length + 1
  foreach ($f in [IO.Directory]::EnumerateFiles($root, '*', [IO.SearchOption]::AllDirectories)) {
    $t[$f.Substring($n)] = (New-Object IO.FileInfo $f).Length
  }
  return $t
}
function Get-Sha([string]$file) { return (Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash }

# -- what is asked ----------------------------------------------------------
if (-not (Test-Path $EnvFile)) { Stop-Here "No .env in this folder - the PACS is not installed here." }
$src = Get-ImageStoragePath $PSScriptRoot $EnvFile
$warn = @()
$why = Test-ImageStorageChoice $To $PSScriptRoot ([ref]$warn)
if ($why) { Stop-Here $why }
$dest = [IO.Path]::GetFullPath($To).TrimEnd('\')
$src = $src.TrimEnd('\')
if ($dest -ieq $src) { Stop-Here "The images are already in $dest - nothing to move." }
if ($dest.StartsWith($src + '\', [StringComparison]::OrdinalIgnoreCase) -or $src.StartsWith($dest + '\', [StringComparison]::OrdinalIgnoreCase)) {
  Stop-Here 'The new folder cannot be inside the old one (or the other way round).'
}
if ((Test-ImageStorage $src) -ne 'store') { Stop-Here "There is no image store at $src - nothing to move. (Is its disk connected?)" }
$state = Test-ImageStorage $dest
if ($state -eq 'store') { Stop-Here "$dest already holds an image store. This script copies into an empty folder only." }
$facts = Get-DriveFacts $dest
if ($facts.usb -and -not $AllowUsb) {
  Stop-Here "$($facts.root) is a USB disk: if it is unplugged or goes to sleep the image server stops. Use an internal disk - or, if this is really meant, run again with -AllowUsb."
}

Say "Image store now : $src"
Say "Move it to      : $dest"
Say ('Drive           : ' + (Format-DriveLine $facts))
foreach ($w in $warn) { Say "Note: $w" 'Yellow' }

$before = Get-Holdings
if (-not $before) { Stop-Here "The image server does not answer at $OrthancUrl. Start it first (start.bat): what it holds is counted before and after the move." }
Say ('It holds        : ' + (Text-Holdings $before))

Say 'Measuring the store on disk...'
$table = Get-FileTable $src
$bytes = [int64]0; foreach ($v in $table.Values) { $bytes += $v }
Say ("On disk         : $($table.Count) files, " + (Format-Size $bytes))
$need = [int64]($bytes * 1.05) + 1GB
if ($facts.free -lt $need) { Stop-Here ("Not enough room on $($facts.root): " + (Format-Size $facts.free) + ' free, ' + (Format-Size $need) + ' needed.') }
if ((Test-SamePhysicalDisk $src $dest) -eq $true) { Say 'Note: the new folder is on the same physical disk as the old one.' 'Yellow' }

if ($Check) { Say 'Checked only (-Check): nothing was stopped, copied or changed.' 'Green'; exit 0 }

# -- the move ---------------------------------------------------------------
$envBefore = Get-Content $EnvFile
function Put-Back([string]$m) {
  Say $m 'Red'
  Say 'Putting things back: .env as it was, the image server on the old place.' 'Yellow'
  Set-Content -Path $EnvFile -Value $envBefore -Encoding ascii
  docker compose up -d 2>&1 | Out-Null
  $h = Wait-Holdings 120
  if (Same-Holdings $h $before) { Say ('The image server runs on the old place again and holds ' + (Text-Holdings $h) + '.') 'Yellow' }
  else { Say 'The image server did not come back as it was - run start.bat and look at: docker logs bethesda-pacs' 'Red' }
  Say "What was copied to $dest is left there (it is not the image store). Nothing was deleted." 'Yellow'
  exit 1
}

Say 'Stopping the image server and the worklist bridge (devices cannot send until this is done)...'
docker compose stop 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-Here 'Could not stop the containers - nothing was changed.' }

# The store must not be changing now: it is measured again after the stop.
$table = Get-FileTable $src
New-Item -ItemType Directory -Force -Path $dest -ErrorAction SilentlyContinue | Out-Null
if (-not (Test-Path -LiteralPath $dest)) { Put-Back "Could not make the folder $dest." }

Say 'Copying (a large store takes long - as long as copying that much between the two disks)...'
$roboLog = Join-Path $logDir 'move-image-storage-robocopy.log'
robocopy $src $dest /E /COPY:DAT /DCOPY:T /R:2 /W:5 /NP /NFL /NDL /LOG:$roboLog | Out-Null
if ($LASTEXITCODE -ge 8) { Put-Back "The copy failed (robocopy said $LASTEXITCODE - see $roboLog)." }

Say 'Comparing every file...'
$copy = Get-FileTable $dest
$bad = @()
foreach ($k in $table.Keys) { if (-not $copy.ContainsKey($k) -or $copy[$k] -ne $table[$k]) { $bad += $k } }
if ($bad.Count -or $copy.Count -ne $table.Count) { Put-Back "The copy is not the same as the original: $($bad.Count) file(s) missing or of another size, $($copy.Count) files against $($table.Count)." }
$names = @($table.Keys)
$compare = if ($FullVerify -or $names.Count -le $SampleFiles) { $names } else { @($names | Where-Object { $_ -notmatch '\\' }) + @($names | Get-Random -Count $SampleFiles) | Select-Object -Unique }
$n = 0
foreach ($k in $compare) {
  try { if ((Get-Sha (Join-Path $src $k)) -ne (Get-Sha (Join-Path $dest $k))) { $bad += $k } } catch { $bad += $k }
  $n++
}
if ($bad.Count) { Put-Back "The copy differs from the original in $($bad.Count) of $n file(s) compared byte for byte." }
Say ("Same: $($table.Count) files by size, $n of them byte for byte" + $(if ($FullVerify) { ' (all).' } else { '.' }))

Set-ImageStorageMarker $dest
Set-EnvValue $EnvFile $StorageEnvKey ($dest.Replace('\', '/'))
Say 'Starting the image server on the new place...'
docker compose up -d 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Put-Back 'The containers did not start on the new place.' }
$after = Wait-Holdings 180
if (-not $after) { Put-Back 'The image server does not answer on the new place.' }
if (-not (Same-Holdings $after $before)) { Put-Back ('On the new place the image server holds ' + (Text-Holdings $after) + ' - before the move it held ' + (Text-Holdings $before) + '.') }
Say ('It holds        : ' + (Text-Holdings $after) + ' - the same as before.') 'Green'

# The old folder is kept under another name: nothing mounts it any more.
$kept = $src + '.moved-' + (Get-Date -Format 'yyyyMMdd-HHmm')
try { Rename-Item -LiteralPath $src -NewName (Split-Path $kept -Leaf) -ErrorAction Stop }
catch { $kept = $src; Say "The old folder could not be renamed (something holds it open): it stays as $src. It is no longer used." 'Yellow' }

Say ''
Say "Done. The images are now in $dest" 'Green'
Say "The old copy is kept as $kept"
Say 'Delete it by hand later - once the images open in the EMR as usual and the nightly backup has run.'
Say 'Until then it takes its room on the old disk.'
exit 0
