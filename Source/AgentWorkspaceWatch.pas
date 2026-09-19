unit AgentWorkspaceWatch;

interface

uses Windows, SysUtils, Classes, SyncObjs;

type
  TAgentWorkspaceWatcher = class(TThread)
  private
    fRoot: String;
    fDirectoryHandle: THandle;
    fStopEvent: THandle;
    fChangeEvent: THandle;
    fReadyEvent: THandle;
    fPaths: TStringList;
    fFirstActions: TStringList;
    fLastActions: TStringList;
    fLock: TCriticalSection;
    fAvailable: Boolean;
    fOverflow: Boolean;
    procedure AddChange(const Path: String; Action: DWORD);
    procedure ReadChanges(Buffer: Pointer; BytesRead: DWORD);
    function GetAvailable: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const Root: String);
    destructor Destroy; override;
    function Finish(Dest: TStrings; States: TStrings = nil): Boolean;
    property Available: Boolean read GetAvailable;
    property Overflow: Boolean read fOverflow;
  end;

implementation

const
  AGENT_FILE_LIST_DIRECTORY = $0001;
  AGENT_FILE_NOTIFY_CHANGE_FILE_NAME = $00000001;
  AGENT_FILE_NOTIFY_CHANGE_DIR_NAME = $00000002;
  AGENT_FILE_NOTIFY_CHANGE_SIZE = $00000008;
  AGENT_FILE_NOTIFY_CHANGE_LAST_WRITE = $00000010;
  AGENT_FILE_NOTIFY_CHANGE_CREATION = $00000040;
  AGENT_FILE_ACTION_ADDED = 1;
  AGENT_FILE_ACTION_REMOVED = 2;
  AGENT_FILE_ACTION_MODIFIED = 3;
  AGENT_FILE_ACTION_RENAMED_OLD_NAME = 4;
  AGENT_FILE_ACTION_RENAMED_NEW_NAME = 5;
  AGENT_NOTIFY_BUFFER_SIZE = 65536;
  AGENT_INVALID_FILE_ATTRIBUTES: DWORD = $FFFFFFFF;

type
  PAgentFileNotifyInformation = ^TAgentFileNotifyInformation;
  TAgentFileNotifyInformation = packed record
    NextEntryOffset: DWORD;
    Action: DWORD;
    FileNameLength: DWORD;
    FileName: array[0..0] of WideChar;
  end;

function CreateFileW(lpFileName: PWideChar; dwDesiredAccess: DWORD;
  dwShareMode: DWORD; lpSecurityAttributes: Pointer; dwCreationDisposition,
  dwFlagsAndAttributes: DWORD; hTemplateFile: THandle): THandle; stdcall;
  external 'kernel32.dll' name 'CreateFileW';

function ReadDirectoryChangesW(hDirectory: THandle; lpBuffer: Pointer;
  nBufferLength: DWORD; bWatchSubtree: BOOL; dwNotifyFilter: DWORD;
  lpBytesReturned: LPDWORD; lpOverlapped: POverlapped;
  lpCompletionRoutine: Pointer): BOOL; stdcall;
  external 'kernel32.dll' name 'ReadDirectoryChangesW';

function IsGitMetadataPath(const Path: String): Boolean;
var
  Normalized: String;
begin
  Normalized := '\' + StringReplace(Path, '/', '\', [rfReplaceAll]) + '\';
  Result := Pos('\.git\', LowerCase(Normalized)) > 0;
end;

constructor TAgentWorkspaceWatcher.Create(const Root: String);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  fRoot := IncludeTrailingPathDelimiter(ExpandFileName(Root));
  fDirectoryHandle := INVALID_HANDLE_VALUE;
  fStopEvent := CreateEvent(nil, True, False, nil);
  fChangeEvent := CreateEvent(nil, True, False, nil);
  fReadyEvent := CreateEvent(nil, True, False, nil);
  fPaths := TStringList.Create;
  fFirstActions := TStringList.Create;
  fLastActions := TStringList.Create;
  fLock := TCriticalSection.Create;
  fAvailable := False;
  fOverflow := False;
  Resume;
  if fReadyEvent <> 0 then
    WaitForSingleObject(fReadyEvent, 500);
end;

destructor TAgentWorkspaceWatcher.Destroy;
begin
  if fStopEvent <> 0 then SetEvent(fStopEvent);
  WaitFor;
  if fDirectoryHandle <> INVALID_HANDLE_VALUE then
    CloseHandle(fDirectoryHandle);
  if fStopEvent <> 0 then CloseHandle(fStopEvent);
  if fChangeEvent <> 0 then CloseHandle(fChangeEvent);
  if fReadyEvent <> 0 then CloseHandle(fReadyEvent);
  fLock.Free;
  fLastActions.Free;
  fFirstActions.Free;
  fPaths.Free;
  inherited Destroy;
end;

procedure TAgentWorkspaceWatcher.AddChange(const Path: String; Action: DWORD);
var
  I: Integer;
begin
  if (Path = '') or IsGitMetadataPath(Path) then Exit;
  fLock.Acquire;
  try
    for I := 0 to fPaths.Count - 1 do
      if SameText(fPaths[I], Path) then begin
        fLastActions[I] := IntToStr(Action);
        Exit;
      end;
    fPaths.Add(Path);
    fFirstActions.Add(IntToStr(Action));
    fLastActions.Add(IntToStr(Action));
  finally
    fLock.Release;
  end;
end;

procedure TAgentWorkspaceWatcher.ReadChanges(Buffer: Pointer; BytesRead: DWORD);
var
  Info: PAgentFileNotifyInformation;
  RelativePath, FullPath: String;
  WidePath: WideString;
begin
  if BytesRead = 0 then Exit;
  Info := PAgentFileNotifyInformation(Buffer);
  repeat
    if Info^.FileNameLength > 0 then begin
      SetLength(WidePath, Info^.FileNameLength div SizeOf(WideChar));
      Move(Info^.FileName[0], WidePath[1], Info^.FileNameLength);
      RelativePath := String(WidePath);
      FullPath := fRoot + RelativePath;
      AddChange(FullPath, Info^.Action);
    end;
    if Info^.NextEntryOffset = 0 then Break;
    Info := PAgentFileNotifyInformation(PAnsiChar(Info) + Info^.NextEntryOffset);
  until False;
end;

function TAgentWorkspaceWatcher.GetAvailable: Boolean;
begin
  if fReadyEvent <> 0 then WaitForSingleObject(fReadyEvent, 1000);
  Result := fAvailable;
end;

procedure TAgentWorkspaceWatcher.Execute;
var
  Buffer: array[0..AGENT_NOTIFY_BUFFER_SIZE - 1] of Byte;
  Overlapped: TOverlapped;
  WaitHandles: array[0..1] of THandle;
  WaitResult, BytesRead, NotifyFilter: DWORD;
  RootWide: WideString;
  ReadPending: Boolean;
begin
  RootWide := WideString(ExcludeTrailingPathDelimiter(fRoot));
  fDirectoryHandle := CreateFileW(PWideChar(RootWide),
    AGENT_FILE_LIST_DIRECTORY, FILE_SHARE_READ or FILE_SHARE_WRITE or
    FILE_SHARE_DELETE, nil, OPEN_EXISTING,
    FILE_FLAG_BACKUP_SEMANTICS or FILE_FLAG_OVERLAPPED, 0);
  if (fDirectoryHandle = INVALID_HANDLE_VALUE) or (fStopEvent = 0) or
     (fChangeEvent = 0) or (fReadyEvent = 0) then begin
    if fReadyEvent <> 0 then SetEvent(fReadyEvent);
    Exit;
  end;

  NotifyFilter := AGENT_FILE_NOTIFY_CHANGE_FILE_NAME or
    AGENT_FILE_NOTIFY_CHANGE_DIR_NAME or AGENT_FILE_NOTIFY_CHANGE_SIZE or
    AGENT_FILE_NOTIFY_CHANGE_LAST_WRITE or AGENT_FILE_NOTIFY_CHANGE_CREATION;
  WaitHandles[0] := fStopEvent;
  WaitHandles[1] := fChangeEvent;
  while not Terminated do begin
    FillChar(Overlapped, SizeOf(Overlapped), 0);
    ResetEvent(fChangeEvent);
    Overlapped.hEvent := fChangeEvent;
    ReadPending := ReadDirectoryChangesW(fDirectoryHandle, @Buffer[0],
      SizeOf(Buffer), True, NotifyFilter, nil, @Overlapped, nil);
    if not ReadPending and (GetLastError <> ERROR_IO_PENDING) then begin
      SetEvent(fReadyEvent);
      Exit;
    end;
    fAvailable := True;
    SetEvent(fReadyEvent);
    WaitResult := WaitForMultipleObjects(2, @WaitHandles[0], False, INFINITE);
    if WaitResult = WAIT_OBJECT_0 then begin
      CancelIo(fDirectoryHandle);
      BytesRead := 0;
      if GetOverlappedResult(fDirectoryHandle, Overlapped, BytesRead, True) and
         (BytesRead > 0) then
        ReadChanges(@Buffer[0], BytesRead);
      Break;
    end;
    if WaitResult = WAIT_OBJECT_0 + 1 then begin
      BytesRead := 0;
      if GetOverlappedResult(fDirectoryHandle, Overlapped, BytesRead, False) then begin
        if BytesRead = 0 then
          fOverflow := True
        else
          ReadChanges(@Buffer[0], BytesRead);
      end
      else if GetLastError = ERROR_NOTIFY_ENUM_DIR then
        fOverflow := True;
    end else
      Break;
  end;
end;

function TAgentWorkspaceWatcher.Finish(Dest: TStrings;
  States: TStrings): Boolean;
var
  I, FirstAction, LastAction: Integer;
  Attributes: DWORD;
  Path, State: String;
begin
  if fStopEvent <> 0 then SetEvent(fStopEvent);
  WaitFor;
  Result := fAvailable;
  if Dest = nil then Exit;
  fLock.Acquire;
  try
    for I := 0 to fPaths.Count - 1 do begin
      Path := fPaths[I];
      Attributes := GetFileAttributes(PChar(Path));
      FirstAction := StrToIntDef(fFirstActions[I], 0);
      LastAction := StrToIntDef(fLastActions[I], 0);
      if Attributes <> AGENT_INVALID_FILE_ATTRIBUTES then begin
        if (Attributes and FILE_ATTRIBUTE_DIRECTORY) = 0 then begin
          if FirstAction = AGENT_FILE_ACTION_ADDED then
            State := 'Added'
          else if (FirstAction in [AGENT_FILE_ACTION_RENAMED_OLD_NAME,
              AGENT_FILE_ACTION_RENAMED_NEW_NAME]) or
              (LastAction in [AGENT_FILE_ACTION_RENAMED_OLD_NAME,
              AGENT_FILE_ACTION_RENAMED_NEW_NAME]) then
            State := 'Renamed'
          else
            State := 'Modified';
          Dest.Add(Path);
          if States <> nil then States.Add(State);
        end;
      end else if not ((FirstAction = AGENT_FILE_ACTION_ADDED) and
        (LastAction = AGENT_FILE_ACTION_REMOVED)) then begin
        if (FirstAction = AGENT_FILE_ACTION_RENAMED_OLD_NAME) or
           (LastAction = AGENT_FILE_ACTION_RENAMED_OLD_NAME) then
          State := 'Renamed'
        else
          State := 'Deleted';
        Dest.Add(Path);
        if States <> nil then States.Add(State);
      end;
    end;
  finally
    fLock.Release;
  end;
end;

end.
