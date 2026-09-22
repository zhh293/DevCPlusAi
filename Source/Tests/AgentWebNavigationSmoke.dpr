program AgentWebNavigationSmoke;
{$APPTYPE CONSOLE}
uses Windows, SysUtils, Forms, Controls, ExtCtrls, ActiveX, ComObj;
type
  TNotify = procedure(Context: Pointer; Kind: Integer; Text: PWideChar); stdcall;
  TCreate = function(Parent: HWND; Uri, Data: PWideChar; Notify: TNotify; Context: Pointer): Pointer; cdecl;
  TClose = procedure(Instance: Pointer); cdecl;
  TPost = function(Instance: Pointer; Json: PWideChar): HRESULT; cdecl;
var
  Lib: HMODULE; CreateView: TCreate; CloseView: TClose; Post: TPost; Host: TForm;
  Panel: TPanel; Instance: Pointer; Ready, Failed, ScriptsReady, AppReady, Sent: Boolean;
  Started, Timeout: DWORD; Packet: WideString;
procedure Notification(Context: Pointer; Kind: Integer; Text: PWideChar); stdcall;
begin
  if Kind = 0 then Ready := True;
  if Kind = 1 then begin
    if Pos('"action":"ready"', String(WideString(Text))) > 0 then ScriptsReady := True;
    if Pos('"action":"app-ready"', String(WideString(Text))) > 0 then AppReady := True;
  end;
  if Kind = 2 then begin Failed := True; Writeln('Bridge error: ', String(WideString(Text))); end;
end;
begin
  try
    OleCheck(CoInitialize(nil));
    Application.Initialize;
    Lib := LoadLibrary(PChar(ParamStr(1)));
    if Lib = 0 then raise Exception.Create('Cannot load x86 bridge DLL');
    @CreateView := GetProcAddress(Lib, 'ABCreate');
    @CloseView := GetProcAddress(Lib, 'ABClose');
    @Post := GetProcAddress(Lib, 'ABPost');
    if not Assigned(CreateView) or not Assigned(CloseView) or not Assigned(Post) then
      raise Exception.Create('Missing bridge exports');
    Host := TForm.CreateNew(nil);
    try
      Host.ClientWidth := 480; Host.ClientHeight := 640;
      Panel := TPanel.Create(Host); Panel.Parent := Host; Panel.Align := alClient;
      Panel.HandleNeeded;
      Instance := CreateView(Panel.Handle, PWideChar(WideString(ParamStr(2))),
        PWideChar(WideString(ParamStr(3))), Notification, nil);
      if Instance = nil then raise Exception.Create('Cannot initialize WebView');
      try
        Started := GetTickCount;
        Timeout := 15000;
        while not AppReady and not Failed and (GetTickCount - Started < Timeout) do begin
          Application.ProcessMessages; Sleep(10);
          if Ready and ScriptsReady and not Sent then begin
            Packet := '{"version":1,"type":"state","status":"Ready","busy":false,' +
              '"model":"release-validation","theme":"dark","fontSize":14,' +
              '"attachments":[],"sessions":[]}';
            OleCheck(Post(Instance, PWideChar(Packet))); Sent := True;
          end;
        end;
        if ParamStr(4) = 'expect-failure' then begin
          if AppReady then raise Exception.Create('Missing scripts were incorrectly accepted');
          if not Ready then raise Exception.Create('Negative test never navigated');
          Writeln('PASS: missing scripts do not report application ready');
        end else begin
        if Failed then raise Exception.Create('WebView navigation failed');
        if not Ready then raise Exception.Create('WebView navigation timed out');
        if not ScriptsReady then raise Exception.Create('Page scripts did not initialize');
        if not AppReady then raise Exception.Create('Host/page state handshake failed');
        Writeln('PASS: real chat page scripts and bidirectional startup handshake');
        end;
      finally CloseView(Instance); end;
    finally Host.Free; end;
  except on E: Exception do begin Writeln(E.Message); Halt(1); end; end;
end.
