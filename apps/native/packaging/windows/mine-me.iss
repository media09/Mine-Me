[Setup]
AppId={{C5B7D6E1-31E9-4E71-8B0B-8A2A7A1B0D20}
AppName=MINE-ME
AppVersion=0.2.0
AppPublisher=MINE-ME
DefaultDirName={autopf}\MINE-ME
DefaultGroupName=MINE-ME
DisableProgramGroupPage=yes
OutputDir=..\..\build\installers
OutputBaseFilename=MineMe-Setup-x64
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mine_me_native.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\THIRD_PARTY_NOTICES.md"; DestDir: "{app}"; DestName: "THIRD_PARTY_NOTICES.md"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\MINE-ME"; Filename: "{app}\mine_me_native.exe"
Name: "{autodesktop}\MINE-ME"; Filename: "{app}\mine_me_native.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le bureau"; GroupDescription: "Raccourcis :"

[Run]
Filename: "{app}\mine_me_native.exe"; Description: "Lancer MINE-ME"; Flags: nowait postinstall skipifsilent
