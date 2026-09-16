{
    This file is part of Red Panda Dev-C++ (AI Agent Integration)

    Red Panda Dev-C++ is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    Red Panda Dev-C++ is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    AgentReader.pas

    Sub-task P1.2: background reader thread.

    A TThread descendant that continuously reads the Agent child process'
    stdout pipe, splits the byte stream on LF (#10) into complete lines and
    delivers each line to the main thread via Synchronize. The CLI uses
    stream-json output, one JSON object per line, so line-splitting is the
    natural framing. Carriage returns (#13) are stripped. The accumulated
    bytes remain UTF-8 until the JSON parser decodes string values.
}
unit AgentReader;

interface

uses
  Windows, Classes, SysUtils;

type
  // Callback fired (on the main thread) whenever a complete line is ready.
  TAgentLineEvent = procedure(const Line: String) of object;

  // Callback fired (on the main thread) when the pipe closes / process exits.
  TAgentExitEvent = procedure of object;

  TAgentReader = class(TThread)
  private
    fPipeRead: THandle;            // stdout read end, from TAgentProcess
    fLineBuffer: AnsiString;       // bytes accumulated for the current line
    fCurrentLine: String;          // UTF-8 line passed to the sync callback
    fOnLineReady: TAgentLineEvent; // line-ready event
    fOnProcessExit: TAgentExitEvent; // process-exit event
    procedure DoLineReady;         // Synchronize target for a ready line
    procedure DoProcessExit;       // Synchronize target for process exit
  protected
    procedure Execute; override;
  public
    constructor Create(PipeHandle: THandle; AOnLineReady: TAgentLineEvent;
      AOnProcessExit: TAgentExitEvent);
    property OnLineReady: TAgentLineEvent read fOnLineReady write fOnLineReady;
    property OnProcessExit: TAgentExitEvent read fOnProcessExit write fOnProcessExit;
  end;

implementation

constructor TAgentReader.Create(PipeHandle: THandle;
  AOnLineReady: TAgentLineEvent; AOnProcessExit: TAgentExitEvent);
begin
  // Bind callbacks before resuming so fast CLI output cannot be lost between
  // construction and the caller assigning event properties.
  inherited Create(True);
  fPipeRead := PipeHandle;
  fLineBuffer := '';
  fCurrentLine := '';
  fOnLineReady := AOnLineReady;
  fOnProcessExit := AOnProcessExit;
  FreeOnTerminate := False;
  Resume;
end;

procedure TAgentReader.DoLineReady;
begin
  if Assigned(fOnLineReady) then
    fOnLineReady(fCurrentLine);
end;

procedure TAgentReader.DoProcessExit;
begin
  if Assigned(fOnProcessExit) then
    fOnProcessExit;
end;

procedure TAgentReader.Execute;
var
  Buffer: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
  i: Integer;
  c: AnsiChar;
begin
  while not Terminated do begin
    BytesRead := 0;
    // ReadFile blocks until data is available, the pipe is closed, or error.
    if not ReadFile(fPipeRead, Buffer[0], SizeOf(Buffer), BytesRead, nil)
       or (BytesRead = 0) then
      Break; // pipe closed (process exited) or read error

    if Terminated then
      Break;

    i := 0;
    while i < Integer(BytesRead) do begin
      c := Buffer[i];
      if c = #10 then begin
        // Complete line: preserve UTF-8 for the JSON parser and hand it to the main thread.
        fCurrentLine := String(fLineBuffer);
        Synchronize(DoLineReady);
        fLineBuffer := '';
      end else if c <> #13 then
        fLineBuffer := fLineBuffer + c;
      Inc(i);
    end;
  end;

  // Flush any trailing partial line (no LF before EOF).
  if (fLineBuffer <> '') and not Terminated then begin
    fCurrentLine := String(fLineBuffer);
    Synchronize(DoLineReady);
    fLineBuffer := '';
  end;

  // Notify that the process / pipe is gone (used by fault-tolerance later).
  if not Terminated then
    Synchronize(DoProcessExit);
end;

end.
