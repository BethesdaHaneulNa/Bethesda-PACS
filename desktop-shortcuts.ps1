# Bethesda PACS - shortcuts on the desktop of this PC (the server):
#   "Bethesda PACS"   the image server's own page (Orthanc, http://localhost:9090) - for the
#                     administrator: it asks for the 'admin' password of .env
#   "Bethesda CD"     the program that copies a patient's images to a CD (bethesda-cd\)
# Run by setup.ps1 at the end of an installation; can be run again by itself.
#
# Only files are made on the desktop (.url / .lnk): no registry key, no scheduled task. A
# shortcut that is there already is corrected, not doubled.
#
#   -IconFile x.ico     the icon of the "Bethesda PACS" shortcut (default: bethesda-pacs.ico
#                       beside this script when there is one, else the browser's own)
param([string]$Desktop = '', [string]$PacsUrl = 'http://localhost:9090', [string]$IconFile = '')
$ErrorActionPreference = 'Stop'
if (-not $Desktop) { $Desktop = [Environment]::GetFolderPath('Desktop') }
if (-not $IconFile) { $own = Join-Path $PSScriptRoot 'bethesda-pacs.ico'; if (Test-Path -LiteralPath $own) { $IconFile = $own } }

# a web address on the desktop: a small text file Windows opens in the browser
$url = Join-Path $Desktop 'Bethesda PACS.url'
$was = Test-Path -LiteralPath $url
$lines = @('[InternetShortcut]', "URL=$PacsUrl")
if ($IconFile -and (Test-Path -LiteralPath $IconFile)) { $lines += @("IconFile=$((Resolve-Path -LiteralPath $IconFile).Path)", 'IconIndex=0') }
[IO.File]::WriteAllLines($url, $lines, [Text.Encoding]::ASCII)
"shortcut: $url -> $PacsUrl ($(if ($was) { 'corrected' } else { 'made' }))"

$cd = Join-Path $PSScriptRoot 'bethesda-cd\install.ps1'
if (Test-Path -LiteralPath $cd) { & $cd -Here -Quiet -Desktop $Desktop }
