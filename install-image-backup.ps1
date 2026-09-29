# Register (or remove) the nightly PACS image backup as a Windows scheduled task.
#
# Runs image-backup.ps1 every night at 02:30 - after the EMR's own database
# backup (02:00 by default). "Only when the user is logged on": Docker Desktop
# itself runs in the logged-on user's session, so the PACS is only up then too,
# and no administrator rights or stored password are needed. A night the PC was
# off is caught up at the next start.
#
# This changes a Windows setting. It is run once, on the clinic's server, by the
# person installing - not by a development session.
#
#   .\install-image-backup.ps1            register
#   .\install-image-backup.ps1 -WhatIf    show what would be registered, change nothing
#   .\install-image-backup.ps1 -Remove    unregister
param(
  [string]$At = '02:30',
  [switch]$Remove,
  [switch]$WhatIf
)
$ErrorActionPreference = 'Continue'
$taskName = 'Bethesda PACS image backup'
$script = Join-Path $PSScriptRoot 'image-backup.ps1'
$arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`""

if ($Remove) {
  if ($WhatIf) { Write-Host "Would remove scheduled task '$taskName'."; exit 0 }
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "Removed '$taskName' (if it existed)."; exit 0
}

Write-Host "Scheduled task '$taskName':"
Write-Host "  every day at $At, only while $env:USERNAME is logged on, catch up a missed night"
Write-Host "  runs: powershell.exe $arg"
if ($WhatIf) { Write-Host "(-WhatIf: nothing registered.)"; exit 0 }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 6) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
if (-not $?) { Write-Host 'Could not register the task.'; exit 1 }
Write-Host 'Registered. Test it now with:  .\image-backup.ps1'
exit 0
