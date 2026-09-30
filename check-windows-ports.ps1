# Read-only check: can Windows hand the PACS its ports? (setup.ps1 runs this.)
#
# Windows reserves blocks of TCP ports for Hyper-V/WSL at every boot, inside its
# "dynamic port range". If 9090 or 4242 falls inside a reserved block, Docker
# cannot publish it - and the container still reports healthy, so the viewer and
# the imaging devices just time out (this happened in 2026: the range had been
# moved to start at 1024; see the EMR wiki, PACS P-1). This only reads and
# warns; the fix needs an administrator and a reboot.
#
# It also looks for OTHER programs already listening on the EMR's and the
# PACS's ports. In 2026-09 a download manager (PikPak's DownloadServer.exe) sat
# on 127.0.0.1:9080: Docker still published 9080 on the other addresses, so the
# EMR opened in a browser, but everything that called 127.0.0.1 or
# host.docker.internal - the worklist bridge included - reached that program
# instead, and no worklist went to the devices.
#
#   .\check-windows-ports.ps1            exit 0 fine, 1 a port is at risk
param(
  [int[]]$Ports = @(9090, 4242),               # reserved-range check
  [int[]]$ListenPorts = @(9080, 9090, 4242)     # "another program listens" check (EMR 9080 too)
)
$ErrorActionPreference = 'Continue'
$risk = $false

# "Start Port : 49152" / "Number of Ports : 16384" (words are localised; the
# numbers come in that order).
$dyn = @(netsh int ipv4 show dynamicport tcp 2>$null | ForEach-Object { if ($_ -match ':\s*(\d+)\s*$') { [int]$Matches[1] } })
if ($dyn.Count -ge 2) {
  $start = $dyn[0]; $end = $dyn[0] + $dyn[1] - 1
  foreach ($p in $Ports) {
    if ($p -ge $start -and $p -le $end) {
      Write-Host "  WARNING: port $p is inside Windows' dynamic port range ($start-$end)." -ForegroundColor Yellow
      Write-Host "           Windows may reserve it at any reboot. Windows' default range starts at 49152." -ForegroundColor Yellow
      $risk = $true
    }
  }
}

# Reserved blocks right now: two numbers per line (start, end).
$ranges = @(netsh interface ipv4 show excludedportrange protocol=tcp 2>$null | ForEach-Object {
  if ($_ -match '^\s*(\d+)\s+(\d+)') { ,@([int]$Matches[1], [int]$Matches[2]) } })
foreach ($p in $Ports) {
  foreach ($r in $ranges) {
    if ($p -ge $r[0] -and $p -le $r[1]) {
      Write-Host "  WARNING: port $p is reserved by Windows right now ($($r[0])-$($r[1])). The PACS will not be reachable on it." -ForegroundColor Yellow
      $risk = $true
    }
  }
}

$rangeRisk = $risk
# Another program listening on one of the ports - on any address, 127.0.0.1
# included. Docker Desktop's own listeners are com.docker.backend (and
# wslrelay for WSL); anything else is someone else's.
$dockerNames = @('com.docker.backend', 'com.docker.proxy', 'wslrelay', 'vpnkit', 'docker-proxy', 'Docker Desktop')
$others = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
  Where-Object { $ListenPorts -contains $_.LocalPort } |
  ForEach-Object {
    $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
    [pscustomobject]@{ Port = $_.LocalPort; Address = $_.LocalAddress; Name = $(if ($proc) { $proc.ProcessName } else { "process $($_.OwningProcess)" }); Path = $(if ($proc) { $proc.Path } else { '' }) }
  } | Where-Object { $dockerNames -notcontains $_.Name } | Sort-Object Port, Name, Address -Unique)
$busy = $false
foreach ($o in $others) {
  Write-Host "  WARNING: port $($o.Port) is already used by another program: $($o.Name) (listening on $($o.Address))." -ForegroundColor Yellow
  if ($o.Path) { Write-Host "           $($o.Path)" -ForegroundColor Yellow }
  $busy = $true
}
if ($busy) {
  Write-Host "  Close that program (and stop it from starting with Windows), or change the port." -ForegroundColor Yellow
  Write-Host "  While it runs, the EMR and the PACS can look fine but not reach each other." -ForegroundColor Yellow
  $risk = $true
}

if ($rangeRisk) {
  Write-Host ""
  Write-Host "  To fix (as administrator), then reboot:" -ForegroundColor Yellow
  Write-Host "    netsh int ipv4 set dynamicport tcp start=49152 num=16384" -ForegroundColor Yellow
  Write-Host "    netsh int ipv6 set dynamicport tcp start=49152 num=16384" -ForegroundColor Yellow
}
if ($risk) { exit 1 }
exit 0
