unit AgentTimeline;
interface
uses Windows, Messages, SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls,
  Graphics, ComCtrls, IniFiles;
type
  TAgentTimeline = class(TScrollBox)
  private
    fBlocks: TList;
    fLastText: TRichEdit;
    fWheelRemainder: Integer;
    procedure TimelineMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ToggleBlock(Sender: TObject);
    procedure LayoutBlocks;
    procedure RenderMarkdown(Edit: TRichEdit);
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
    property LastText: TRichEdit read fLastText;
    procedure AppendText(const Text: String; TextColor: TColor; Bold: Boolean);
    procedure AddTool(const Id, Caption, Details: String);
  end;
implementation
type
  TWheelControl = class(TControl);
  TTimelineRichEdit = class(TRichEdit)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;
  TTimelineMemo = class(TMemo)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;
  TTimelineButton = class(TButton)
  protected
    procedure WndProc(var Message: TMessage); override;
  end;
  TTimelineTool = class(TPanel)
  public
    ToolId: String;
    Header: TButton;
    Body: TMemo;
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

constructor TAgentTimeline.Create(AOwner: TComponent);
begin
  inherited;
  fBlocks := TList.Create;
  fWheelRemainder := 0;
  BorderStyle := bsNone;
  AutoScroll := True;
  HorzScrollBar.Visible := False;
  VertScrollBar.Tracking := True;
  OnMouseWheel := TimelineMouseWheel;
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
  fBlocks.Free;
  inherited;
end;
function TAgentTimeline.BlockCount: Integer;
begin Result := fBlocks.Count; end;
function TAgentTimeline.BlockAt(Index: Integer): TControl;
begin Result := TControl(fBlocks[Index]); end;

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
var Ini: TMemIniFile; I: Integer; Section: String; Block: TObject;
begin
  Ini := TMemIniFile.Create(Path);
  try
    Ini.Clear;
    Ini.WriteInteger('timeline', 'count', fBlocks.Count);
    for I := 0 to fBlocks.Count - 1 do begin
      Section := IntToStr(I);
      Block := TObject(fBlocks[I]);
      if Block is TTimelineTool then begin
        Ini.WriteString(Section, 'kind', 'tool');
        Ini.WriteString(Section, 'id', TTimelineTool(Block).ToolId);
        Ini.WriteString(Section, 'title', TTimelineTool(Block).Header.Hint);
        TTimelineTool(Block).Body.Lines.SaveToFile(Path + '.' + Section);
      end else begin
        Ini.WriteString(Section, 'kind', 'text');
        TRichEdit(Block).PlainText := True;
        TRichEdit(Block).Lines.SaveToFile(Path + '.' + Section);
      end;
    end;
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

procedure TAgentTimeline.LoadFromFile(const Path: String);
var Ini: TMemIniFile; Lines: TStringList; I: Integer; Section: String;
begin
  Clear;
  Ini := TMemIniFile.Create(Path);
  Lines := TStringList.Create;
  try
    for I := 0 to Ini.ReadInteger('timeline', 'count', 0) - 1 do begin
      Section := IntToStr(I);
      Lines.Clear;
      if FileExists(Path + '.' + Section) then Lines.LoadFromFile(Path + '.' + Section);
      if Ini.ReadString(Section, 'kind', '') = 'tool' then
        AddTool(Ini.ReadString(Section, 'id', ''), Ini.ReadString(Section, 'title', ''), Lines.Text)
      else AppendText(Lines.Text, Font.Color, False);
    end;
  finally
    Lines.Free;
    Ini.Free;
  end;
end;
procedure TAgentTimeline.Clear;
var I: Integer;
begin
  if fBlocks = nil then Exit;
  for I := fBlocks.Count - 1 downto 0 do TObject(fBlocks[I]).Free;
  fBlocks.Clear;
  fLastText := nil;
end;
procedure TAgentTimeline.Resize;
begin
  inherited;
  if fBlocks <> nil then LayoutBlocks;
end;
procedure TAgentTimeline.LayoutBlocks;
var I, Y, OldPosition, BottomPosition: Integer; Block: TControl;
    KeepAtBottom: Boolean;
begin
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
end;

procedure TAgentTimeline.RenderMarkdown(Edit: TRichEdit);
var I, J, K, Start, LineLength, BaseSize, Level: Integer;
    InCode: Boolean; Line, Token: String;
    SavedStart, SavedLength: Integer;
begin
  if (Edit = nil) or (Edit.GetTextLen = 0) then Exit;
  SavedStart := Edit.SelStart;
  SavedLength := Edit.SelLength;
  BaseSize := Edit.Font.Size;
  InCode := False;
  for I := 0 to Edit.Lines.Count - 1 do begin
    Line := Edit.Lines[I];
    Start := SendMessage(Edit.Handle, EM_LINEINDEX, I, 0);
    if Start < 0 then Continue;
    LineLength := Length(Line);
    Token := TrimLeft(Line);
    if (Length(Token) >= 3) and (Copy(Token, 1, 3) = '```') then begin
      Edit.SelStart := Start;
      Edit.SelLength := LineLength;
      Edit.SelAttributes.Name := 'Courier New';
      Edit.SelAttributes.Size := BaseSize - 1;
      Edit.SelAttributes.Style := [fsBold];
      InCode := not InCode;
      Continue;
    end;
    if InCode then begin
      Edit.SelStart := Start;
      Edit.SelLength := LineLength;
      Edit.SelAttributes.Name := 'Courier New';
      Edit.SelAttributes.Size := BaseSize - 1;
      Continue;
    end;
    Level := 0;
    while (Level < Length(Token)) and (Token[Level + 1] = '#') do Inc(Level);
    if (Level > 0) and (Level <= 4) and (Length(Token) > Level) and
      (Token[Level + 1] = ' ') then begin
      Edit.SelStart := Start;
      Edit.SelLength := LineLength;
      Edit.SelAttributes.Style := [fsBold];
      Edit.SelAttributes.Size := BaseSize + 4 - Level;
    end;
    { Apply inline code and emphasis without changing the transcript text. }
    J := 1;
    while J <= LineLength do begin
      if (Line[J] = '`') then begin
        K := J + 1;
        while (K <= LineLength) and (Line[K] <> '`') do Inc(K);
        if K <= LineLength then begin
          Edit.SelStart := Start + J;
          Edit.SelLength := K - J - 1;
          Edit.SelAttributes.Name := 'Courier New';
          Edit.SelAttributes.Size := BaseSize - 1;
          J := K + 1;
          Continue;
        end;
      end;
      if ((Line[J] = '*') and (J < LineLength) and (Line[J + 1] = '*')) or
        ((Line[J] = '_') and (J < LineLength) and (Line[J + 1] = '_')) then begin
        Token := Copy(Line, J, 2);
        K := J + 2;
        while (K < LineLength) and (Copy(Line, K, 2) <> Token) do Inc(K);
        if K < LineLength then begin
          Edit.SelStart := Start + J + 1;
          Edit.SelLength := K - J - 2;
          Edit.SelAttributes.Style := [fsBold];
          J := K + 2;
          Continue;
        end;
      end;
      Inc(J);
    end;
  end;
  Edit.SelStart := SavedStart;
  Edit.SelLength := SavedLength;
end;
procedure TAgentTimeline.AppendText(const Text: String; TextColor: TColor; Bold: Boolean);
var Lines, OldStart, OldLength: Integer;
begin
  if fLastText = nil then begin
    fLastText := TTimelineRichEdit.Create(Self);
    fLastText.Parent := Self;
    fLastText.OnMouseWheel := TimelineMouseWheel;
    fLastText.ReadOnly := True;
    fLastText.PopupMenu := PopupMenu;
    fLastText.BorderStyle := bsNone;
    fLastText.Color := Color;
    fLastText.Font.Assign(Font);
    fLastText.ScrollBars := ssNone;
    fLastText.WordWrap := True;
    fLastText.Width := ClientWidth - 24;
    fBlocks.Add(fLastText);
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
  RenderMarkdown(fLastText);
  LayoutBlocks;
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
procedure TAgentTimeline.AddTool(const Id, Caption, Details: String);
var I: Integer; Block: TTimelineTool;
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
    Block.BevelOuter := bvNone;
    Block.Height := 32;
    Block.Header := TTimelineButton.Create(Block);
    Block.Header.Parent := Block;
    TWheelControl(Block.Header).OnMouseWheel := TimelineMouseWheel;
    Block.Header.SetBounds(0, 0, ClientWidth - 24, 32);
    Block.Header.Anchors := [akLeft, akTop, akRight];
    Block.Header.OnClick := ToggleBlock;
    Block.Body := TTimelineMemo.Create(Block);
    Block.Body.Parent := Block;
    TWheelControl(Block.Body).OnMouseWheel := TimelineMouseWheel;
    Block.Body.SetBounds(0, 36, ClientWidth - 24, 140);
    Block.Body.Anchors := [akLeft, akTop, akRight, akBottom];
    Block.Body.ReadOnly := True;
    Block.Body.PopupMenu := PopupMenu;
    Block.Body.Color := Color;
    Block.Body.Font.Assign(Font);
    Block.Body.ScrollBars := ssBoth;
    Block.Body.Visible := False;
    fBlocks.Add(Block);
  end;
  Block.Header.Hint := Caption;
  Block.Header.Caption := '>  ' + Caption;
  if Details <> '' then Block.Body.Lines.Add(Details);
  LayoutBlocks;
end;
end.
