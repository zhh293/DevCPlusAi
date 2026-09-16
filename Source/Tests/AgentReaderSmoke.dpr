program AgentReaderSmoke;

{$APPTYPE CONSOLE}

uses
  Windows, Classes, SysUtils, AgentReader;

type
  TCollector = class
  public
    Lines: TStringList;
    ExitNotified: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure LineReady(const Line: String);
    procedure ProcessExit;
  end;

constructor TCollector.Create;
begin
  inherited Create;
  Lines := TStringList.Create;
  ExitNotified := False;
end;

destructor TCollector.Destroy;
begin
  Lines.Free;
  inherited Destroy;
end;

procedure TCollector.LineReady(const Line: String);
begin
  Lines.Add(Line);
end;

procedure TCollector.ProcessExit;
begin
  ExitNotified := True;
end;

procedure Require(Condition: Boolean; const Message: String);
begin
  if not Condition then
    raise Exception.Create('AgentReader smoke test failed: ' + Message);
end;

procedure WriteAll(Handle: THandle; const Data: AnsiString);
var
  Offset, Remaining: Integer;
  Written: DWORD;
begin
  Offset := 0;
  Remaining := Length(Data);
  while Remaining > 0 do begin
    Written := 0;
    if not WriteFile(Handle, (PAnsiChar(Data) + Offset)^, Remaining,
        Written, nil) then
      raise Exception.Create('Pipe write failed: ' +
        SysErrorMessage(GetLastError));
    Require(Written > 0, 'pipe write made no progress');
    Inc(Offset, Written);
    Dec(Remaining, Written);
  end;
end;

function WideToAnsi(const Value: WideString): String;
var
  Count: Integer;
begin
  Result := '';
  if Value = '' then
    Exit;
  Count := WideCharToMultiByte(CP_ACP, 0, PWideChar(Value), Length(Value),
    nil, 0, nil, nil);
  Require(Count > 0, 'could not convert expected Unicode text');
  SetLength(Result, Count);
  WideCharToMultiByte(CP_ACP, 0, PWideChar(Value), Length(Value),
    PAnsiChar(Result), Count, nil, nil);
end;

var
  ReadPipe, WritePipe: THandle;
  Reader: TAgentReader;
  Collector: TCollector;
  Rows: AnsiString;
  ExpectedWide: WideString;
  ExpectedAnsi: String;
  I: Integer;
begin
  ReadPipe := 0;
  WritePipe := 0;
  Reader := nil;
  Collector := TCollector.Create;
  try
    Require(CreatePipe(ReadPipe, WritePipe, nil, 65536),
      'CreatePipe failed');
    Reader := TAgentReader.Create(ReadPipe, Collector.LineReady,
      Collector.ProcessExit);

    Writeln('AgentReader smoke test: fragmented line');
    WriteAll(WritePipe, 'first');
    WriteAll(WritePipe, '-line'#13#10);

    Writeln('AgentReader smoke test: UTF-8 line');
    SetLength(ExpectedWide, 2);
    ExpectedWide[1] := WideChar($4F60);
    ExpectedWide[2] := WideChar($597D);
    ExpectedAnsi := UTF8Encode(ExpectedWide);
    WriteAll(WritePipe, #$E4#$BD#$A0#$E5#$A5#$BD#10);

    Writeln('AgentReader smoke test: 1000 lines');
    Rows := '';
    for I := 0 to 999 do
      Rows := Rows + 'row-' + AnsiString(IntToStr(I)) + #10;
    WriteAll(WritePipe, Rows);

    Writeln('AgentReader smoke test: trailing line without LF');
    WriteAll(WritePipe, 'tail');
    CloseHandle(WritePipe);
    WritePipe := 0;

    Reader.WaitFor;

    Require(Collector.Lines.Count = 1003, 'unexpected line count');
    Require(Collector.Lines[0] = 'first-line', 'fragmented line mismatch');
    Require(Collector.Lines[1] = ExpectedAnsi, 'UTF-8 line mismatch');
    Require(Collector.Lines[2] = 'row-0', 'first bulk line mismatch');
    Require(Collector.Lines[1001] = 'row-999', 'last bulk line mismatch');
    Require(Collector.Lines[1002] = 'tail', 'trailing line mismatch');
    Require(Collector.ExitNotified, 'exit callback was not delivered');
    Writeln('AgentReader smoke test passed.');
  finally
    Reader.Free;
    if WritePipe <> 0 then
      CloseHandle(WritePipe);
    if ReadPipe <> 0 then
      CloseHandle(ReadPipe);
    Collector.Free;
  end;
end.
