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

    AgentProcess.pas

    Sub-task P1.1: lifecycle management of the Claude Code CLI child process
    Sub-task P1.7: BuildEnvironmentBlock - environment block construction

    This unit wraps the full lifecycle of the Agent (Claude Code) CLI child
    process: creating anonymous pipes for stdin/stdout, launching the process
    with CreateProcess, writing to stdin, stopping/terminating the process and
    releasing the handles. The process is started with a dedicated environment
    block (see BuildEnvironmentBlock) so the child can resolve nodejs / claude
    CLI / MinGW through PATH and receive the API key, without polluting the IDE
    process or the system environment. The legacy Delphi 7 build uses an
    ANSI environment block to match its CreateProcess call.
}
unit AgentProcess;

interface

uses
  Windows, Classes, SysUtils;

type
  TAgentProcess = class(TObject)
  private
    fOutputRead: THandle;   // stdout pipe, read end (kept by us)
    fOutputWrite: THandle;  // stdout pipe, write end (given to child)
    fInputRead: THandle;    // stdin pipe, read end (given to child)
    fInputWrite: THandle;   // stdin pipe, write end (kept by us)
    fProcessHandle: THandle;// child process handle
    fJobHandle: THandle;    // kills cmd.exe and its Node child together
    fProcessId: DWORD;      // child process id (used for ctrl events)
    fRunning: Boolean;      // running flag
    fWorkDir: String;       // working directory of the child process
    fCliPath: String;       // path to the claude CLI launcher
    fSystemPromptFile: String; // UTF-8 prompt file kept for child lifetime
    fResumeSessionId: String; // project session to resume, if any
    fLastError: String;     // last error message (for graceful failures)
    function GetIsRunning: Boolean;
    procedure DeleteSystemPromptFile;
    function CreateSystemPromptFile(const Prompt: String): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    // Start the child process with the given working directory.
    // Returns True on success; on failure fLastError is set and fRunning
    // stays False (graceful failure, never raises).
    function Start(const WorkDir: String): Boolean;

    // Stop / terminate the child process and release child-side handles.
    procedure Stop;

    // Release the stdout read handle after the reader thread has exited.
    procedure CloseOutputRead;

    // Stop + Start combination. UI callers should use their own timer when
    // restarting after an unexpected process exit.
    function Restart(const NewWorkDir: String): Boolean;

    // Write a UTF-8 encoded message to the child's stdin, terminated by LF.
    // Returns False and sets LastError if no complete JSONL record was sent.
    function SendMessage(const Text: String): Boolean;
    function SendPermissionResponse(const RequestId, InputJSON: String; Allow: Boolean): Boolean;

    // Send a user message whose content may contain local image resources.
    // Non-image attachments are sent as path references so Claude can read
    // them with its normal file tools instead of copying their contents into
    // the prompt.
    function SendMessageWithAttachments(const Text: String;
      Attachments: TStrings): Boolean;

    // Send an interrupt (Ctrl+C) to the child process group.
    procedure SendInterrupt;

    property IsRunning: Boolean read GetIsRunning;
    property WorkDir: String read fWorkDir;
    property CliPath: String read fCliPath write fCliPath;
    property ResumeSessionId: String read fResumeSessionId write fResumeSessionId;
    property OutputRead: THandle read fOutputRead;
    property InputWrite: THandle read fInputWrite;
    property LastError: String read fLastError;
  end;

// Build an environment block for the Agent child process.
//   - inherits the current process environment
//   - prepends nodejs / claude-cli / MinGW64 dirs to PATH
//   - injects the provider API key environment variables
// Returns a freshly allocated block; caller must FreeMem it after use.
function BuildEnvironmentBlock(const WorkDir: String): PChar;

implementation

uses
  Utils, devCFG, AgentPipeIO, AgentConfig;

type
  TCreateJobObjectFunc = function(lpJobAttributes: Pointer;
    lpName: PChar): THandle; stdcall;
  TAssignProcessToJobObjectFunc = function(hJob, hProcess: THandle): BOOL; stdcall;
  TTerminateJobObjectFunc = function(hJob: THandle; uExitCode: UINT): BOOL; stdcall;

function KernelProc(const Name: PChar): Pointer;
var
  Kernel32: HMODULE;
begin
  Kernel32 := GetModuleHandle('kernel32.dll');
  if Kernel32 = 0 then
    Result := nil
  else
    Result := GetProcAddress(Kernel32, Name);
end;

function CreateAgentJobObject: THandle;
var
  Proc: TCreateJobObjectFunc;
begin
  Proc := TCreateJobObjectFunc(KernelProc('CreateJobObjectA'));
  if Assigned(Proc) then
    Result := Proc(nil, nil)
  else
    Result := 0;
end;

function AssignAgentToJob(JobHandle, ProcessHandle: THandle): Boolean;
var
  Proc: TAssignProcessToJobObjectFunc;
begin
  Proc := TAssignProcessToJobObjectFunc(KernelProc('AssignProcessToJobObject'));
  Result := Assigned(Proc) and Proc(JobHandle, ProcessHandle);
end;

function TerminateAgentJob(JobHandle: THandle): Boolean;
var
  Proc: TTerminateJobObjectFunc;
begin
  Proc := TTerminateJobObjectFunc(KernelProc('TerminateJobObject'));
  Result := Assigned(Proc) and Proc(JobHandle, 0);
end;

function CanonicalPermissionMode(const Value: String): String;
begin
  if SameText(Value, 'acceptEdits') then
    Result := 'acceptEdits'
  else if SameText(Value, 'auto') then
    Result := 'auto'
  else if SameText(Value, 'bypassPermissions') then
    Result := 'bypassPermissions'
  else if SameText(Value, 'dontAsk') then
    Result := 'dontAsk'
  else if SameText(Value, 'plan') then
    Result := 'plan'
  else if SameText(Value, 'manual') or SameText(Value, 'default') then
    // Claude CLI 2.1.211 documents "manual". Treat the legacy "default"
    // value as an alias so old IDE configurations keep their safe behavior.
    Result := 'manual'
  else
    Result := 'manual';
end;

procedure CloseAgentHandle(var Handle: THandle);
begin
  if Handle <> 0 then begin
    CloseHandle(Handle);
    Handle := 0;
  end;
end;

function JsonQuoteUtf8(const Value: String): AnsiString;
var
  Utf8: AnsiString;
  I: Integer;
  B: Byte;
begin
  Utf8 := AnsiToUTF8(Value);
  Result := '"';
  for I := 1 to Length(Utf8) do begin
    B := Byte(Utf8[I]);
    case B of
      8:  Result := Result + '\b';
      9:  Result := Result + '\t';
      10: Result := Result + '\n';
      12: Result := Result + '\f';
      13: Result := Result + '\r';
      34: Result := Result + '\"';
      92: Result := Result + '\\';
    else
      if B < 32 then
        Result := Result + '\u00' + IntToHex(B, 2)
      else
        Result := Result + AnsiChar(B);
    end;
  end;
  Result := Result + '"';
end;

function Base64Encode(const Value: AnsiString): AnsiString;
const
  Alphabet: AnsiString =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
var
  I, N, B0, B1, B2: Integer;
begin
  Result := '';
  I := 1;
  N := Length(Value);
  while I <= N do begin
    B0 := Byte(Value[I]);
    Inc(I);
    if I <= N then begin
      B1 := Byte(Value[I]);
      Inc(I);
    end else
      B1 := -1;
    if I <= N then begin
      B2 := Byte(Value[I]);
      Inc(I);
    end else
      B2 := -1;

    Result := Result + Alphabet[(B0 shr 2) + 1];
    if B1 < 0 then begin
      Result := Result + Alphabet[((B0 and $03) shl 4) + 1] + '==';
    end else begin
      Result := Result + Alphabet[(((B0 and $03) shl 4) or (B1 shr 4)) + 1];
      if B2 < 0 then
        Result := Result + Alphabet[((B1 and $0F) shl 2) + 1] + '='
      else begin
        Result := Result + Alphabet[(((B1 and $0F) shl 2) or (B2 shr 6)) + 1];
        Result := Result + Alphabet[(B2 and $3F) + 1];
      end;
    end;
  end;
end;

function ImageMimeType(const FileName: String): String;
var
  Ext: String;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  if Ext = '.png' then
    Result := 'image/png'
  else if (Ext = '.jpg') or (Ext = '.jpeg') then
    Result := 'image/jpeg'
  else if Ext = '.gif' then
    Result := 'image/gif'
  else if Ext = '.webp' then
    Result := 'image/webp'
  else
    Result := '';
end;

function ReadImageBase64(const FileName: String; var MimeType, Data: String): Boolean;
const
  MaxImageBytes = 12 * 1024 * 1024;
var
  Stream: TFileStream;
  Bytes: AnsiString;
begin
  Result := False;
  MimeType := ImageMimeType(FileName);
  Data := '';
  if (MimeType = '') or not FileExists(FileName) then
    Exit;
  Stream := nil;
  try
    try
      Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
      if (Stream.Size <= 0) or (Stream.Size > MaxImageBytes) then
        Exit;
      SetLength(Bytes, Integer(Stream.Size));
      Stream.ReadBuffer(Bytes[1], Length(Bytes));
      Data := String(Base64Encode(Bytes));
      Result := Data <> '';
    except
      Result := False;
    end;
  finally
    Stream.Free;
  end;
end;

function IsSafeCliPath(const Value: String): Boolean;
begin
  Result := (Value <> '') and (Pos('"', Value) = 0) and
    (Pos(#13, Value) = 0) and (Pos(#10, Value) = 0);
end;

function IsAbsoluteWindowsPath(const Value: String): Boolean;
begin
  Result := (Length(Value) >= 2) and
    (((Value[2] = ':') and ((Value[1] >= 'A') and (Value[1] <= 'Z') or
      (Value[1] >= 'a') and (Value[1] <= 'z'))) or
     ((Value[1] = '\') and (Value[2] = '\')));
end;

function BuildPathOption(const OptionName, Values, WorkDir: String;
  DirectoriesAllowed: Boolean): String;
var
  Paths: TStringList;
  I: Integer;
  Path: String;
begin
  Result := '';
  if Trim(Values) = '' then
    Exit;
  Paths := TStringList.Create;
  try
    ExtractStrings([';'], [], PChar(Values), Paths);
    for I := 0 to Paths.Count - 1 do begin
      Path := Trim(Paths[I]);
      if Path = '' then
        Continue;
      if not IsAbsoluteWindowsPath(Path) and (WorkDir <> '') then
        Path := IncludeTrailingPathDelimiter(WorkDir) + Path;
      Path := ExpandFileName(Path);
      while (Length(Path) > 3) and
            (Path[Length(Path)] in ['\', '/']) do
        Delete(Path, Length(Path), 1);
      if not IsSafeCliPath(Path) then
        Continue;
      if DirectoriesAllowed then begin
        if not DirectoryExists(Path) then
          Continue;
      end else if not FileExists(Path) then
        Continue;
      Result := Result + ' ' + OptionName + ' "' + Path + '"';
    end;
  finally
    Paths.Free;
  end;
end;

function BuildUserContentJson(const Text: String; Attachments: TStrings): AnsiString;
var
  I: Integer;
  Path, MimeType, ImageData: String;
  FirstBlock: Boolean;

  procedure AddBlock(const Block: AnsiString);
  begin
    if not FirstBlock then
      Result := Result + ',';
    Result := Result + Block;
    FirstBlock := False;
  end;

begin
  if (Attachments = nil) or (Attachments.Count = 0) then begin
    Result := JsonQuoteUtf8(Text);
    Exit;
  end;

  Result := '[';
  FirstBlock := True;
  if Trim(Text) <> '' then
    AddBlock('{"type":"text","text":' + JsonQuoteUtf8(Text) + '}')
  else
    AddBlock('{"type":"text","text":"Please process the following attachments."}');

  for I := 0 to Attachments.Count - 1 do begin
    Path := Attachments[I];
    if ReadImageBase64(Path, MimeType, ImageData) then begin
      AddBlock('{"type":"text","text":' +
        JsonQuoteUtf8('[IDE image attachment] ' + Path) + '}');
      AddBlock('{"type":"image","source":{"type":"base64","media_type":' +
        JsonQuoteUtf8(MimeType) + ',"data":' + JsonQuoteUtf8(ImageData) + '}}');
    end else begin
      // The path is intentionally kept as a normal text block. Claude can
      // decide whether to read it with Read/Glob/Bash under its permissions.
      AddBlock('{"type":"text","text":' + JsonQuoteUtf8(
        '[IDE file attachment]' + #13#10 + 'Path: ' + Path + #13#10 +
        'Use Claude file tools to read it.') + '}');
    end;
  end;
  Result := Result + ']';
end;

function FindAgentOnPath(const FileName: String): String;
var
  Paths: TStringList;
  PathValue, Candidate: String;
  I: Integer;
begin
  Result := '';
  PathValue := GetEnvironmentVariable('PATH');
  Paths := TStringList.Create;
  try
    ExtractStrings([';'], [], PChar(PathValue), Paths);
    for I := 0 to Paths.Count - 1 do begin
      if Paths[I] = '' then
        Candidate := FileName
      else
        Candidate := IncludeTrailingPathDelimiter(Paths[I]) + FileName;
      if FileExists(Candidate) then begin
        Result := ExpandFileName(Candidate);
        Exit;
      end;
    end;
  finally
    Paths.Free;
  end;
end;

function ResolveAgentCliPath(const ConfiguredPath: String): String;
var
  BundledPath: String;
begin
  if ConfiguredPath <> '' then begin
    Result := ConfiguredPath;
    Exit;
  end;

  BundledPath := ExtractFilePath(ParamStr(0)) + 'claude-cli\bin\claude.cmd';
  if FileExists(BundledPath) then begin
    Result := BundledPath;
    Exit;
  end;

  // Recent Claude Code packages ship a native Windows launcher instead of a
  // generated .cmd shim. Prefer it before falling back to PATH discovery.
  BundledPath := ExtractFilePath(ParamStr(0)) + 'claude-cli\bin\claude.exe';
  if FileExists(BundledPath) then begin
    Result := BundledPath;
    Exit;
  end;

  // Development machines often install Claude globally. Keep the bundled
  // path as the first choice, but allow a PATH installation as a fallback.
  Result := FindAgentOnPath('claude.cmd');
  if Result = '' then
    Result := FindAgentOnPath('claude.bat');
  if Result = '' then
    Result := FindAgentOnPath('claude.exe');
end;

{ ------------------------------------------------------------------ }
{ Environment block construction (P1.7)                              }
{ ------------------------------------------------------------------ }

// Read all current environment variables into a string list (key=value).
procedure ReadCurrentEnvironment(List: TStringList);
var
  EnvPtr, P: PChar;
  Entry: String;
begin
  EnvPtr := GetEnvironmentStrings;
  if EnvPtr = nil then
    Exit;
  try
    P := EnvPtr;
    while P^ <> #0 do begin
      Entry := String(P);
      // Skip the leading "=::=::\" drive entries that begin with '='
      if (Length(Entry) > 0) and (Entry[1] <> '=') then
        List.Add(Entry);
      Inc(P, StrLen(P) + 1);
    end;
  finally
    FreeEnvironmentStrings(EnvPtr);
  end;
end;

function BuildEnvironmentBlock(const WorkDir: String): PChar;
var
  EnvList: TStringList;
  InstallDir, OldPath, NewPath, CompilerBinDir: String;
  i, Total, Pos: Integer;
  Provider, ApiKey, BaseUrl, Model: String;

  procedure SetVar(const Name, Value: String);
  var
    j, idx: Integer;
    upper: String;
  begin
    idx := -1;
    upper := UpperCase(Name) + '=';
    for j := 0 to EnvList.Count - 1 do
      if SameText(Copy(EnvList[j], 1, Length(upper)), upper) then begin
        idx := j;
        Break;
      end;
    if idx >= 0 then
      EnvList[idx] := Name + '=' + Value
    else
      EnvList.Add(Name + '=' + Value);
  end;

  procedure RemoveVar(const Name: String);
  var
    j: Integer;
    Prefix: String;
  begin
    Prefix := Name + '=';
    for j := EnvList.Count - 1 downto 0 do
      if SameText(Copy(EnvList[j], 1, Length(Prefix)), Prefix) then
        EnvList.Delete(j);
  end;

  function GetVar(const Name: String): String;
  var
    j: Integer;
    prefix: String;
  begin
    Result := '';
    prefix := UpperCase(Name) + '=';
    for j := 0 to EnvList.Count - 1 do
      if SameText(Copy(EnvList[j], 1, Length(prefix)), prefix) then begin
        Result := Copy(EnvList[j], Length(prefix) + 1, MaxInt);
        Break;
      end;
  end;

begin
  EnvList := TStringList.Create;
  try
    ReadCurrentEnvironment(EnvList);

    // Install directory = folder containing devcpp.exe
    InstallDir := ExtractFilePath(ParamStr(0));
    InstallDir := ExcludeTrailingBackslash(InstallDir);

    // Prepend the bundled toolchain folders to PATH
    OldPath := GetVar('PATH');
    CompilerBinDir := InstallDir + '\MinGW64\bin';
    if not DirectoryExists(CompilerBinDir) then
      CompilerBinDir := InstallDir + '\MinGW32\bin';
    NewPath := InstallDir + '\nodejs;' +
               InstallDir + '\claude-cli\bin;' +
               CompilerBinDir;
    if OldPath <> '' then
      NewPath := NewPath + ';' + OldPath;
    SetVar('PATH', NewPath);

    // Inject the API key according to the configured provider.
    if Assigned(devAgentConfig) then begin
      Provider := LowerCase(Trim(devAgentConfig.Provider));
      ApiKey := devAgentConfig.ApiKey;
      BaseUrl := NormalizeAgentBaseUrl(Provider, devAgentConfig.BaseUrl);
      if Provider = 'deepseek' then begin
        Model := NormalizeAgentModel(Provider, devAgentConfig.Model);
        SetVar('ANTHROPIC_MODEL', AgentCliModel(Provider, Model));
        SetVar('ANTHROPIC_DEFAULT_OPUS_MODEL', AgentCliModel(Provider, Model));
        SetVar('ANTHROPIC_DEFAULT_SONNET_MODEL', AgentCliModel(Provider, Model));
        SetVar('ANTHROPIC_DEFAULT_HAIKU_MODEL', Model);
        SetVar('ANTHROPIC_SMALL_FAST_MODEL', Model);
        SetVar('CLAUDE_CODE_SUBAGENT_MODEL', Model);
        if AgentCliModel(Provider, Model) <> Model then
          SetVar('CLAUDE_CODE_AUTO_COMPACT_WINDOW', '786432');
        SetVar('ANTHROPIC_BASE_URL', BaseUrl);
      end;

      if ApiKey <> '' then begin
        // Claude Code authenticates through the Anthropic-compatible channel.
        // Keep OPENAI_API_KEY for compatible gateways, but do not rely on it
        // as the CLI's primary credential.
        if Provider = 'openai' then
          SetVar('OPENAI_API_KEY', ApiKey);
        if Provider = 'anthropic' then
          SetVar('ANTHROPIC_API_KEY', ApiKey)
        else begin
          SetVar('ANTHROPIC_API_KEY', ApiKey);
          SetVar('ANTHROPIC_AUTH_TOKEN', ApiKey);
        end;
        // DeepSeek's documented Claude Code path uses bearer authentication.
        // Do not inherit a competing Anthropic API key from the parent shell.
        if Provider = 'deepseek' then
          RemoveVar('ANTHROPIC_API_KEY');
        if BaseUrl <> '' then
          SetVar('ANTHROPIC_BASE_URL', BaseUrl);
      end;
    end;

    // Serialize the list into the CreateProcess environment block format:
    // key=value#0key=value#0...#0#0
    Total := 0;
    for i := 0 to EnvList.Count - 1 do
      Inc(Total, Length(EnvList[i]) + 1);
    Inc(Total); // final terminating #0

    GetMem(Result, Total * SizeOf(Char));
    Pos := 0;
    for i := 0 to EnvList.Count - 1 do begin
      StrPCopy(Result + Pos, EnvList[i]);
      Inc(Pos, Length(EnvList[i]) + 1);
    end;
    (Result + Pos)^ := #0; // double-null terminate
  finally
    EnvList.Free;
  end;
end;

{ ------------------------------------------------------------------ }
{ TAgentProcess                                                      }
{ ------------------------------------------------------------------ }

constructor TAgentProcess.Create;
begin
  inherited Create;
  fOutputRead := 0;
  fOutputWrite := 0;
  fInputRead := 0;
  fInputWrite := 0;
  fProcessHandle := 0;
  fJobHandle := 0;
  fProcessId := 0;
  fRunning := False;
  fWorkDir := '';
  fCliPath := '';
  fSystemPromptFile := '';
  fResumeSessionId := '';
  fLastError := '';
end;

destructor TAgentProcess.Destroy;
begin
  Stop;
  CloseOutputRead;
  DeleteSystemPromptFile;
  inherited;
end;

procedure TAgentProcess.DeleteSystemPromptFile;
begin
  if fSystemPromptFile = '' then
    Exit;
  try
    if FileExists(fSystemPromptFile) then
      DeleteFile(fSystemPromptFile);
  except
    // A stale prompt file is non-fatal; Windows cleans the temp directory.
  end;
  fSystemPromptFile := '';
end;

function TAgentProcess.CreateSystemPromptFile(const Prompt: String): Boolean;
var
  TempPath: array[0..MAX_PATH] of Char;
  Utf8: AnsiString;
  Stream: TFileStream;
begin
  Result := False;
  DeleteSystemPromptFile;
  if Trim(Prompt) = '' then begin
    Result := True;
    Exit;
  end;
  if GetTempPath(SizeOf(TempPath), TempPath) = 0 then
    Exit;
  fSystemPromptFile := IncludeTrailingPathDelimiter(String(TempPath)) +
    'devcpp-agent-prompt-' + IntToStr(GetCurrentProcessId) + '-' +
    IntToStr(GetTickCount) + '.txt';
  if not IsSafeCliPath(fSystemPromptFile) then begin
    fSystemPromptFile := '';
    Exit;
  end;
  Stream := nil;
  try
    try
      Utf8 := AnsiToUTF8(Prompt);
      Stream := TFileStream.Create(fSystemPromptFile, fmCreate or fmShareExclusive);
      if Length(Utf8) > 0 then
        Stream.WriteBuffer(Utf8[1], Length(Utf8));
      Result := True;
    except
      Result := False;
    end;
  finally
    Stream.Free;
    if not Result then
      DeleteSystemPromptFile;
  end;
end;

function TAgentProcess.Start(const WorkDir: String): Boolean;
var
  sa: TSecurityAttributes;
  si: TStartupInfo;
  pi: TProcessInformation;
  CmdLine, CommandShell, Model, ModelArg, PermissionArg, ResumeArg: String;
  SystemPromptArg: String;
  McpArg, PluginArg: String;
  EnvBlock: PChar;
  WorkDirPtr: PChar;
  JobHandle: THandle;
begin
  Result := False;
  fLastError := '';
  DeleteSystemPromptFile;

  // A previous failed launch may have closed a handle without resetting the
  // field. Normalize all fields before attempting another launch.
  CloseAgentHandle(fOutputWrite);
  CloseAgentHandle(fInputRead);
  CloseAgentHandle(fInputWrite);

  if fRunning then
    Stop;
  CloseOutputRead;

  fWorkDir := WorkDir;

  // The CLI launcher path. Prefer the bundled launcher, then a PATH install.
  if fCliPath = '' then
    fCliPath := ResolveAgentCliPath('');

  if (Pos('"', fCliPath) > 0) or (Pos(#13, fCliPath) > 0) or
     (Pos(#10, fCliPath) > 0) then begin
    fLastError := 'Invalid Agent CLI path.';
    LogError('AgentProcess.pas TAgentProcess.Start', fLastError);
    Exit;
  end;
  if not FileExists(fCliPath) then begin
    if fCliPath = '' then
      fLastError := 'Can''t find Claude CLI. Put claude.cmd or claude.exe beside the IDE or configure its full path.'
    else
      fLastError := Format('Can''t find Agent CLI in: %s', [fCliPath]);
    LogError('AgentProcess.pas TAgentProcess.Start', fLastError);
    Exit;
  end;

  // Security attributes: inheritable handles for the pipes.
  sa.nLength := SizeOf(TSecurityAttributes);
  sa.lpSecurityDescriptor := nil;
  sa.bInheritHandle := True;

  // Create the stdout pipe (child writes, we read).
  if not CreatePipe(fOutputRead, fOutputWrite, @sa, 0) then begin
    fLastError := Format('Create stdout pipe failed: %s', [SysErrorMessage(GetLastError)]);
    LogError('AgentProcess.pas TAgentProcess.Start', fLastError);
    Exit;
  end;
  // Our read end must NOT be inherited by the child.
  if not SetHandleInformation(fOutputRead, HANDLE_FLAG_INHERIT, 0) then begin
    fLastError := Format('Set stdout pipe flag failed: %s', [SysErrorMessage(GetLastError)]);
    LogError('AgentProcess.pas TAgentProcess.Start', fLastError);
    CloseAgentHandle(fOutputRead);
    CloseAgentHandle(fOutputWrite);
    Exit;
  end;

  // Create the stdin pipe (we write, child reads).
  if not CreatePipe(fInputRead, fInputWrite, @sa, 0) then begin
    fLastError := Format('Create stdin pipe failed: %s', [SysErrorMessage(GetLastError)]);
    LogError('AgentProcess.pas TAgentProcess.Start', fLastError);
    CloseAgentHandle(fOutputRead);
    CloseAgentHandle(fOutputWrite);
    Exit;
  end;
  // Our write end must NOT be inherited by the child.
  if not SetHandleInformation(fInputWrite, HANDLE_FLAG_INHERIT, 0) then begin
    fLastError := Format('Set stdin pipe flag failed: %s', [SysErrorMessage(GetLastError)]);
    LogError('AgentProcess.pas TAgentProcess.Start', fLastError);
    CloseAgentHandle(fOutputRead);
    CloseAgentHandle(fOutputWrite);
    CloseAgentHandle(fInputRead);
    CloseAgentHandle(fInputWrite);
    Exit;
  end;

  // Startup info: redirect std handles, hide window.
  FillChar(si, SizeOf(TStartupInfo), 0);
  si.cb := SizeOf(TStartupInfo);
  si.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
  si.hStdInput := fInputRead;
  si.hStdOutput := fOutputWrite;
  si.hStdError := fOutputWrite;
  si.wShowWindow := SW_HIDE;

  ModelArg := '';
  if Assigned(devAgentConfig) then begin
    Model := AgentCliModel(devAgentConfig.Provider, devAgentConfig.Model);
    if (Model <> '') and (Pos('"', Model) = 0) and
       (Pos(#13, Model) = 0) and (Pos(#10, Model) = 0) then
      ModelArg := ' --model "' + Model + '"';
    // Keep external Claude settings from overriding the IDE provider credentials.
    if SameText(devAgentConfig.Provider, 'deepseek') then
      ModelArg := ModelArg + ' --setting-sources ""';
  end;

  ResumeArg := '';
  if (Trim(fResumeSessionId) <> '') and
     (Pos('"', fResumeSessionId) = 0) and
     (Pos(#13, fResumeSessionId) = 0) and
     (Pos(#10, fResumeSessionId) = 0) then
    ResumeArg := ' --resume "' + Trim(fResumeSessionId) + '"';

  PermissionArg := '';
  if Assigned(devAgentConfig) then begin
    PermissionArg := ' --permission-prompt-tool stdio --permission-mode ' +
      CanonicalPermissionMode(devAgentConfig.PermissionMode);
  end;

  McpArg := '';
  PluginArg := '';
  SystemPromptArg := '';
  if Assigned(devAgentConfig) then begin
    McpArg := BuildPathOption('--mcp-config', devAgentConfig.McpConfigFiles,
      WorkDir, False);
    PluginArg := BuildPathOption('--plugin-dir', devAgentConfig.PluginDirs,
      WorkDir, True);
    if Trim(devAgentConfig.SystemPrompt) <> '' then begin
      if not CreateSystemPromptFile(devAgentConfig.SystemPrompt) then begin
        fLastError := 'Could not create the temporary system prompt file.';
        LogError('AgentProcess.pas TAgentProcess.Start', fLastError);
        CloseAgentHandle(fOutputRead);
        CloseAgentHandle(fOutputWrite);
        CloseAgentHandle(fInputRead);
        CloseAgentHandle(fInputWrite);
        Exit;
      end;
      SystemPromptArg := ' --append-system-prompt-file "' +
        fSystemPromptFile + '"';
    end;
  end;

  // CreateProcess cannot execute .cmd/.bat files directly. Route launcher
  // scripts through the user's command shell while keeping the CLI path
  // quoted as a single argument.
  if SameText(ExtractFileExt(fCliPath), '.cmd') or
     SameText(ExtractFileExt(fCliPath), '.bat') then begin
    CommandShell := GetEnvironmentVariable('COMSPEC');
    if CommandShell = '' then
      CommandShell := 'cmd.exe';
    CmdLine := '"' + CommandShell + '" /d /s /c ""' + fCliPath +
      '" --print --input-format stream-json --output-format stream-json --verbose' +
      ' --include-partial-messages --include-hook-events --prompt-suggestions' +
      ModelArg + ResumeArg + PermissionArg + McpArg + PluginArg +
      SystemPromptArg + '"';
  end else
    CmdLine := '"' + fCliPath +
      '" --print --input-format stream-json --output-format stream-json --verbose' +
      ' --include-partial-messages --include-hook-events --prompt-suggestions' +
      ModelArg + ResumeArg + PermissionArg + McpArg + PluginArg +
      SystemPromptArg;

  EnvBlock := nil;
  EnvBlock := BuildEnvironmentBlock(WorkDir);

  if WorkDir <> '' then
    WorkDirPtr := PChar(WorkDir)
  else
    WorkDirPtr := nil;

  // A .cmd launcher creates a second process for Node. A job object lets Stop
  // terminate the complete process tree instead of leaving Node holding the
  // stdout pipe open.
  JobHandle := CreateAgentJobObject;

  try
    // BuildEnvironmentBlock uses the ANSI PChar representation used by this
    // Delphi 7 project, so do not mark it as a Unicode environment block.
    if not CreateProcess(nil, PChar(CmdLine), nil, nil, True,
        CREATE_NEW_PROCESS_GROUP,
        EnvBlock, WorkDirPtr, si, pi) then begin
      fLastError := Format('Create Agent process failed: %s', [SysErrorMessage(GetLastError)]);
      LogError('AgentProcess.pas TAgentProcess.Start', fLastError);
      CloseAgentHandle(fOutputRead);
      CloseAgentHandle(fOutputWrite);
      CloseAgentHandle(fInputRead);
      CloseAgentHandle(fInputWrite);
      DeleteSystemPromptFile;
      if JobHandle <> 0 then
        CloseHandle(JobHandle);
      Exit;
    end;
  finally
    if EnvBlock <> nil then
      FreeMem(EnvBlock);
  end;

  fProcessHandle := pi.hProcess;
  fProcessId := pi.dwProcessId;
  if (JobHandle <> 0) and AssignAgentToJob(JobHandle, fProcessHandle) then
    fJobHandle := JobHandle
  else if JobHandle <> 0 then
    CloseHandle(JobHandle);
  // The thread handle is not needed.
  CloseHandle(pi.hThread);

  // Close the ends used only by the child so that EOF propagates correctly.
  CloseAgentHandle(fOutputWrite);
  CloseAgentHandle(fInputRead);

  fRunning := True;
  Result := True;
end;

procedure TAgentProcess.Stop;
begin
  if not fRunning and (fProcessHandle = 0) and (fJobHandle = 0) then begin
    DeleteSystemPromptFile;
    Exit;
  end;

  fRunning := False;

  if fProcessHandle <> 0 then begin
    if (fJobHandle = 0) or not TerminateAgentJob(fJobHandle) then
      TerminateProcess(fProcessHandle, 0);
    WaitForSingleObject(fProcessHandle, 2000);
    CloseHandle(fProcessHandle);
    fProcessHandle := 0;
  end;
  if fJobHandle <> 0 then begin
    CloseHandle(fJobHandle);
    fJobHandle := 0;
  end;

  if fOutputWrite <> 0 then begin
    CloseHandle(fOutputWrite);
    fOutputWrite := 0;
  end;
  if fInputRead <> 0 then begin
    CloseHandle(fInputRead);
    fInputRead := 0;
  end;
  if fInputWrite <> 0 then begin
    CloseHandle(fInputWrite);
    fInputWrite := 0;
  end;

  fProcessId := 0;
  DeleteSystemPromptFile;
end;

procedure TAgentProcess.CloseOutputRead;
begin
  if fOutputRead <> 0 then begin
    CloseHandle(fOutputRead);
    fOutputRead := 0;
  end;
end;

function TAgentProcess.Restart(const NewWorkDir: String): Boolean;
begin
  Stop;
  CloseOutputRead;
  Result := Start(NewWorkDir);
end;

function TAgentProcess.SendPermissionResponse(const RequestId, InputJSON: String;
  Allow: Boolean): Boolean;
var
  Data, Decision: AnsiString;
  PipeError: String;
begin
  Result := False;
  if not IsRunning or (fInputWrite = 0) or (RequestId = '') then Exit;
  if Allow then begin
    Decision := '{"behavior":"allow"';
    if InputJSON <> '' then Decision := Decision + ',"updatedInput":' + InputJSON;
    Decision := Decision + '}';
  end else Decision := '{"behavior":"deny","message":"The user denied this tool operation."}';
  Data := '{"type":"control_response","response":{"subtype":"success","request_id":' +
    JsonQuoteUtf8(RequestId) + ',"response":' + Decision + '}}' + #10;
  Result := WriteAgentPipeData(fInputWrite, Data, PipeError);
  if not Result then fLastError := 'Could not send permission decision: ' + PipeError;
end;
function TAgentProcess.SendMessage(const Text: String): Boolean;
begin
  Result := SendMessageWithAttachments(Text, nil);
end;

function TAgentProcess.SendMessageWithAttachments(const Text: String;
  Attachments: TStrings): Boolean;
var
  Data: AnsiString;
  PipeError: String;
begin
  Result := False;
  fLastError := '';
  if not fRunning or (fInputWrite = 0) then begin
    fLastError := 'The AI process is not ready to receive messages.';
    Exit;
  end;
  if (Text = '') and ((Attachments = nil) or (Attachments.Count = 0)) then begin
    fLastError := 'Cannot send an empty AI message.';
    Exit;
  end;
  // Claude Code's headless streaming mode consumes JSONL user messages. With
  // attachments the content is an Anthropic-compatible content block array.
  Data := '{"type":"user","message":{"role":"user","content":' +
    BuildUserContentJson(Text, Attachments) + '}}' + #10;
  if not WriteAgentPipeData(fInputWrite, Data, PipeError) then begin
    fLastError := 'Could not send the AI message: ' + PipeError;
    LogError('AgentProcess.pas TAgentProcess.SendMessageWithAttachments',
      fLastError);
    Stop;
    Exit;
  end;
  Result := True;
end;

procedure TAgentProcess.SendInterrupt;
begin
  if not fRunning or (fProcessId = 0) then
    Exit;
  // Send Ctrl+C to the child's process group (it was created with
  // CREATE_NEW_PROCESS_GROUP, so the event is delivered to the child only).
  if not GenerateConsoleCtrlEvent(CTRL_C_EVENT, fProcessId) then begin
    // A GUI parent may not have a console attached. Ensure Stop still has a
    // deterministic fallback instead of leaving a stuck child process.
    Stop;
  end;
end;

function TAgentProcess.GetIsRunning: Boolean;
var
  ExitCode: DWORD;
begin
  Result := False;
  if not fRunning or (fProcessHandle = 0) then
    Exit;
  if GetExitCodeProcess(fProcessHandle, ExitCode) then
    Result := (ExitCode = STILL_ACTIVE);
end;

end.
