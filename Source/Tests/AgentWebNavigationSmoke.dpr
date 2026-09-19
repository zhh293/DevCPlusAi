program AgentWebNavigationSmoke;
{$APPTYPE CONSOLE}
uses Windows, SysUtils, Forms, Controls, ExtCtrls, ActiveX, ComObj;
type
  TNotify = procedure(Context: Pointer; Kind: Integer; Text: PWideChar); stdcall;
  TCreate = function(Parent: HWND; Uri, Data: PWideChar; Notify: TNotify; Context: Pointer): Pointer; cdecl;
  TClose = procedure(Instance: Pointer); cdecl;
var
  Lib: HMODULE; CreateView: TCreate; CloseView: TClose; Host: TForm;
  Panel: TPanel; Instance: Pointer; Ready, Failed: Boolean; Started: DWORD;
procedure Notification(Context: Pointer; Kind: Integer; Text: PWideChar); stdcall;
begin
  if Kind = 0 then Ready := True;
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
    if not Assigned(CreateView) or not Assigned(CloseView) then
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
        while not Ready and not Failed and (GetTickCount - Started < 15000) do begin
          Application.ProcessMessages; Sleep(10);
        end;
        if Failed then raise Exception.Create('WebView navigation failed');
        if not Ready then raise Exception.Create('WebView navigation timed out');
      finally CloseView(Instance); end;
    finally Host.Free; end;
    Writeln('PASS: WebView navigation with local Unicode path');
  except on E: Exception do begin Writeln(E.Message); Halt(1); end; end;
end.
