program AgentPipeIOSmoke;

{$APPTYPE CONSOLE}

uses
  Windows, SysUtils, AgentPipeIO;

procedure Require(Condition: Boolean; const Message: String);
begin
  if not Condition then
    raise Exception.Create('AgentPipeIO smoke test failed: ' + Message);
end;

function ReadBytes(Handle: THandle; Count: Integer): AnsiString;
var
  BytesRead: DWORD;
begin
  SetLength(Result, Count);
  BytesRead := 0;
  Require(ReadFile(Handle, Result[1], Count, BytesRead, nil),
    'pipe read failed');
  Require(Integer(BytesRead) = Count, 'pipe read returned an unexpected size');
end;

var
  ReadPipe, WritePipe: THandle;
  Data, Received: AnsiString;
  ErrorMessage: String;
begin
  ReadPipe := 0;
  WritePipe := 0;
  try
    Writeln('AgentPipeIO smoke test: invalid handle');
    Require(not WriteAgentPipeData(0, 'message', ErrorMessage),
      'invalid handle was accepted');
    Require(ErrorMessage <> '', 'invalid handle did not return an error');

    Writeln('AgentPipeIO smoke test: complete write');
    Require(CreatePipe(ReadPipe, WritePipe, nil, 65536),
      'CreatePipe failed');
    Data := '{"type":"user","message":"hello"}'#10;
    Require(WriteAgentPipeData(WritePipe, Data, ErrorMessage),
      'valid pipe write failed: ' + ErrorMessage);
    Received := ReadBytes(ReadPipe, Length(Data));
    Require(Received = Data, 'pipe payload mismatch');
    CloseHandle(ReadPipe);
    ReadPipe := 0;
    CloseHandle(WritePipe);
    WritePipe := 0;

    Writeln('AgentPipeIO smoke test: broken pipe');
    Require(CreatePipe(ReadPipe, WritePipe, nil, 65536),
      'second CreatePipe failed');
    CloseHandle(ReadPipe);
    ReadPipe := 0;
    Require(not WriteAgentPipeData(WritePipe, 'message', ErrorMessage),
      'broken pipe was accepted');
    Require(ErrorMessage <> '', 'broken pipe did not return an error');
    Writeln('AgentPipeIO smoke test passed.');
  finally
    if WritePipe <> 0 then
      CloseHandle(WritePipe);
    if ReadPipe <> 0 then
      CloseHandle(ReadPipe);
  end;
end.
