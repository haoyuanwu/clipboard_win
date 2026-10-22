#ifndef AppVersion
  #define AppVersion "1.2.0"
#endif
#ifndef PackageDir
  #error PackageDir must point to the prepared portable application directory.
#endif
[Setup]
AppId={{A6BA36B5-F85F-4D88-9818-2B0DD71AE95E}
AppName=SuperClipboard
AppVersion={#AppVersion}
AppPublisher=haoyuanwu
AppPublisherURL=https://github.com/haoyuanwu/SuperClipboard-Windows
AppSupportURL=https://github.com/haoyuanwu/SuperClipboard-Windows/issues
AppUpdatesURL=https://github.com/haoyuanwu/SuperClipboard-Windows/releases
DefaultDirName={localappdata}\Programs\SuperClipboard
DefaultGroupName=SuperClipboard
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\dist
OutputBaseFilename=SuperClipboard-{#AppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\SuperClipboard.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
AppMutex=Local\SuperClipboard.Windows
CloseApplications=yes
RestartApplications=no
[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"
[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; Flags: unchecked
[Files]
Source: "{#PackageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\SuperClipboard"; Filename: "{app}\SuperClipboard.exe"
Name: "{autodesktop}\SuperClipboard"; Filename: "{app}\SuperClipboard.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\SuperClipboard.exe"; Description: "启动 SuperClipboard"; Flags: nowait postinstall skipifsilent
; User history in APPDATA is intentionally preserved during uninstall.
