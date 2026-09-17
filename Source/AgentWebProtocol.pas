unit AgentWebProtocol;
interface
uses SysUtils;
function WebQuote(const Text: WideString): String;
implementation
function WebQuote(const Text: WideString): String;
var I, C: Integer;
begin
  Result := '"';
  for I := 1 to Length(Text) do begin
    C := Ord(Text[I]);
    if (C < 32) or (C > 126) or (C = 34) or (C = 92) then
      Result := Result + '\u' + IntToHex(C, 4)
    else Result := Result + Char(C);
  end;
  Result := Result + '"';
end;
end.
