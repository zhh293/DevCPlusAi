program AgentWebProbe;
{$APPTYPE CONSOLE}
uses Windows, SysUtils, Forms, Controls, ExtCtrls, ActiveX, ComObj;
type
  TNotify = procedure(Context: Pointer; Kind: Integer; Text: PWideChar); stdcall;
  TCreate = function(Parent: HWND; Uri, Data: PWideChar; Notify: TNotify; Context: Pointer): Pointer; cdecl;
  TResize = procedure(Instance: Pointer); cdecl;
  TPost = function(Instance: Pointer; Json: PWideChar): HRESULT; cdecl;
  TClose = procedure(Instance: Pointer); cdecl;
var
  Lib: HMODULE; CreateView: TCreate; ResizeView: TResize;
  Post: TPost; CloseView: TClose; Instance: Pointer;
  Host: TForm; Panel: TPanel; Uri, Data, Payload, Expected: WideString;
  Ready, Received, Failed: Boolean; Started: DWORD;
procedure Notification(Context: Pointer; Kind: Integer; Text: PWideChar); stdcall;
begin
  if Kind = 0 then Ready := True;
  if Kind = 1 then Received := WideString(Text) = Expected;
  if Kind = 2 then begin Failed := True; Writeln('Bridge error: ', String(WideString(Text))); end;
end;
begin
  try
    OleCheck(CoInitialize(nil));
    Application.Initialize;
    Lib := LoadLibrary(PChar(ParamStr(1)));
    if Lib = 0 then raise Exception.Create('Cannot load x86 bridge DLL');
    @CreateView := GetProcAddress(Lib, 'ABCreate');
    @ResizeView := GetProcAddress(Lib, 'ABResize');
    @Post := GetProcAddress(Lib, 'ABPost');
    @CloseView := GetProcAddress(Lib, 'ABClose');
    if not Assigned(CreateView) or not Assigned(Post) or not Assigned(CloseView) or
      not Assigned(ResizeView) then raise Exception.Create('Missing bridge exports');
    Host := TForm.CreateNew(nil);
    try
      Host.ClientWidth := 480; Host.ClientHeight := 640;
      Panel := TPanel.Create(Host); Panel.Parent := Host; Panel.Align := alClient;
      Panel.HandleNeeded;
      Uri := WideString(ParamStr(2)); Data := WideString(ParamStr(3));
      Expected := WideChar($4F60) + WideString(WideChar($597D));
      Instance := CreateView(Panel.Handle, PWideChar(Uri), PWideChar(Data), Notification, nil);
      if Instance = nil then raise Exception.Create('Cannot initialize WebView');
      try
        Started := GetTickCount;
        while not Ready and not Failed and (GetTickCount - Started < 15000) do begin
          Application.ProcessMessages; Sleep(10);
        end;
        if not Ready or Failed then raise Exception.Create('WebView initialization timed out/failed');
        Host.ClientWidth := 320; ResizeView(Instance);
        Host.ClientWidth := 800; ResizeView(Instance);
        Payload := '{"kind":"probe","text":"' + Expected + '"}';
        OleCheck(Post(Instance, PWideChar(Payload)));
        Started := GetTickCount;
        while not Received and not Failed and (GetTickCount - Started < 5000) do begin
          Application.ProcessMessages; Sleep(10);
        end;
        if not Received then raise Exception.Create('Unicode roundtrip failed');
      finally CloseView(Instance); end;
    finally Host.Free; end;
    Writeln('PASS: Delphi 7 x86 host, offline HTML, resize, Unicode roundtrip, close');
    { Keep the DLL loaded until process exit: COM may retain pending callbacks. }
  except on E: Exception do begin Writeln(E.Message); Halt(1); end; end;
end.
