procedure TMainForm.RunAgentInteractionChecks(const Root, Cli: String);
var
  Key1, Key2, Id1, SavedCliHome, Expected: String;
  PermissionSnapshot, AnswersJSON: String;
  PermissionEvent: TAgentEvent;
  Data: TStringList;
  KeyMessage: TWMKey;
  Keyboard, SavedKeyboard: TKeyboardState;
  SavedDirs: TdevDirs;
  SavedConfig: TdevAgentConfig;
  procedure Require(Condition: Boolean; const Why: String);
  begin
    if not Condition then raise Exception.Create('Agent integration: ' + Why);
  end;
  procedure WaitReady;
  var Started: DWORD;
  begin
    Started := GetTickCount;
    repeat
      CheckSynchronize;
      Application.ProcessMessages;
      if (fAgentSessionId <> '') and not fAgentResumeAttempted and (fAgentPanelFrame.Status = asReady) then Exit;
      Sleep(5);
    until GetTickCount - Started > 5000;
    raise Exception.Create('Fixture response timed out');
  end;
  procedure SelectKey(const Key: String);
  var I: Integer;
  begin
    for I := 0 to fAgentPanelFrame.SessionPicker.Items.Count - 1 do begin
      fAgentPanelFrame.SessionPicker.ItemIndex := I;
      if fAgentPanelFrame.SelectedSession = Key then begin
        fAgentPanelFrame.SessionPicker.OnChange(fAgentPanelFrame.SessionPicker);
        Exit;
      end;
    end;
    raise Exception.Create('History key missing: ' + Key);
  end;
  procedure CheckResume(const ExpectedId: String);
  begin
    Require(fAgentProcess.ResumeSessionId = ExpectedId, 'wrong process resume selection');
    WaitReady;
    Data.LoadFromFile(IncludeTrailingPathDelimiter(devDirs.Exec) + 'fixture-resume.txt');
    Require(Trim(Data.Text) = ExpectedId, 'actual CLI --resume argument mismatch');
  end;
begin
  SavedDirs := devDirs;
  SavedConfig := devAgentConfig;
  SavedCliHome := GetEnvironmentVariable('CLAUDE_CONFIG_DIR');
  Data := TStringList.Create;
  devDirs := TdevDirs(TdevDirs.NewInstance);
  devAgentConfig := TdevAgentConfig(TdevAgentConfig.NewInstance);
  try
    devDirs.Exec := IncludeTrailingPathDelimiter(Root);
    devDirs.Config := IncludeTrailingPathDelimiter(Root) + 'config\';
    ForceDirectories(devDirs.Config);
    SetEnvironmentVariable('CLAUDE_CONFIG_DIR', PChar(IncludeTrailingPathDelimiter(Root) + 'cli-config'));
    devAgentConfig.SettoDefaults;
    devAgentConfig.ApiKey := 'fixture-placeholder';
    devAgentConfig.CliPath := Cli;
    devAgentConfig.Enabled := True;
    fAgentPanelFrame := TAgentPanelFrame.Create(Self);
    fAgentPanelFrame.Parent := Self;
    fAgentPanelFrame.Align := alClient;
    fAgentPanelFrame.OnSessionChange := AgentSessionChange;
    ClientWidth := 400;
    ClientHeight := 650;
    Left := -2000;
    Show;
    fAgentPanelFrame.memoInput.SetFocus;
    fAgentPanelFrame.memoInput.Text := 'clipboard sample';
    fAgentPanelFrame.memoInput.SelectAll;
    FillChar(KeyMessage, SizeOf(KeyMessage), 0);
    KeyMessage.CharCode := Ord('C');
    // Call the same panel shortcut route used by IsShortCut, independent of keyboard state.
    Require(fAgentPanelFrame.HandleEditShortcut(Ord('C'), [ssCtrl]), 'Ctrl+C unhandled');
    Require(Clipboard.AsText = 'clipboard sample', 'input copy failed');
    GetKeyboardState(SavedKeyboard);
    Keyboard := SavedKeyboard;
    Keyboard[VK_CONTROL] := $80;
    Keyboard[VK_SHIFT] := 0;
    Keyboard[VK_MENU] := 0;
    SetKeyboardState(Keyboard);
    try
      KeyMessage.CharCode := Ord('A');
      Require(IsShortCut(KeyMessage), 'main window shortcut route did not handle Ctrl+A');
      Require(fAgentPanelFrame.memoInput.SelText = 'clipboard sample', 'main shortcut selected wrong control');
    finally
      SetKeyboardState(SavedKeyboard);
    end;
    fAgentPanelFrame.memoInput.Clear;
    Require(fAgentPanelFrame.HandleEditShortcut(VK_INSERT, [ssShift]), 'Shift+Insert unhandled');
    Require(fAgentPanelFrame.memoInput.Text = 'clipboard sample', 'input paste failed');
    fAgentPanelFrame.memoInput.SelectAll;
    actCutExecute(nil);
    Require(fAgentPanelFrame.memoInput.Text = '', 'Edit menu cut failed');
    actPasteExecute(nil);
    Require(fAgentPanelFrame.memoInput.Text = 'clipboard sample', 'Edit menu paste failed');
    fAgentPanelFrame.AppendAIText('copy reply');
    fAgentPanelFrame.Timeline.LastText.SetFocus;
    actSelectAllExecute(nil);
    actCopyExecute(nil);
    Require(Clipboard.AsText = 'copy reply', 'reply copy failed');
    fAgentPanelFrame.memoInput.Clear;
    actPasteExecute(nil);
    Require(fAgentPanelFrame.memoInput.Text = 'copy reply', 'reply to input paste failed: [' + fAgentPanelFrame.memoInput.Text + '] focused=' + BoolToStr(fAgentPanelFrame.reChat.Focused, True));
    fAgentPanelFrame.ClearChat;
    Writeln('Agent integration: native clipboard actions passed');

    StartAgent;
    CheckResume('');
    FillChar(PermissionEvent, SizeOf(PermissionEvent), 0);
    PermissionEvent.EventType := aetPermission;
    PermissionEvent.Subtype := 'can_use_tool';
    PermissionEvent.EventId := 'ask-answer';
    PermissionEvent.ToolName := 'AskUserQuestion';
    PermissionEvent.ToolInput := '{"questions":[{"question":"Which compiler?","header":"Compiler","multiSelect":false,' +
      '"options":[{"label":"GCC","description":"GNU"},{"label":"Clang","description":"LLVM"}]}]}';
    fAgentPanelFrame.QueuePermission(PermissionEvent, 'C:\work');
    PermissionSnapshot := fAgentPanelFrame.Timeline.WebBlock(fAgentPanelFrame.Timeline.BlockCount - 1);
    Require(Pos('"requestId":"ask-answer"', PermissionSnapshot) > 0,
      'inline approval request id missing');
    Require((Pos('"workDir":', PermissionSnapshot) > 0) and
      (Pos('work', PermissionSnapshot) > 0),
      'inline approval working directory missing');
    Require(fAgentPanelFrame.ResolvePermission('ask-answer', 'answer',
      '{"Which compiler?":"GCC"}'), 'AskUserQuestion answer was rejected');
    Sleep(100);
    Data.LoadFromFile(IncludeTrailingPathDelimiter(devDirs.Exec) + 'fixture-decision.txt');
    Require(Pos('"request_id":"ask-answer"', Data.Text) > 0,
      'AskUserQuestion response request id missing');
    Require(Pos('"answers":{"Which compiler?":"GCC"}', Data.Text) > 0,
      'AskUserQuestion answer was not returned as updated input');
    PermissionEvent.EventId := 'ask-invalid';
    fAgentPanelFrame.QueuePermission(PermissionEvent, 'C:\work');
    Require(not fAgentPanelFrame.ResolvePermission('ask-invalid', 'answer', '{}'),
      'incomplete question answers must be rejected');
    fAgentPanelFrame.ExpirePendingPermissions;
    PermissionSnapshot := fAgentPanelFrame.Timeline.WebBlock(fAgentPanelFrame.Timeline.BlockCount - 1);
    Require(Pos('"status":"interrupted"', PermissionSnapshot) > 0,
      'expired permission was not marked stale');
    Require(not fAgentPanelFrame.ResolvePermission('ask-invalid', 'answer',
      '{"Which compiler?":"GCC"}'), 'expired permission was accepted');
    Writeln('Agent integration: inline request lifecycle and AskUserQuestion response passed');
    Require(fAgentProcess.SendPermissionResponse('allow-request', '{"command":"echo sample"}', True), 'approval write failed');
    Sleep(100);
    Data.LoadFromFile(IncludeTrailingPathDelimiter(devDirs.Exec) + 'fixture-decision.txt');
    Require(Pos('"behavior":"allow"', Data.Text) > 0, 'allow response missing');
    Require(Pos('echo sample', Data.Text) > 0, 'approved command changed');
    Require(fAgentProcess.SendPermissionResponse('deny-request', '{}', False), 'deny write failed');
    Sleep(100);
    Data.LoadFromFile(IncludeTrailingPathDelimiter(devDirs.Exec) + 'fixture-decision.txt');
    Require(Pos('"behavior":"deny"', Data.Text) > 0, 'deny response missing');
    Require(Pos('deny-request', Data.Text) > 0, 'deny request mismatch');
    Writeln('Agent integration: permission decisions delivered to CLI stdin');
    fAgentPanelFrame.SendPrompt('First conversation');
    WaitReady;
    Id1 := fAgentSessionId;
    Key1 := fAgentChatKey;
    fAgentPanelFrame.memoInput.Text := 'first draft';
    fAgentPanelFrame.SessionPicker.ItemIndex := -1;
    AgentSessionChange(Self);
    CheckResume('');
    Key2 := fAgentChatKey;
    Require(Key2 <> Key1, 'new chat reused history key');
    Require(fAgentPanelFrame.reChat.Text = '', 'new chat retained transcript');
    fAgentPanelFrame.SendPrompt('Second conversation');
    WaitReady;
    SelectKey(Key1);
    CheckResume(Id1);
    Require(Pos('First conversation', fAgentPanelFrame.reChat.Text) > 0, 'first transcript missing');
    Require(Pos('Second conversation', fAgentPanelFrame.reChat.Text) = 0, 'conversation transcripts mixed');
    Require(Trim(fAgentPanelFrame.memoInput.Text) = 'first draft', 'draft not restored');
    StopAgent;
    fAgentChatKey := '';
    fAgentSessionFile := '';
    StartAgent;
    CheckResume(Id1);
    Require(fAgentChatKey = Key1, 'restart selected wrong history');
    Require(Pos('First conversation', fAgentPanelFrame.reChat.Text) > 0, 'restart lost transcript');
    fAgentPanelFrame.SendPrompt('Continue first');
    WaitReady;
    Require(fAgentSessionId = Id1, 'continuation changed CLI session');
    Writeln('Agent integration: new, select, restart and continue sessions passed');
    AgentSessionAction(Self, 'rename-session', Key1, 'Renamed conversation');
    StopAgent;
    Data.LoadFromFile(IncludeTrailingPathDelimiter(AgentHistoryPath(fAgentSessionFile)) + Key1 + '.title');
    Require(Trim(Data.Text) = 'Renamed conversation', 'renamed title overwritten by save');
    AgentSessionAction(Self, 'delete-session', Key2, '');
    Require(FileExists(IncludeTrailingPathDelimiter(AgentHistoryPath(fAgentSessionFile)) + Key2 + '.deleted'),
      'history removal marker missing');
    Require(fAgentPanelFrame.SessionPicker.Items.Count = 1, 'removed session still listed');
    RefreshAgentSessions;
    Require(fAgentPanelFrame.SessionPicker.Items.Count = 1, 'removed session reimported');
    Writeln('Agent integration: title persistence and history removal passed');

    StopAgent;
    SaveAgentSession(IncludeTrailingPathDelimiter(AgentHistoryPath(fAgentSessionFile)) + 'empty-chat.session', '');
    SaveAgentSession(fAgentSessionFile + '.active', 'empty-chat');
    SaveAgentSession(fAgentSessionFile, Id1);
    fAgentChatKey := '';
    fAgentSessionFile := '';
    StartAgent;
    CheckResume('');
    Require(fAgentChatKey = 'empty-chat', 'empty selection lost');
    Require(Pos('First conversation', fAgentPanelFrame.reChat.Text) = 0, 'empty chat reused legacy transcript');
    ForceDirectories(AgentCliHistoryDir);
    Data.Text := '{"type":"user","uuid":"u1","message":{"role":"user","content":"Legacy question"}}' + #13#10 +
      '{"type":"assistant","uuid":"a1","message":{"id":"legacy-msg","content":[{"type":"text","text":"Legacy answer"}]}}';
    Data.SaveToFile(AgentCliHistoryDir + 'legacy-session.jsonl');
    RefreshAgentSessions;
    SelectKey('legacy-session');
    CheckResume('legacy-session');
    Require(Pos('Legacy question', fAgentPanelFrame.reChat.Text) > 0, 'old CLI user history not imported');
    Require(Pos('Legacy answer', fAgentPanelFrame.reChat.Text) > 0, 'old CLI reply not imported');
    Writeln('Agent integration: empty-history isolation and legacy import passed');
    StopAgent;
    devDirs.Exec := IncludeTrailingPathDelimiter(Root) + 'other-project\';
    ForceDirectories(devDirs.Exec);
    StartAgent;
    CheckResume('');
    Require(Pos('Legacy question', fAgentPanelFrame.reChat.Text) = 0, 'project switch leaked transcript');
    Require(fAgentPanelFrame.SessionPicker.Items.Count = 1, 'project histories mixed');
    Writeln('Agent integration: project isolation passed');
  finally
    StopAgent;
    fAgentPanelFrame.Free;
    fAgentPanelFrame := nil;
    devAgentConfig.Free;
    devAgentConfig := SavedConfig;
    devDirs.Free;
    devDirs := SavedDirs;
    SetEnvironmentVariable('CLAUDE_CONFIG_DIR', PChar(SavedCliHome));
    Data.Free;
  end;
end;


