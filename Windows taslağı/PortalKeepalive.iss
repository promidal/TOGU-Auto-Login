; PortalKeepalive Inno Setup script
; The release workflow passes /DAppVer=<tag without v>
#ifndef AppVer
  #define AppVer "0.0.0-dev"
#endif
[Setup]
AppName=PortalKeepalive
AppVersion={#AppVer}
DefaultDirName={autopf}\PortalKeepalive
DefaultGroupName=PortalKeepalive
OutputBaseFilename=PortalKeepalive-Setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin

[Files]
Source: "PortalKeepalive.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "Install-PortalKeepalive.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "Uninstall-PortalKeepalive.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\PortalKeepalive - Şifreyi Değiştir"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\PortalKeepalive.ps1"" login"
Name: "{group}\PortalKeepalive - Kaldır"; Filename: "{uninstallexe}"

[Run]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\Install-PortalKeepalive.ps1"""; Flags: runasoriginaluser waituntilterminated

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\Uninstall-PortalKeepalive.ps1"""; Flags: runhidden
