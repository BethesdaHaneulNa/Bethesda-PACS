# First-run setup for Bethesda PACS (Orthanc) (Windows).
# Generates a .env with a random Orthanc admin password (only if missing), then starts.
# Safe to re-run: it never overwrites an existing .env.
#
#   .\setup.ps1            normal install (pulls/builds; needs internet)
#   .\setup.ps1 -Offline   use images already loaded from the offline kit; never builds
param([switch]$Offline)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function New-Secret([int]$bytes) {
  $b = New-Object byte[] $bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
  return ([System.BitConverter]::ToString($b) -replace '-', '').ToLower()
}

$bridgeToken = ""
if (-not (Test-Path .env)) {
  Write-Host "First run: generating .env with a random Orthanc password and bridge token..."
  $bridgeToken = New-Secret 24
  @"
ORTHANC_PASSWORD=$(New-Secret 16)

# Worklist bridge -> EMR. BRIDGE_TOKEN must match the EMR's
# Settings -> Order Feed -> Bridge Token. pair-with-emr.ps1 sets both.
BRIDGE_TOKEN=$bridgeToken
# EMR_FEED_URL=http://host.docker.internal:9080/api/pacs/worklist-feed
"@ | Out-File -FilePath .env -Encoding ascii
  Write-Host ".env created. Orthanc login: user 'admin', password is in .env (ORTHANC_PASSWORD)."
} else {
  Write-Host ".env already exists - keeping current secrets."
}

# From here on, docker's own stderr must not stop the script: Windows PowerShell
# 5.1 turns redirected native stderr into terminating errors. Exit codes are checked.
$ErrorActionPreference = 'Continue'

# Warn (only) if Windows could keep 9090/4242 from Docker: the container would
# still look healthy while nothing answers (EMR wiki, PACS P-1).
& (Join-Path $PSScriptRoot 'check-windows-ports.ps1')

if ($Offline) {
  Write-Host "Offline mode: starting from pre-loaded images (no build, no downloads)."
  docker compose up -d --no-build
} else {
  docker compose up -d
}
if ($LASTEXITCODE -ne 0) { Write-Host "Could not start the PACS containers." -ForegroundColor Red; exit 1 }

# First run with the EMR on this machine: pair the two directly, so the token is
# never read off the screen and typed into the EMR. pair-with-emr.ps1 makes a new
# token, gives it to the EMR on stdin and to .env, and restarts the bridge.
$paired = $false
if ($bridgeToken) {
  $emrDb = (docker inspect -f '{{.State.Running}}' bethesda-emr-db 2>$null)
  if ($emrDb -eq 'true') {
    Write-Host ""
    Write-Host "The EMR is running on this machine - pairing the worklist bridge with it..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'pair-with-emr.ps1')
    $paired = ($LASTEXITCODE -eq 0)
  }
}

# The address the other PCs' browsers use for the viewer. localhost only works on
# this machine; the EMR setting must name this PC as the others see it.
$lanIp = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.InterfaceAlias -notmatch 'vEthernet|WSL|Docker|Loopback' } |
  Select-Object -ExpandProperty IPAddress) | Select-Object -First 1

Write-Host ""
Write-Host "Bethesda PACS (Orthanc) is starting at http://localhost:9090"
Write-Host "Login with user 'admin' and the ORTHANC_PASSWORD value in .env"
if ($lanIp) {
  Write-Host ""
  Write-Host "Imaging devices send to this PC: $lanIp, DICOM port 4242 (give this PC a fixed IP)."
  Write-Host "Staff see images inside the EMR - nothing to set for the viewer."
}
if ($paired) {
  Write-Host ""
  Write-Host "Worklist bridge paired with the EMR on this machine - nothing to copy."
} elseif ($bridgeToken) {
  Write-Host ""
  Write-Host "==================================================================="
  Write-Host " IMPORTANT - pair the worklist bridge with the EMR:"
  Write-Host " If the EMR runs on this machine: start it, then run .\pair-with-emr.ps1"
  Write-Host " Otherwise, in the EMR open Settings -> Order Feed -> Bridge Token"
  Write-Host " and set it to:"
  Write-Host "   $bridgeToken"
  Write-Host "==================================================================="
}
Write-Host ""
Write-Host "After restoring an EMR backup, run .\pair-with-emr.ps1 again - the backup"
Write-Host "brings the old machine's bridge token with it."
exit 0
