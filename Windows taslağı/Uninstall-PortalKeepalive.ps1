$ErrorActionPreference = "SilentlyContinue"

$AppName = "PortalKeepalive"
$BaseDir = Join-Path $env:ProgramData $AppName

foreach ($t in $AppName, "$AppName-Notify") { try { Unregister-ScheduledTask -TaskName $t -Confirm:$false } catch {} }
Remove-Item -Recurse -Force $BaseDir

Write-Host "PortalKeepalive uninstalled."
