$ErrorActionPreference = "Stop"

$AppName = "PortalKeepalive"
$BaseDir = Join-Path $env:APPDATA $AppName
$ScriptName = "PortalKeepalive.ps1"
$ScriptPath = Join-Path $BaseDir $ScriptName

if (-not (Test-Path $BaseDir)) { New-Item -ItemType Directory -Path $BaseDir | Out-Null }

# Copy script (expects to be in same folder as installer)
$src = Join-Path $PSScriptRoot $ScriptName
if (Test-Path $src) {
    Copy-Item $src $ScriptPath -Force
} else {
    throw "PortalKeepalive.ps1 not found next to installer"
}

# Register scheduled task (current user, at logon + every 1 minute)
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" keepalive"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$trigger.Repetition.Interval = "PT1M"
$trigger.Repetition.Duration = "P1D"
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
try {
    Register-ScheduledTask -TaskName $AppName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host "Scheduled task registered"
} catch {
    Write-Warning "Could not register scheduled task: $_"
}

# Initial login (prompts for credentials)
Write-Host "Initial setup: you will be asked for username and password."
& powershell.exe -ExecutionPolicy Bypass -File $ScriptPath login

Write-Host "Installation complete. Keepalive will run at logon and every 1 minute."
