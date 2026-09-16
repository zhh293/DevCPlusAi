unit AgentTimeline;
interface
uses Windows, Messages, SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls,
  Graphics, ComCtrls, IniFiles, AgentUITheme;
type
  TAgentTimeline = class(TScrollBox)
  private
    fBlocks: TList;
    fLastText: TRichEdit;
    fLastIsMarkdown: Boolean;
    fWheelRemainder: Integer;
    procedure TimelineMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ToggleBlock(Sender: TObject);
    procedure LayoutBlocks;
    procedure RenderMarkdown(Edit: TRichEdit; const RawText: String);
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
    property LastText: TRichEdit read fLastText;
    procedure AppendText(const Text: String; TextColor: TColor; Bold: Boolean);
    procedure AppendMarkdown(const Text: String; TextColor: TColor);
    procedure AppendMessage(const Text: String; TextColor: TColor; IsUser: Boolean);
    procedure AddTool(const Id, Caption, Details: String);
  end;
implementation
type
  TWheelControl = class(TControl);
  TTimelineRichEdit = class(TRichEdit)
  public
    RawText: String;
    IsUserMessage: Boolean;
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
  fLastIsMarkdown := False;
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
    Lines: TStringList;
begin
  Ini := TMemIniFile.Create(Path);
  try
    Ini.Clear;
    Ini.WriteInteger('timeline', 'version', 2);
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
        if (Block is TTimelineRichEdit) and TTimelineRichEdit(Block).IsUserMessage then
          Ini.WriteString(Section, 'role', 'user')
        else
          Ini.WriteString(Section, 'role', 'assistant');
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
      else if SameText(Ini.ReadString(Section, 'markdown', ''), '1') then
        AppendMarkdown(Lines.Text, Font.Color)
      else if SameText(Ini.ReadString(Section, 'role', ''), 'user') then
        AppendMessage(Lines.Text, Font.Color, True)
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
  fLastIsMarkdown := False;
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
  IsUser: Boolean);
var R: TTimelineRichEdit; Lines: Integer;
begin
  fLastText := NewTextBlock;
  fLastIsMarkdown := False;
  R := TTimelineRichEdit(fLastText);
  R.IsUserMessage := IsUser;
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
