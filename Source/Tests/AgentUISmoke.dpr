program AgentUISmoke;

{$APPTYPE CONSOLE}

uses
  Windows, SysUtils, Classes, Controls, Forms, AgentPanel, AgentSetupFrm;

procedure Require(Condition: Boolean; const Message: String);
begin
  if not Condition then
    raise Exception.Create('Agent UI smoke test failed: ' + Message);
end;

var
  Host: TForm;
  Panel: TAgentPanelFrame;
  Setup: TAgentSetupForm;
  I: Integer;
begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    Host := TForm.CreateNew(nil);
    try
      Writeln('Agent UI smoke test: load chat frame DFM');
      Panel := TAgentPanelFrame.Create(Host);
      Panel.Parent := Host;
      Panel.Align := alClient;
      for I := 0 to 2 do begin
        Host.ClientWidth := 400 + I * 200;
        Host.ClientHeight := 600;
        Host.HandleNeeded;
        Panel.HandleNeeded;
        Panel.Realign;
        Require(Panel.btnAttach.Caption = 'Add file', 'attachment button missing');
        Require(Panel.btnPasteImage.Left >= Panel.btnAttach.Left +
          Panel.btnAttach.Width, 'attachment buttons overlap');
        Require(Panel.btnRemoveAttachment.Left >= Panel.btnPasteImage.Left +
          Panel.btnPasteImage.Width, 'remove button overlaps paste');
        Require(Panel.btnSend.Left + Panel.btnSend.Width =
          Panel.pnlInput.ClientWidth, 'send button does not follow right edge');
        Require(Panel.memoInput.Width > 0, 'input area collapsed');
        Require(Panel.memoInput.Left + Panel.memoInput.Width <=
          Panel.btnSend.Left, 'input overlaps send button');
        Panel.SetStatus(asThinking);
        Require(Panel.btnStop.Visible, 'stop button is hidden while thinking');
        Panel.SetStatus(asReady);
      end;
      Writeln('Agent UI smoke test: load settings DFM');
      Setup := TAgentSetupForm.Create(Host);
      Require(Setup.Caption = 'AI Assistant Setup', 'settings caption missing');
      Require(Setup.edtApiKey.PasswordChar <> #0, 'API key field is not masked');
      Require(Setup.btnOK.Caption = 'OK', 'settings controls were not loaded');
    finally
      Host.Free;
    end;
    Writeln('Agent UI smoke test passed.');
  except
    on E: Exception do begin
      Writeln(E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
