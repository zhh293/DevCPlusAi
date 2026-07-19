unit AgentPipeIO;

interface

uses
  Windows, SysUtils;

// Writes the complete byte string to a synchronous Windows handle. A partial
// write is retried until every byte has been accepted. On failure, callers get
// a human-readable error and must treat the JSONL record as unsent.
function WriteAgentPipeData(Handle: THandle; const Data: AnsiString;
  var ErrorMessage: String): Boolean;

implementation

function WriteAgentPipeData(Handle: THandle; const Data: AnsiString;
  var ErrorMessage: String): Boolean;
var
  BytesWritten, Offset, Remaining, ErrorCode: DWORD;
begin
  Result := False;
  ErrorMessage := '';
  if Handle = 0 then begin
    ErrorMessage := 'The input pipe handle is not available.';
    Exit;
  end;

  Offset := 1;
  Remaining := Length(Data);
  while Remaining > 0 do begin
    if not WriteFile(Handle, Data[Offset], Remaining, BytesWritten, nil) then begin
      ErrorCode := GetLastError;
      ErrorMessage := SysErrorMessage(ErrorCode);
      Exit;
    end;
    if BytesWritten = 0 then begin
      ErrorMessage := 'The input pipe accepted no data.';
      Exit;
    end;
    Inc(Offset, BytesWritten);
    Dec(Remaining, BytesWritten);
  end;
  Result := True;
end;

end.
