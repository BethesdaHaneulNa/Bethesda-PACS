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
# Settings -> Order Feed -> Bridge Token (paste the value printed below).
BRIDGE_TOKEN=$bridgeToken
# EMR_FEED_URL=http://host.docker.internal:9080/api/pacs/worklist-feed
"@ | Out-File -FilePath .env -Encoding ascii
  Write-Host ".env created. Orthanc login: user 'admin', password is in .env (ORTHANC_PASSWORD)."
} else {
  Write-Host ".env already exists - keeping current secrets."
}

if ($Offline) {
  Write-Host "Offline mode: starting from pre-loaded images (no build, no downloads)."
  docker compose up -d --no-build
} else {
  docker compose up -d
}

Write-Host ""
Write-Host "Bethesda PACS (Orthanc) is starting at http://localhost:9090"
Write-Host "Login with user 'admin' and the ORTHANC_PASSWORD value in .env"
if ($bridgeToken) {
  Write-Host ""
  Write-Host "==================================================================="
  Write-Host " IMPORTANT - pair the worklist bridge with the EMR:"
  Write-Host " In the EMR, open Settings -> Order Feed -> Bridge Token and set it to:"
  Write-Host "   $bridgeToken"
  Write-Host "==================================================================="
}
