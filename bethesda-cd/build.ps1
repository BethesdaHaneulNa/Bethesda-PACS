# Bethesda CD - build. Uses only what Windows has: the C# compiler of the .NET Framework
# (csc.exe, C# 5). Nothing is installed, nothing is downloaded.
#
#   .\build.ps1                  -> build\Bethesda-CD.exe   (the viewer VIEWER.EXE is inside it)
#   .\build.ps1 -IconFile x.ico  with a given icon file
#
# The icon: -IconFile when given; else icon\Bethesda-CD.ico when that file is there (the
# chosen one, once it exists); else one drawn on the spot by icon\make-icon.ps1 (-Icon A, B, C).
#
# Two programs are built:
#   VIEWER.EXE        the small viewer that goes on every disc  (src\viewer + src\shared)
#   Bethesda-CD.exe   the program the clinic runs               (src\app + src\shared, and the
#                     viewer's reading of a disc - src\viewer\Dicom.cs, Disc.cs - for "bring in"),
#                     carrying VIEWER.EXE inside itself as a resource - so every disc
#                     it makes gets the very same viewer file.
param([string]$Out = (Join-Path $PSScriptRoot 'build'), [ValidateSet('A', 'B', 'C')][string]$Icon = 'A', [string]$IconFile = '')
$ErrorActionPreference = 'Stop'
$csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { throw "The C# compiler of the .NET Framework was not found: $csc" }
if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Path $Out | Out-Null }
$src = Join-Path $PSScriptRoot 'src'
function Sources([string[]]$Folders) { foreach ($f in $Folders) { Get-ChildItem -LiteralPath (Join-Path $src $f) -Filter '*.cs' -File | Sort-Object Name | ForEach-Object { $_.FullName } } }
function Compile([string]$What, [string[]]$Arguments) {
  $log = & $csc /nologo /warn:4 /optimize+ /platform:anycpu /codepage:65001 $Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { $log | ForEach-Object { Write-Host $_ }; throw "$What did not compile" }
  $log | Where-Object { $_ -match 'warning' } | ForEach-Object { Write-Host $_ }
}

$ico = Join-Path $Out 'Bethesda-CD.ico'
if (-not $IconFile) { $chosen = Join-Path $PSScriptRoot 'icon\Bethesda-CD.ico'; if (Test-Path -LiteralPath $chosen) { $IconFile = $chosen } }
if ($IconFile) {
  if (-not (Test-Path -LiteralPath $IconFile)) { throw "The icon file was not found: $IconFile" }
  Copy-Item -LiteralPath $IconFile -Destination $ico -Force
} else { & (Join-Path $PSScriptRoot 'icon\make-icon.ps1') -Variant $Icon -Out $ico | Out-Null }

$viewer = Join-Path $Out 'VIEWER.EXE'
Compile 'The viewer' (@('/target:winexe', "/out:$viewer", "/win32icon:$ico", '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll') + (Sources 'shared', 'viewer'))

$exe = Join-Path $Out 'Bethesda-CD.exe'
Compile 'Bethesda CD' (@('/target:winexe', "/out:$exe", "/win32icon:$ico", "/resource:$viewer,VIEWER.EXE",
    '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll', '/r:System.IO.Compression.dll', '/r:System.IO.Compression.FileSystem.dll',
    '/r:System.Web.Extensions.dll', '/r:Microsoft.CSharp.dll') + (Sources 'shared', 'app') + @((Join-Path $src 'viewer\Dicom.cs'), (Join-Path $src 'viewer\Disc.cs')))

$v = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
"built: $exe"
"  $($v.ProductName) $($v.ProductVersion) - $((Get-Item $exe).Length) bytes, the viewer inside it $((Get-Item $viewer).Length) bytes"
