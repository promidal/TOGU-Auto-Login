# Auto-Login (GOP University captive portal)

Keeps the session alive for https://denetim.gop.edu.tr/

## Folders
- `Mac/` - macOS solution (launchd + Python).
- `Windows taslağı/` - Windows solution (PowerShell + Task Scheduler + optional Inno Setup).
- `.github/workflows/` - GitHub Actions to build the Windows installer.

## Build Windows installer via GitHub
1. Create a GitHub repository and push this folder.
2. Go to Actions -> "Build Windows Installer" -> Run workflow.
3. Download the artifact `PortalKeepalive-Windows-Installer`.
