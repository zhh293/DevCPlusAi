program AgentMainSmoke;
{$APPTYPE CONSOLE}
uses Windows, SysUtils, Forms, main;
var Host: TMainForm;
begin
  try
    Application.Initialize;
    Application.ShowMainForm := False;
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
