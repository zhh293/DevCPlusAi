program AgentMainSmoke;
{$APPTYPE CONSOLE}
uses Windows, SysUtils, Classes, Controls, Forms, ExtCtrls, StdCtrls, main, AgentApprovalFrm;
type
  TApprovalProbe = class
    Decision: Integer;
    Seen: Boolean;
    SeenQuestion: Boolean;
    procedure Tick(Sender: TObject);
    procedure Failure(Sender: TObject; E: Exception);
    procedure SelectQuestionDefaults(Parent: TWinControl);
    function ClickQuestionSubmit(Parent: TWinControl): Boolean;
  end;
procedure TApprovalProbe.Failure(Sender: TObject; E: Exception);
begin
  Writeln('Unhandled VCL exception: ' + E.ClassName + ': ' + E.Message);
  Flush(Output);
  Halt(1);
end;
procedure TApprovalProbe.Tick(Sender: TObject);
var I: Integer;
begin
  for I := 0 to Screen.FormCount - 1 do begin
    if Screen.Forms[I].Caption = 'Review tool operation' then begin
      Seen := True;
      Screen.Forms[I].ModalResult := Decision;
    end else if Screen.Forms[I].Caption = 'Answer the AI questions' then begin
      SeenQuestion := True;
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
    if (Control is TButton) and (TButton(Control).Caption = 'Submit answers') then begin
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
var Host: TMainForm; Probe: TApprovalProbe; Timer: TTimer; AnswersJSON: String;
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
      Writeln('Agent integration: checking allow dialog'); Flush(Output);
      if not RequestAgentApproval('Bash', 'test workspace', '{"command":"echo test"}') or not Probe.Seen then
        raise Exception.Create('Approval allow dialog failed');
      Probe.Seen := False;
      Probe.Decision := mrNo;
      Writeln('Agent integration: checking deny dialog'); Flush(Output);
      if RequestAgentApproval('Bash', 'test workspace', '{"command":"echo test"}') or not Probe.Seen then
        raise Exception.Create('Approval deny dialog failed');
      Probe.SeenQuestion := False;
      if not RequestAgentQuestion(
        '{"questions":[{"question":"Compiler?","header":"Compiler","multiSelect":false,' +
        '"options":[{"label":"GCC","description":"GNU"},{"label":"Clang","description":"LLVM"}]},' +
        '{"question":"Checks?","header":"Checks","multiSelect":true,"options":' +
        '[{"label":"Warnings","description":"Show warnings"},' +
        '{"label":"Sanitizers","description":"Find memory errors"}]}]}', AnswersJSON) or
        not Probe.SeenQuestion then
        raise Exception.Create('AskUserQuestion dialog failed');
      if (Pos('"Compiler?":"GCC"', AnswersJSON) = 0) or
         (Pos('"Checks?":"Warnings, Sanitizers"', AnswersJSON) = 0) then
        raise Exception.Create('AskUserQuestion answer format failed: ' + AnswersJSON);
      Writeln('Agent integration: approval and AskUserQuestion fallback dialogs passed');
      Flush(Output);
    finally
      Timer.Free;
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
