procedure TMainForm.RunAgentInteractionChecks(const Root, Cli: String);
var
  Key1, Key2, Id1, SavedCliHome, Expected, QuestionUTF8,
    SavedAgentIni, ContextIni: String;
  I: Integer;
  QuestionWide: WideString;
  PermissionSnapshot, AnswersJSON: String;
  PermissionEvent: TAgentEvent;
  Data: TStringList;
  KeyMessage: TWMKey;
  Keyboard, SavedKeyboard: TKeyboardState;
  SavedDirs: TdevDirs;
  SavedConfig: TdevAgentConfig;
  ContextRoundTrip: TdevAgentConfig;
  SavedContextPreference: Boolean;
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
  Require(Pos('selected C/C++ code', AgentCodeActionPrompt(0, True)) > 0,
    'selected-code quick action did not target the selection');
  Require(Pos('current editor context around the caret',
    AgentCodeActionPrompt(0, False)) > 0,
    'no-selection quick action did not target the caret context');
  Require(Pos('selected C/C++ code', AgentCodeActionPrompt(1, False)) = 0,
    'no-selection fix action still claimed that code was selected');
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
    SavedAgentIni := devData.INIFileName;
    ContextIni := IncludeTrailingPathDelimiter(Root) + 'agent-context-test.ini';
    SavedContextPreference := devAgentConfig.AttachIdeContext;
    ContextRoundTrip := nil;
    DeleteFile(ContextIni);
    try
      devData.INIFileName := ContextIni;
      devAgentConfig.AttachIdeContext := False;
      devAgentConfig.SaveSettings;
      ContextRoundTrip := TdevAgentConfig.Create;
      try
        Require(not ContextRoundTrip.AttachIdeContext,
          'disabled IDE context preference did not survive configuration reload');
      finally
        ContextRoundTrip.Free;
        ContextRoundTrip := nil;
      end;
    finally
      if Assigned(ContextRoundTrip) then ContextRoundTrip.Free;
      devData.INIFileName := SavedAgentIni;
      DeleteFile(ContextIni);
      devAgentConfig.AttachIdeContext := SavedContextPreference;
    end;
    devAgentConfig.AttachIdeContext := False;
    fAgentPanelFrame := TAgentPanelFrame.Create(Self);
    Require(not fAgentPanelFrame.ContextEnabled,
      'panel did not initialize its context switch from saved preferences');
    devAgentConfig.AttachIdeContext := SavedContextPreference;
    fAgentPanelFrame.ContextEnabled := SavedContextPreference;
    // Keep this smoke test on the legacy VCL controls it is exercising. The
    // separate AgentWebPanelSmoke test covers the embedded renderer.
    for I := 0 to fAgentPanelFrame.ComponentCount - 1 do
      if fAgentPanelFrame.Components[I] is TTimer then
        TTimer(fAgentPanelFrame.Components[I]).Enabled := False;
    fAgentPanelFrame.Parent := Self;
    fAgentPanelFrame.Align := alClient;
    fAgentPanelFrame.OnSessionChange := AgentSessionChange;
    fAgentPanelFrame.OnPrepareContext := AgentPrepareContext;
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
    fAgentPanelFrame.memoInput.SetFocus;
    actPasteExecute(nil);
    Require(fAgentPanelFrame.memoInput.Text = 'copy reply',
      'reply to input paste failed: [' + fAgentPanelFrame.memoInput.Text +
      '] inputFocused=' + BoolToStr(fAgentPanelFrame.memoInput.Focused, True) +
      ' inputCanFocus=' + BoolToStr(fAgentPanelFrame.memoInput.CanFocus, True) +
      ' timelineEdit=' + BoolToStr(fAgentPanelFrame.Timeline.FocusedEdit <> nil, True));
    fAgentPanelFrame.ClearChat;
    Writeln('Agent integration: native clipboard actions passed');

    Writeln('Agent integration: starting diagnostic fixture'); Flush(Output);
    StartAgent;
    Writeln('Agent integration: diagnostic fixture started'); Flush(Output);
    CheckResume('');
    Writeln('Agent integration: diagnostic fixture ready'); Flush(Output);
    if not Assigned(fLogOutputRawData) then
      fLogOutputRawData := TStringList.Create;
    fLogOutputRawData.Clear;
    fLogOutputRawData.Add('ld.exe: undefined reference to `main`');
    DeleteFile(IncludeTrailingPathDelimiter(devDirs.Exec) + 'fixture-last-message.txt');
    UpdateAgentCompileContext;
    fAgentPanelFrame.SendPrompt('Diagnose the latest build output');
    PermissionSnapshot := fAgentPanelFrame.Timeline.WebBlock(
      fAgentPanelFrame.Timeline.BlockCount - 1);
    Require(Pos('contextSummary', PermissionSnapshot) > 0,
      'IDE context summary was not attached to the user message');
    Require(Pos('raw build lines', PermissionSnapshot) > 0,
      'raw compiler output count was missing from the user message summary');
    WaitReady;
    Data.LoadFromFile(IncludeTrailingPathDelimiter(devDirs.Exec) + 'fixture-last-message.txt');
    Require(Pos('undefined reference', Data.Text) > 0,
      'raw linker diagnostics were not attached to the AI request');
    fAgentPanelFrame.ContextEnabled := False;
    fAgentPanelFrame.SendPrompt('Context opt-out smoke test');
    PermissionSnapshot := fAgentPanelFrame.Timeline.WebBlock(
      fAgentPanelFrame.Timeline.BlockCount - 1);
    Require(Pos('context disabled', PermissionSnapshot) > 0,
      'the user message did not record that IDE context was disabled');
    WaitReady;
    Data.LoadFromFile(IncludeTrailingPathDelimiter(devDirs.Exec) + 'fixture-last-message.txt');
    Require(Pos('Context opt-out smoke test', Data.Text) > 0,
      'context opt-out prompt was not delivered to the agent');
    Require((Pos('undefined reference', Data.Text) = 0) and
      (Pos('Active editor:', Data.Text) = 0),
      'disabled context still included editor code or compiler diagnostics');
    fAgentPanelFrame.ContextEnabled := True;
    fLogOutputRawData.Clear;
    Writeln('Agent integration: compiler context attachment and opt-out passed');
    FillChar(PermissionEvent, SizeOf(PermissionEvent), 0);
    PermissionEvent.EventType := aetPermission;
    PermissionEvent.Subtype := 'can_use_tool';
    PermissionEvent.EventId := 'ask-answer';
    PermissionEvent.ToolName := 'AskUserQuestion';
    QuestionWide := UTF8Decode(#$E4#$BD#$BF#$E7#$94#$A8#$E5#$93#$AA#$E4#$B8#$AA#$E7#$BC#$96#$E8#$AF#$91#$E5#$99#$A8#$EF#$BC#$9F);
    QuestionUTF8 := UTF8Encode(QuestionWide);
    PermissionEvent.ToolInput := '{"questions":[{"question":"' + QuestionUTF8 + '","header":"Compiler","multiSelect":false,' +
      '"options":[{"label":"GCC","description":"GNU"},{"label":"Clang","description":"LLVM"}]}]}';
    fAgentPanelFrame.QueuePermission(PermissionEvent, 'C:\work');
    Require(fAgentPanelFrame.StatusBar.Panels[0].Text = String(UTF8Decode(
      #$E7#$AD#$89#$E5#$BE#$85#$E4#$BD#$A0#$E5#$AE#$A1#$E6#$89#$B9#$E2#$80#$A6)),
      'pending question did not update the IDE status');
    Require(not fAgentPanelFrame.btnSend.Enabled and
      fAgentPanelFrame.btnStop.Visible,
      'pending approval must pause sending and allow cancellation');
    PermissionSnapshot := fAgentPanelFrame.Timeline.WebBlock(fAgentPanelFrame.Timeline.BlockCount - 1);
    Require(Pos('"requestId":"ask-answer"', PermissionSnapshot) > 0,
      'inline approval request id missing');
    Require(Pos('\u4F7F\u7528\u54EA\u4E2A\u7F16\u8BD1\u5668\uFF1F', PermissionSnapshot) > 0,
      'UTF-8 question text was corrupted in the approval timeline');
    Require((Pos('"workDir":', PermissionSnapshot) > 0) and
      (Pos('work', PermissionSnapshot) > 0),
      'inline approval working directory missing');
    Require(fAgentPanelFrame.ResolvePermission('ask-answer', 'answer',
      '{"' + String(QuestionWide) + '":"GCC"}'), 'AskUserQuestion answer was rejected');
    Require(fAgentPanelFrame.StatusBar.Panels[0].Text = String(UTF8Decode(
      #$E5#$B0#$B1#$E7#$BB#$AA)),
      'answered question did not restore the previous IDE status');
    Require(fAgentPanelFrame.btnSend.Enabled and
      not fAgentPanelFrame.btnStop.Visible,
      'resolved approval did not restore the composer');
    PermissionSnapshot := fAgentPanelFrame.Timeline.WebBlock(fAgentPanelFrame.Timeline.BlockCount - 1);
    Require(Pos('"status":"answered"', PermissionSnapshot) > 0,
      'submitted question answer was shown as a completed tool');
    Require(Pos('\u4F7F\u7528\u54EA\u4E2A\u7F16\u8BD1\u5668\uFF1F', PermissionSnapshot) > 0,
      'answered UTF-8 question text was corrupted in the conversation timeline');
    Require((Pos('answers', PermissionSnapshot) > 0) and
      (Pos('GCC', PermissionSnapshot) > 0),
      'submitted question answer was not retained in the conversation timeline');
    Sleep(100);
    Data.LoadFromFile(IncludeTrailingPathDelimiter(devDirs.Exec) + 'fixture-decision.txt');
    Require(Pos('"request_id":"ask-answer"', Data.Text) > 0,
      'AskUserQuestion response request id missing');
    Require(Pos('"answers":{"' + QuestionUTF8 + '":"GCC"}', Data.Text) > 0,
      'AskUserQuestion answer was not returned as updated input');
    PermissionEvent.EventId := 'ask-invalid';
    fAgentPanelFrame.QueuePermission(PermissionEvent, 'C:\work');
    Require(fAgentPanelFrame.StatusBar.Panels[0].Text = String(UTF8Decode(
      #$E7#$AD#$89#$E5#$BE#$85#$E4#$BD#$A0#$E5#$AE#$A1#$E6#$89#$B9#$E2#$80#$A6)),
      'pending approval status was lost after a new request');
    Require(not fAgentPanelFrame.ResolvePermission('ask-invalid', 'answer', '{}'),
      'incomplete question answers must be rejected');
    fAgentPanelFrame.ExpirePendingPermissions;
    Require(fAgentPanelFrame.StatusBar.Panels[0].Text = String(UTF8Decode(
      #$E5#$B0#$B1#$E7#$BB#$AA)),
      'expired approval did not restore the previous IDE status');
    Require(fAgentPanelFrame.StatusBar.Panels[0].Text = String(UTF8Decode(
      #$E5#$B0#$B1#$E7#$BB#$AA)),
      'expired approval did not restore the previous IDE status');
    PermissionSnapshot := fAgentPanelFrame.Timeline.WebBlock(fAgentPanelFrame.Timeline.BlockCount - 1);
    Require(Pos('"status":"interrupted"', PermissionSnapshot) > 0,
      'expired permission was not marked stale');
    Require(not fAgentPanelFrame.ResolvePermission('ask-invalid', 'answer',
      '{"Which compiler?":"GCC"}'), 'expired permission was accepted');
    PermissionEvent.EventId := 'rewrite-request';
    PermissionEvent.ToolName := 'Write';
    PermissionEvent.ToolInput :=
      '{"file_path":"C:\\work\\sieve.cpp","content":"broken"}';
    fAgentPanelFrame.QueuePermission(PermissionEvent, 'C:\work');
    Require(fAgentPanelFrame.ResolvePermission('rewrite-request', 'deny', '',
      'Please regenerate with valid UTF-8 text.'),
      'encoding feedback denial was rejected');
    Sleep(100);
    Data.LoadFromFile(IncludeTrailingPathDelimiter(devDirs.Exec) + 'fixture-decision.txt');
    Require(Pos('"request_id":"rewrite-request"', Data.Text) > 0,
      'encoding feedback was sent for the wrong request');
    Require(Pos('"message":"Please regenerate with valid UTF-8 text."', Data.Text) > 0,
      'encoding feedback was not delivered to the model');
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


