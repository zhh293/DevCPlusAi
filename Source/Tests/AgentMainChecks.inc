procedure TMainForm.RunAgentInteractionChecks(const Root, Cli: String);
var
  Key1, Key2, Id1, SavedCliHome, Expected: String;
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
    fAgentPanelFrame.reChat.SetFocus;
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


