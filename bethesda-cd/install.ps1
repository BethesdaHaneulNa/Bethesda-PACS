# Bethesda CD - put the program on this PC and a shortcut on the desktop.
#
#   install.bat                      double-click: copies Bethesda-CD.exe to this user's programs
#                                    folder, asks for the address of the EMR, makes "Bethesda CD"
#                                    on the desktop
#   .\install.ps1 -EmrUrl http://192.168.1.10:9080        the same, without the question
#   .\install.ps1 -Here              no copy: the shortcut points at the program where it is
#                                    (the server PC, where this folder stays)
#
# What it does, and nothing else: copies one file (Bethesda-CD.exe - the viewer is inside
# it), writes Bethesda-CD.ini beside it when there is none (the EMR's address, never a
# password), and makes or corrects one shortcut file on the desktop. No registry key, no
# scheduled task, no system setting. To remove: delete the shortcut and the folder.
param(
  [string]$To = '',              # where the program goes (default: %LOCALAPPDATA%\Programs\Bethesda CD)
  [string]$EmrUrl = '',          # the address of the EMR, e.g. http://192.168.1.10:9080
  [string]$Desktop = '',         # where the shortcut goes (default: this user's desktop)
  [string]$IconFile = '',        # an .ico for the shortcut (default: the program's own icon)
  [switch]$Here, [switch]$Quiet  # -Quiet: ask nothing
)
$ErrorActionPreference = 'Stop'
$name = 'Bethesda CD'

# the program: built here, or lying beside this script
$exe = Join-Path $PSScriptRoot 'build\Bethesda-CD.exe'
if (-not (Test-Path -LiteralPath $exe)) {
  if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'src\app')) { & (Join-Path $PSScriptRoot 'build.ps1') | Out-Null }
  elseif (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Bethesda-CD.exe')) { $exe = Join-Path $PSScriptRoot 'Bethesda-CD.exe' }
}
if (-not (Test-Path -LiteralPath $exe)) { throw 'Bethesda-CD.exe was not found (run build.ps1 first).' }

if ($Here) { $target = $exe }
else {
  if (-not $To) { $To = Join-Path $env:LOCALAPPDATA "Programs\$name" }
  if (-not (Test-Path -LiteralPath $To)) { New-Item -ItemType Directory -Path $To -Force | Out-Null }
  $target = Join-Path $To 'Bethesda-CD.exe'
  Copy-Item -LiteralPath $exe -Destination $target -Force
  "program: $target"
}

# the settings beside it: written only when there are none yet
$ini = Join-Path (Split-Path -Parent $target) 'Bethesda-CD.ini'
if (-not (Test-Path -LiteralPath $ini)) {
  if (-not $EmrUrl -and -not $Quiet) { $EmrUrl = Read-Host "Address of the EMR (for example http://192.168.1.10:9080 - Enter to type it later in the program)" }
  $EmrUrl = "$EmrUrl".Trim()
  if ($EmrUrl) {
    if ($EmrUrl -notmatch '^https?://[^/\s]+') { throw "The address of the EMR must start with http:// - got: $EmrUrl" }
    [IO.File]::WriteAllLines($ini, @('# Bethesda CD. The address of the EMR, the last folder a copy was saved in, the language (fr, ko, en).', "emr_url=$EmrUrl", 'last_folder='), (New-Object Text.UTF8Encoding($false)))
    "settings: $ini (EMR at $EmrUrl)"
  }
} else { "settings: $ini kept as it is" }

# the shortcut: made, or corrected when it is there already - never a second one
if (-not $Desktop) { $Desktop = [Environment]::GetFolderPath('Desktop') }
$lnk = Join-Path $Desktop "$name.lnk"
$was = Test-Path -LiteralPath $lnk
$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($lnk)
$s.TargetPath = $target; $s.WorkingDirectory = Split-Path -Parent $target
$s.Description = 'Copy a patient''s images to a CD'
$s.IconLocation = $(if ($IconFile -and (Test-Path -LiteralPath $IconFile)) { (Resolve-Path -LiteralPath $IconFile).Path + ',0' } else { "$target,0" })
$s.Save()
"shortcut: $lnk ($(if ($was) { 'corrected' } else { 'made' }))"
