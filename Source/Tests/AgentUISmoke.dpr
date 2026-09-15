program AgentUISmoke;

{$APPTYPE CONSOLE}

uses
  Windows, SysUtils, Classes, Graphics, Controls, Forms, AgentPanel, AgentSetupFrm, AgentProtocol;

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
  Events: TAgentEventArray;
  ReplyText: String;
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

      Writeln('Agent UI smoke test: UTF-8 streaming, thinking and final deduplication');
      Panel.ClearChat;
      ParseLineEvents('{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"hidden\n\n\n\n\n\n\n\n\n\n"}}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      Require(Panel.reChat.GetTextLen = 0, 'thinking polluted the answer');
      ParseLineEvents('{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"' + #$E4#$BD#$A0#$E5#$A5#$BD + '\ncode"}}}', Events);
      ReplyText := Events[0].Content;
      Require(ReplyText = String(UTF8Decode(#$E4#$BD#$A0#$E5#$A5#$BD)) + #10 + 'code',
        'UTF-8 response decoded incorrectly');
      Require(Copy(ReplyText, 1, 2) <> '??', 'Chinese reply lost during parsing');
      Panel.HandleAgentEvent(Events[0]);
      ParseLineEvents('{"type":"assistant","message":{"content":[{"type":"text","text":"' + #$E4#$BD#$A0#$E5#$A5#$BD + '\ncode"}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      Require(Pos('code', Panel.reChat.Text) > 0, 'reply missing from RichEdit');
      Require(Pos(String(UTF8Decode(#$E4#$BD#$A0#$E5#$A5#$BD)), Panel.reChat.Text) > 0,
        'Chinese missing from rendered response');
      Require(Panel.reChat.Lines.Count < 8, 'unexpected blank lines');
      Require(Pos('code', Copy(Panel.reChat.Text, Pos('code', Panel.reChat.Text) + 4, MaxInt)) = 0,
        'completed response duplicated streamed text');
      Panel.ClearChat;
      ParseLineEvents('{"type":"assistant","message":{"content":[{"type":"text","text":"Example:\n```cpp\nint main() {}\n```"}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      Require(Panel.AnswerCode = 'int main() {}' + #10, 'code extraction lost content');
      Panel.ClearChat;
      Require(Panel.AnswerCode = '', 'clear retained stale code');
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
