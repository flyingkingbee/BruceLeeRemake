; Inno Setup 6 script for the Bruce Lee Remake installer.
; deploy.bat compiles it. By hand, from the workspace root:
;   ISCC.exe /DAppVersion=1.0.0 installer\BruceLee.iss
; The setup program lands in dist\.
;
; Setup asks whether to install for the current user only, which needs no
; admin rights and goes to %LOCALAPPDATA%\Programs, or for all users, which
; goes to Program Files. The game never writes to its install folder:
; config.ini, Saves, and screenshots live in the user's own folders.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "Bruce Lee Remake"
#define AppExe "BruceLee.exe"

[Setup]
; Never change AppId. Upgrades find the old install by it.
AppId={{4667ABED-5751-4ED1-9218-6E0A4C4A3E07}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Jacob Marner
AppPublisherURL=https://github.com/flyingkingbee/BruceLeeRemake
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=no
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SourceDir=..
OutputDir=dist
OutputBaseFilename=BruceLeeRemake-Setup-{#AppVersion}
SetupIconFile=src\BruceLee.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
LicenseFile=LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; A file dropped from data\ in a later version must not linger from an older one.
Type: filesandordirs; Name: "{app}\data"

[Files]
Source: "build\Release\{#AppExe}"; DestDir: "{app}"; Flags: ignoreversion
; Everything in data\, whatever it holds when the installer is built.
Source: "data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
; The template the game copies to %APPDATA%\Bruce Lee Remake on its first start.
Source: "config.ini"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autoprograms}\{#AppName} manual"; Filename: "{app}\data\GameManual.pdf"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; The uninstaller removes only what setup installed. The player's settings,
; saves, and screenshots stay in %APPDATA% and Pictures.
