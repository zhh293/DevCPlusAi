program AgentUISmoke;

{$APPTYPE CONSOLE}

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, AgentPanel, AgentSetupFrm, AgentProtocol;

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
  ReplyText, Snapshot, BeforeTools: String;
  Histories: TStringList;
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
      Panel.AppendAIText('# Heading' + #13#10 + 'Use **bold** and `code`.' + #13#10 +
        '- item');
      Panel.Timeline.LastText.SelStart := 0;
      Panel.Timeline.LastText.SelLength := Length('Heading');
      Require(Panel.Timeline.LastText.SelAttributes.Style = [fsBold],
        'markdown heading was not rendered bold');
      Require(Pos('# Heading', Panel.Timeline.LastText.Text) = 0,
        'markdown heading marker was left in display text');
      Require(Pos('**bold**', Panel.Timeline.LastText.Text) = 0,
        'markdown emphasis markers were left in display text');
      Panel.Timeline.LastText.SelStart := Pos('code', Panel.Timeline.LastText.Text) - 1;
      Panel.Timeline.LastText.SelLength := 4;
      Require(SameText(Panel.Timeline.LastText.SelAttributes.Name, 'Courier New'),
        'markdown inline code was not rendered with a code font');
      Panel.ClearChat;
      Panel.AppendAIText('| Op | Avg | Worst |' + #13#10 +
        '| --- | --- | --- |' + #13#10 + '| 查找 | O(1) | O(n) |' + #13#10 +
        '---');
      Require(Pos('| --- |', Panel.Timeline.LastText.Text) = 0,
        'markdown table separator was left in display text');
      Require((Pos('Op', Panel.Timeline.LastText.Text) > 0) and
        (Pos('Avg', Panel.Timeline.LastText.Text) > 0) and
        (Pos('Worst', Panel.Timeline.LastText.Text) > 0),
        'markdown table columns were not rendered');
      Panel.ClearChat;
      Panel.AppendUserMessage('User bubble');
      Require(Panel.Timeline.BlockCount = 1, 'user message did not become a card');
      Require(Panel.Timeline.BlockAt(0).Left > 12, 'user message is not right aligned');
      Writeln('Agent UI smoke test: collapsed tool activity and persistence');
      Panel.AppendAIText('Visible answer');
      BeforeTools := Panel.reChat.Text;
      ParseLineEvents('{"type":"assistant","message":{"content":[{"type":"tool_use","id":"read-1","name":"Read","input":{"file_path":"main.cpp"}}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      Require(Panel.reChat.Text = BeforeTools, 'tool call polluted answer');
      Require(not Panel.ToolTree.Visible, 'tool area opened automatically');
      Require(not Panel.ToolTree.Items.GetFirstNode.Expanded, 'tool node opened automatically');
      ParseLineEvents('{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"read-1","content":"line one\nline two"}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      Require(Panel.reChat.Text = BeforeTools, 'tool result polluted answer');
      Require(Panel.ToolTree.Items.GetFirstNode.GetNextSibling = nil, 'result was not grouped with its call');
      Require(Pos('[Done]', Panel.ToolTree.Items.GetFirstNode.Text) > 0, 'tool completion absent');
      Panel.ToolToggle.Click;
      Require(Panel.ToolTree.Visible, 'tool toggle did not expand');
      Panel.ToolTree.Items.GetFirstNode.Expand(False);
      Require(Panel.ToolTree.Items.GetFirstNode.Expanded, 'individual tool did not expand');
      Panel.ToolToggle.Click;
      Require(not Panel.ToolTree.Visible, 'tool toggle did not collapse');
      Panel.memoInput.Text := 'unsent draft';
      Snapshot := ExtractFilePath(ParamStr(0)) + '..\..\.tools\ui-history-' + IntToStr(GetCurrentProcessId) + '\chat';
      Panel.SaveConversation(Snapshot);
      Panel.ClearChat;
      Panel.LoadConversation(Snapshot);
      Require(Panel.reChat.Text = BeforeTools, 'snapshot changed transcript');
      Require(Trim(Panel.memoInput.Text) = 'unsent draft', 'snapshot lost draft');
      Require(Panel.ToolTree.Items.GetFirstNode <> nil, 'snapshot lost tools');
      Require(not Panel.ToolTree.Visible and not Panel.ToolTree.Items.GetFirstNode.Expanded,
        'restored tool activity should start collapsed');
      Histories := TStringList.Create;
      try
        Histories.Add('id-one=First question');
        Histories.Add('id-two=Second question');
        Panel.SetSessions(Histories, 'id-two');
        Require(Panel.SelectedSession = 'id-two', 'history selection lost ID');
        Require(Panel.SessionPicker.Text = 'Second question', 'history title missing');
        Require(Panel.memoInput.PopupMenu <> nil, 'input context menu missing');
        Require(Panel.reChat.PopupMenu <> nil, 'reply context menu missing');
      finally
        Histories.Free;
      end;
      Panel.ClearChat;
      Panel.AppendAIText('Before');
      ParseLineEvents('{"type":"assistant","message":{"content":[{"type":"tool_use","id":"ordered-tool","name":"Read","input":{"file_path":"main.cpp"}}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      Panel.AppendAIText('After');
      Require(Panel.Timeline.BlockCount = 3, 'timeline must contain text/tool/text');
      Require(Panel.Timeline.BlockAt(0).Top < Panel.Timeline.BlockAt(1).Top, 'tool precedes first text');
      Require(Panel.Timeline.BlockAt(1).Top < Panel.Timeline.BlockAt(2).Top, 'tool follows last text');
      Require(Panel.Timeline.BlockAt(1).Height = 32, 'inline tool not initially collapsed');
      Panel.SaveConversation(Snapshot);
      Panel.LoadConversation(Snapshot);
      Require(Panel.Timeline.BlockCount = 3, 'history lost ordered blocks');      Panel.ClearChat;
      for I := 0 to 80 do Panel.AppendAIText('Scrollable response line' + #13#10);
      Panel.Timeline.VertScrollBar.Position := 0;
      Panel.Timeline.ScrollWheel(-WHEEL_DELTA);
      Require(Panel.Timeline.VertScrollBar.Position > 0, 'wheel over response did not scroll down');
      Panel.Timeline.ScrollWheel(WHEEL_DELTA);
      Require(Panel.Timeline.VertScrollBar.Position = 0, 'wheel over response did not scroll up');
      Panel.Timeline.ScrollWheel(-60);
      Require(Panel.Timeline.VertScrollBar.Position = 0, 'partial wheel step moved early');
      Panel.Timeline.ScrollWheel(-60);
      Require(Panel.Timeline.VertScrollBar.Position > 0, 'high resolution wheel deltas lost');
      Writeln('Agent UI smoke test: mouse wheel scrolling passed');      Writeln('Agent UI smoke test: load settings DFM and DeepSeek choices');
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
