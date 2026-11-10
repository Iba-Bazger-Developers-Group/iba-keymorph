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
; The icon is named explicitly so the shortcut never keeps an icon of its own from an older version.
Name: "{userprograms}\IBA KeyMorph"; Filename: "{app}\IbaKeyMorph.exe"; IconFilename: "{app}\IbaKeyMorph.exe"; IconIndex: 0

[InstallDelete]
; Leftovers of a previous installation next to the program (the exe is replaced in place; nothing else ships).
Type: files; Name: "{app}\*.old"
Type: files; Name: "{app}\*.tmp"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "IBA KeyMorph"; ValueData: """{app}\IbaKeyMorph.exe"""; Flags: uninsdeletevalue; Tasks: autostart

[Run]
Filename: "{app}\IbaKeyMorph.exe"; Description: "Запустить IBA KeyMorph"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/im IbaKeyMorph.exe /f"; Flags: runhidden; RunOnceId: "StopKeyMorph"

[Code]
const
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';
  RunName = 'IBA KeyMorph';
  SHCNE_ASSOCCHANGED = $08000000;

procedure SHChangeNotify(wEventId, uFlags: Integer; dwItem1, dwItem2: Integer);
  external 'SHChangeNotify@shell32.dll stdcall';

function KeyMorphExe: String;
begin
  Result := ExpandConstant('{app}\IbaKeyMorph.exe');
end;

{ Every .lnk in Dir (Desktop, Start menu, Startup, pinned items) that starts IbaKeyMorph.exe gets the exe's own icon again,
  so a shortcut made by an older version or by the user stops showing a stale icon. Targets are left as they are. }
procedure RefreshShortcuts(Dir: String);
var
  Find: TFindRec;
  Shell, Link: Variant;
  Path, Target: String;
begin
  if not DirExists(Dir) then
    Exit;
  if FindFirst(AddBackslash(Dir) + '*.lnk', Find) then
  begin
    try
      try
        Shell := CreateOleObject('WScript.Shell');
        repeat
          Path := AddBackslash(Dir) + Find.Name;
          Link := Shell.CreateShortcut(Path);
          Target := Link.TargetPath;
          if Pos('\ibakeymorph.exe', Lowercase(Target)) > 0 then
          begin
            Link.IconLocation := Target + ',0';
            Link.Save;
          end;
        until not FindNext(Find);
      except
        Log('Shortcut refresh skipped in ' + Dir + ': ' + GetExceptionMessage);
      end;
    finally
      FindClose(Find);
    end;
  end;
end;

{ Autostart written by an older version or by the program's own switch may point to another copy of the exe
  (an old install folder, a portable file). When it is on, it is made to start this installation. }
procedure PointAutostartHere;
var
  Current: String;
begin
  if RegQueryStringValue(HKCU, RunKey, RunName, Current) then
    if CompareText(Current, '"' + KeyMorphExe + '"') <> 0 then
      RegWriteStringValue(HKCU, RunKey, RunName, '"' + KeyMorphExe + '"');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    PointAutostartHere;
    RefreshShortcuts(ExpandConstant('{userdesktop}'));
    RefreshShortcuts(ExpandConstant('{userprograms}'));
    RefreshShortcuts(ExpandConstant('{userstartup}'));
    RefreshShortcuts(ExpandConstant('{userappdata}\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'));
    RefreshShortcuts(ExpandConstant('{userappdata}\Microsoft\Internet Explorer\Quick Launch\User Pinned\StartMenu'));
    { Explorer, the taskbar and the Start menu redraw icons from their cache; this tells them the icons changed. }
    SHChangeNotify(SHCNE_ASSOCCHANGED, 0, 0, 0);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    { The program's own "start with Windows" switch writes this value even when the installer task was not chosen. }
    RegDeleteValue(HKCU, RunKey, RunName);
    SHChangeNotify(SHCNE_ASSOCCHANGED, 0, 0, 0);
  end;
end;
