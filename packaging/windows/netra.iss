; NETRA installer for Windows (Inno Setup 6): the service with its own PostgreSQL.
; Built by the release workflow: iscc /DVersion=1.2.0 /DStage=<dir> packaging\windows\netra.iss
; <Stage> holds netra.exe, netra-service.exe (WinSW 2), pgsql\ (PostgreSQL binaries), INSTALL.md.

#ifndef Version
  #define Version "0.0.0"
#endif
#ifndef Stage
  #define Stage "stage"
#endif
#define Port "8080"

[Setup]
AppId={{6E3C1A54-8E8B-4C2B-9F0E-3B9C7D8A4E21}
AppName=NETRA
AppVersion={#Version}
AppPublisher=EZRA Robotics
AppComments=Patrol command center
DefaultDirName={autopf}\NETRA
DefaultGroupName=NETRA
DisableProgramGroupPage=yes
OutputBaseFilename=NETRA-Setup-{#Version}-x64
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\netra.exe
UninstallDisplayName=NETRA
CloseApplications=no

[Files]
Source: "{#Stage}\netra.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\netra-service.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "netra-service.xml"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Stage}\pgsql\*"; DestDir: "{app}\pgsql"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#Stage}\INSTALL.md"; DestDir: "{app}"; Flags: ignoreversion

[Dirs]
Name: "{commonappdata}\NETRA"; Permissions: networkservice-modify
Name: "{commonappdata}\NETRA\data"; Permissions: networkservice-modify
Name: "{commonappdata}\NETRA\logs"; Permissions: networkservice-modify

[Icons]
Name: "{group}\NETRA Dashboard"; Filename: "http://localhost:{#Port}"
Name: "{group}\NETRA data and configuration"; Filename: "{commonappdata}\NETRA"
Name: "{group}\Uninstall NETRA"; Filename: "{uninstallexe}"

[Run]
Filename: "{app}\netra-service.exe"; Parameters: "install"; Flags: runhidden; StatusMsg: "Installing the NETRA service..."
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""NETRA"" dir=in action=allow protocol=TCP localport={#Port}"; Flags: runhidden; StatusMsg: "Opening port {#Port}..."
Filename: "{app}\netra-service.exe"; Parameters: "start"; Flags: runhidden; StatusMsg: "Starting NETRA..."
Filename: "http://localhost:{#Port}"; Description: "Open NETRA to finish the setup"; Flags: shellexec postinstall nowait skipifsilent

[UninstallRun]
Filename: "{app}\netra-service.exe"; Parameters: "stop"; Flags: runhidden; RunOnceId: "StopService"
Filename: "{app}\netra-service.exe"; Parameters: "uninstall"; Flags: runhidden; RunOnceId: "RemoveService"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""NETRA"""; Flags: runhidden; RunOnceId: "RemoveFirewallRule"

[Code]
const
  CRLF = #13#10;

{ An upgrade replaces netra.exe: stop the running service first. }
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Code: Integer;
begin
  if FileExists(ExpandConstant('{app}\netra-service.exe')) then
    Exec(ExpandConstant('{app}\netra-service.exe'), 'stop', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Result := '';
end;

{ The configuration is written once and kept across upgrades and uninstalls, with the data. }
procedure CurStepChanged(CurStep: TSetupStep);
var
  Env: String;
begin
  if CurStep = ssPostInstall then
  begin
    Env := ExpandConstant('{commonappdata}\NETRA\netra.env');
    if not FileExists(Env) then
      SaveStringToFile(Env,
        '# NETRA configuration. Restart the NETRA service after a change.' + CRLF +
        '# Every setting: https://github.com/DarmawanWeb/netra-fleet-be/blob/main/docs/configuration.md' + CRLF +
        'NETRA_ADDR=:{#Port}' + CRLF +
        '# Address robots and phones use to reach this computer, e.g. http://192.168.1.10:{#Port}' + CRLF +
        'NETRA_PUBLIC_URL=' + CRLF +
        'NETRA_TZ=Asia/Jakarta' + CRLF +
        'NETRA_LANG=id' + CRLF +
        'NETRA_DATA_DIR=' + ExpandConstant('{commonappdata}\NETRA\data') + CRLF +
        '# The private PostgreSQL of this installation' + CRLF +
        'NETRA_PG_BIN=' + ExpandConstant('{app}\pgsql\bin') + CRLF +
        'NETRA_PG_PORT=5433' + CRLF +
        '# The license file (or Settings > License in the dashboard)' + CRLF +
        'NETRA_LICENSE_FILE=' + ExpandConstant('{commonappdata}\NETRA\license.lic') + CRLF +
        'NETRA_BACKUP_KEEP_DAYS=14' + CRLF +
        '# NETRA_TLS=self-signed' + CRLF +
        '# NETRA_OLLAMA_URL=http://localhost:11434' + CRLF, False);
  end;
end;
