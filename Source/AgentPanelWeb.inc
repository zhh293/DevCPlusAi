procedure TAgentPanelFrame.WebTick(Sender: TObject);
const Assets: array[0..7] of String = ('index.html', 'panel.js', 'panel.css',
  'messages.js', 'highlight.js', 'highlight.css', 'layout.css', 'vendor\marked.umd.js');
var Root, Page, Command: String; I: Integer;
begin
  if (csDestroying in ComponentState) or (Parent = nil) then Exit;
  fWebTimer.Enabled := False;
  try
    if not fWebStarted then begin
      fWebStarted := True;
      fWebStartTick := GetTickCount;
      Root := ExtractFilePath(Application.ExeName);
      Page := Root + 'AgentWeb\index.html';
      if not FileExists(Page) or not FileExists(Root + 'AgentWebHost.dll') then begin
        WebError(Self, 'Missing AgentWeb assets or AgentWebHost.dll beside devcpp.exe');
        Exit;
      end;
      for I := Low(Assets) to High(Assets) do
        if not FileExists(Root + 'AgentWeb\' + Assets[I]) then begin
          WebError(Self, 'Missing chat asset: AgentWeb\' + Assets[I]); Exit;
        end;
      fWeb := TAgentWebView.Create(Self);
      fWeb.Parent := Self;
      fWeb.Visible := False;
      fWeb.SetBounds(0, 0, ClientWidth, ClientHeight);
      fWeb.OnReady := WebReady;
      fWeb.OnMessage := WebMessage;
      fWeb.OnError := WebError;
      Root := GetEnvironmentVariable('LOCALAPPDATA') + '\DevCPlusAi\WebView';
      ForceDirectories(Root);
      if not fWeb.Start(ExtractFilePath(Application.ExeName) + 'AgentWebHost.dll',
        WideString(Page), WideString(Root)) and not fWebFailed then
        WebError(Self, 'Could not initialize the browser runtime');
    end;
    while fWebQueue.Count > 0 do begin
      Command := fWebQueue[0]; fWebQueue.Delete(0);
      WebDispatch(UTF8Decode(Command));
    end;
    if Assigned(fWeb) and fWeb.Ready and fWebScriptReady and not fWebFailed then begin
      fWeb.SetBounds(0, 0, ClientWidth, ClientHeight);
      fWeb.SyncWindow;
      WebSync;
    end;
    if not fWebAppReady and not fWebFailed and (GetTickCount - fWebStartTick > 15000) then
      WebError(Self, 'Chat startup handshake timed out (scripts=' +
        BoolToStr(fWebScriptReady, True) + ', app=' + BoolToStr(fWebAppReady, True) + ')');
  finally
    if not (csDestroying in ComponentState) then fWebTimer.Enabled := True;
  end;
end;

procedure TAgentPanelFrame.WebReady(Sender: TObject);
begin
  if fWebFailed then Exit;
  fWebCache.Clear;
  fWebGeneration := -1;
  fWebTimelineRevision := -1;
  fWebState := '';
  fWebDraft := #1;
end;

procedure TAgentPanelFrame.WebError(Sender: TObject; const Text: WideString);
begin
  if fWebFailed then Exit;
  fWebFailed := True;
  fWebAppReady := False;
  fWebErrorText := String(Text);
  if Assigned(fWeb) then fWeb.Visible := False;
  if not Assigned(fWebRetry) then begin
    fWebRetry := TButton.Create(Self);
    fWebRetry.Parent := Self;
    fWebRetry.SetBounds(8, 4, 180, 28);
    fWebRetry.Caption := 'Retry AI chat renderer';
    fWebRetry.OnClick := RetryWeb;
  end;
  fWebRetry.Visible := True;
  fWebRetry.BringToFront;
  if not Assigned(fWebDiagnostics) then begin
    fWebDiagnostics := TButton.Create(Self);
    fWebDiagnostics.Parent := Self;
    fWebDiagnostics.SetBounds(8, 36, 180, 28);
    fWebDiagnostics.Caption := 'Copy UI diagnostics';
    fWebDiagnostics.OnClick := CopyWebDiagnostics;
  end;
  fWebDiagnostics.Visible := True;
  fWebDiagnostics.BringToFront;
  AppendSystemMessage('Chat renderer unavailable: ' + String(Text));
end;

procedure TAgentPanelFrame.RetryWeb(Sender: TObject);
begin
  FreeAndNil(fWeb);
  fWebQueue.Clear;
  fWebFailed := False;
  fWebScriptReady := False;
  fWebAppReady := False;
  fWebErrorText := '';
  fWebStarted := False;
  fWebRetry.Visible := False;
  if Assigned(fWebDiagnostics) then fWebDiagnostics.Visible := False;
end;

procedure TAgentPanelFrame.CopyWebDiagnostics(Sender: TObject);
var Lines, Build: TStringList; Root, S: String; I: Integer;
begin
  Lines := TStringList.Create; Build := TStringList.Create;
  try
    Root := ExtractFilePath(Application.ExeName);
    Lines.Add('DevCPlusAi ' + DEVCPP_VERSION);
    Lines.Add('Base IDE: Red Panda Dev-C++ ' + DEVCPP_BASE_VERSION);
    Lines.Add('Executable: ' + Application.ExeName);
    Lines.Add('Renderer: WebView2 / local virtual host');
    if Assigned(fWeb) then Lines.Add('WebView2 runtime: ' + String(fWeb.RuntimeVersion));
    Lines.Add('Page scripts ready: ' + BoolToStr(fWebScriptReady, True));
    Lines.Add('UI handshake ready: ' + BoolToStr(fWebAppReady, True));
    Lines.Add('Last renderer error: ' + fWebErrorText);
    Lines.Add('AgentWebHost.dll present: ' + BoolToStr(FileExists(Root + 'AgentWebHost.dll'), True));
    Lines.Add('Chat page present: ' + BoolToStr(FileExists(Root + 'AgentWeb\index.html'), True));
    if FileExists(Root + 'BUILD-INFO.txt') then begin
      Build.LoadFromFile(Root + 'BUILD-INFO.txt');
      for I := 0 to Build.Count - 1 do begin
        S := Build[I];
        if (Pos('Package-Version:', S) = 1) or (Pos('Source-Commit:', S) = 1) or
           (Pos('Generated-UTC:', S) = 1) then Lines.Add(S);
      end;
    end;
    { Deliberately do not read configuration, environment credentials or chat logs. }
    Clipboard.AsText := Lines.Text;
    if Sender = fWebDiagnostics then fWebDiagnostics.Caption := 'Diagnostics copied';
  finally Build.Free; Lines.Free; end;
end;

procedure TAgentPanelFrame.WebMessage(Sender: TObject; const Text: WideString);
begin
  { Modal dialogs and agent commands must run outside WebView COM callbacks. }
  if (Length(Text) <= 1048576) and (fWebQueue.Count < 100) then
    fWebQueue.Add(UTF8Encode(Text));
end;

procedure TAgentPanelFrame.WebDispatch(const Text: WideString);
var J, Field: TlkJSONbase; Action, Packet, RequestId, CopyError, LinkUrl,
    PermissionMode, PermissionModeError, PermissionModeReason: String;
  CopySucceeded, ContextEnabled, PermissionModeSuccess: Boolean;
  I: Integer; OpenResult: HINST;
  function Value(const Name: String): WideString;
  var V: TlkJSONbase;
  begin
    Result := ''; V := J.Field[Name];
    if (V <> nil) and (V is TlkJSONstring) then Result := V.Value;
  end;
begin
  J := nil;
  try
   try
    J := TlkJSON.ParseText(UTF8Encode(Text));
    if not (J is TlkJSONobject) then Exit;
    Field := J.Field['version'];
    if Field = nil then Exit;
    if Field.Value <> 1 then Exit;
    Action := String(Value('action'));
    if Action = 'ready' then fWebScriptReady := True
    else if Action = 'app-ready' then begin
      if fWebScriptReady and Assigned(fWeb) and fWeb.Ready and not fWebFailed then begin
        fWebAppReady := True;
        if Assigned(fWebRetry) then fWebRetry.Visible := False;
        if Assigned(fWebDiagnostics) then fWebDiagnostics.Visible := False;
        fWeb.Visible := True; fWeb.BringToFront; fWeb.SyncWindow;
      end;
    end else if Action = 'diagnostics' then CopyWebDiagnostics(Self)
    else if Action = 'draft' then begin
      memoInput.Text := String(Value('text')); fWebDraft := memoInput.Text;
    end else if Action = 'send' then begin
      if IsAgentBusy then begin
        fWeb.PostJSON(WideString('{"version":1,"type":"rejected","requestId":' + WebQuote(Value('requestId')) + '}'));
        Exit;
      end;
      memoInput.Text := String(Value('text'));
      SendCurrentInput;
      fWebDraft := memoInput.Text;
      if fStatus = asThinking then
        fWeb.PostJSON(WideString('{"version":1,"type":"accepted","requestId":' + WebQuote(Value('requestId')) + '}'))
      else
        fWeb.PostJSON(WideString('{"version":1,"type":"rejected","requestId":' + WebQuote(Value('requestId')) + '}'));
    end else if Action = 'stop' then btnStopClick(Self)
    else if Action = 'settings' then btnSettingsClick(Self)
    else if Action = 'permission-mode' then begin
      PermissionMode := String(Value('mode'));
      PermissionModeError := '';
      PermissionModeReason := '';
      PermissionModeSuccess := False;
      if SameText(PermissionMode, 'plan') then PermissionMode := 'plan'
      else if SameText(PermissionMode, 'manual') then PermissionMode := 'manual'
      else if SameText(PermissionMode, 'acceptEdits') then PermissionMode := 'acceptEdits'
      else PermissionModeReason := 'unsupported';
      if PermissionModeReason = '' then begin
        if IsAgentBusy then
          PermissionModeReason := 'busy'
        else if not Assigned(fOnPermissionModeChange) then
          PermissionModeReason := 'unavailable'
        else begin
          PermissionModeSuccess := fOnPermissionModeChange(Self,
            PermissionMode, PermissionModeError);
          if not PermissionModeSuccess then PermissionModeReason := 'failed';
        end;
      end;
      Packet := '{"version":1,"type":"permission-mode-result","success":' +
        LowerCase(BoolToStr(PermissionModeSuccess, True)) +
        ',"mode":' + WebQuote(PermissionMode) +
        ',"reason":' + WebQuote(PermissionModeReason);
      if PermissionModeError <> '' then
        Packet := Packet + ',"detail":' + WebQuote(PermissionModeError);
      Packet := Packet + '}';
      fWeb.PostJSON(WideString(Packet));
    end
    else if Action = 'attach' then btnAttachClick(Self)
    else if Action = 'paste-image' then btnPasteImageClick(Self)
    else if Action = 'remove' then begin
      I := StrToIntDef(String(Value('index')), -1);
      if (I >= 0) and (I < fAttachments.Count) then RemoveAttachmentAt(I);
    end else if Action = 'new' then begin
      if not IsAgentBusy then NewSessionClick(Self);
    end else if Action = 'session' then begin
      if IsAgentBusy then Exit;
      I := fSessionKeys.IndexOf(String(Value('key')));
      if I >= 0 then begin fSessions.ItemIndex := I; SessionChange(Self); end;
    end else if (Action = 'rename-session') or (Action = 'delete-session') then begin
      if IsAgentBusy then Exit;
      I := fSessionKeys.IndexOf(String(Value('key')));
      if (I >= 0) and Assigned(fOnSessionAction) then
        fOnSessionAction(Self, Action, fSessionKeys[I], Copy(Trim(String(Value('title'))), 1, 120));
    end else if Action = 'copy' then CopyAnswerClick(Self)
    else if Action = 'copy-code-block' then begin
      RequestId := String(Value('requestId'));
      CopySucceeded := False;
      CopyError := '';
      try
        Clipboard.AsText := String(Value('text'));
        CopySucceeded := True;
      except
        on E: Exception do CopyError := E.Message;
      end;
      Packet := '{"version":1,"type":"code-copy-result","requestId":' +
        WebQuote(RequestId) + ',"success":' +
        LowerCase(BoolToStr(CopySucceeded, True));
      if CopyError <> '' then Packet := Packet + ',"error":' + WebQuote(CopyError);
      Packet := Packet + '}';
      fWeb.PostJSON(WideString(Packet));
    end
    else if Action = 'open-code' then OpenCodeClick(Self)
    else if Action = 'open-code-block' then begin
      fWebCode := String(Value('text'));
      try OpenCodeClick(Self); finally fWebCode := ''; end;
    end
    else if Action = 'open-link' then begin
      LinkUrl := String(Value('url'));
      if not AgentIsSafeExternalUrl(LinkUrl) then Exit;
      OpenResult := ShellExecute(Application.Handle, 'open', PChar(LinkUrl), nil, nil, SW_SHOWNORMAL);
      if Integer(OpenResult) <= 32 then
        AppendSystemMessage('[Error] Could not open the external link in the default browser.');
    end
    else if Action = 'insert-code-block' then begin
      if not IsAgentBusy and Assigned(fOnInsertCode) then
        fOnInsertCode(Self, String(Value('text')));
    end
    else if Action = 'open-file' then
      OpenChangedFile(String(Value('path')))
    else if Action = 'undo-file-change' then
      UndoFileChange(String(Value('undoToken')))
    else if Action = 'context' then PrepareContextClick(Self)
    else if Action = 'context-enabled' then begin
      if not IsAgentBusy then begin
        ContextEnabled := SameText(String(Value('enabled')), 'true');
        if ContextEnabled <> fContextEnabled then begin
          fContextEnabled := ContextEnabled;
          if Assigned(devAgentConfig) then begin
            devAgentConfig.AttachIdeContext := fContextEnabled;
            devAgentConfig.SaveSettings;
          end;
        end;
      end;
    end
    else if Action = 'clear' then begin
      if not IsAgentBusy then ClearChatClick(Self);
    end else if Action = 'permission' then begin
      if not ResolvePermission(String(Value('requestId')), String(Value('decision')),
        String(Value('answers')), String(Value('reason'))) then
        fWeb.PostJSON(WideString('{"version":1,"type":"permission-error","requestId":' +
          WebQuote(String(Value('requestId'))) + ',"message":' +
          WebQuote('此请求已失效或提交失败，请检查回答后重试。') + '}'));
    end else if Action = 'logs' then fDetails.Checked := not fDetails.Checked
    else if Action = 'quick' then begin
      I := StrToIntDef(String(Value('index')), -1);
      if (I >= 0) and (I < fQuickActions.Items.Count) then begin
        fQuickActions.ItemIndex := I; QuickActionClick(Self);
      end;
    end;
  except
    on E: Exception do AppendSystemMessage('AI panel action failed: ' + E.Message);
  end;
  finally
    J.Free;
  end;
end;

procedure TAgentPanelFrame.WebSync;
var I: Integer; Packet, Sessions, Attachments, Theme, Busy, Permission,
    FontName, FontSize: String;
begin
  if fWebGeneration <> fTimeline.Generation then begin
    fWeb.PostJSON('{"version":1,"type":"reset"}');
    fWebGeneration := fTimeline.Generation;
    fWebCache.Clear;
  end;
  if fWebTimelineRevision <> fTimeline.Revision then begin
   for I := 0 to fTimeline.BlockCount - 1 do begin
    Packet := fTimeline.WebBlock(I);
    if I >= fWebCache.Count then fWebCache.Add('');
    if fWebCache[I] <> Packet then
      if fWeb.PostJSON(WideString(Packet)) then fWebCache[I] := Packet;
   end;
   fWebTimelineRevision := fTimeline.Revision;
  end;
  Sessions := '[';
  for I := 0 to fSessionKeys.Count - 1 do begin
    if I > 0 then Sessions := Sessions + ',';
    Sessions := Sessions + '{"key":' + WebQuote(fSessionKeys[I]) +
      ',"title":' + WebQuote(fSessions.Items[I]) + '}';
  end;
  Sessions := Sessions + ']';
  Attachments := '[';
  for I := 0 to fAttachments.Count - 1 do begin
    if I > 0 then Attachments := Attachments + ',';
    Attachments := Attachments + '{"name":' +
      WebQuote(ExtractFileName(fAttachments[I])) + ',"path":' +
      WebQuote(fAttachments[I]) + '}';
  end;
  Attachments := Attachments + ']';
  Theme := 'light'; if AgentUiIsDark(reChat.Color) then Theme := 'dark';
  Busy := 'false'; if IsAgentBusy then Busy := 'true';
  Permission := 'manual';
  if Assigned(devAgentConfig) then Permission := devAgentConfig.PermissionMode;
  FontName := reChat.Font.Name;
  FontSize := IntToStr(reChat.Font.Size);
  Packet := '{"version":1,"type":"state","busy":' + Busy +
    ',"contextEnabled":' + LowerCase(BoolToStr(fContextEnabled, True)) +
    ',"status":' + WebQuote(StatusBar.Panels[0].Text) + ',"model":' + WebQuote(fModelName) +
    ',"theme":' + WebQuote(Theme) + ',"sessions":' + Sessions +
    ',"selected":' + WebQuote(SelectedSession) + ',"attachments":' + Attachments +
    ',"permission":' + WebQuote(Permission) +
    ',"contextSummary":' + WebQuote(fContextSummary) +
    ',"contextPayload":' + WebQuote(fContextPreviewPayload) +
    ',"fontName":' + WebQuote(FontName) + ',"fontSize":' + FontSize +
    ',"ctrlEnter":' + LowerCase(BoolToStr(fSendOnCtrlEnter, True)) + '}';
  if Packet <> fWebState then
    if fWeb.PostJSON(WideString(Packet)) then fWebState := Packet;
  if fWebDraft <> memoInput.Text then begin
    fWebDraft := memoInput.Text;
    fWeb.PostJSON(WideString('{"version":1,"type":"draft","text":' + WebQuote(fWebDraft) + '}'));
  end;
end;
