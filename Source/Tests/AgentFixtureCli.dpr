program AgentFixtureCli;
{$APPTYPE CONSOLE}
uses SysUtils, Classes;
var
  I, N: Integer;
  Id, Line: String;
  Data: TStringList;
begin
  Id := '';
  for I := 1 to ParamCount - 1 do
    if ParamStr(I) = '--resume' then Id := ParamStr(I + 1);
  Data := TStringList.Create;
  try
    Data.Text := Id;
    Data.SaveToFile('fixture-resume.txt');
    if Id = '' then begin
      N := 0;
      if FileExists('fixture-count.txt') then begin
        Data.LoadFromFile('fixture-count.txt');
        N := StrToIntDef(Trim(Data.Text), 0);
      end;
      Inc(N);
      Data.Text := IntToStr(N);
      Data.SaveToFile('fixture-count.txt');
      Id := 'fixture-session-' + IntToStr(N);
    end;
    Writeln('{"type":"system","subtype":"init","session_id":"' + Id + '","model":"fixture"}');
    Flush(Output);
    while not Eof(Input) do begin
      Readln(Line);
      if Pos('control_response', Line) > 0 then begin
        Data.Text := Line;
        Data.SaveToFile('fixture-decision.txt');
        Continue;
      end;
      if Line <> '' then begin
        Writeln('{"type":"assistant","session_id":"' + Id + '","message":{"id":"msg-' + Id + '","content":[{"type":"text","text":"Reply for ' + Id + '"}]}}');
        Writeln('{"type":"result","subtype":"success","session_id":"' + Id + '","result":"Reply for ' + Id + '","is_error":false}');
        Flush(Output);
      end;
    end;
  finally
    Data.Free;
  end;
end.
