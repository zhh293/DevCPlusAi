program AgentWebPanelSmoke;
{$APPTYPE CONSOLE}
uses Windows, SysUtils, Classes, Controls, Forms, Graphics,
  AgentPanel, AgentWebView;
type
  TProbe = class
    SettingsCount: Integer;
    procedure Settings(Sender: TObject);
  end;
procedure TProbe.Settings(Sender: TObject);
begin Inc(SettingsCount); end;
procedure Pump(Milliseconds: DWORD);
var Started: DWORD;
begin
  Started := GetTickCount;
  while GetTickCount - Started < Milliseconds do begin
    Application.ProcessMessages; Sleep(5);
  end;
end;
var Host: TForm; Panel: TAgentPanelFrame; Probe: TProbe; Started: DWORD; Snapshot: String;
begin
  try
    Application.Initialize;
    Host := TForm.CreateNew(nil); Probe := TProbe.Create;
    try
      Host.ClientWidth := 480; Host.ClientHeight := 780;
      Panel := TAgentPanelFrame.Create(Host);
      Panel.Parent := Host; Panel.Align := alClient;
      Panel.OnSettings := Probe.Settings;
      Started := GetTickCount;
      repeat
        Pump(20);
        if Assigned(Panel.WebView) then
          if Panel.WebView.Ready then Break;
      until GetTickCount - Started > 15000;
      if not Assigned(Panel.WebView) then raise Exception.Create('Web renderer not created');
      if not Panel.WebView.Ready then raise Exception.Create('Web renderer not ready');
      Host.Left := -30000;
      Host.Show;
      Pump(250);
      if not Panel.WebView.BrowserVisible then raise Exception.Create('Browser remained hidden after host show');
      Host.Hide;
      Pump(250);
      if Panel.WebView.BrowserVisible then raise Exception.Create('Browser remained visible after host hide');
      Host.Show;
      Pump(250);
      if not Panel.WebView.BrowserVisible then raise Exception.Create('Browser did not reappear');
      Panel.AppendUserMessage('Hello');
      Panel.AppendAIText('## Heading' + #13#10 + '**bold**');
      Panel.Timeline.AddTool('test', 'Bash [Done]', 'test output');
      Pump(250);
      if Pos('assistant', Panel.Timeline.WebBlock(1)) = 0 then
        raise Exception.Create('Markdown snapshot missing');
      Panel.WebView.OnMessage(Panel.WebView, '{"version":1,"action":"draft","text":"\u4f60\u597d"}');
      Panel.WebView.OnMessage(Panel.WebView, '{"version":1,"action":"settings"}');
      Pump(250);
      if Probe.SettingsCount <> 1 then raise Exception.Create('Settings bridge not dispatched');
      if Panel.memoInput.Text <> String(WideChar($4F60) + WideString(WideChar($597D))) then
        raise Exception.Create('Unicode draft bridge failed');
      Panel.WebView.OnMessage(Panel.WebView, '{"version":99,"action":"settings"}');
      Pump(150);
      if Probe.SettingsCount <> 1 then raise Exception.Create('Unknown protocol version accepted');
      Host.ClientWidth := 320; Pump(150); Host.ClientWidth := 800; Pump(150);
      Panel.Timeline.AddTool('result', 'Bash', 'input command', 'running', False);
      Panel.Timeline.AddTool('result', 'Bash', 'error output', 'failed', True);
      Snapshot := ChangeFileExt(Application.ExeName, '.timeline');
      Panel.Timeline.SaveToFile(Snapshot);
      Panel.Timeline.LoadFromFile(Snapshot);
      Snapshot := Panel.Timeline.WebBlock(Panel.Timeline.BlockCount - 1);
      if (Pos('input command', Snapshot) = 0) or (Pos('error output', Snapshot) = 0) or
        (Pos('"status":"failed"', Snapshot) = 0) then
        raise Exception.Create('Structured tool persistence failed');
      Panel.ClearChat; Pump(150);
      if Panel.Timeline.BlockCount <> 0 then raise Exception.Create('Clear failed');
      Panel.Free; Pump(200);
    finally Probe.Free; Host.Free; end;
    Writeln('PASS: real AgentPanel WebView startup, messages, tools, Unicode draft, settings dispatch, protocol validation, resize, clear, teardown');
  except on E: Exception do begin Writeln(E.Message); Halt(1); end; end;
end.
