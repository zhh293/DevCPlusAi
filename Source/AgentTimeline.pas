unit AgentTimeline;
interface
uses Windows, Messages, SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls,
  Graphics, ComCtrls, IniFiles, AgentUITheme;
type
  TAgentOpenFile = procedure(Sender: TObject; const FileName: String) of object;

  TAgentTimeline = class(TScrollBox)
  private
    fBlocks: TList;
    fLastText: TRichEdit;
    fLastIsMarkdown: Boolean;
    fWheelRemainder: Integer;
    fPalette: TAgentUiPalette;
    fGeneration: Integer;
    fRevision: Integer;
    fClearing, fLayoutActive: Boolean;
    fOnOpenFile: TAgentOpenFile;
    procedure TimelineMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ToggleBlock(Sender: TObject);
    procedure OpenChangedFile(Sender: TObject);
    procedure LayoutBlocks;
    procedure RenderMarkdown(Edit: TRichEdit; const RawText: String);
    procedure ApplyBlockAppearance(Block: TControl; const FontName: String;
      FontSize: Integer);
    function NewTextBlock: TRichEdit;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ScrollWheel(Delta: Integer);
    procedure Clear;
    procedure SaveToFile(const Path: String);
    procedure LoadFromFile(const Path: String);
    function FocusedEdit: TCustomEdit;
    function BlockCount: Integer;
    function BlockAt(Index: Integer): TControl;
    function WebBlock(Index: Integer): String;
    property Generation: Integer read fGeneration;
    property Revision: Integer read fRevision;
    property LastText: TRichEdit read fLastText;
    procedure AppendText(const Text: String; TextColor: TColor; Bold: Boolean);
    procedure AppendMarkdown(const Text: String; TextColor: TColor);
    procedure AppendMessage(const Text: String; TextColor: TColor; IsUser: Boolean;
      const ContextSummary: String = ''; const ContextPayload: String = '');
    procedure AddTool(const Id, Caption, Details: String;
      const Status: String = ''; IsResult: Boolean = False);
    procedure AddFileChange(const State, FileName, DiffText, DiffSummary: String;
      CanOpen: Boolean; const UndoToken: String = '';
      CanUndo: Boolean = False);
    procedure SetFileChangeUndoState(const UndoToken, State: String);
    procedure AddPermission(const Id, Caption, InputJSON, WorkDir: String);
    procedure UpdatePermission(const Id, Status, Details: String;
      const InputJSON: String = '');
    procedure ApplyAppearance(AEditorColor, ATextColor: TColor;
      const FontName: String; FontSize: Integer);
    property OnOpenFile: TAgentOpenFile read fOnOpenFile write fOnOpenFile;
  end;
implementation
uses AgentWebProtocol;
type
  TWheelControl = class(TControl);
  TTimelineRichEdit = class(TRichEdit)
  public
    RawText: String;
    IsUserMessage: Boolean;
    ContextSummary, ContextPayload: String;
  protected
    procedure WndProc(var Message: TMessage); override;
  end;
  TTimelineMemo = class(TMemo)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;
  TTimelineButton = class(TPanel)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;
  TTimelineNativeButton = class(TButton)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;
  TTimelineTool = class(TPanel)
  public
    ToolId: String;
    InputText, OutputText, State: String;
    IsFileChange, CanOpenFile: Boolean;
    FilePath, FileState, DiffSummary, UndoToken, UndoState: String;
    CanUndoFile: Boolean;
    PermissionRequestId, PermissionWorkDir: String;
    Header: TTimelineButton;
    Body: TMemo;
    OpenButton: TButton;
  end;
function ForwardWheel(Control: TControl; var Message: TMessage): Boolean;
var ParentControl: TControl; Info: TScrollInfo; Delta: Integer; AtEdge: Boolean;
begin
  Result := Message.Msg = WM_MOUSEWHEEL;
  if not Result then Exit;
  Delta := SmallInt(Message.WParam shr 16);
  { Expanded tool output has its own scrollbar. Let the memo consume the
    wheel while it can move, then continue scrolling the conversation when
    the memo is already at the corresponding edge. }
  if Control is TTimelineMemo then begin
    FillChar(Info, SizeOf(Info), 0);
    Info.cbSize := SizeOf(Info);
    Info.fMask := SIF_RANGE or SIF_PAGE or SIF_POS;
    if GetScrollInfo(TTimelineMemo(Control).Handle, SB_VERT, Info) then begin
      if Delta < 0 then
        AtEdge := Info.nPos >= Info.nMax - Integer(Info.nPage) + 1
      else
        AtEdge := Info.nPos <= Info.nMin;
      if not AtEdge then begin
        Result := False;
        Exit;
      end;
    end;
  end;
  ParentControl := Control.Parent;
  while (ParentControl <> nil) and not (ParentControl is TAgentTimeline) do
    ParentControl := ParentControl.Parent;
  Result := ParentControl <> nil;
  if Result then begin
    TAgentTimeline(ParentControl).ScrollWheel(Delta);
    Message.Result := 1;
  end;
end;
procedure TTimelineRichEdit.WndProc(var Message: TMessage);
begin
  if not ForwardWheel(Self, Message) then inherited WndProc(Message);
end;
procedure TTimelineMemo.WndProc(var Message: TMessage);
begin
  if not ForwardWheel(Self, Message) then inherited WndProc(Message);
end;
procedure TTimelineButton.WndProc(var Message: TMessage);
begin
  if not ForwardWheel(Self, Message) then inherited WndProc(Message);
end;
procedure TTimelineNativeButton.WndProc(var Message: TMessage);
begin
  if not ForwardWheel(Self, Message) then inherited WndProc(Message);
end;

constructor TAgentTimeline.Create(AOwner: TComponent);
begin
  inherited;
  fBlocks := TList.Create;
  fLastIsMarkdown := False;
  fWheelRemainder := 0;
  AgentBuildPalette(clWindow, clWindowText, fPalette);
  BorderStyle := bsNone;
  AutoScroll := True;
  HorzScrollBar.Visible := False;
  VertScrollBar.Tracking := True;
  OnMouseWheel := TimelineMouseWheel;
end;

procedure TAgentTimeline.ApplyBlockAppearance(Block: TControl;
  const FontName: String; FontSize: Integer);
var R: TTimelineRichEdit; Tool: TTimelineTool;
begin
  if Block is TTimelineRichEdit then begin
    R := TTimelineRichEdit(Block);
    R.Font.Name := FontName;
    R.Font.Size := FontSize;
    R.Font.Color := fPalette.Text;
    R.Color := fPalette.Panel;
    if R.IsUserMessage then begin
      if AgentUiIsDark(fPalette.Panel) then
        R.Color := RGB(48, 51, 56)
      else
        R.Color := RGB(237, 242, 248);
    end;
  end else if Block is TTimelineTool then begin
    Tool := TTimelineTool(Block);
    Tool.Color := fPalette.Panel;
    Tool.Font.Name := FontName;
    Tool.Font.Size := FontSize;
    Tool.Font.Color := fPalette.Text;
    if Assigned(Tool.Header) then begin
      Tool.Header.ParentColor := False;
      Tool.Header.Color := fPalette.Elevated;
      Tool.Header.Font.Name := FontName;
      Tool.Header.Font.Size := FontSize;
      Tool.Header.Font.Color := fPalette.Text;
    end;
    if Assigned(Tool.Body) then begin
      Tool.Body.ParentColor := False;
      Tool.Body.Color := fPalette.Panel;
      Tool.Body.Font.Name := FontName;
      Tool.Body.Font.Size := FontSize;
      Tool.Body.Font.Color := fPalette.Text;
    end;
  end;
end;

procedure TAgentTimeline.ApplyAppearance(AEditorColor, ATextColor: TColor;
  const FontName: String; FontSize: Integer);
var I: Integer;
begin
  Color := AEditorColor;
  Font.Name := FontName;
  Font.Size := FontSize;
  Font.Color := ATextColor;
  AgentBuildPalette(AEditorColor, ATextColor, fPalette);
  for I := 0 to fBlocks.Count - 1 do
    ApplyBlockAppearance(TControl(fBlocks[I]), FontName, FontSize);
end;
procedure TAgentTimeline.ScrollWheel(Delta: Integer);
var Steps, Distance: Integer; Lines: UINT;
begin
  Inc(fWheelRemainder, Delta);
  Steps := fWheelRemainder div WHEEL_DELTA;
  fWheelRemainder := fWheelRemainder mod WHEEL_DELTA;
  if Steps = 0 then Exit;
  Lines := 3;
  SystemParametersInfo(SPI_GETWHEELSCROLLLINES, 0, @Lines, 0);
  if Lines = UINT(-1) then Distance := ClientHeight
  else Distance := Integer(Lines) * (Abs(Font.Height) + 6);
  VertScrollBar.Position := VertScrollBar.Position - Steps * Distance;
end;

procedure TAgentTimeline.TimelineMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  ScrollWheel(WheelDelta);
  Handled := True;
end;
destructor TAgentTimeline.Destroy;
begin
  Clear;
  FreeAndNil(fBlocks);
  inherited;
end;
function TAgentTimeline.BlockCount: Integer;
begin Result := fBlocks.Count; end;
function TAgentTimeline.BlockAt(Index: Integer): TControl;
begin Result := TControl(fBlocks[Index]); end;

function TAgentTimeline.WebBlock(Index: Integer): String;
var Block: TObject; Kind, Text, Name, InputText, OutputText, State,
  RequestId, WorkDir, FilePath, FileState, DiffSummary, ContextSummary,
  ContextPayload, UndoToken, UndoState: String;
  CanOpen, CanUndo: Boolean; R: TTimelineRichEdit;
begin
  Block := TObject(fBlocks[Index]);
  Kind := 'system'; Text := ''; Name := '';
  InputText := ''; OutputText := ''; State := ''; RequestId := ''; WorkDir := '';
  FilePath := ''; FileState := ''; DiffSummary := ''; ContextSummary := '';
  ContextPayload := '';
  UndoToken := ''; UndoState := ''; CanOpen := False; CanUndo := False;
  if Block is TTimelineTool then begin
    Kind := 'tool'; Name := TTimelineTool(Block).Header.Hint;
    Text := TTimelineTool(Block).Body.Text;
    InputText := TTimelineTool(Block).InputText;
    OutputText := TTimelineTool(Block).OutputText;
    State := TTimelineTool(Block).State;
    RequestId := TTimelineTool(Block).PermissionRequestId;
    WorkDir := TTimelineTool(Block).PermissionWorkDir;
    if TTimelineTool(Block).IsFileChange then begin
      Kind := 'file-change';
      FilePath := TTimelineTool(Block).FilePath;
      FileState := TTimelineTool(Block).FileState;
      DiffSummary := TTimelineTool(Block).DiffSummary;
      CanOpen := TTimelineTool(Block).CanOpenFile;
      UndoToken := TTimelineTool(Block).UndoToken;
      UndoState := TTimelineTool(Block).UndoState;
      CanUndo := TTimelineTool(Block).CanUndoFile;
    end;
  end else if Block is TTimelineRichEdit then begin
    R := TTimelineRichEdit(Block); Text := R.Text;
    ContextSummary := R.ContextSummary;
    ContextPayload := R.ContextPayload;
    if R.IsUserMessage then Kind := 'user'
    else if R.RawText <> '' then begin Kind := 'assistant'; Text := R.RawText; end;
  end;
  Result := '{"version":1,"type":"upsert","item":{"id":' +
    WebQuote(IntToStr(fGeneration) + '-' + IntToStr(Index)) +
    ',"kind":' + WebQuote(Kind) + ',"text":' + WebQuote(Text) +
    ',"name":' + WebQuote(Name) + ',"status":' + WebQuote(State) +
    ',"input":' + WebQuote(InputText) + ',"output":' + WebQuote(OutputText) +
    ',"requestId":' + WebQuote(RequestId) +
    ',"workDir":' + WebQuote(WorkDir) +
    ',"path":' + WebQuote(FilePath) +
    ',"fileState":' + WebQuote(FileState) +
    ',"diffSummary":' + WebQuote(DiffSummary) +
    ',"contextSummary":' + WebQuote(ContextSummary) +
    ',"contextPayload":' + WebQuote(ContextPayload) +
    ',"undoToken":' + WebQuote(UndoToken) +
    ',"undoState":' + WebQuote(UndoState) +
    ',"canUndo":' + LowerCase(BoolToStr(CanUndo, True)) +
    ',"canOpen":' + LowerCase(BoolToStr(CanOpen, True)) + '}}';
end;

function TAgentTimeline.FocusedEdit: TCustomEdit;
var I: Integer; Block: TObject;
begin
  Result := nil;
  for I := 0 to fBlocks.Count - 1 do begin
    Block := TObject(fBlocks[I]);
    if (Block is TRichEdit) and TRichEdit(Block).Focused then Result := TRichEdit(Block);
    if (Block is TTimelineTool) and TTimelineTool(Block).Body.Focused then Result := TTimelineTool(Block).Body;
  end;
end;

procedure TAgentTimeline.SaveToFile(const Path: String);
var Ini: TMemIniFile; I, OldCount: Integer; Section: String; Block: TObject;
    Lines: TStringList; Stream: TFileStream;
begin
  Ini := TMemIniFile.Create(Path);
  try
    OldCount := Ini.ReadInteger('timeline', 'count', 0);
    for I := 0 to OldCount - 1 do
      DeleteFile(Path + '.' + IntToStr(I) + '.context');
    Ini.Clear;
    Ini.WriteInteger('timeline', 'version', 5);
    Ini.WriteInteger('timeline', 'count', fBlocks.Count);
    for I := 0 to fBlocks.Count - 1 do begin
      Section := IntToStr(I);
      Block := TObject(fBlocks[I]);
      if (Block is TTimelineTool) and TTimelineTool(Block).IsFileChange then begin
        Ini.WriteString(Section, 'kind', 'file-change');
        Ini.WriteString(Section, 'state', TTimelineTool(Block).FileState);
        Ini.WriteString(Section, 'file', TTimelineTool(Block).FilePath);
        Ini.WriteString(Section, 'summary', TTimelineTool(Block).DiffSummary);
        Ini.WriteBool(Section, 'canOpen', TTimelineTool(Block).CanOpenFile);
        TTimelineTool(Block).Body.Lines.SaveToFile(Path + '.' + Section);
      end else if Block is TTimelineTool then begin
        Ini.WriteString(Section, 'kind', 'tool');
        Ini.WriteString(Section, 'id', TTimelineTool(Block).ToolId);
        Ini.WriteString(Section, 'title', TTimelineTool(Block).Header.Hint);
        TTimelineTool(Block).Body.Lines.SaveToFile(Path + '.' + Section);
        Ini.WriteString(Section, 'status', TTimelineTool(Block).State);
        Lines := TStringList.Create;
        try
          Lines.Text := TTimelineTool(Block).InputText;
          Lines.SaveToFile(Path + '.' + Section + '.input');
          Lines.Text := TTimelineTool(Block).OutputText;
          Lines.SaveToFile(Path + '.' + Section + '.output');
        finally Lines.Free; end;
      end else begin
        Ini.WriteString(Section, 'kind', 'text');
        if (Block is TTimelineRichEdit) and TTimelineRichEdit(Block).IsUserMessage then
          Ini.WriteString(Section, 'role', 'user')
        else
          Ini.WriteString(Section, 'role', 'assistant');
        if (Block is TTimelineRichEdit) and
           (TTimelineRichEdit(Block).ContextSummary <> '') then
          Ini.WriteString(Section, 'contextSummary',
            TTimelineRichEdit(Block).ContextSummary);
        if (Block is TTimelineRichEdit) and
           (TTimelineRichEdit(Block).ContextPayload <> '') then begin
          Ini.WriteBool(Section, 'hasContextPayload', True);
          Stream := TFileStream.Create(Path + '.' + Section + '.context', fmCreate);
          try
            Stream.WriteBuffer(PChar(TTimelineRichEdit(Block).ContextPayload)^,
              Length(TTimelineRichEdit(Block).ContextPayload));
          finally
            Stream.Free;
          end;
        end;
        if (Block is TTimelineRichEdit) and (TTimelineRichEdit(Block).RawText <> '') then begin
          Ini.WriteString(Section, 'markdown', '1');
          Lines := TStringList.Create;
          try
            Lines.Text := TTimelineRichEdit(Block).RawText;
            Lines.SaveToFile(Path + '.' + Section);
          finally
            Lines.Free;
          end;
        end else begin
          TRichEdit(Block).PlainText := True;
          TRichEdit(Block).Lines.SaveToFile(Path + '.' + Section);
        end;
      end;
    end;
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

procedure TAgentTimeline.LoadFromFile(const Path: String);
var Ini: TMemIniFile; Lines: TStringList; I, Size: Integer; Section: String;
    ContextPayload: String; Stream: TFileStream;
begin
  Clear;
  Ini := TMemIniFile.Create(Path);
  Lines := TStringList.Create;
  try
    for I := 0 to Ini.ReadInteger('timeline', 'count', 0) - 1 do begin
      Section := IntToStr(I);
      Lines.Clear;
      if FileExists(Path + '.' + Section) then Lines.LoadFromFile(Path + '.' + Section);
      ContextPayload := '';
      if Ini.ReadBool(Section, 'hasContextPayload', False) and
         FileExists(Path + '.' + Section + '.context') then begin
        Stream := TFileStream.Create(Path + '.' + Section + '.context',
          fmOpenRead or fmShareDenyNone);
        try
          if (Stream.Size > 0) and (Stream.Size <= 1048576) then begin
            Size := Integer(Stream.Size);
            SetLength(ContextPayload, Size);
            Stream.ReadBuffer(PChar(ContextPayload)^, Size);
          end;
        finally
          Stream.Free;
        end;
      end;
      if Ini.ReadString(Section, 'kind', '') = 'file-change' then begin
        AddFileChange(Ini.ReadString(Section, 'state', 'Modified'),
          Ini.ReadString(Section, 'file', ''), Lines.Text,
          Ini.ReadString(Section, 'summary', ''),
          Ini.ReadBool(Section, 'canOpen', False));
      end else if Ini.ReadString(Section, 'kind', '') = 'tool' then begin
        AddTool(Ini.ReadString(Section, 'id', ''), Ini.ReadString(Section, 'title', ''), Lines.Text,
          Ini.ReadString(Section, 'status', ''));
        if SameText(TTimelineTool(fBlocks[fBlocks.Count - 1]).State, 'approval') then
          TTimelineTool(fBlocks[fBlocks.Count - 1]).State := 'interrupted';
        if FileExists(Path + '.' + Section + '.input') then begin
          Lines.LoadFromFile(Path + '.' + Section + '.input');
          TTimelineTool(fBlocks[fBlocks.Count - 1]).InputText := Lines.Text;
        end;
        if FileExists(Path + '.' + Section + '.output') then begin
          Lines.LoadFromFile(Path + '.' + Section + '.output');
          TTimelineTool(fBlocks[fBlocks.Count - 1]).OutputText := Lines.Text;
        end;
      end
      else if SameText(Ini.ReadString(Section, 'markdown', ''), '1') then
        AppendMarkdown(Lines.Text, Font.Color)
      else if SameText(Ini.ReadString(Section, 'role', ''), 'user') then
        AppendMessage(Lines.Text, Font.Color, True,
          Ini.ReadString(Section, 'contextSummary', ''), ContextPayload)
      else AppendText(Lines.Text, Font.Color, False);
    end;
  finally
    Lines.Free;
    Ini.Free;
  end;
end;
procedure TAgentTimeline.Clear;
var Block: TObject;
begin
  if fBlocks = nil then Exit;
  fClearing := True;
  DisableAlign;
  try
    while fBlocks.Count > 0 do begin
      Block := TObject(fBlocks[fBlocks.Count - 1]);
      fBlocks.Delete(fBlocks.Count - 1);
      Block.Free;
    end;
  finally
    EnableAlign;
    fClearing := False;
  end;
  Inc(fGeneration);
  Inc(fRevision);
  fLastText := nil;
  fLastIsMarkdown := False;
end;
procedure TAgentTimeline.Resize;
begin
  inherited;
  if fBlocks <> nil then LayoutBlocks;
end;

procedure HighlightCppLine(Edit: TRichEdit; Start, LineLength: Integer); forward;

procedure TAgentTimeline.LayoutBlocks;
var I, Y, OldPosition, BottomPosition: Integer; Block: TControl;
    KeepAtBottom: Boolean;
begin
  if fClearing or fLayoutActive or (fBlocks = nil) or
    (csDestroying in ComponentState) then Exit;
  fLayoutActive := True;
  try
  Inc(fRevision);
  // TScrollBox moves its child controls when the scrollbar position changes.
  // Do not subtract Position here, otherwise every wheel event moves the
  // content twice and the scrollbar range collapses back to zero.
  OldPosition := VertScrollBar.Position;
  BottomPosition := VertScrollBar.Range - ClientHeight;
  if BottomPosition < 0 then BottomPosition := 0;
  KeepAtBottom := OldPosition >= BottomPosition - 4;
  Y := 12;
  DisableAlign;
  try
    for I := 0 to fBlocks.Count - 1 do begin
      Block := TControl(fBlocks[I]);
      if (Block is TTimelineRichEdit) and TTimelineRichEdit(Block).IsUserMessage then
        Block.SetBounds(ClientWidth - 12 - ((ClientWidth - 24) * 3 div 4), Y,
          (ClientWidth - 24) * 3 div 4, Block.Height)
      else
        Block.SetBounds(12, Y, ClientWidth - 24, Block.Height);
      if Block is TRichEdit then
        Block.Height := (SendMessage(TRichEdit(Block).Handle, EM_GETLINECOUNT, 0, 0) + 1) * (Abs(Font.Height) + 6);
      Inc(Y, Block.Height + 12);
    end;
  finally
    EnableAlign;
  end;
  BottomPosition := VertScrollBar.Range - ClientHeight;
  if BottomPosition < 0 then BottomPosition := 0;
  if KeepAtBottom then
    VertScrollBar.Position := BottomPosition
  else if OldPosition > BottomPosition then
    VertScrollBar.Position := BottomPosition
  else
    VertScrollBar.Position := OldPosition;
  finally fLayoutActive := False; end;
end;

procedure TAgentTimeline.RenderMarkdown(Edit: TRichEdit; const RawText: String);
var I, J, Start, LineLength, BaseSize, Level: Integer;
    InCode: Boolean; Line, Token, Normalized: String;
    SavedStart, SavedLength: Integer; RawLines, DisplayLines, Kinds,
    InlineSpans, SpanParts: TStringList;
    CleanLine, SpanInfo: String; InlineStart, SpanEnd, BoldStart, P: Integer;
    InInline, InBold: Boolean;
  function IsTableSeparator(const Value: String): Boolean;
  var S: String; I: Integer;
  begin
    S := Trim(Value);
    Result := Pos('|', S) > 0;
    if not Result then Exit;
    Result := Pos('-', S) > 0;
    if not Result then Exit;
    for I := Length(S) downto 1 do
      if S[I] in ['|', '-', ':', ' ', #9] then Delete(S, I, 1);
    Result := S = '';
  end;
  function TableCellText(const Value: String): String;
  var S: String; Cells: TStringList; I: Integer;
  begin
    S := Trim(Value);
    if (S <> '') and (S[1] = '|') then Delete(S, 1, 1);
    if (S <> '') and (S[Length(S)] = '|') then Delete(S, Length(S), 1);
    Cells := TStringList.Create;
    try
      ExtractStrings(['|'], [], PChar(S), Cells);
      Result := '';
      for I := 0 to Cells.Count - 1 do begin
        if I > 0 then Result := Result + '   ';
        Result := Result + Trim(Cells[I]);
      end;
    finally
      Cells.Free;
    end;
  end;
begin
  if Edit = nil then Exit;
  SavedStart := Edit.SelStart;
  SavedLength := Edit.SelLength;
  Normalized := StringReplace(RawText, #13#10, #10, [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #13, #10, [rfReplaceAll]);
  Normalized := StringReplace(Normalized, #10, #13#10, [rfReplaceAll]);
  RawLines := TStringList.Create;
  DisplayLines := TStringList.Create;
  Kinds := TStringList.Create;
  InlineSpans := TStringList.Create;
  SpanParts := TStringList.Create;
  try
    RawLines.Text := Normalized;
    InCode := False;
    for I := 0 to RawLines.Count - 1 do begin
      Line := RawLines[I];
      Token := TrimLeft(Line);
      if (Length(Token) >= 3) and (Copy(Token, 1, 3) = '```') then begin
        InCode := not InCode;
        Continue;
      end;
      if InCode then
        Kinds.Add('code')
      else
        Kinds.Add('text');
      if (not InCode) and IsTableSeparator(Line) then begin
        Kinds[Kinds.Count - 1] := 'table-separator';
        Line := '';
      end;
      if (not InCode) and (Pos('|', Line) > 0) and
        (Pos('|', Copy(Line, Pos('|', Line) + 1, MaxInt)) > 0) then begin
        Line := TableCellText(Line);
        if (I + 1 < RawLines.Count) and IsTableSeparator(RawLines[I + 1]) then begin
          Kinds[Kinds.Count - 1] := 'tablehead';
        end else
          Kinds[Kinds.Count - 1] := 'table';
      end;
      if (not InCode) and (Length(Token) > 1) and (Token[1] = '#') then begin
        J := 1;
        while (J < Length(Token)) and (Token[J] = '#') do Inc(J);
        if (J <= 4) and (J <= Length(Token)) and (Token[J] = ' ') then begin
          Line := Copy(Token, J + 1, MaxInt);
          Kinds[Kinds.Count - 1] := 'heading' + IntToStr(J);
        end;
      end else if (not InCode) and (Length(Token) >= 2) and
        ((Copy(Token, 1, 2) = '- ') or (Copy(Token, 1, 2) = '* ')) then
        Line := StringOfChar(' ', Length(Line) - Length(Token)) + #183 + ' ' +
          Copy(Token, 3, MaxInt)
      else if (not InCode) and (Length(Token) >= 2) and (Copy(Token, 1, 2) = '> ') then
        Line := StringOfChar(' ', Length(Line) - Length(Token)) + '| ' +
          Copy(Token, 3, MaxInt);
      if (not InCode) and ((Trim(Line) = '---') or (Trim(Line) = '***')) then begin
        Line := StringOfChar('-', 32);
        Kinds[Kinds.Count - 1] := 'divider';
      end;
      CleanLine := '';
      SpanInfo := '';
    InlineStart := -1;
    InInline := False;
    BoldStart := -1;
    InBold := False;
      J := 1;
      while J <= Length(Line) do begin
        if (not InCode) and (Line[J] = '`') then begin
          if InInline then begin
            SpanEnd := Length(CleanLine);
            SpanInfo := SpanInfo + 'c:' + IntToStr(InlineStart) + ':' +
              IntToStr(SpanEnd - InlineStart) + ';';
          end else
            InlineStart := Length(CleanLine);
          InInline := not InInline;
          Inc(J);
          Continue;
        end;
        if (not InCode) and (J < Length(Line)) and
          ((Copy(Line, J, 2) = '**') or (Copy(Line, J, 2) = '__')) then begin
          if InBold then begin
            SpanEnd := Length(CleanLine);
            SpanInfo := SpanInfo + 'b:' + IntToStr(BoldStart) + ':' +
              IntToStr(SpanEnd - BoldStart) + ';';
            InBold := False;
            BoldStart := -1;
          end else begin
            InBold := True;
            BoldStart := Length(CleanLine);
          end;
          Inc(J, 2);
          Continue;
        end;
        CleanLine := CleanLine + Line[J];
        Inc(J);
      end;
      Line := CleanLine;
      if InBold then begin
        SpanEnd := Length(CleanLine);
        SpanInfo := SpanInfo + 'b:' + IntToStr(BoldStart) + ':' +
          IntToStr(SpanEnd - BoldStart) + ';';
      end;
      DisplayLines.Add(Line);
      InlineSpans.Add(SpanInfo);
    end;
    Normalized := DisplayLines.Text;
    if (Length(RawText) > 0) and (RawText[Length(RawText)] <> #10) and
      (RawText[Length(RawText)] <> #13) and
      (Length(Normalized) >= 2) and
      (Copy(Normalized, Length(Normalized) - 1, 2) = #13#10) then
      Delete(Normalized, Length(Normalized) - 1, 2);
    Edit.Text := Normalized;
    Edit.PlainText := True;
    if Edit.GetTextLen > 0 then begin
      Edit.SelStart := 0;
      Edit.SelLength := Edit.GetTextLen;
      Edit.SelAttributes.Name := Edit.Font.Name;
      Edit.SelAttributes.Size := Edit.Font.Size;
      Edit.SelAttributes.Color := Edit.Font.Color;
      Edit.SelAttributes.Style := [];
    end;
    BaseSize := Edit.Font.Size;
    for I := 0 to Edit.Lines.Count - 1 do begin
      Line := Edit.Lines[I];
      Start := SendMessage(Edit.Handle, EM_LINEINDEX, I, 0);
      if Start < 0 then Continue;
      LineLength := Length(Line);
      Token := TrimLeft(Line);
      if (I < Kinds.Count) and (Kinds[I] = 'code') then begin
        Edit.SelStart := Start;
        Edit.SelLength := LineLength;
        Edit.SelAttributes.Name := 'Courier New';
        Edit.SelAttributes.Size := BaseSize - 1;
        Edit.SelAttributes.Color := Edit.Font.Color;
        HighlightCppLine(Edit, Start, LineLength);
      end else if (I < Kinds.Count) and (Copy(Kinds[I], 1, 7) = 'heading') then begin
        Level := StrToIntDef(Copy(Kinds[I], 8, MaxInt), 2);
        Edit.SelStart := Start;
        Edit.SelLength := LineLength;
        Edit.SelAttributes.Style := [fsBold];
        Edit.SelAttributes.Size := BaseSize + 4 - Level;
      end else if (I < Kinds.Count) and (Kinds[I] = 'tablehead') then begin
        Edit.SelStart := Start;
        Edit.SelLength := LineLength;
        Edit.SelAttributes.Style := [fsBold];
      end else if (I < Kinds.Count) and (Kinds[I] = 'divider') then begin
        Edit.SelStart := Start;
        Edit.SelLength := LineLength;
        Edit.SelAttributes.Color := RGB(128, 128, 128);
      end;
      if (I < InlineSpans.Count) and (InlineSpans[I] <> '') then begin
        SpanParts.Delimiter := ';';
        SpanParts.DelimitedText := InlineSpans[I];
        for J := 0 to SpanParts.Count - 1 do begin
          P := Pos(':', SpanParts[J]);
          if P > 0 then begin
            Token := Copy(SpanParts[J], 1, P - 1);
            if (Token = 'c') or (Token = 'b') then begin
              SpanInfo := Copy(SpanParts[J], P + 1, MaxInt);
              P := Pos(':', SpanInfo);
              if P > 0 then begin
                Edit.SelStart := Start + StrToIntDef(Copy(SpanInfo, 1, P - 1), 0);
                Edit.SelLength := StrToIntDef(Copy(SpanInfo, P + 1, MaxInt), 0);
                if Token = 'c' then begin
                  Edit.SelAttributes.Name := 'Courier New';
                  Edit.SelAttributes.Size := BaseSize - 1;
                end else begin
                  Edit.SelAttributes.Style := [fsBold];
                end;
              end;
            end else begin
              Edit.SelStart := Start + StrToIntDef(Copy(SpanParts[J], 1, P - 1), 0);
              Edit.SelLength := StrToIntDef(Copy(SpanParts[J], P + 1, MaxInt), 0);
              Edit.SelAttributes.Name := 'Courier New';
              Edit.SelAttributes.Size := BaseSize - 1;
            end;
          end;
        end;
      end;
    end;
  finally
    RawLines.Free;
    DisplayLines.Free;
    Kinds.Free;
    InlineSpans.Free;
    SpanParts.Free;
  end;
  if SavedStart > Edit.GetTextLen then SavedStart := Edit.GetTextLen;
  Edit.SelStart := SavedStart;
  Edit.SelLength := SavedLength;
end;

function TAgentTimeline.NewTextBlock: TRichEdit;
begin
  Result := TTimelineRichEdit.Create(Self);
  Result.Parent := Self;
  Result.OnMouseWheel := TimelineMouseWheel;
  Result.ReadOnly := True;
  Result.PopupMenu := PopupMenu;
  Result.BorderStyle := bsNone;
  Result.Color := Color;
  Result.Font.Assign(Font);
  Result.Font.Color := fPalette.Text;
  Result.ScrollBars := ssNone;
  Result.WordWrap := True;
  Result.Width := ClientWidth - 24;
  SendMessage(Result.Handle, EM_SETMARGINS, EC_LEFTMARGIN or EC_RIGHTMARGIN,
    LPARAM(8 or (8 shl 16)));
  TTimelineRichEdit(Result).IsUserMessage := False;
  fBlocks.Add(Result);
end;
procedure TAgentTimeline.AppendText(const Text: String; TextColor: TColor; Bold: Boolean);
var Lines, OldStart, OldLength: Integer;
begin
  if (fLastText = nil) or fLastIsMarkdown then begin
    fLastText := NewTextBlock;
    fLastIsMarkdown := False;
  end;
  OldStart := fLastText.SelStart;
  OldLength := fLastText.SelLength;
  SendMessage(fLastText.Handle, EM_SETSEL, WPARAM(-1), LPARAM(-1));
  fLastText.SelAttributes.Color := TextColor;
  if Bold then fLastText.SelAttributes.Style := [fsBold]
  else fLastText.SelAttributes.Style := [];
  fLastText.SelText := Text;
  if OldLength > 0 then begin
    fLastText.SelStart := OldStart;
    fLastText.SelLength := OldLength;
  end;
  Lines := SendMessage(fLastText.Handle, EM_GETLINECOUNT, 0, 0);
  fLastText.Height := (Lines + 1) * (Abs(Font.Height) + 6);
  LayoutBlocks;
end;

procedure TAgentTimeline.AppendMarkdown(const Text: String; TextColor: TColor);
var Lines: Integer; R: TTimelineRichEdit;
begin
  if (fLastText = nil) or (not fLastIsMarkdown) then begin
    fLastText := NewTextBlock;
    fLastIsMarkdown := True;
  end;
  R := TTimelineRichEdit(fLastText);
  R.RawText := R.RawText + Text;
  R.Font.Color := TextColor;
  RenderMarkdown(R, R.RawText);
  Lines := SendMessage(R.Handle, EM_GETLINECOUNT, 0, 0);
  R.Height := (Lines + 1) * (Abs(Font.Height) + 6);
  LayoutBlocks;
end;

procedure TAgentTimeline.AppendMessage(const Text: String; TextColor: TColor;
  IsUser: Boolean; const ContextSummary, ContextPayload: String);
var R: TTimelineRichEdit; Lines: Integer;
begin
  fLastText := NewTextBlock;
  fLastIsMarkdown := False;
  R := TTimelineRichEdit(fLastText);
  R.IsUserMessage := IsUser;
  R.ContextSummary := ContextSummary;
  R.ContextPayload := ContextPayload;
  R.Font.Color := TextColor;
  R.Color := Color;
  if IsUser then begin
    if AgentUiIsDark(Color) then
      R.Color := RGB(48, 51, 56)
    else
      R.Color := RGB(237, 242, 248);
    R.Paragraph.Alignment := taLeftJustify;
  end else
    R.Paragraph.Alignment := taLeftJustify;
  R.SelStart := 0;
  R.SelLength := 0;
  R.SelText := Text;
  Lines := SendMessage(R.Handle, EM_GETLINECOUNT, 0, 0);
  R.Height := (Lines + 1) * (Abs(Font.Height) + 8);
  LayoutBlocks;
end;

function IsCppKeyword(const Token: String): Boolean;
begin
  Result := SameText(Token, 'auto') or SameText(Token, 'bool') or
    SameText(Token, 'break') or SameText(Token, 'case') or
    SameText(Token, 'catch') or SameText(Token, 'char') or
    SameText(Token, 'class') or SameText(Token, 'const') or
    SameText(Token, 'continue') or SameText(Token, 'default') or
    SameText(Token, 'delete') or SameText(Token, 'do') or
    SameText(Token, 'double') or SameText(Token, 'else') or
    SameText(Token, 'enum') or SameText(Token, 'explicit') or
    SameText(Token, 'extern') or SameText(Token, 'false') or
    SameText(Token, 'float') or SameText(Token, 'for') or
    SameText(Token, 'friend') or SameText(Token, 'if') or
    SameText(Token, 'inline') or SameText(Token, 'int') or
    SameText(Token, 'long') or SameText(Token, 'namespace') or
    SameText(Token, 'new') or SameText(Token, 'nullptr') or
    SameText(Token, 'operator') or SameText(Token, 'private') or
    SameText(Token, 'protected') or SameText(Token, 'public') or
    SameText(Token, 'return') or SameText(Token, 'short') or
    SameText(Token, 'signed') or SameText(Token, 'sizeof') or
    SameText(Token, 'static') or SameText(Token, 'struct') or
    SameText(Token, 'switch') or SameText(Token, 'template') or
    SameText(Token, 'this') or SameText(Token, 'throw') or
    SameText(Token, 'true') or SameText(Token, 'try') or
    SameText(Token, 'typedef') or SameText(Token, 'typename') or
    SameText(Token, 'union') or SameText(Token, 'unsigned') or
    SameText(Token, 'using') or SameText(Token, 'virtual') or
    SameText(Token, 'void') or SameText(Token, 'volatile') or
    SameText(Token, 'while');
end;

procedure HighlightCppLine(Edit: TRichEdit; Start, LineLength: Integer);
var
  Line, Token: String;
  I, TokenStart, QuoteEnd, CommentStart: Integer;
  Dark: Boolean;
  KeywordColor, StringColor, CommentColor: TColor;
begin
  if (Edit = nil) or (LineLength <= 0) then
    Exit;
  Line := Copy(Edit.Text, Start + 1, LineLength);
  Dark := AgentUiIsDark(Edit.Color);
  if Dark then begin
    KeywordColor := RGB(86, 156, 214);
    StringColor := RGB(206, 145, 120);
    CommentColor := RGB(106, 153, 85);
  end else begin
    KeywordColor := RGB(0, 80, 160);
    StringColor := RGB(128, 40, 0);
    CommentColor := RGB(0, 110, 40);
  end;
  CommentStart := Pos('//', Line);
  if CommentStart > 0 then begin
    Edit.SelStart := Start + CommentStart - 1;
    Edit.SelLength := LineLength - CommentStart + 1;
    Edit.SelAttributes.Color := CommentColor;
  end;
  I := 1;
  while I <= Length(Line) do begin
    if (CommentStart > 0) and (I >= CommentStart) then
      Break;
    if Line[I] in ['"', ''''] then begin
      QuoteEnd := I + 1;
      while QuoteEnd <= Length(Line) do begin
        if (Line[QuoteEnd] = Line[I]) and (Line[QuoteEnd - 1] <> '\') then
          Break;
        Inc(QuoteEnd);
      end;
      if QuoteEnd > Length(Line) then QuoteEnd := Length(Line);
      Edit.SelStart := Start + I - 1;
      Edit.SelLength := QuoteEnd - I + 1;
      Edit.SelAttributes.Color := StringColor;
      I := QuoteEnd + 1;
    end else if (Line[I] in ['A'..'Z', 'a'..'z', '_']) then begin
      TokenStart := I;
      Inc(I);
      while (I <= Length(Line)) and
        (Line[I] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(I);
      Token := Copy(Line, TokenStart, I - TokenStart);
      if IsCppKeyword(Token) then begin
        Edit.SelStart := Start + TokenStart - 1;
        Edit.SelLength := Length(Token);
        Edit.SelAttributes.Color := KeywordColor;
      end;
    end else
      Inc(I);
  end;
end;

procedure TAgentTimeline.ToggleBlock(Sender: TObject);
var Block: TTimelineTool;
begin
  Block := TTimelineTool(TControl(Sender).Parent);
  Block.Body.Visible := not Block.Body.Visible;
  if Block.Body.Visible then begin
    Block.Height := 180;
    Block.Header.Caption := 'v  ' + Block.Header.Hint;
  end else begin
    Block.Height := 32;
    Block.Header.Caption := '>  ' + Block.Header.Hint;
  end;
  LayoutBlocks;
end;

procedure TAgentTimeline.OpenChangedFile(Sender: TObject);
var Control: TControl; Block: TTimelineTool;
begin
  if not (Sender is TControl) then Exit;
  Control := TControl(Sender).Parent;
  if (Control = nil) or not (Control.Parent is TTimelineTool) then Exit;
  Block := TTimelineTool(Control.Parent);
  if Block.CanOpenFile and Assigned(fOnOpenFile) then
    fOnOpenFile(Self, Block.FilePath);
end;

procedure TAgentTimeline.AddTool(const Id, Caption, Details: String;
  const Status: String; IsResult: Boolean);
var I: Integer; Block: TTimelineTool; OldText: String;
begin
  Block := nil;
  for I := 0 to fBlocks.Count - 1 do
    if TObject(fBlocks[I]) is TTimelineTool then
      if TTimelineTool(fBlocks[I]).ToolId = Id then begin
        Block := TTimelineTool(fBlocks[I]);
        Break;
      end;
  if Block = nil then begin
    fLastText := nil;
    Block := TTimelineTool.Create(Self);
    Block.Parent := Self;
    Block.OnMouseWheel := TimelineMouseWheel;
    Block.ToolId := Id;
    Block.IsFileChange := False;
    Block.CanOpenFile := False;
    Block.OpenButton := nil;
    Block.BevelOuter := bvNone;
    Block.Height := 32;
    Block.Header := TTimelineButton.Create(Block);
    Block.Header.Parent := Block;
    Block.Header.BevelOuter := bvNone;
    Block.Header.Alignment := taLeftJustify;
    TWheelControl(Block.Header).OnMouseWheel := TimelineMouseWheel;
    Block.Header.SetBounds(0, 0, ClientWidth - 24, 32);
    Block.Header.Anchors := [akLeft, akTop, akRight];
    Block.Header.OnClick := ToggleBlock;
    Block.Header.ParentColor := False;
    Block.Header.Color := fPalette.Elevated;
    Block.Header.Font.Assign(Font);
    Block.Header.Font.Color := fPalette.Text;
    Block.Body := TTimelineMemo.Create(Block);
    Block.Body.Parent := Block;
    TWheelControl(Block.Body).OnMouseWheel := TimelineMouseWheel;
    Block.Body.SetBounds(0, 36, ClientWidth - 24, 140);
    Block.Body.Anchors := [akLeft, akTop, akRight, akBottom];
    Block.Body.ReadOnly := True;
    Block.Body.PopupMenu := PopupMenu;
    Block.Body.Color := Color;
    Block.Body.Font.Assign(Font);
    Block.Body.ParentColor := False;
    Block.Body.Color := fPalette.Panel;
    Block.Body.Font.Color := fPalette.Text;
    Block.Body.ScrollBars := ssBoth;
    Block.Body.Visible := False;
    fBlocks.Add(Block);
  end;
  ApplyBlockAppearance(Block, Font.Name, Font.Size);
  Block.Header.Hint := Caption;
  if Block.Body.Visible then Block.Header.Caption := 'v  ' + Caption
  else Block.Header.Caption := '>  ' + Caption;
  Block.State := Status;
  if IsResult then Block.OutputText := Details
  else if Details <> '' then Block.InputText := Details;
  OldText := Block.Body.Lines.Text;
  if Block.InputText <> '' then
    Block.Body.Lines.Text := Block.InputText
  else if Block.OutputText <> '' then
    Block.Body.Lines.Text := Block.OutputText
  else
    Block.Body.Clear;
  if IsResult and (Block.InputText <> '') and (Block.OutputText <> '') then
    Block.Body.Lines.Text := Block.InputText + #13#10 + Block.OutputText;
  if OldText <> Block.Body.Lines.Text then
    Block.Body.SelStart := 0;
  LayoutBlocks;
end;

procedure TAgentTimeline.AddFileChange(const State, FileName, DiffText,
  DiffSummary: String; CanOpen: Boolean; const UndoToken: String;
  CanUndo: Boolean);
var Block: TTimelineTool; Caption: String; Id: String;
begin
  Id := 'file-change-' + IntToStr(fGeneration) + '-' + IntToStr(fBlocks.Count);
  Caption := '[' + State + '] ' + FileName;
  AddTool(Id, Caption, DiffText, State, False);
  Block := TTimelineTool(fBlocks[fBlocks.Count - 1]);
  Block.IsFileChange := True;
  Block.CanOpenFile := CanOpen;
  Block.FilePath := FileName;
  Block.FileState := State;
  Block.DiffSummary := DiffSummary;
  Block.UndoToken := UndoToken;
  Block.UndoState := '';
  Block.CanUndoFile := CanUndo and (UndoToken <> '');
  if Block.OpenButton = nil then begin
    Block.OpenButton := TTimelineNativeButton.Create(Block);
    Block.OpenButton.Parent := Block.Header;
    TTimelineNativeButton(Block.OpenButton).OnMouseWheel := TimelineMouseWheel;
    Block.OpenButton.SetBounds(Block.Header.ClientWidth - 84, 3, 80, 25);
    Block.OpenButton.Anchors := [akTop, akRight];
    Block.OpenButton.Caption := 'Open file';
    Block.OpenButton.Enabled := CanOpen;
    Block.OpenButton.OnClick := OpenChangedFile;
  end else
    Block.OpenButton.Enabled := CanOpen;
  Block.Header.Hint := Caption;
  if Block.Body.Visible then Block.Header.Caption := 'v  ' + Caption
  else Block.Header.Caption := '>  ' + Caption;
  LayoutBlocks;
end;

procedure TAgentTimeline.SetFileChangeUndoState(const UndoToken,
  State: String);
var I: Integer; Block: TTimelineTool;
begin
  if UndoToken = '' then Exit;
  for I := 0 to fBlocks.Count - 1 do
    if TObject(fBlocks[I]) is TTimelineTool then begin
      Block := TTimelineTool(fBlocks[I]);
      if Block.IsFileChange and (Block.UndoToken = UndoToken) then begin
        Block.UndoState := State;
        Block.CanUndoFile := False;
        Inc(fRevision);
        Exit;
      end;
    end;
end;

procedure TAgentTimeline.AddPermission(const Id, Caption, InputJSON,
  WorkDir: String);
var I: Integer; Block: TTimelineTool;
begin
  // Keep permission payloads as UTF-8 for the CLI, but store a local-codepage
  // copy in the timeline because it is only used for display/history.
  AddTool('permission-' + Id, Caption, String(UTF8Decode(InputJSON)),
    'approval', False);
  for I := 0 to fBlocks.Count - 1 do
    if TObject(fBlocks[I]) is TTimelineTool then
      if TTimelineTool(fBlocks[I]).ToolId = 'permission-' + Id then begin
        Block := TTimelineTool(fBlocks[I]);
        Block.PermissionRequestId := Id;
        Block.PermissionWorkDir := WorkDir;
        Inc(fRevision);
        Break;
      end;
end;

procedure TAgentTimeline.UpdatePermission(const Id, Status, Details: String;
  const InputJSON: String);
var I: Integer; Block: TTimelineTool;
begin
  for I := 0 to fBlocks.Count - 1 do
    if TObject(fBlocks[I]) is TTimelineTool then
      if TTimelineTool(fBlocks[I]).PermissionRequestId = Id then begin
        Block := TTimelineTool(fBlocks[I]);
        Block.State := Status;
        if InputJSON <> '' then
          Block.InputText := String(UTF8Decode(InputJSON));
        Block.OutputText := Details;
        if Details <> '' then begin
          if Block.InputText <> '' then
            Block.Body.Lines.Text := Block.InputText + #13#10 + Details
          else
            Block.Body.Lines.Text := Details;
        end;
        if Status <> 'approval' then Block.PermissionRequestId := '';
        Inc(fRevision);
        LayoutBlocks;
        Break;
      end;
end;
end.
