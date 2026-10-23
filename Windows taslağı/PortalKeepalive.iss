; PortalKeepalive Inno Setup script
[Setup]
AppName=PortalKeepalive
AppVersion=1.0
DefaultDirName={autopf}\PortalKeepalive
DefaultGroupName=PortalKeepalive
OutputBaseFilename=PortalKeepalive-Setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin

[Files]
Source: "PortalKeepalive.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "Install-PortalKeepalive.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\Install-PortalKeepalive.ps1"""; Flags: runasoriginaluser waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\Uninstall-PortalKeepalive.ps1"""; Flags: runasoriginaluser waituntilterminated
