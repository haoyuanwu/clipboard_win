#ifndef AppVersion
  #define AppVersion "1.2.0"
#endif
#ifndef PackageDir
  #error PackageDir must point to the prepared portable application directory.
#endif
[Setup]
AppId={{A6BA36B5-F85F-4D88-9818-2B0DD71AE95E}
AppName=口袋Cube
AppVersion={#AppVersion}
AppPublisher=haoyuanwu
AppPublisherURL=https://github.com/haoyuanwu/clipboard_win
AppSupportURL=https://github.com/haoyuanwu/clipboard_win/issues
AppUpdatesURL=https://github.com/haoyuanwu/clipboard_win/releases
DefaultDirName={localappdata}\Programs\PocketCube
DefaultGroupName=口袋Cube
UsePreviousGroup=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\dist
OutputBaseFilename=PocketCube-{#AppVersion}-windows-x64-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\PocketCube.exe
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
[InstallDelete]
Type: files; Name: "{app}\SuperClipboard.exe"
Type: files; Name: "{userprograms}\SuperClipboard\SuperClipboard.lnk"
Type: files; Name: "{userdesktop}\SuperClipboard.lnk"
[Files]
Source: "{#PackageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\口袋Cube"; Filename: "{app}\PocketCube.exe"
Name: "{autodesktop}\口袋Cube"; Filename: "{app}\PocketCube.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\PocketCube.exe"; Description: "启动 口袋Cube"; Flags: nowait postinstall skipifsilent
; User history in APPDATA is intentionally preserved during uninstall.
