unit AgentWebLinks;

interface

function AgentIsSafeExternalUrl(const URL: String): Boolean;

implementation

uses SysUtils;

function AgentIsSafeExternalUrl(const URL: String): Boolean;
var
  Candidate, LowerCandidate, Authority: String;
  PrefixLength, AuthorityEnd, I: Integer;
  Ch: Char;
begin
  Result := False;
  Candidate := Trim(URL);
  if (Candidate = '') or (Length(Candidate) > 2048) then Exit;
  for I := 1 to Length(Candidate) do begin
    Ch := Candidate[I];
    if (Ord(Ch) <= 32) or (Ord(Ch) = 127) or
       (Ch in ['\', '"', '<', '>']) or (Ch = #39) then Exit;
  end;

  LowerCandidate := LowerCase(Candidate);
  if Copy(LowerCandidate, 1, 8) = 'https://' then
    PrefixLength := 8
  else if Copy(LowerCandidate, 1, 7) = 'http://' then
    PrefixLength := 7
  else
    Exit;

  AuthorityEnd := Length(Candidate);
  for I := PrefixLength + 1 to Length(Candidate) do
    if Candidate[I] in ['/', '?', '#'] then begin
      AuthorityEnd := I - 1;
      Break;
    end;
  Authority := Copy(Candidate, PrefixLength + 1,
    AuthorityEnd - PrefixLength);
  if (Authority = '') or (Pos('@', Authority) > 0) then Exit;
  Result := True;
end;

end.
