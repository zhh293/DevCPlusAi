program AgentUISmoke;

{$APPTYPE CONSOLE}

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, AgentPanel,
  AgentSetupFrm, AgentProtocol, AgentWorkspaceWatch, AgentApprovalFrm,
  AgentFileUndo;

procedure Require(Condition: Boolean; const Message: String);
begin
  if not Condition then
    raise Exception.Create('Agent UI smoke test failed: ' + Message);
end;

function TestUiText(const Utf8Bytes: AnsiString): String;
begin
  Result := String(UTF8Decode(Utf8Bytes));
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

procedure CheckWorkspaceWatcher(const Root: String);
var
  Watcher: TAgentWorkspaceWatcher;
  Changed, States, Lines: TStringList;
  I: Integer;
  SawCreated, SawModified, SawRenamedFrom, SawRenamedTo,
    SawDeleted, SawEphemeral, SawGitMetadata: Boolean;
  CreatedAdded, ModifiedState, RenamedFromState, RenamedToState,
    DeletedState: Boolean;
  procedure WriteText(const FileName, Text: String);
  begin
    Lines.Text := Text;
    Lines.SaveToFile(IncludeTrailingPathDelimiter(Root) + FileName);
  end;
begin
  ForceDirectories(Root + '\.git');
  Lines := TStringList.Create;
  Changed := TStringList.Create;
  States := TStringList.Create;
  Watcher := nil;
  try
    WriteText('modify.cpp', 'before');
    WriteText('rename-from.cpp', 'rename');
    WriteText('deleted.cpp', 'delete');
    ForceDirectories(Root + '\.git');
    Watcher := TAgentWorkspaceWatcher.Create(Root);
    Require(Watcher.Available, 'workspace watcher did not start');
    WriteText('created.cpp', 'created');
    WriteText('modify.cpp', 'after with different content');
    Require(RenameFile(Root + '\rename-from.cpp', Root + '\rename-to.cpp'),
      'workspace watcher rename fixture failed');
    Require(DeleteFile(Root + '\deleted.cpp'),
      'workspace watcher delete fixture failed');
    WriteText('ephemeral.cpp', 'temporary');
    DeleteFile(Root + '\ephemeral.cpp');
    WriteText('.git\config', 'internal');
    Sleep(100);
    Watcher.Finish(Changed, States);
    Require(States.Count = Changed.Count,
      'workspace watcher returned mismatched file states');
    SawCreated := False;
    SawModified := False;
    SawRenamedFrom := False;
    SawRenamedTo := False;
    SawDeleted := False;
    SawEphemeral := False;
    SawGitMetadata := False;
    CreatedAdded := False;
    ModifiedState := False;
    RenamedFromState := False;
    RenamedToState := False;
    DeletedState := False;
    for I := 0 to Changed.Count - 1 do begin
      if Pos('created.cpp', LowerCase(Changed[I])) > 0 then begin
        SawCreated := True;
        CreatedAdded := SameText(States[I], 'Added');
      end;
      if Pos('modify.cpp', LowerCase(Changed[I])) > 0 then begin
        SawModified := True;
        ModifiedState := SameText(States[I], 'Modified');
      end;
      if Pos('rename-from.cpp', LowerCase(Changed[I])) > 0 then begin
        SawRenamedFrom := True;
        RenamedFromState := SameText(States[I], 'Renamed');
      end;
      if Pos('rename-to.cpp', LowerCase(Changed[I])) > 0 then begin
        SawRenamedTo := True;
        RenamedToState := SameText(States[I], 'Renamed');
      end;
      if Pos('deleted.cpp', LowerCase(Changed[I])) > 0 then begin
        SawDeleted := True;
        DeletedState := SameText(States[I], 'Deleted');
      end;
      if Pos('ephemeral.cpp', LowerCase(Changed[I])) > 0 then SawEphemeral := True;
      if Pos('\.git\', LowerCase(Changed[I])) > 0 then SawGitMetadata := True;
    end;
    Require(SawCreated, 'workspace watcher missed a created file');
    Require(SawModified, 'workspace watcher missed a modified file');
    Require(SawRenamedFrom and SawRenamedTo, 'workspace watcher missed a rename');
    Require(SawDeleted, 'workspace watcher missed a deleted file');
    Require(CreatedAdded and ModifiedState and RenamedFromState and
      RenamedToState and DeletedState,
      'workspace watcher returned the wrong change state');
    Require(not SawEphemeral, 'workspace watcher reported a transient file');
    Require(not SawGitMetadata, 'workspace watcher reported Git internals');
  finally
    if Assigned(Watcher) then Watcher.Free;
    States.Free;
    Changed.Free;
    Lines.Free;
    DeleteFile(Root + '\created.cpp');
    DeleteFile(Root + '\modify.cpp');
    DeleteFile(Root + '\rename-from.cpp');
    DeleteFile(Root + '\rename-to.cpp');
    DeleteFile(Root + '\deleted.cpp');
    DeleteFile(Root + '\ephemeral.cpp');
    DeleteFile(Root + '\.git\config');
    RemoveDir(Root + '\.git');
    RemoveDir(Root);
  end;
end;

procedure CheckFileUndo(const Root: String);
var Manager: TAgentFileUndoManager; Token, ErrorCode, Path: String;
  CanUndo, Stale: Boolean;
  procedure WriteBytes(const FileName, Value: String);
  var Output: TFileStream;
  begin
    Output := TFileStream.Create(FileName, fmCreate);
    try
      if Value <> '' then Output.WriteBuffer(Value[1], Length(Value));
    finally
      Output.Free;
    end;
  end;
  function ReadBytes(const FileName: String): String;
  var Input: TFileStream;
  begin
    Input := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Result, Integer(Input.Size));
      if Result <> '' then Input.ReadBuffer(Result[1], Length(Result));
    finally
      Input.Free;
    end;
  end;
begin
  ForceDirectories(Root);
  Manager := TAgentFileUndoManager.Create;
  try
    Path := IncludeTrailingPathDelimiter(Root) + 'encoding.cpp';
    WriteBytes(Path, #$EF#$BB#$BF + 'int value = 1;' + #13#10);
    Require(Manager.BeginChange(Path, Root, Token, ErrorCode),
      'undo snapshot should capture an existing source file');
    WriteBytes(Path, #$EF#$BB#$BF + 'int value = 2;' + #13#10);
    Require(Manager.CompleteChange(Token, CanUndo, ErrorCode) and CanUndo,
      'a changed file should receive an undo action');
    Require(Manager.UndoChange(Token, ErrorCode, Stale) and not Stale,
      'guarded undo should restore an unchanged AI result');
    Require(ReadBytes(Path) = #$EF#$BB#$BF + 'int value = 1;' + #13#10,
      'undo did not preserve the original BOM and line endings');

    Require(Manager.BeginChange(Path, Root, Token, ErrorCode),
      'a later turn should create a fresh undo snapshot');
    WriteBytes(Path, 'int value = 3;' + #13#10);
    Require(Manager.CompleteChange(Token, CanUndo, ErrorCode) and CanUndo,
      'second file change should receive an undo action');
    WriteBytes(Path, 'int value = 99;' + #13#10);
    Require(not Manager.UndoChange(Token, ErrorCode, Stale) and Stale,
      'undo must refuse to overwrite edits made after the AI change');
    Require(ReadBytes(Path) = 'int value = 99;' + #13#10,
      'stale undo changed the newer file contents');

    Path := IncludeTrailingPathDelimiter(Root) + 'new-file.cpp';
    DeleteFile(Path);
    Require(Manager.BeginChange(Path, Root, Token, ErrorCode),
      'undo snapshot should record that a file did not exist before');
    WriteBytes(Path, 'int main() {}' + #13#10);
    Require(Manager.CompleteChange(Token, CanUndo, ErrorCode) and CanUndo,
      'a newly created file should receive an undo action');
    Require(Manager.UndoChange(Token, ErrorCode, Stale) and not FileExists(Path),
      'undo of a new file should remove it when its contents still match');

    Path := ExcludeTrailingPathDelimiter(Root) + '-outside.cpp';
    Require(not Manager.BeginChange(Path, Root, Token, ErrorCode),
      'undo must reject files outside the active workspace');
  finally
    Manager.Free;
    DeleteFile(IncludeTrailingPathDelimiter(Root) + 'encoding.cpp');
    DeleteFile(IncludeTrailingPathDelimiter(Root) + 'new-file.cpp');
    RemoveDir(Root);
  end;
end;

var
  Host: TForm;
  Panel: TAgentPanelFrame;
  Setup: TAgentSetupForm;
  I: Integer;
  Events: TAgentEventArray;
  FinalEvent: TAgentEvent;
  ReplyText, Snapshot, BeforeTools, WatchRoot, UndoRoot, DiffText,
    DiffSummary: String;
  Histories: TStringList;
begin
  try
    DiffText := BuildAgentFileDiffText('int main() { return 1; }' + #13#10,
      'int main() { return 0; }' + #13#10, DiffSummary);
    Require((Pos('- int main() { return 1; }', DiffText) > 0) and
      (Pos('+ int main() { return 0; }', DiffText) > 0),
      'file change diff did not mark removed and added lines');
    Require(Pos('+1 / -1 lines', DiffSummary) > 0,
      'file change diff summary did not count lines');
    Application.Initialize;
    Application.ShowMainForm := False;
    WatchRoot := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
      'DevCPlusAi-watch-' + IntToStr(GetCurrentProcessId);
    Writeln('Agent UI smoke test: workspace file change capture');
    CheckWorkspaceWatcher(WatchRoot);
    UndoRoot := WatchRoot + '-undo';
    Writeln('Agent UI smoke test: guarded file undo');
    CheckFileUndo(UndoRoot);
    Host := TForm.CreateNew(nil);
    try
      Writeln('Agent UI smoke test: load chat frame DFM');
      Panel := TAgentPanelFrame.Create(Host);
      Panel.Parent := Host;
      Panel.Align := alClient;
      Require(Panel.StatusBar.Panels[0].Text =
        TestUiText(#$E6#$9C#$AA#$E8#$BF#$9E#$E6#$8E#$A5),
        'native fallback should start with a localized disconnected status');
      Panel.SetStatus(asReady);
      Require(Panel.StatusBar.Panels[0].Text =
        TestUiText(#$E5#$B0#$B1#$E7#$BB#$AA),
        'native fallback ready status should be localized');
      Panel.SetStatus(asExecuting);
      Require(Panel.StatusBar.Panels[0].Text =
        TestUiText(#$E6#$AD#$A3#$E5#$9C#$A8#$E6#$89#$A7#$E8#$A1#$8C#$E5#$B7#$A5#$E5#$85#$B7#$E2#$80#$A6),
        'native fallback tool status should be localized');
      Panel.SetStatus(asError);
      Require(Panel.StatusBar.Panels[0].Text =
        TestUiText(#$E5#$8F#$91#$E7#$94#$9F#$E9#$94#$99#$E8#$AF#$AF),
        'native fallback error status should be localized');
      Panel.SetStatus(asDisconnected);
      Require(Panel.StatusBar.Panels[0].Text =
        TestUiText(#$E6#$9C#$AA#$E8#$BF#$9E#$E6#$8E#$A5),
        'native fallback disconnected status should be localized');
      for I := 0 to 2 do begin
        Host.ClientWidth := 280 + I * 200;
        Host.ClientHeight := 600;
        Host.HandleNeeded;
        Panel.HandleNeeded;
        CheckLayout(Panel);
        Require(not Panel.pnlAttachments.Visible, 'empty attachment area is visible');
        Require(not Panel.btnRemoveAttachment.Enabled, 'remove enabled without attachments');
        Panel.SetStatus(asThinking);
        Require(Panel.StatusBar.Panels[0].Text =
          TestUiText(#$E6#$AD#$A3#$E5#$9C#$A8#$E6#$80#$9D#$E8#$80#$83#$E2#$80#$A6),
          'native fallback thinking status should be localized');
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
      Panel.Timeline.LastText.SelStart := Pos('int', Panel.Timeline.LastText.Text) - 1;
      Panel.Timeline.LastText.SelLength := 3;
      Require(Panel.Timeline.LastText.SelAttributes.Color <>
        Panel.Timeline.LastText.Font.Color,
        'C++ keyword was not syntax highlighted');
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
      Panel.Timeline.LastText.SelStart := Pos('bold', Panel.Timeline.LastText.Text) - 1;
      Panel.Timeline.LastText.SelLength := 4;
      Require(Panel.Timeline.LastText.SelAttributes.Style = [fsBold],
        'markdown emphasis was not rendered bold');
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
      Snapshot := ExpandFileName(ExtractFilePath(ParamStr(0)) +
        '..\\..\\.tools\\ui-history-' + IntToStr(GetCurrentProcessId) +
        '\\chat');
      Require(ForceDirectories(ExtractFilePath(Snapshot)),
        'could not create conversation snapshot test directory');
      Panel.AppendUserMessage('User bubble', 'test.cpp | unsaved | cursor L9',
        #13#10 + 'Context snapshot marker: intact' + #13#10);
      Require(Panel.Timeline.BlockCount = 1, 'user message did not become a card');
      Require(Panel.Timeline.BlockAt(0).Left > 12, 'user message is not right aligned');
      ReplyText := Panel.Timeline.WebBlock(0);
      Require(Pos('Context snapshot marker: intact', ReplyText) > 0,
        'the user message did not expose its context snapshot');
      Panel.SaveConversation(Snapshot);
      Panel.ClearChat;
      Panel.LoadConversation(Snapshot);
      ReplyText := Panel.Timeline.WebBlock(0);
      Require(Pos('\u000D\u000AContext snapshot marker: intact\u000D\u000A',
        ReplyText) > 0,
        'the exact context snapshot did not survive conversation reload');
      Panel.ClearChat;
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
      Panel.ClearChat;
      ParseLineEvents('{"type":"assistant","message":{"content":[{"type":"tool_use","id":"write-1","name":"Write","input":{"file_path":"C:\\work\\hello.cpp","content":"int main() {}"}}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      Require(Pos('Files handled by file tools', Panel.reChat.Text) = 0,
        'pending write was reported before its result');
      ParseLineEvents('{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"write-1","content":"File written"}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      ParseLineEvents('{"type":"assistant","message":{"content":[{"type":"tool_use","id":"edit-1","name":"Edit","input":{"file_path":"C:\\work\\hello.cpp","old_string":"old","new_string":"new"}}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      ParseLineEvents('{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"edit-1","content":"File edited"}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      FillChar(FinalEvent, SizeOf(FinalEvent), 0);
      FinalEvent.EventType := aetResult;
      FinalEvent.Content := 'Done.';
      Panel.HandleAgentEvent(FinalEvent);
      Require(Pos('Files handled by file tools (1)', Panel.reChat.Text) > 0,
        'completed file operations were not summarized');
      Require(Pos('Expand a file below', Panel.reChat.Text) > 0,
        'file operation summary did not explain how to review changes');
      ReplyText := '';
      for I := 0 to Panel.Timeline.BlockCount - 1 do begin
        ReplyText := Panel.Timeline.WebBlock(I);
        if Pos('"kind":"file-change"', ReplyText) > 0 then Break;
      end;
      Require((Pos('"path":', ReplyText) > 0) and
        (Pos('hello.cpp', ReplyText) > 0),
        'file change card omitted the path: ' + ReplyText);
      Require(Pos('"fileState":"Written/edited"', ReplyText) > 0,
        'file change card omitted its state');
      Require(Pos('"diffSummary":"Diff unavailable"', ReplyText) > 0,
        'shell/file fallback did not explain that the diff is unavailable');
      Panel.SaveConversation(Snapshot);
      Panel.ClearChat;
      Panel.LoadConversation(Snapshot);
      ReplyText := '';
      for I := 0 to Panel.Timeline.BlockCount - 1 do begin
        ReplyText := Panel.Timeline.WebBlock(I);
        if Pos('"kind":"file-change"', ReplyText) > 0 then Break;
      end;
      Require((Pos('"path":', ReplyText) > 0) and
        (Pos('hello.cpp', ReplyText) > 0),
        'conversation history did not preserve file change cards');
      ReplyText := Panel.reChat.Text;
      Require(Pos('C:\work\hello.cpp', Copy(ReplyText,
        Pos('C:\work\hello.cpp', ReplyText) + Length('C:\work\hello.cpp'), MaxInt)) = 0,
        'duplicate file paths were not deduplicated');
      Panel.ClearChat;
      ParseLineEvents('{"type":"assistant","message":{"content":[{"type":"tool_use","id":"write-fail","name":"Write","input":{"file_path":"C:\\work\\failed.cpp","content":"broken"}}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      ParseLineEvents('{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"write-fail","is_error":true,"content":"write failed"}]}}', Events);
      Panel.HandleAgentEvent(Events[0]);
      Panel.HandleAgentEvent(FinalEvent);
      Require(Pos('failed.cpp', Panel.reChat.Text) = 0,
        'failed file tool was reported as a completed change');
      Panel.ClearChat;
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
