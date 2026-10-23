$ErrorActionPreference = "SilentlyContinue"

$AppName = "PortalKeepalive"
$BaseDir = Join-Path $env:APPDATA $AppName

try { Unregister-ScheduledTask -TaskName $AppName -Confirm:$false } catch {}
Remove-Item -Recurse -Force $BaseDir

Write-Host "PortalKeepalive uninstalled."
