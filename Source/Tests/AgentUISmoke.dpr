program AgentUISmoke;

{$APPTYPE CONSOLE}

uses
  Windows, SysUtils, Classes, Graphics, Controls, Forms, AgentPanel, AgentSetupFrm;

procedure Require(Condition: Boolean; const Message: String);
begin
  if not Condition then
    raise Exception.Create('Agent UI smoke test failed: ' + Message);
end;

procedure CheckLayout(Panel: TAgentPanelFrame);
begin
  Panel.Realign;
  Require(Panel.btnPasteImage.Left >= Panel.btnAttach.Left +
    Panel.btnAttach.Width, 'attachment buttons overlap');
  Require(Panel.btnRemoveAttachment.Left >= Panel.btnPasteImage.Left +
    Panel.btnPasteImage.Width, 'remove button overlaps paste');
  Require(Panel.btnSend.Left + Panel.btnSend.Width =
    Panel.pnlSendTools.ClientWidth, 'send button does not follow right edge');
  Require(Panel.btnSend.Height <= 32, 'send button is oversized');
  Require(Panel.memoInput.Height >= 60, 'input area collapsed');
  Require(Panel.memoInput.Top + Panel.memoInput.Height <=
    Panel.pnlSendTools.Top, 'input overlaps send toolbar');
  Require(Panel.btnSettings.Left + Panel.btnSettings.Width <=
    Panel.pnlHeader.ClientWidth, 'settings button is clipped');
  Require(Panel.btnStop.BoundsRect.Left = Panel.btnSend.BoundsRect.Left,
    'send and stop do not share the same position');
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
        Host.ClientWidth := 280 + I * 200;
        Host.ClientHeight := 600;
        Host.HandleNeeded;
        Panel.HandleNeeded;
        CheckLayout(Panel);
        Require(not Panel.pnlAttachments.Visible, 'empty attachment area is visible');
        Require(not Panel.btnRemoveAttachment.Enabled, 'remove enabled without attachments');
        Panel.SetStatus(asThinking);
        Require(Panel.btnStop.Visible and not Panel.btnSend.Visible,
          'send and stop do not swap while thinking');
        CheckLayout(Panel);
        Panel.SetStatus(asReady);
        Require(Panel.btnSend.Visible and not Panel.btnStop.Visible,
          'send button was not restored');
      end;
      Panel.SetSendKey('ctrl+enter');
      Require(Panel.lblSendHint.Caption = 'Ctrl+Enter to send', 'send hint is stale');
      Panel.ApplyAppearance(clBtnFace, clWindowText, clWindow, clWindowText,
        'Tahoma', 9);
      Require(Panel.memoInput.Font.Name = 'Tahoma', 'input ignores application font');
      Panel.SetModelName('deepseek-v4-flash');
      Panel.AppendUserMessage('Explain this function.');
      Panel.AppendAIText('I can help you read, edit and debug your C/C++ code.');
      Host.ClientWidth := 400;
      CheckLayout(Panel);
      Panel.ApplyAppearance(RGB(45,45,48), clWhite, RGB(30,30,30), clSilver,
        'Tahoma', 9);
      Require(Panel.memoInput.Color = RGB(30,30,30), 'input ignores dark theme');
      Require(Panel.reChat.Color = RGB(30,30,30), 'chat ignores dark theme');

      Writeln('Agent UI smoke test: load settings DFM and DeepSeek choices');
      Setup := TAgentSetupForm.Create(Host);
      Require(Setup.Caption = 'AI Assistant Setup', 'settings caption missing');
      Require(Setup.edtApiKey.PasswordChar <> #0, 'API key field is not masked');
      Setup.edtModel.Text := '';
      Setup.edtBaseUrl.Text := '';
      Setup.rgProvider.ItemIndex := 2;
      Setup.rgProviderClick(nil);
      Require(Setup.edtModel.Text = 'deepseek-v4-flash', 'DeepSeek default is not Flash');
      Require(Setup.edtModel.Items.IndexOf('deepseek-v4-pro') >= 0, 'Pro choice missing');
      Require(Setup.edtBaseUrl.Text = 'https://api.deepseek.com/anthropic',
        'DeepSeek endpoint is not Anthropic compatible');
      Setup.edtModel.Text := 'deepseek-v4-pro';
      Setup.rgProviderClick(nil);
      Require(Setup.edtModel.Text = 'deepseek-v4-pro', 'explicit Pro choice was reset');
      Setup.edtModel.Text := 'gateway-custom-model';
      Setup.rgProviderClick(nil);
      Require(Setup.edtModel.Text = 'gateway-custom-model', 'custom model was reset');
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
