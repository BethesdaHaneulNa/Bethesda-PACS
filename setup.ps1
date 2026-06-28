# First-run setup for Bethesda PACS (Orthanc) (Windows).
# Generates a .env with a random Orthanc admin password (only if missing), then starts.
# Safe to re-run: it never overwrites an existing .env.
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
# EMR_FEED_URL=http://host.docker.internal:8080/api/pacs/worklist-feed
"@ | Out-File -FilePath .env -Encoding ascii
  Write-Host ".env created. Orthanc login: user 'admin', password is in .env (ORTHANC_PASSWORD)."
} else {
  Write-Host ".env already exists - keeping current secrets."
}

docker compose up -d

Write-Host ""
Write-Host "Bethesda PACS (Orthanc) is starting at http://localhost:8090"
Write-Host "Login with user 'admin' and the ORTHANC_PASSWORD value in .env"
if ($bridgeToken) {
  Write-Host ""
  Write-Host "==================================================================="
  Write-Host " IMPORTANT - pair the worklist bridge with the EMR:"
  Write-Host " In the EMR, open Settings -> Order Feed -> Bridge Token and set it to:"
  Write-Host "   $bridgeToken"
  Write-Host "==================================================================="
}
