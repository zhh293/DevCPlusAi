program AgentMainSmoke;
{$APPTYPE CONSOLE}
uses Windows, SysUtils, Classes, Controls, Forms, ExtCtrls, StdCtrls, ComCtrls,
  main, AgentApprovalFrm;
type
  TApprovalProbe = class
    Decision: Integer;
    Seen, SeenUtf8ApprovalContent, SeenDiffRemoval, SeenSafetyText,
      SeenForbiddenText, SeenDiffContext: Boolean;
    SeenQuestion, SeenLocalizedApproval, SeenLocalizedDeny,
      SeenLocalizedAllow, SeenLocalizedQuestion: Boolean;
    ExpectedApprovalText, ExpectedRemovedText, ExpectedSafetyText,
      ExpectedForbiddenText, ExpectedContextText: String;
    procedure Tick(Sender: TObject);
    procedure Failure(Sender: TObject; E: Exception);
    procedure SelectQuestionDefaults(Parent: TWinControl);
    function ClickQuestionSubmit(Parent: TWinControl): Boolean;
end;
function AgentTestUiText(const Utf8Bytes: AnsiString): String;
begin
  Result := String(UTF8Decode(Utf8Bytes));
end;
procedure TApprovalProbe.Failure(Sender: TObject; E: Exception);
begin
  Writeln('Unhandled VCL exception: ' + E.ClassName + ': ' + E.Message);
  Flush(Output);
  Halt(1);
end;
procedure TApprovalProbe.Tick(Sender: TObject);
var I, J: Integer; Control: TControl;
begin
  for I := 0 to Screen.FormCount - 1 do begin
    if Screen.Forms[I].Caption = AgentTestUiText(#$41#$49#$20#$E6#$93#$8D#$E4#$BD#$9C#$E5#$AE#$A1#$E6#$89#$B9) then begin
      Seen := True;
      for J := 0 to Screen.Forms[I].ControlCount - 1 do begin
        Control := Screen.Forms[I].Controls[J];
        if (Control is TButton) and
           (TButton(Control).Caption = AgentTestUiText(#$E6#$8B#$92#$E7#$BB#$9D)) then
          SeenLocalizedDeny := True;
        if (Control is TButton) and
           (TButton(Control).Caption = AgentTestUiText(#$E5#$85#$81#$E8#$AE#$B8#$E4#$B8#$80#$E6#$AC#$A1)) then
          SeenLocalizedAllow := True;
        SeenLocalizedApproval := SeenLocalizedDeny and SeenLocalizedAllow;
        if (Control is TMemo) and (ExpectedApprovalText <> '') and
           (Pos(ExpectedApprovalText, TMemo(Control).Text) > 0) then
          SeenUtf8ApprovalContent := True;
        if (Control is TMemo) then begin
          if (ExpectedSafetyText <> '') and
             (Pos(ExpectedSafetyText, TMemo(Control).Text) > 0) then
            SeenSafetyText := True;
          if (ExpectedForbiddenText <> '') and
             (Pos(ExpectedForbiddenText, TMemo(Control).Text) > 0) then
            SeenForbiddenText := True;
        end;
        if (Control is TRichEdit) then begin
          if (ExpectedApprovalText <> '') and
             (Pos(ExpectedApprovalText, TRichEdit(Control).Text) > 0) then
            SeenUtf8ApprovalContent := True;
          if (ExpectedRemovedText <> '') and
             (Pos(ExpectedRemovedText, TRichEdit(Control).Text) > 0) then
            SeenDiffRemoval := True;
          if (ExpectedContextText <> '') and
             (Pos(ExpectedContextText, TRichEdit(Control).Text) > 0) then
            SeenDiffContext := True;
        end;
      end;
      Screen.Forms[I].ModalResult := Decision;
    end else if Screen.Forms[I].Caption = AgentTestUiText(#$E5#$9B#$9E#$E7#$AD#$94#$20#$41#$49#$20#$E7#$9A#$84#$E9#$97#$AE#$E9#$A2#$98) then begin
      SeenQuestion := True;
      SeenLocalizedQuestion := True;
      SelectQuestionDefaults(Screen.Forms[I]);
      ClickQuestionSubmit(Screen.Forms[I]);
      Exit;
    end;
  end;
end;
procedure TApprovalProbe.SelectQuestionDefaults(Parent: TWinControl);
var I: Integer; Control: TControl; List: TListBox;
begin
  for I := 0 to Parent.ControlCount - 1 do begin
    Control := Parent.Controls[I];
    if Control is TListBox then begin
      List := TListBox(Control);
      if List.Items.Count > 0 then List.Selected[0] := True;
      if List.MultiSelect and (List.Items.Count > 1) then List.Selected[1] := True;
    end;
    if Control is TWinControl then SelectQuestionDefaults(TWinControl(Control));
  end;
end;
function TApprovalProbe.ClickQuestionSubmit(Parent: TWinControl): Boolean;
var I: Integer; Control: TControl;
begin
  Result := False;
  for I := 0 to Parent.ControlCount - 1 do begin
    Control := Parent.Controls[I];
    if (Control is TButton) and
       (TButton(Control).Caption = AgentTestUiText(#$E6#$8F#$90#$E4#$BA#$A4#$E5#$9B#$9E#$E7#$AD#$94)) then begin
      TButton(Control).Click;
      Result := True;
      Exit;
    end;
    if Control is TWinControl then
      if ClickQuestionSubmit(TWinControl(Control)) then begin
        Result := True;
        Exit;
      end;
  end;
end;
var Host: TMainForm; Probe: TApprovalProbe; Timer: TTimer;
  AnswersJSON, ChineseText, ProposalUTF8, ProposalJSON, EditJSON, ReviewDir,
  ReviewName, ReviewPath, ReviewRoot, OutsidePath: String;
  ChineseWide, ProposalWide: WideString;
  ReviewLines: TStringList;
begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    Probe := TApprovalProbe.Create;
    Application.OnException := Probe.Failure;
    Timer := TTimer.Create(nil);
    try
      Timer.Interval := 50;
      Timer.OnTimer := Probe.Tick;
      Probe.Decision := mrYes;
      Probe.SeenLocalizedApproval := False;
      Probe.SeenLocalizedDeny := False;
      Probe.SeenLocalizedAllow := False;
      Writeln('Agent integration: checking allow dialog'); Flush(Output);
      if not RequestAgentApproval('Bash', 'test workspace', '{"command":"echo test"}') or not Probe.Seen or
         not Probe.SeenLocalizedApproval then
        raise Exception.Create('Approval allow dialog failed');
      Probe.Seen := False;
      Probe.SeenLocalizedApproval := False;
      Probe.SeenLocalizedDeny := False;
      Probe.SeenLocalizedAllow := False;
      Probe.Decision := mrNo;
      Writeln('Agent integration: checking deny dialog'); Flush(Output);
      if RequestAgentApproval('Bash', 'test workspace', '{"command":"echo test"}') or
         not Probe.Seen or not Probe.SeenLocalizedApproval then
        raise Exception.Create('Approval deny dialog failed');
      ChineseWide := UTF8Decode(#$E4#$BD#$A0#$E5#$A5#$BD);
      ChineseText := String(ChineseWide);
      ReviewRoot := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
        'DevCPlusAi-AgentDiff-' + IntToStr(GetCurrentProcessId) + '-' +
        IntToStr(GetTickCount);
      ReviewDir := IncludeTrailingPathDelimiter(ReviewRoot) + 'workspace';
      ForceDirectories(ReviewDir);
      ReviewName := 'DevCPlusAi-AgentDiff-' + IntToStr(GetCurrentProcessId) + '.cpp';
      ReviewPath := IncludeTrailingPathDelimiter(ReviewDir) + ReviewName;
      OutsidePath := IncludeTrailingPathDelimiter(ReviewRoot) + 'outside.cpp';
      ReviewLines := TStringList.Create;
      try
        ReviewLines.Text := 'int main() {' + #13#10 + '    return 0;' + #13#10 + '}';
        ReviewLines.SaveToFile(ReviewPath);
      finally
        ReviewLines.Free;
      end;
      ProposalWide := '// ' + ChineseWide + #13#10 + 'int main() {' + #13#10 +
        '    return 1;' + #13#10 + '}';
      ProposalUTF8 := UTF8Encode(ProposalWide);
      ProposalUTF8 := StringReplace(ProposalUTF8, '\', '\\', [rfReplaceAll]);
      ProposalUTF8 := StringReplace(ProposalUTF8, '"', '\"', [rfReplaceAll]);
      ProposalUTF8 := StringReplace(ProposalUTF8, #13#10, '\n', [rfReplaceAll]);
      ProposalJSON := '{"file_path":"' + ReviewName + '","content":"' +
        ProposalUTF8 + '"}';
      Probe.Seen := False;
      Probe.SeenUtf8ApprovalContent := False;
      Probe.SeenDiffRemoval := False;
      Probe.SeenDiffContext := False;
      Probe.ExpectedApprovalText := '+ // ' + ChineseText;
      Probe.ExpectedRemovedText := '-     return 0;';
      Probe.ExpectedContextText := '  int main() {';
      Probe.Decision := mrYes;
      try
        if not RequestAgentApproval('Write', ReviewDir, ProposalJSON) or
          not Probe.Seen or not Probe.SeenUtf8ApprovalContent or
          not Probe.SeenDiffRemoval or not Probe.SeenDiffContext then
          raise Exception.Create('UTF-8 file diff was not displayed correctly');
        Probe.Seen := False;
        Probe.SeenUtf8ApprovalContent := False;
        Probe.SeenDiffRemoval := False;
        Probe.ExpectedApprovalText := '+     return 1;';
        Probe.ExpectedRemovedText := '-     return 0;';
        EditJSON := '{"file_path":"' + ReviewName +
          '","old_string":"    return 0;","new_string":"    return 1;"}';
        if not RequestAgentApproval('Edit', ReviewDir, EditJSON) or
          not Probe.Seen or not Probe.SeenUtf8ApprovalContent or
          not Probe.SeenDiffRemoval then
          raise Exception.Create('Edit tool diff was not displayed correctly');
      finally
        DeleteFile(ReviewPath);
      end;
      ReviewLines := TStringList.Create;
      try
        ReviewLines.Text := 'OUTSIDE_MARKER';
        ReviewLines.SaveToFile(OutsidePath);
      finally
        ReviewLines.Free;
      end;
      Probe.Seen := False;
      Probe.SeenUtf8ApprovalContent := False;
      Probe.SeenSafetyText := False;
      Probe.SeenForbiddenText := False;
      Probe.ExpectedApprovalText := 'proposed content';
      Probe.ExpectedSafetyText := AgentTestUiText(
        #$E7#$9B#$AE#$E6#$A0#$87#$E4#$BD#$8D#$E4#$BA#$8E#$E5#$B7#$A5#$E4#$BD#$9C#$E7#$9B#$AE#$E5#$BD#$95#$E4#$B9#$8B#$E5#$A4#$96);
      Probe.ExpectedForbiddenText := 'OUTSIDE_MARKER';
      try
        if not RequestAgentApproval('Write', ReviewDir,
          '{"file_path":"../outside.cpp","content":"proposed content"}') or
          not Probe.Seen or not Probe.SeenSafetyText or
          not Probe.SeenUtf8ApprovalContent or Probe.SeenForbiddenText then
          raise Exception.Create('Out-of-workspace approval read or hid the target contents');
      finally
        DeleteFile(OutsidePath);
        RemoveDir(ReviewDir);
        RemoveDir(ReviewRoot);
      end;
      Probe.ExpectedApprovalText := '';
      Probe.ExpectedRemovedText := '';
      Probe.ExpectedContextText := '';
      Probe.ExpectedSafetyText := '';
      Probe.ExpectedForbiddenText := '';
      Probe.SeenQuestion := False;
      Probe.SeenLocalizedQuestion := False;
      if not RequestAgentQuestion(
        '{"questions":[{"question":"Compiler?","header":"Compiler","multiSelect":false,' +
        '"options":[{"label":"GCC","description":"GNU"},{"label":"Clang","description":"LLVM"}]},' +
        '{"question":"Checks?","header":"Checks","multiSelect":true,"options":' +
        '[{"label":"Warnings","description":"Show warnings"},' +
        '{"label":"Sanitizers","description":"Find memory errors"}]}]}', AnswersJSON) or
        not Probe.SeenQuestion or not Probe.SeenLocalizedQuestion then
        raise Exception.Create('AskUserQuestion dialog failed');
      if (Pos('"Compiler?":"GCC"', AnswersJSON) = 0) or
         (Pos('"Checks?":"Warnings, Sanitizers"', AnswersJSON) = 0) then
        raise Exception.Create('AskUserQuestion answer format failed: ' + AnswersJSON);
      Writeln('Agent integration: approval and AskUserQuestion fallback dialogs passed');
      Flush(Output);
    finally
      Timer.Free;
    end;
    if SameText(ParamStr(3), '--approval-only') then begin
      Application.OnException := nil;
      Probe.Free;
      Writeln('Agent approval and AskUserQuestion smoke test passed.');
      Flush(Output);
      Halt(0);
    end;
    Host := TMainForm.CreateNew(nil);
    Writeln('Agent integration: checking IDE actions'); Flush(Output);
    try
      Host.RunAgentInteractionChecks(ParamStr(1), ParamStr(2));
    finally
      Host.Free;
      Application.OnException := nil;
      Probe.Free;
    end;
    Writeln('Agent main integration smoke test passed.');
  except
    on E: Exception do begin
      Writeln(E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
