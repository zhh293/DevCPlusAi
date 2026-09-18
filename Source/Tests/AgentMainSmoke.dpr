program AgentMainSmoke;
{$APPTYPE CONSOLE}
uses Windows, SysUtils, Classes, Controls, Forms, ExtCtrls, main, AgentApprovalFrm;
type
  TApprovalProbe = class
    Decision: Integer;
    Seen: Boolean;
    procedure Tick(Sender: TObject);
    procedure Failure(Sender: TObject; E: Exception);
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
      Writeln('Agent integration: approval allow and deny dialogs passed');
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
