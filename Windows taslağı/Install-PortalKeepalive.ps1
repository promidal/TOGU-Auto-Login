$ErrorActionPreference = "Stop"

# Keep the console open on failure, otherwise the window just vanishes
trap {
    Write-Host "Kurulum hatasi: $_" -ForegroundColor Red
    Read-Host "Kapatmak icin Enter'a basin" | Out-Null
    exit 1
}

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
# An AtLogOn trigger has no Repetition object to set fields on; borrow one (empty Duration = indefinitely)
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1)).Repetition
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
try {
    Register-ScheduledTask -TaskName $AppName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host "Scheduled task registered"
} catch {
    Write-Warning "Could not register scheduled task: $_"
}

Write-Host "Installation complete. Keepalive will run at logon and every 1 minute."

# Initial login (prompts for credentials, then waits for Enter)
Write-Host "Initial setup: you will be asked for username and password."
& powershell.exe -ExecutionPolicy Bypass -File $ScriptPath login
