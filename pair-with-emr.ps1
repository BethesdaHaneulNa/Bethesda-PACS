# Pair this PACS with the EMR running on the same machine (Windows).
#
# Makes a new bridge token and puts the same value in this folder's .env and in
# the EMR's settings (pacs_config.bridge_token), then restarts the bridge so it
# uses it. The value never appears on screen, on a command line or in a log:
# the EMR receives it on stdin, and the two copies are compared by hash.
#
# Run it:
#   - after installing (setup.ps1 does this for you when the EMR is already up),
#   - again AFTER RESTORING AN EMR BACKUP - the backup brings the old machine's
#     token with it, and the bridge is refused until the two match again.
#
#   .\pair-with-emr.ps1
#   .\pair-with-emr.ps1 -NoRestart          # leave the bridge alone (tests)
param(
  [string]$EnvFile = (Join-Path $PSScriptRoot '.env'),
  [string]$DbContainer = 'bethesda-emr-db',
  [switch]$NoRestart
)
# Not 'Stop': Windows PowerShell 5.1 turns anything a native command (docker)
# writes to stderr into a terminating error, which would replace the messages
# below with a stack trace. Every docker call's exit code is checked instead.
$ErrorActionPreference = 'Continue'

if (-not (Test-Path $EnvFile)) { Write-Host "No .env at $EnvFile - run setup first."; exit 1 }
$running = (docker inspect -f '{{.State.Running}}' $DbContainer 2>$null)
if ($running -ne 'true') { Write-Host "The EMR database ($DbContainer) is not running on this machine - start the EMR first."; exit 1 }

$lines = @(Get-Content $EnvFile -ErrorAction Stop)
if (@($lines | Where-Object { $_ -match '^BRIDGE_TOKEN=' }).Count -ne 1) {
  Write-Host 'BRIDGE_TOKEN= must appear exactly once in .env - stopped, nothing changed.'; exit 1
}

function Md5([string]$s) {
  ([System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($s))) -replace '-', '').ToLower()
}

$b = New-Object byte[] 24
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
$tok = ([System.BitConverter]::ToString($b) -replace '-', '').ToLower()

# The EMR creates its tables when its backend first starts, which may still be
# under way right after installing - so try for a minute before giving up.
# The EMR is written first: if it fails, .env is untouched and nothing is out of step.
$ok = $false
for ($i = 0; $i -lt 20 -and -not $ok; $i++) {
  "UPDATE pacs_config SET bridge_token = '$tok', updated_at = NOW() WHERE id = 1;" |
    docker exec -i $DbContainer psql -U medconnect -d medconnect -q -v ON_ERROR_STOP=1 2>$null
  if ($LASTEXITCODE -eq 0) { $ok = $true } else { Start-Sleep -Seconds 3 }
}
if (-not $ok) { Write-Host 'Could not write to the EMR settings (is the EMR finished starting?) - .env not changed.'; exit 1 }

# Keep the old .env outside this folder until the new one is confirmed: a copy
# left beside it would end up in an install kit (it holds the Orthanc password).
$backup = Join-Path $env:TEMP ('pacs-env-before-pair-' + [guid]::NewGuid().ToString('N') + '.bak')
Copy-Item $EnvFile $backup -Force -ErrorAction Stop
$lines = $lines | ForEach-Object { if ($_ -match '^BRIDGE_TOKEN=') { "BRIDGE_TOKEN=$tok" } else { $_ } }
Set-Content -Path $EnvFile -Value $lines -Encoding ascii -ErrorAction Stop

$want = Md5 $tok
Remove-Variable tok, b
$db = (docker exec $DbContainer psql -U medconnect -d medconnect -tAc "SELECT md5(bridge_token) FROM pacs_config WHERE id = 1").Trim()
$fileTok = ((Get-Content $EnvFile) | Where-Object { $_ -match '^BRIDGE_TOKEN=' }) -replace '^BRIDGE_TOKEN=', ''
$file = Md5 $fileTok
Remove-Variable fileTok
if ($db -ne $want -or $file -ne $want) {
  Write-Host "FAILED - the EMR and .env do not hold the same token. The previous .env is at $backup"
  exit 1
}
Remove-Item $backup -Force

if (-not $NoRestart) {
  # The bridge reads .env only when its container is created.
  Push-Location $PSScriptRoot
  docker compose up -d --force-recreate worklist-bridge
  $restarted = ($LASTEXITCODE -eq 0)
  Pop-Location
  if (-not $restarted) { Write-Host 'Paired, but the bridge did not restart - run: docker compose up -d --force-recreate worklist-bridge'; exit 1 }
}
Write-Host 'Paired with the EMR: both hold the same new bridge token (not shown).'
exit 0
