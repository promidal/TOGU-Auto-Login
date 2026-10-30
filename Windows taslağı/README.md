# PortalKeepalive (Windows)

Keeps the GOP University captive portal session (denetim.gop.edu.tr) alive on Windows.

## Install
1. Copy `PortalKeepalive.ps1` and `Install-PortalKeepalive.ps1` to the same folder.
2. Right-click `Install-PortalKeepalive.ps1` -> "Run with PowerShell" (or run in PowerShell).
3. When prompted, enter your institutional email and password.
4. The script registers a scheduled task (at logon + every 1 minute) and performs the first login.

## Changing the password
Start menu -> "PortalKeepalive - Şifreyi Değiştir" (or run `PortalKeepalive.ps1 login`). It asks for the
username and password again, tests them and saves them.

If the portal rejects the saved password (e.g. it was changed), the keepalive shows a warning once and
stops retrying (to avoid locking the account) until new credentials are entered this way.

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

## Updates
Once a day the keepalive checks the latest GitHub release of `promidal/TOGU-Auto-Login`. When a newer
version is out it shows a one-time notice offering to open the download page; run the new installer over
the old one. Releasing: push a tag like `v1.0.2` and the release workflow stamps that version into the
script and the installer.
