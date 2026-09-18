unit AgentFileUndo;

interface

uses Windows, SysUtils, Classes;

type
  TAgentFileUndoEntry = class
  public
    Token, Path, WorkDir: String;
    TurnId: Integer;
    BeforeExists, AfterExists, Pending, Completed, CanUndo: Boolean;
    BeforeAttributes: DWORD;
    BeforeBytes, AfterBytes: TMemoryStream;
    destructor Destroy; override;
  end;

  TAgentFileUndoManager = class
  private
    fEntries: TList;
    fTurnId, fNextToken: Integer;
    fMemoryBytes: Int64;
    function FindToken(const Token: String): Integer;
    function IsSafePath(const Path, WorkDir: String): Boolean;
    function ReadSnapshot(const Path: String; out Exists: Boolean;
      out Attributes: DWORD; out Data: TMemoryStream;
      out ErrorCode: String): Boolean;
    function WriteSnapshot(const Path: String; Attributes: DWORD;
      Data: TMemoryStream): Boolean;
    procedure ReleaseBuffers(Entry: TAgentFileUndoEntry);
    procedure RemoveEntry(Index: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    procedure BeginTurn;
    procedure Clear;
    function BeginChange(const Path, WorkDir: String; out Token,
      ErrorCode: String): Boolean;
    procedure CancelChange(const Token: String);
    function CompleteChange(const Token: String; out CanUndo: Boolean;
      out ErrorCode: String): Boolean;
    function UndoChange(const Token: String; out ErrorCode: String;
      out Stale: Boolean): Boolean;
    function GetPath(const Token: String): String;
  end;

implementation

const
  AGENT_UNDO_MAX_FILE_BYTES = 2 * 1024 * 1024;
  AGENT_UNDO_MAX_MEMORY_BYTES = 32 * 1024 * 1024;
  AGENT_UNDO_MAX_ENTRIES = 64;
  AGENT_FILE_ATTRIBUTE_REPARSE_POINT = $00000400;
  AGENT_MOVEFILE_REPLACE_EXISTING = $00000001;
  AGENT_MOVEFILE_WRITE_THROUGH = $00000008;

function SameStreamData(Left, Right: TMemoryStream): Boolean;
begin
  Result := False;
  if (Left = nil) or (Right = nil) then Exit;
  if Left.Size <> Right.Size then Exit;
  Result := (Left.Size = 0) or
    CompareMem(Left.Memory, Right.Memory, Left.Size);
end;

destructor TAgentFileUndoEntry.Destroy;
begin
  AfterBytes.Free;
  BeforeBytes.Free;
  inherited Destroy;
end;

constructor TAgentFileUndoManager.Create;
begin
  inherited Create;
  fEntries := TList.Create;
  fTurnId := 1;
  fNextToken := 0;
  fMemoryBytes := 0;
end;

destructor TAgentFileUndoManager.Destroy;
begin
  Clear;
  fEntries.Free;
  inherited Destroy;
end;

procedure TAgentFileUndoManager.ReleaseBuffers(Entry: TAgentFileUndoEntry);
begin
  if Entry = nil then Exit;
  if Entry.BeforeBytes <> nil then begin
    Dec(fMemoryBytes, Entry.BeforeBytes.Size);
    Entry.BeforeBytes.Free;
    Entry.BeforeBytes := nil;
  end;
  if Entry.AfterBytes <> nil then begin
    Dec(fMemoryBytes, Entry.AfterBytes.Size);
    Entry.AfterBytes.Free;
    Entry.AfterBytes := nil;
  end;
  if fMemoryBytes < 0 then fMemoryBytes := 0;
end;

procedure TAgentFileUndoManager.RemoveEntry(Index: Integer);
var Entry: TAgentFileUndoEntry;
begin
  if (Index < 0) or (Index >= fEntries.Count) then Exit;
  Entry := TAgentFileUndoEntry(fEntries[Index]);
  fEntries.Delete(Index);
  Entry.Free;
end;

procedure TAgentFileUndoManager.Clear;
var I: Integer;
begin
  if fEntries = nil then Exit;
  for I := fEntries.Count - 1 downto 0 do
    RemoveEntry(I);
  fMemoryBytes := 0;
  Inc(fTurnId);
end;

procedure TAgentFileUndoManager.BeginTurn;
begin
  Inc(fTurnId);
  if fTurnId <= 0 then fTurnId := 1;
end;

function TAgentFileUndoManager.FindToken(const Token: String): Integer;
var I: Integer;
begin
  Result := -1;
  if Token = '' then Exit;
  for I := 0 to fEntries.Count - 1 do
    if TAgentFileUndoEntry(fEntries[I]).Token = Token then begin
      Result := I;
      Exit;
    end;
end;

function TAgentFileUndoManager.IsSafePath(const Path, WorkDir: String): Boolean;
var Target, Root, Prefix, Dir, Parent: String; Attributes: DWORD;
begin
  Result := False;
  if (Trim(Path) = '') or (Trim(WorkDir) = '') then Exit;
  Target := ExpandFileName(Path);
  Root := ExcludeTrailingPathDelimiter(ExpandFileName(WorkDir));
  if SameText(Target, Root) then Exit;
  Prefix := IncludeTrailingPathDelimiter(Root);
  if CompareText(Copy(Target, 1, Length(Prefix)), Prefix) <> 0 then Exit;

  Attributes := GetFileAttributes(PChar(Target));
  if Attributes <> DWORD(-1) then begin
    if (Attributes and (FILE_ATTRIBUTE_DIRECTORY or
        AGENT_FILE_ATTRIBUTE_REPARSE_POINT)) <> 0 then Exit;
  end else if not (GetLastError in [ERROR_FILE_NOT_FOUND,
      ERROR_PATH_NOT_FOUND]) then Exit;

  Dir := ExcludeTrailingPathDelimiter(ExtractFileDir(Target));
  while Dir <> '' do begin
    Attributes := GetFileAttributes(PChar(Dir));
    if (Attributes = DWORD(-1)) or
       ((Attributes and (FILE_ATTRIBUTE_DIRECTORY or
         AGENT_FILE_ATTRIBUTE_REPARSE_POINT)) <> FILE_ATTRIBUTE_DIRECTORY) then
      Exit;
    if SameText(Dir, Root) then begin
      Result := True;
      Exit;
    end;
    Parent := ExcludeTrailingPathDelimiter(ExtractFileDir(Dir));
    if (Parent = '') or SameText(Parent, Dir) then Exit;
    Dir := Parent;
  end;
end;

function TAgentFileUndoManager.ReadSnapshot(const Path: String;
  out Exists: Boolean; out Attributes: DWORD; out Data: TMemoryStream;
  out ErrorCode: String): Boolean;
var Stream: TFileStream; LastError: DWORD;
begin
  Result := False;
  Exists := False;
  Attributes := DWORD(-1);
  Data := TMemoryStream.Create;
  ErrorCode := '';
  Attributes := GetFileAttributes(PChar(Path));
  if Attributes = DWORD(-1) then begin
    LastError := GetLastError;
    if LastError in [ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND] then begin
      Result := True;
      Exit;
    end;
    ErrorCode := 'unavailable';
    Data.Free;
    Data := nil;
    Exit;
  end;
  if (Attributes and (FILE_ATTRIBUTE_DIRECTORY or
      AGENT_FILE_ATTRIBUTE_REPARSE_POINT)) <> 0 then begin
    ErrorCode := 'unsafe_target';
    Data.Free;
    Data := nil;
    Exit;
  end;
  Stream := nil;
  try
    try
      Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
      if Stream.Size > AGENT_UNDO_MAX_FILE_BYTES then begin
        ErrorCode := 'too_large';
        Exit;
      end;
      Data.CopyFrom(Stream, 0);
      Data.Position := 0;
      Exists := True;
      Result := True;
    except
      on E: Exception do begin
        ErrorCode := 'unavailable';
        Result := False;
      end;
    end;
  finally
    Stream.Free;
    if not Result then begin
      Data.Free;
      Data := nil;
    end;
  end;
end;

function TAgentFileUndoManager.BeginChange(const Path, WorkDir: String;
  out Token, ErrorCode: String): Boolean;
var I: Integer; Entry: TAgentFileUndoEntry; Exists: Boolean;
  Attributes: DWORD; Data: TMemoryStream; Target: String;
begin
  Result := False;
  Token := '';
  ErrorCode := '';
  Target := ExpandFileName(Path);
  if not IsSafePath(Target, WorkDir) then begin
    ErrorCode := 'unsafe_target';
    Exit;
  end;
  for I := fEntries.Count - 1 downto 0 do begin
    Entry := TAgentFileUndoEntry(fEntries[I]);
    if (Entry.TurnId = fTurnId) and SameText(Entry.Path, Target) and
       (Entry.BeforeBytes <> nil) then begin
      Entry.Pending := True;
      Token := Entry.Token;
      Result := True;
      Exit;
    end;
  end;
  if fEntries.Count >= AGENT_UNDO_MAX_ENTRIES then begin
    ErrorCode := 'limit';
    Exit;
  end;
  Data := nil;
  if not ReadSnapshot(Target, Exists, Attributes, Data, ErrorCode) then Exit;
  if (Data <> nil) and
     (fMemoryBytes + Data.Size > AGENT_UNDO_MAX_MEMORY_BYTES) then begin
    Data.Free;
    ErrorCode := 'limit';
    Exit;
  end;
  Entry := TAgentFileUndoEntry.Create;
  Entry.Path := Target;
  Entry.WorkDir := ExpandFileName(WorkDir);
  Entry.TurnId := fTurnId;
  Entry.BeforeExists := Exists;
  Entry.BeforeAttributes := Attributes;
  Entry.BeforeBytes := Data;
  Entry.Pending := True;
  Inc(fNextToken);
  if fNextToken <= 0 then fNextToken := 1;
  Entry.Token := 'undo-' + IntToStr(fNextToken);
  Inc(fMemoryBytes, Data.Size);
  fEntries.Add(Entry);
  Token := Entry.Token;
  Result := True;
end;

procedure TAgentFileUndoManager.CancelChange(const Token: String);
var Index: Integer; Entry: TAgentFileUndoEntry;
begin
  Index := FindToken(Token);
  if Index < 0 then Exit;
  Entry := TAgentFileUndoEntry(fEntries[Index]);
  Entry.Pending := False;
  if not Entry.Completed then
    RemoveEntry(Index);
end;

function TAgentFileUndoManager.CompleteChange(const Token: String;
  out CanUndo: Boolean; out ErrorCode: String): Boolean;
var Index: Integer; Entry: TAgentFileUndoEntry; Exists: Boolean;
  Attributes: DWORD; Data: TMemoryStream; OldAfterSize: Int64;
  Changed: Boolean;
begin
  Result := False;
  CanUndo := False;
  ErrorCode := '';
  Index := FindToken(Token);
  if Index < 0 then begin
    ErrorCode := 'unavailable';
    Exit;
  end;
  Entry := TAgentFileUndoEntry(fEntries[Index]);
  Data := nil;
  if not IsSafePath(Entry.Path, Entry.WorkDir) or
     not ReadSnapshot(Entry.Path, Exists, Attributes, Data, ErrorCode) then begin
    if ErrorCode = '' then ErrorCode := 'unsafe_target';
    Entry.Pending := False;
    Entry.CanUndo := False;
    Exit;
  end;
  OldAfterSize := 0;
  if Entry.AfterBytes <> nil then OldAfterSize := Entry.AfterBytes.Size;
  if fMemoryBytes - OldAfterSize + Data.Size >
     AGENT_UNDO_MAX_MEMORY_BYTES then begin
    Data.Free;
    ErrorCode := 'limit';
    Entry.Pending := False;
    Entry.CanUndo := False;
    ReleaseBuffers(Entry);
    RemoveEntry(Index);
    Result := True;
    Exit;
  end;
  Changed := (Exists <> Entry.BeforeExists);
  if not Changed and Exists then
    Changed := not SameStreamData(Data, Entry.BeforeBytes);
  if Entry.AfterBytes <> nil then begin
    Dec(fMemoryBytes, Entry.AfterBytes.Size);
    Entry.AfterBytes.Free;
  end;
  Entry.AfterBytes := Data;
  Inc(fMemoryBytes, Data.Size);
  Entry.AfterExists := Exists;
  Entry.Pending := False;
  Entry.Completed := True;
  Entry.CanUndo := Changed;
  CanUndo := Entry.CanUndo;
  if not Entry.CanUndo then begin
    ReleaseBuffers(Entry);
    RemoveEntry(Index);
  end;
  Result := True;
end;

function TAgentFileUndoManager.WriteSnapshot(const Path: String;
  Attributes: DWORD; Data: TMemoryStream): Boolean;
var TempFile, Directory: String; TempName: array[0..MAX_PATH] of Char;
  Stream: TFileStream; SavedAttributes: DWORD;
begin
  Result := False;
  Directory := IncludeTrailingPathDelimiter(ExtractFileDir(Path));
  TempName[0] := #0;
  if GetTempFileName(PChar(Directory), 'dca', 0, TempName) = 0 then Exit;
  TempFile := String(TempName);
  Stream := nil;
  try
    try
      Stream := TFileStream.Create(TempFile, fmOpenWrite or fmShareExclusive);
      Data.Position := 0;
      Stream.CopyFrom(Data, 0);
      Stream.Free;
      Stream := nil;
      if not MoveFileEx(PChar(TempFile), PChar(Path),
        AGENT_MOVEFILE_REPLACE_EXISTING or AGENT_MOVEFILE_WRITE_THROUGH) then
        Exit;
      SavedAttributes := Attributes and not FILE_ATTRIBUTE_DIRECTORY;
      if SavedAttributes <> DWORD(-1) then
        SetFileAttributes(PChar(Path), SavedAttributes);
      Result := True;
    except
      Result := False;
    end;
  finally
    Stream.Free;
    if FileExists(TempFile) then DeleteFile(PChar(TempFile));
  end;
end;

function TAgentFileUndoManager.UndoChange(const Token: String;
  out ErrorCode: String; out Stale: Boolean): Boolean;
var Index: Integer; Entry: TAgentFileUndoEntry; Exists: Boolean;
  Attributes: DWORD; Current: TMemoryStream;
begin
  Result := False;
  Stale := False;
  ErrorCode := '';
  Index := FindToken(Token);
  if Index < 0 then begin
    ErrorCode := 'unavailable';
    Exit;
  end;
  Entry := TAgentFileUndoEntry(fEntries[Index]);
  if not Entry.CanUndo or not Entry.Completed then begin
    ErrorCode := 'unavailable';
    Exit;
  end;
  if not IsSafePath(Entry.Path, Entry.WorkDir) then begin
    ErrorCode := 'stale';
    Stale := True;
    Entry.CanUndo := False;
    Exit;
  end;
  Current := nil;
  if not ReadSnapshot(Entry.Path, Exists, Attributes, Current, ErrorCode) then
    Exit;
  if Exists <> Entry.AfterExists then begin
    ErrorCode := 'stale';
    Stale := True;
  end else if Exists and not SameStreamData(Current, Entry.AfterBytes) then begin
    ErrorCode := 'stale';
    Stale := True;
  end;
  Current.Free;
  if Stale then begin
    Entry.CanUndo := False;
    Exit;
  end;

  if Entry.BeforeExists then begin
    if not WriteSnapshot(Entry.Path, Entry.BeforeAttributes,
      Entry.BeforeBytes) then begin
      ErrorCode := 'restore_failed';
      Exit;
    end;
  end else if Exists and not DeleteFile(PChar(Entry.Path)) then begin
    ErrorCode := 'restore_failed';
    Exit;
  end;
  Entry.CanUndo := False;
  Entry.Pending := False;
  ReleaseBuffers(Entry);
  Result := True;
end;

function TAgentFileUndoManager.GetPath(const Token: String): String;
var Index: Integer;
begin
  Result := '';
  Index := FindToken(Token);
  if Index >= 0 then
    Result := TAgentFileUndoEntry(fEntries[Index]).Path;
end;

end.
