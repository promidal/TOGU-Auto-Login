$ErrorActionPreference = "Stop"

# Keep the console open on failure, otherwise the window just vanishes
trap {
    Write-Host "Kurulum hatasi: $_" -ForegroundColor Red
    Read-Host "Kapatmak icin Enter'a basin" | Out-Null
    exit 1
}

$AppName = "PortalKeepalive"
$BaseDir = Join-Path $env:ProgramData $AppName
# Program Files is admin-only: SYSTEM runs this script, so users must not be able to edit it
$InstallDir = Join-Path $env:ProgramFiles $AppName
$ScriptName = "PortalKeepalive.ps1"
$ScriptPath = Join-Path $InstallDir $ScriptName

# The boot task runs as SYSTEM, which needs an elevated installer
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { throw "Yonetici olarak calistirin (sag tik -> Yonetici olarak calistir)" }

foreach ($d in $BaseDir, $InstallDir) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
# Data dir: users must be able to change the password (login mode) without elevation
& icacls.exe $BaseDir /grant "*S-1-5-32-545:(OI)(CI)M" | Out-Null

# Copy script (expects to be in same folder as installer); the Inno installer already put it there
$src = Join-Path $PSScriptRoot $ScriptName
if (-not (Test-Path $src)) { throw "PortalKeepalive.ps1 not found next to installer" }
if ((Resolve-Path $src).Path -ne $ScriptPath) { Copy-Item $src $ScriptPath -Force }

# conhost --headless: -WindowStyle Hidden still flashes a console window on every run, because it only applies once PowerShell has started
function New-HeadlessAction($mode) {
    New-ScheduledTaskAction -Execute "conhost.exe" -Argument "--headless powershell.exe -ExecutionPolicy Bypass -File `"$ScriptPath`" $mode"
}

# Keepalive: SYSTEM at boot + every minute, so the connection is up before anyone logs on and no window ever shows
$startTrigger = New-ScheduledTaskTrigger -AtStartup
# Separate trigger for the repeat: a startup trigger's repetition is unreliable (empty Duration = indefinitely)
$repeatTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$system = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
# Without the task nothing keeps the session alive, so a failure here must stop the install (see trap above)
Register-ScheduledTask -TaskName $AppName -Action (New-HeadlessAction "keepalive") -Trigger @($startTrigger, $repeatTrigger) -Principal $system -Settings $settings -Force | Out-Null

# Warnings (rejected password, new version) can't be shown from SYSTEM: show them once at each user's logon
$users = New-ScheduledTaskPrincipal -GroupId "S-1-5-32-545" -RunLevel Limited
Register-ScheduledTask -TaskName "$AppName-Notify" -Action (New-HeadlessAction "notify") -Trigger (New-ScheduledTaskTrigger -AtLogOn) -Principal $users -Settings $settings -Force | Out-Null
Write-Host "Scheduled tasks registered"

# Credentials from a pre-boot-task install lived per user in %APPDATA%; they are asked for again below
Remove-Item -Recurse -Force (Join-Path $env:APPDATA $AppName) -ErrorAction SilentlyContinue

Write-Host "Installation complete. Keepalive will run at boot and every 1 minute."

# Initial login (prompts for credentials, then waits for Enter)
Write-Host "Initial setup: you will be asked for username and password."
& powershell.exe -ExecutionPolicy Bypass -File $ScriptPath login
