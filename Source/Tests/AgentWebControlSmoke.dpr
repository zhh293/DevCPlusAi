program AgentWebControlSmoke;
{$APPTYPE CONSOLE}
uses Windows, SysUtils, Classes, Controls, Forms, ActiveX, ComObj,
  AgentWebView in '..\AgentWebView.pas';
type
  TProbe = class
    Count: Integer;
    procedure MessageReceived(Sender: TObject; const Text: WideString);
  end;
procedure TProbe.MessageReceived(Sender: TObject; const Text: WideString);
begin
  if Text = WideChar($4F60) + WideString(WideChar($597D)) then Inc(Count);
end;
var Host: TForm; View: TAgentWebView; Probe: TProbe; I: Integer;
  Started: DWORD; Payload: WideString;
begin
  try
    OleCheck(CoInitialize(nil)); Application.Initialize;
    Probe := TProbe.Create;
    Host := TForm.CreateNew(nil);
    try
      Host.ClientWidth := 480; Host.ClientHeight := 640;
      for I := 1 to 4 do begin
        View := TAgentWebView.Create(Host);
        try
          if View.Start(ParamStr(1), ParamStr(2), ParamStr(3)) then
            raise Exception.Create('Parentless initialization must be rejected');
          View.Parent := Host; View.Align := alClient;
          View.OnMessage := Probe.MessageReceived;
          if not View.Start(ParamStr(1), ParamStr(2), ParamStr(3)) then
            raise Exception.Create('Start failed');
          if I mod 2 = 0 then Continue; { destroy during asynchronous start }
          Started := GetTickCount;
          while not View.Ready and (GetTickCount - Started < 15000) do begin
            Application.ProcessMessages; Sleep(5);
          end;
          if not View.Ready then raise Exception.Create('Ready timeout');
          Host.ClientWidth := 320; Host.ClientWidth := 800;
          Payload := '{"kind":"probe","text":"\u4f60\u597d"}';
          if not View.PostJSON(Payload) then raise Exception.Create('Post failed');
          Started := GetTickCount;
          while (Probe.Count < (I + 1) div 2) and (GetTickCount - Started < 5000) do begin
            Application.ProcessMessages; Sleep(5);
          end;
          if Probe.Count <> (I + 1) div 2 then raise Exception.Create('Unicode roundtrip failed');
          View.Stop;
          if View.PostJSON(Payload) then raise Exception.Create('Posting after stop succeeded');
        finally View.Free; end;
        Application.ProcessMessages;
      end;
      Started := GetTickCount;
      while GetTickCount - Started < 500 do begin Application.ProcessMessages; Sleep(5); end;
    finally Host.Free; Probe.Free; end;
    Writeln('PASS: reusable VCL control, parent guard, Unicode, resize, stop, initialization teardown');
  except on E: Exception do begin Writeln(E.Message); Halt(1); end; end;
end.
