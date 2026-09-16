program AgentMainSmoke;
{$APPTYPE CONSOLE}
uses Windows, SysUtils, Classes, Controls, Forms, ExtCtrls, main, AgentApprovalFrm;
type
  TApprovalProbe = class
    Decision: Integer;
    Seen: Boolean;
    procedure Tick(Sender: TObject);
  end;
procedure TApprovalProbe.Tick(Sender: TObject);
var I: Integer;
begin
  for I := 0 to Screen.FormCount - 1 do
    if Screen.Forms[I].Caption = 'AI tool approval' then begin
      Seen := True;
      Screen.Forms[I].ModalResult := Decision;
    end;
end;
var Host: TMainForm; Probe: TApprovalProbe; Timer: TTimer;
begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
    Probe := TApprovalProbe.Create;
    Timer := TTimer.Create(nil);
    try
      Timer.Interval := 50;
      Timer.OnTimer := Probe.Tick;
      Probe.Decision := mrYes;
      if not RequestAgentApproval('Bash', 'test workspace', '{"command":"echo test"}') or not Probe.Seen then
        raise Exception.Create('Approval allow dialog failed');
      Probe.Seen := False;
      Probe.Decision := mrNo;
      if RequestAgentApproval('Bash', 'test workspace', '{"command":"echo test"}') or not Probe.Seen then
        raise Exception.Create('Approval deny dialog failed');
      Writeln('Agent integration: approval allow and deny dialogs passed');
    finally
      Timer.Free;
      Probe.Free;
    end;
    Host := TMainForm.CreateNew(nil);
    try
      Host.RunAgentInteractionChecks(ParamStr(1), ParamStr(2));
    finally
      Host.Free;
    end;
    Writeln('Agent main integration smoke test passed.');
  except
    on E: Exception do begin
      Writeln(E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
