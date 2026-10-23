# PortalKeepalive (Windows)

Keeps the GOP University captive portal session (denetim.gop.edu.tr) alive on Windows.

## Install
1. Copy `PortalKeepalive.ps1` and `Install-PortalKeepalive.ps1` to the same folder.
2. Right-click `Install-PortalKeepalive.ps1` -> "Run with PowerShell" (or run in PowerShell).
3. When prompted, enter your institutional email and password.
4. The script registers a scheduled task (at logon + every 1 minute) and performs the first login.

## Uninstall
Run `Uninstall-PortalKeepalive.ps1`.

## Files
- `PortalKeepalive.ps1` - main keepalive/login logic.
- `Install-PortalKeepalive.ps1` - installer.
- `Uninstall-PortalKeepalive.ps1` - uninstaller.
- `PortalKeepalive.iss` - optional Inno Setup script to build an .exe installer.

## Build an .exe installer (optional)
Install Inno Setup on Windows, then compile `PortalKeepalive.iss`. The installer will install the PowerShell scripts and run the installer as the original user.

## Notes
- Credentials are stored with Windows DPAPI (user-scoped, encrypted) in `%APPDATA%\PortalKeepalive\pass.enc`.
- Logs: `%APPDATA%\PortalKeepalive\portal.log`.
- Requires `curl.exe` (built into Windows 10/11).
- If the portal returns an empty response, the script attempts a re-login automatically.
