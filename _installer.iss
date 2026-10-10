; Auto-generated installer script
[Setup]
AppName=BackroomsSurvivor
AppVersion=1.0.0
AppPublisher=Your Studio Name
AppPublisherURL=https://example.com
DefaultDirName={autopf}\BackroomsSurvivor
DefaultGroupName=BackroomsSurvivor
UninstallDisplayIcon={app}\BackroomsSurvivor.exe
OutputDir=Installer Output
OutputBaseFilename=BackroomsSurvivor_Setup_1.0.0
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=no
PrivilegesRequired=lowest

[Files]
Source: "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\LOVE\Backrooms_Survivor - V12- after sound-resolution-difficulty fixes\Packaged Build Executable\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\BackroomsSurvivor"; Filename: "{app}\BackroomsSurvivor.exe"
Name: "{autodesktop}\BackroomsSurvivor"; Filename: "{app}\BackroomsSurvivor.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\BackroomsSurvivor.exe"; Description: "Launch BackroomsSurvivor"; Flags: nowait postinstall skipifsilent
