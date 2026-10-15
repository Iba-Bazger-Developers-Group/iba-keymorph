; Inno Setup 6 script for IBA KeyMorph (per-user install, no administrator rights needed).
; Build: iscc /DAppVersion=1.0.0 /DSourceDir=..\publish\win-x64 /DArch=x64 IbaKeyMorph.iss

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\publish\win-x64"
#endif
#ifndef Arch
  #define Arch "x64"
#endif

[Setup]
AppId={{6B0C7E4B-3C9A-4C69-9C8F-1BA4B4D2E0A1}
AppName=IBA KeyMorph
AppVersion={#AppVersion}
AppPublisher=IBA
DefaultDirName={localappdata}\Programs\IBA KeyMorph
DefaultGroupName=IBA KeyMorph
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=IbaKeyMorph-{#AppVersion}-{#Arch}-setup
OutputDir=..\publish
SetupIconFile=..\..\assets\keymorph.ico
WizardImageFile=..\..\assets\installer\wizard-164x314.bmp,..\..\assets\installer\wizard-246x471.bmp,..\..\assets\installer\wizard-328x628.bmp
WizardSmallImageFile=..\..\assets\installer\wizard-small-55.bmp,..\..\assets\installer\wizard-small-83.bmp,..\..\assets\installer\wizard-small-110.bmp
UninstallDisplayIcon={app}\IbaKeyMorph.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "autostart"; Description: "Запускать IBA KeyMorph при входе в Windows"; Flags: checkedonce

[Files]
Source: "{#SourceDir}\IbaKeyMorph.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\IBA KeyMorph"; Filename: "{app}\IbaKeyMorph.exe"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "IBA KeyMorph"; ValueData: """{app}\IbaKeyMorph.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\IbaKeyMorph.exe"; Description: "Запустить IBA KeyMorph"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/im IbaKeyMorph.exe /f"; Flags: runhidden; RunOnceId: "StopKeyMorph"
