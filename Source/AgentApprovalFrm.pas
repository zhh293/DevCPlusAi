unit AgentApprovalFrm;
interface
uses Windows, SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Dialogs,
  Graphics, ComCtrls;
function RequestAgentApproval(const ToolName, WorkDir, InputJSON: String): Boolean;
function RequestAgentQuestion(const InputJSON: String;
  out AnswersJSON: String): Boolean;
function AgentPathWithinWorkDir(const FileName, WorkDir: String): Boolean;
function BuildFilePreview(const ToolName, WorkDir, InputJSON: String;
  out FileName, BeforeText, AfterText, ErrorText: String;
  out IsNewFile: Boolean): Boolean;
function BuildAgentFileDiffText(const BeforeText, AfterText: String;
  out Summary: String): String;
implementation
uses uLkJSON, Variants;

function AgentUiText(const Utf8Bytes: AnsiString): String;
begin
  Result := String(UTF8Decode(Utf8Bytes));
end;

function ApprovalToolName(const ToolName: String): String;
begin
  if SameText(ToolName, 'Write') then
    Result := AgentUiText(#$E5#$86#$99#$E5#$85#$A5#$E6#$96#$87#$E4#$BB#$B6)
  else if SameText(ToolName, 'Edit') then
    Result := AgentUiText(#$E4#$BF#$AE#$E6#$94#$B9#$E6#$96#$87#$E4#$BB#$B6)
  else if SameText(ToolName, 'Bash') then
    Result := AgentUiText(#$E6#$89#$A7#$E8#$A1#$8C#$E5#$91#$BD#$E4#$BB#$A4)
  else if SameText(ToolName, 'Read') then
    Result := AgentUiText(#$E8#$AF#$BB#$E5#$8F#$96#$E6#$96#$87#$E4#$BB#$B6)
  else if SameText(ToolName, 'Glob') then
    Result := AgentUiText(#$E6#$90#$9C#$E7#$B4#$A2#$E6#$96#$87#$E4#$BB#$B6)
  else if SameText(ToolName, 'Grep') then
    Result := AgentUiText(#$E6#$90#$9C#$E7#$B4#$A2#$E5#$86#$85#$E5#$AE#$B9)
  else
    Result := ToolName;
end;

type
  TApprovalDiffRow = array of Integer;
  TApprovalDiffMatrix = array of TApprovalDiffRow;

  TAgentQuestionEntry = class
  public
    Question: WideString;
    MultiSelect: Boolean;
    ChoiceList: TListBox;
    CustomAnswer: TEdit;
    OtherIndex: Integer;
    Labels: TStringList;
    constructor Create;
    destructor Destroy; override;
  end;

  TAgentQuestionDialog = class(TForm)
  public
    Entries: TList;
    AnswersJSON: String;
    procedure AcceptAnswers(Sender: TObject);
    destructor Destroy; override;
  end;

function JsonField(Node: TlkJSONbase; const Name: String): WideString;
var Field: TlkJSONbase;
begin
  Result := '';
  if Node = nil then Exit;
  Field := Node.Field[Name];
  if (Field <> nil) and not (Field is TlkJSONobject) and
     not (Field is TlkJSONlist) then
    Result := VarToWideStr(Field.Value);
end;

function JsonBoolean(Node: TlkJSONbase; const Name: String): Boolean;
var Field: TlkJSONbase;
begin
  Result := False;
  if Node = nil then Exit;
  Field := Node.Field[Name];
  if Field <> nil then
    Result := SameText(VarToStr(Field.Value), 'true');
end;

function FileIsWithinWorkDir(const FileName, WorkDir: String): Boolean;
var BasePath, TargetPath, Prefix: String;
begin
  Result := False;
  if Trim(WorkDir) = '' then Exit;
  BasePath := ExcludeTrailingPathDelimiter(ExpandFileName(WorkDir));
  TargetPath := ExpandFileName(FileName);
  if SameText(TargetPath, BasePath) then begin
    Result := True;
    Exit;
  end;
  Prefix := IncludeTrailingPathDelimiter(BasePath);
  Result := CompareText(Copy(TargetPath, 1, Length(Prefix)), Prefix) = 0;
end;

function AgentPathWithinWorkDir(const FileName, WorkDir: String): Boolean;
begin
  Result := FileIsWithinWorkDir(FileName, WorkDir);
end;

function ReadReviewFile(const FileName: String; out Text, ErrorText: String):
  Boolean;
var Stream: TFileStream; Bytes: String; WideText: WideString; I: Integer;
begin
  Result := False;
  Text := '';
  ErrorText := '';
  Stream := nil;
  try
    try
      Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
      if Stream.Size > 2 * 1024 * 1024 then begin
        ErrorText := AgentUiText(#$E5#$B7#$B2#$E6#$9C#$89#$E6#$96#$87#$E4#$BB#$B6#$E8#$B6#$85#$E5#$87#$BA#$20#$32#$20#$4D#$42#$20#$E5#$AE#$A1#$E9#$98#$85#$E9#$99#$90#$E5#$88#$B6#$E3#$80#$82);
        Exit;
      end;
      SetLength(Bytes, Stream.Size);
      if Length(Bytes) > 0 then
        Stream.ReadBuffer(Bytes[1], Length(Bytes));
      if Copy(Bytes, 1, 3) = #$EF#$BB#$BF then
        WideText := UTF8Decode(Copy(Bytes, 4, MaxInt))
      else if Copy(Bytes, 1, 2) = #$FF#$FE then begin
        SetLength(WideText, (Length(Bytes) - 2) div 2);
        if Length(WideText) > 0 then
          Move(Bytes[3], WideText[1], Length(WideText) * SizeOf(WideChar));
      end else if Copy(Bytes, 1, 2) = #$FE#$FF then begin
        SetLength(WideText, (Length(Bytes) - 2) div 2);
        for I := 0 to Length(WideText) - 1 do begin
          WideText[I + 1] := WideChar((Ord(Bytes[3 + I * 2]) shl 8) or
            Ord(Bytes[4 + I * 2]));
        end;
      end else if (Length(Bytes) > 0) and
        (MultiByteToWideChar(CP_UTF8, $00000008, PAnsiChar(Bytes),
          Length(Bytes), nil, 0) > 0) then
        WideText := UTF8Decode(Bytes)
      else begin
        for I := 1 to Length(Bytes) do
          if Bytes[I] = #0 then begin
            ErrorText := AgentUiText(#$E7#$9B#$AE#$E6#$A0#$87#$E4#$B8#$BA#$E4#$BA#$8C#$E8#$BF#$9B#$E5#$88#$B6#$E6#$96#$87#$E4#$BB#$B6#$EF#$BC#$8C#$E6#$97#$A0#$E6#$B3#$95#$E9#$A2#$84#$E8#$A7#$88#$E3#$80#$82);
            Exit;
          end;
        WideText := Bytes;
      end;
      Text := String(WideText);
      Result := True;
    except
      on E: Exception do ErrorText := E.Message;
    end;
  finally
    Stream.Free;
  end;
end;

function CountSubstring(const Text, SubText: String): Integer;
var P, StartAt: Integer;
begin
  Result := 0;
  if SubText = '' then Exit;
  StartAt := 1;
  repeat
    P := Pos(SubText, Copy(Text, StartAt, MaxInt));
    if P = 0 then Break;
    Inc(Result);
    Inc(StartAt, P + Length(SubText) - 1);
  until StartAt > Length(Text);
end;

function BuildFilePreview(const ToolName, WorkDir, InputJSON: String;
  out FileName, BeforeText, AfterText, ErrorText: String;
  out IsNewFile: Boolean): Boolean;
var Node: TlkJSONbase; Target, Content, OldText, NewText: WideString;
  TargetName, OldPart, NewPart: String; P: Integer;
begin
  Result := False;
  FileName := '';
  BeforeText := '';
  AfterText := '';
  ErrorText := '';
  IsNewFile := False;
  Node := nil;
  try
    try Node := TlkJSON.ParseText(InputJSON); except Node := nil; end;
    if not (Node is TlkJSONobject) then Exit;
    Target := JsonField(Node, 'file_path');
    if Target = '' then Target := JsonField(Node, 'path');
    if Target = '' then Exit;
    TargetName := String(Target);
    if (ExtractFileDrive(TargetName) = '') and
       ((TargetName = '') or (TargetName[1] <> '\')) then
      TargetName := IncludeTrailingPathDelimiter(WorkDir) + TargetName;
    FileName := ExpandFileName(TargetName);
    if Trim(WorkDir) = '' then begin
      ErrorText := AgentUiText(#$E5#$BD#$93#$E5#$89#$8D#$E5#$B7#$A5#$E4#$BD#$9C#$E7#$9B#$AE#$E5#$BD#$95#$E4#$B8#$8D#$E5#$8F#$AF#$E7#$94#$A8#$EF#$BC#$9B#$E6#$9C#$AA#$E8#$AF#$BB#$E5#$8F#$96#$E7#$9B#$AE#$E6#$A0#$87#$E6#$96#$87#$E4#$BB#$B6#$E3#$80#$82);
      Exit;
    end;
    if not FileIsWithinWorkDir(FileName, WorkDir) then begin
      ErrorText := AgentUiText(#$E7#$9B#$AE#$E6#$A0#$87#$E4#$BD#$8D#$E4#$BA#$8E#$E5#$B7#$A5#$E4#$BD#$9C#$E7#$9B#$AE#$E5#$BD#$95#$E4#$B9#$8B#$E5#$A4#$96#$E3#$80#$82#$E6#$9C#$AA#$E8#$AF#$BB#$E5#$8F#$96#$E7#$8E#$B0#$E6#$9C#$89#$E5#$86#$85#$E5#$AE#$B9#$EF#$BC#$8C#$E8#$AF#$B7#$E6#$A3#$80#$E6#$9F#$A5#$E4#$B8#$8B#$E6#$96#$B9#$E8#$AF#$B7#$E6#$B1#$82#$E8#$AF#$A6#$E6#$83#$85#$E3#$80#$82);
      Exit;
    end;

    if FileExists(FileName) then begin
      if not ReadReviewFile(FileName, BeforeText, ErrorText) then Exit;
    end else begin
      IsNewFile := True;
      if SameText(ToolName, 'Edit') then begin
        ErrorText := AgentUiText(#$E7#$BC#$96#$E8#$BE#$91#$E8#$AF#$B7#$E6#$B1#$82#$E6#$B2#$A1#$E6#$9C#$89#$E6#$97#$A7#$E6#$96#$87#$E6#$9C#$AC#$E5#$8F#$AF#$E6#$9B#$BF#$E6#$8D#$A2#$E3#$80#$82);
        Exit;
      end;
    end;

    if SameText(ToolName, 'Write') then begin
      if Node.Field['content'] = nil then Exit;
      Content := JsonField(Node, 'content');
      AfterText := String(Content);
    end else if SameText(ToolName, 'Edit') then begin
      OldText := JsonField(Node, 'old_string');
      NewText := JsonField(Node, 'new_string');
      OldPart := String(OldText);
      NewPart := String(NewText);
      if OldPart = '' then begin
        ErrorText := AgentUiText(#$E7#$BC#$96#$E8#$BE#$91#$E8#$AF#$B7#$E6#$B1#$82#$E6#$B2#$A1#$E6#$9C#$89#$E6#$97#$A7#$E6#$96#$87#$E6#$9C#$AC#$E5#$8F#$AF#$E6#$9B#$BF#$E6#$8D#$A2#$E3#$80#$82);
        Exit;
      end;
      P := Pos(OldPart, BeforeText);
      if P = 0 then begin
        ErrorText := AgentUiText(#$E5#$BD#$93#$E5#$89#$8D#$E6#$96#$87#$E4#$BB#$B6#$E4#$B8#$AD#$E6#$89#$BE#$E4#$B8#$8D#$E5#$88#$B0#$E8#$A6#$81#$E6#$9B#$BF#$E6#$8D#$A2#$E7#$9A#$84#$E5#$8E#$9F#$E6#$96#$87#$E3#$80#$82);
        Exit;
      end;
      if JsonBoolean(Node, 'replace_all') then begin
        AfterText := StringReplace(BeforeText, OldPart, NewPart, [rfReplaceAll]);
      end else begin
        if CountSubstring(BeforeText, OldPart) > 1 then begin
          ErrorText := 'The old text occurs more than once; the CLI requires a unique match.';
          Exit;
        end;
        AfterText := Copy(BeforeText, 1, P - 1) + NewPart +
          Copy(BeforeText, P + Length(OldPart), MaxInt);
      end;
    end else Exit;
    Result := True;
  finally
    Node.Free;
  end;
end;

function BuildAgentFileDiffText(const BeforeText, AfterText: String;
  out Summary: String): String;
var BeforeLines, AfterLines, DiffLines: TStringList;
  Lcs: TApprovalDiffMatrix;
  I, J, OldCount, NewCount, Added, Removed: Integer;
  Normalized: String;
begin
  Result := '';
  Summary := '';
  BeforeLines := TStringList.Create;
  AfterLines := TStringList.Create;
  DiffLines := TStringList.Create;
  try
    Normalized := StringReplace(BeforeText, #13#10, #10, [rfReplaceAll]);
    Normalized := StringReplace(Normalized, #13, #10, [rfReplaceAll]);
    BeforeLines.Text := StringReplace(Normalized, #10, #13#10, [rfReplaceAll]);
    Normalized := StringReplace(AfterText, #13#10, #10, [rfReplaceAll]);
    Normalized := StringReplace(Normalized, #13, #10, [rfReplaceAll]);
    AfterLines.Text := StringReplace(Normalized, #10, #13#10, [rfReplaceAll]);
    OldCount := BeforeLines.Count;
    NewCount := AfterLines.Count;
    if (OldCount + 1) > 4000000 div (NewCount + 1) then begin
      Summary := 'Diff omitted to keep this review responsive';
      Result := 'Line-by-line comparison was skipped for this large change.';
      Exit;
    end;
    SetLength(Lcs, OldCount + 1);
    for I := 0 to OldCount do SetLength(Lcs[I], NewCount + 1);
    for I := OldCount - 1 downto 0 do
      for J := NewCount - 1 downto 0 do
        if BeforeLines[I] = AfterLines[J] then
          Lcs[I][J] := Lcs[I + 1][J + 1] + 1
        else if Lcs[I + 1][J] >= Lcs[I][J + 1] then
          Lcs[I][J] := Lcs[I + 1][J]
        else
          Lcs[I][J] := Lcs[I][J + 1];
    I := 0;
    J := 0;
    Added := 0;
    Removed := 0;
    while (I < OldCount) or (J < NewCount) do begin
      if (I < OldCount) and (J < NewCount) and
         (BeforeLines[I] = AfterLines[J]) then begin
        DiffLines.Add('  ' + BeforeLines[I]);
        Inc(I);
        Inc(J);
      end else if (J < NewCount) and ((I >= OldCount) or
        (Lcs[I][J + 1] >= Lcs[I + 1][J])) then begin
        DiffLines.Add('+ ' + AfterLines[J]);
        Inc(Added);
        Inc(J);
      end else begin
        DiffLines.Add('- ' + BeforeLines[I]);
        Inc(Removed);
        Inc(I);
      end;
    end;
    Summary := '+' + IntToStr(Added) + ' / -' + IntToStr(Removed) + ' lines';
    if (Added = 0) and (Removed = 0) then
      DiffLines.Add('  (No content changes detected)');
    Result := DiffLines.Text;
  finally
    DiffLines.Free;
    AfterLines.Free;
    BeforeLines.Free;
  end;
end;

procedure AddDiffLine(Editor: TRichEdit; const Prefix, Line: String;
  Color: TColor; Bold: Boolean);
begin
  Editor.SelStart := Length(Editor.Text);
  Editor.SelLength := 0;
  Editor.SelAttributes.Color := Color;
  if Bold then Editor.SelAttributes.Style := [fsBold]
  else Editor.SelAttributes.Style := [];
  Editor.SelText := Prefix + Line + #13#10;
end;

procedure RenderFileDiff(Editor: TRichEdit; const BeforeText, AfterText: String;
  out Summary: String);
var BeforeLines, AfterLines: TStringList; Lcs: TApprovalDiffMatrix;
  I, J, Removed, Added, OldCount, NewCount: Integer; Normalized: String;
begin
  BeforeLines := TStringList.Create;
  AfterLines := TStringList.Create;
  try
    Normalized := StringReplace(BeforeText, #13#10, #10, [rfReplaceAll]);
    Normalized := StringReplace(Normalized, #13, #10, [rfReplaceAll]);
    BeforeLines.Text := StringReplace(Normalized, #10, #13#10, [rfReplaceAll]);
    Normalized := StringReplace(AfterText, #13#10, #10, [rfReplaceAll]);
    Normalized := StringReplace(Normalized, #13, #10, [rfReplaceAll]);
    AfterLines.Text := StringReplace(Normalized, #10, #13#10, [rfReplaceAll]);
    OldCount := BeforeLines.Count;
    NewCount := AfterLines.Count;
    Editor.Clear;
    Added := 0;
    Removed := 0;
    if (OldCount + 1) > 4000000 div (NewCount + 1) then begin
      Summary := AgentUiText(#$E5#$A4#$A7#$E6#$96#$87#$E4#$BB#$B6#$EF#$BC#$9A#$E4#$B8#$BA#$E4#$BF#$9D#$E6#$8C#$81#$E5#$AE#$A1#$E9#$98#$85#$E6#$B5#$81#$E7#$95#$85#$EF#$BC#$8C#$E5#$B7#$B2#$E8#$B7#$B3#$E8#$BF#$87#$E9#$80#$90#$E8#$A1#$8C#$E6#$AF#$94#$E8#$BE#$83#$E3#$80#$82);
      Editor.SelAttributes.Color := clGrayText;
      Editor.Lines.Add(Summary);
      Editor.Lines.Add(AgentUiText(#$E6#$8B#$9F#$E5#$86#$99#$E5#$85#$A5#$E7#$9A#$84#$E6#$96#$87#$E4#$BB#$B6#$E5#$86#$85#$E5#$AE#$B9#$EF#$BC#$9A));
      Editor.Lines.Add('');
      Editor.Lines.Add(AfterText);
      Exit;
    end;

    SetLength(Lcs, OldCount + 1);
    for I := 0 to OldCount do SetLength(Lcs[I], NewCount + 1);
    for I := OldCount - 1 downto 0 do
      for J := NewCount - 1 downto 0 do
        if BeforeLines[I] = AfterLines[J] then
          Lcs[I][J] := Lcs[I + 1][J + 1] + 1
        else if Lcs[I + 1][J] >= Lcs[I][J + 1] then
          Lcs[I][J] := Lcs[I + 1][J]
        else
          Lcs[I][J] := Lcs[I][J + 1];

    I := 0;
    J := 0;
    while (I < OldCount) or (J < NewCount) do begin
      if (I < OldCount) and (J < NewCount) and
         (BeforeLines[I] = AfterLines[J]) then begin
        AddDiffLine(Editor, '  ', BeforeLines[I], clGrayText, False);
        Inc(I);
        Inc(J);
      end else if (J < NewCount) and ((I >= OldCount) or
        (Lcs[I][J + 1] >= Lcs[I + 1][J])) then begin
        AddDiffLine(Editor, '+ ', AfterLines[J], RGB(0, 128, 0), False);
        Inc(Added);
        Inc(J);
      end else begin
        AddDiffLine(Editor, '- ', BeforeLines[I], clRed, False);
        Inc(Removed);
        Inc(I);
      end;
    end;
    Summary := AgentUiText(#$E6#$96#$B0#$E5#$A2#$9E#$20) + IntToStr(Added) +
      AgentUiText(#$20#$E8#$A1#$8C#$20#$C2#$B7#$20#$E5#$88#$A0#$E9#$99#$A4#$20) +
      IntToStr(Removed) + AgentUiText(#$20#$E8#$A1#$8C);
    if (Added = 0) and (Removed = 0) then
      AddDiffLine(Editor, '  ', AgentUiText(#$E6#$9C#$AA#$E6#$A3#$80#$E6#$B5#$8B#$E5#$88#$B0#$E5#$86#$85#$E5#$AE#$B9#$E5#$B7#$AE#$E5#$BC#$82), clGrayText, False);
    Editor.SelStart := 0;
    Editor.SelLength := 0;
  finally
    AfterLines.Free;
    BeforeLines.Free;
  end;
end;

function PrettyApprovalInput(const ToolName, WorkDir, InputJSON: String):
  String;
var Node: TlkJSONbase; Target, Command, Content, OldText,
  NewText: WideString;
begin
  Result := '';
  Node := nil;
  try
    // InputJSON is already UTF-8 as emitted by the agent protocol.
    try Node := TlkJSON.ParseText(InputJSON); except Node := nil; end;
    Target := JsonField(Node, 'file_path');
    if Target = '' then Target := JsonField(Node, 'path');
    Command := JsonField(Node, 'command');
    Content := JsonField(Node, 'content');
    OldText := JsonField(Node, 'old_string');
    NewText := JsonField(Node, 'new_string');
    if Target <> '' then begin
      Result := AgentUiText(#$E7#$9B#$AE#$E6#$A0#$87#$E6#$96#$87#$E4#$BB#$B6#$EF#$BC#$9A) + #13#10 + String(UTF8Decode(UTF8Encode(Target))) +
        #13#10#13#10 + AgentUiText(#$E5#$B7#$A5#$E4#$BD#$9C#$E7#$9B#$AE#$E5#$BD#$95) + ':' + #13#10 + WorkDir;
      if Command = '' then begin
        if SameText(ToolName, 'Write') then
          Result := Result + #13#10#13#10 + AgentUiText(#$E5#$86#$99#$E5#$85#$A5#$E5#$86#$85#$E5#$AE#$B9#$EF#$BC#$9A) + #13#10 +
            String(UTF8Decode(UTF8Encode(Content)))
        else if SameText(ToolName, 'Edit') then
          Result := Result + #13#10#13#10 + AgentUiText(#$E6#$9B#$BF#$E6#$8D#$A2#$E5#$86#$85#$E5#$AE#$B9#$EF#$BC#$9A) + #13#10 +
            String(UTF8Decode(UTF8Encode(OldText))) + #13#10#13#10 +
            AgentUiText(#$E6#$9B#$BF#$E6#$8D#$A2#$E4#$B8#$BA#$EF#$BC#$9A) + #13#10 + String(UTF8Decode(UTF8Encode(NewText)));
      end;
    end else if Command <> '' then
      Result := AgentUiText(#$E5#$91#$BD#$E4#$BB#$A4#$EF#$BC#$9A) + #13#10 + String(UTF8Decode(UTF8Encode(Command))) +
        #13#10#13#10 + AgentUiText(#$E5#$B7#$A5#$E4#$BD#$9C#$E7#$9B#$AE#$E5#$BD#$95) + ':' + #13#10 + WorkDir
    else if Node <> nil then
      Result := String(UTF8Decode(TLKJSON.GenerateText(Node)));
    if (Result = '') and (InputJSON <> '') then
      Result := String(UTF8Decode(InputJSON));
  finally
    Node.Free;
  end;
end;

function RequestAgentApproval(const ToolName, WorkDir, InputJSON: String): Boolean;
var
  Dialog: TForm;
  Heading, TargetLabel, PreviewLabel: TLabel;
  Details: TMemo;
  Diff: TRichEdit;
  DenyButton, AllowButton: TButton;
  PrettyText, FileName, BeforeText, AfterText, ErrorText, Summary: String;
  P: Integer;
  HasPreview, IsNewFile: Boolean;
begin
  HasPreview := BuildFilePreview(ToolName, WorkDir, InputJSON, FileName,
    BeforeText, AfterText, ErrorText, IsNewFile);
  Dialog := TForm.CreateNew(nil);
  try
    Dialog.Caption := AgentUiText(#$41#$49#$20#$E6#$93#$8D#$E4#$BD#$9C#$E5#$AE#$A1#$E6#$89#$B9);
    Dialog.Position := poScreenCenter;
    Dialog.BorderStyle := bsSizeable;
    Dialog.ClientWidth := 880;
    Dialog.ClientHeight := 620;
    Dialog.Constraints.MinWidth := 700;
    Dialog.Constraints.MinHeight := 500;
    Dialog.Font.Name := 'Segoe UI';
    Dialog.Font.Size := 10;
    Heading := TLabel.Create(Dialog);
    Heading.Parent := Dialog;
    Heading.SetBounds(20, 16, 840, 27);
    Heading.AutoSize := False;
    Heading.Font.Style := [fsBold];
    Heading.Font.Size := 12;
    if HasPreview then
      Heading.Caption := AgentUiText(#$E8#$AF#$B7#$E5#$AE#$A1#$E9#$98#$85#$E5#$8D#$B3#$E5#$B0#$86#$E5#$BA#$94#$E7#$94#$A8#$E7#$9A#$84#$E6#$96#$87#$E4#$BB#$B6#$E5#$8F#$98#$E6#$9B#$B4)
    else
      Heading.Caption := AgentUiText(#$E8#$AF#$B7#$E7#$A1#$AE#$E8#$AE#$A4#$E4#$BB#$A5#$E4#$B8#$8B#$E6#$93#$8D#$E4#$BD#$9C);
    TargetLabel := TLabel.Create(Dialog);
    TargetLabel.Parent := Dialog;
    TargetLabel.SetBounds(20, 48, 840, 46);
    TargetLabel.AutoSize := False;
    TargetLabel.WordWrap := True;
    Details := nil;
    Diff := nil;
    if HasPreview then begin
      TargetLabel.Caption := ApprovalToolName(ToolName) + '  |  ' + FileName + #13#10 +
        AgentUiText(#$E5#$B7#$A5#$E4#$BD#$9C#$E7#$9B#$AE#$E5#$BD#$95) + ': ' + WorkDir;
      PreviewLabel := TLabel.Create(Dialog);
      PreviewLabel.Parent := Dialog;
      PreviewLabel.SetBounds(20, 98, 840, 22);
      PreviewLabel.AutoSize := False;
      PreviewLabel.Font.Style := [fsBold];
      Diff := TRichEdit.Create(Dialog);
      Diff.Parent := Dialog;
      Diff.SetBounds(20, 122, 840, 420);
      Diff.Anchors := [akLeft, akTop, akRight, akBottom];
      Diff.ReadOnly := True;
      Diff.PlainText := True;
      Diff.ScrollBars := ssBoth;
      Diff.WordWrap := False;
      Diff.Font.Name := 'Consolas';
      Diff.Font.Size := 10;
      Diff.Color := clWindow;
      RenderFileDiff(Diff, BeforeText, AfterText, Summary);
      if IsNewFile then PreviewLabel.Caption := AgentUiText(#$E6#$96#$B0#$E5#$BB#$BA#$E6#$96#$87#$E4#$BB#$B6) + '  |  ' + Summary
      else PreviewLabel.Caption := Summary;
    end else begin
      TargetLabel.Caption := ApprovalToolName(ToolName) + '  |  ' + WorkDir;
      Details := TMemo.Create(Dialog);
      Details.Parent := Dialog;
      Details.SetBounds(20, 106, 840, 436);
      Details.Anchors := [akLeft, akTop, akRight, akBottom];
      Details.ReadOnly := True;
      Details.ScrollBars := ssBoth;
      Details.WordWrap := True;
      Details.Font.Name := 'Consolas';
      PrettyText := PrettyApprovalInput(ToolName, WorkDir, InputJSON);
      P := Pos(AgentUiText(#$E7#$9B#$AE#$E6#$A0#$87#$E6#$96#$87#$E4#$BB#$B6#$EF#$BC#$9A) + #13#10, PrettyText);
      if P > 0 then begin
        Delete(PrettyText, 1, P + Length(AgentUiText(#$E7#$9B#$AE#$E6#$A0#$87#$E6#$96#$87#$E4#$BB#$B6#$EF#$BC#$9A) + #13#10) - 1);
        P := Pos(#13#10, PrettyText);
        if P > 0 then begin
          TargetLabel.Caption := ApprovalToolName(ToolName) + '  |  ' + Copy(PrettyText, 1, P - 1);
          Delete(PrettyText, 1, P + 1);
        end;
      end;
      if ErrorText <> '' then
        PrettyText := AgentUiText(#$E6#$96#$87#$E4#$BB#$B6#$E5#$B7#$AE#$E5#$BC#$82#$E9#$A2#$84#$E8#$A7#$88#$E4#$B8#$8D#$E5#$8F#$AF#$E7#$94#$A8#$EF#$BC#$9A) + ErrorText + #13#10#13#10 +
          PrettyText;
      Details.Text := PrettyText;
    end;
    DenyButton := TButton.Create(Dialog);
    DenyButton.Parent := Dialog;
    DenyButton.SetBounds(644, 566, 104, 30);
    DenyButton.Anchors := [akRight, akBottom];
    DenyButton.Caption := AgentUiText(#$E6#$8B#$92#$E7#$BB#$9D);
    DenyButton.ModalResult := mrNo;
    DenyButton.Cancel := True;
    AllowButton := TButton.Create(Dialog);
    AllowButton.Parent := Dialog;
    AllowButton.SetBounds(756, 566, 104, 30);
    AllowButton.Anchors := [akRight, akBottom];
    AllowButton.Caption := AgentUiText(#$E5#$85#$81#$E8#$AE#$B8#$E4#$B8#$80#$E6#$AC#$A1);
    AllowButton.ModalResult := mrYes;
    AllowButton.Default := True;
    Result := Dialog.ShowModal = mrYes;
  finally
    Dialog.Free;
  end;
end;

constructor TAgentQuestionEntry.Create;
begin
  inherited Create;
  Labels := TStringList.Create;
  OtherIndex := -1;
end;

destructor TAgentQuestionEntry.Destroy;
begin
  Labels.Free;
  inherited Destroy;
end;

destructor TAgentQuestionDialog.Destroy;
var I: Integer;
begin
  if Assigned(Entries) then begin
    for I := 0 to Entries.Count - 1 do TObject(Entries[I]).Free;
    Entries.Free;
  end;
  inherited Destroy;
end;

procedure TAgentQuestionDialog.AcceptAnswers(Sender: TObject);
var I, J, SelectedCount: Integer; Entry: TAgentQuestionEntry;
  Answer: WideString; Answers: TlkJSONobject;
begin
  Answers := TlkJSONobject.Create;
  try
    for I := 0 to Entries.Count - 1 do begin
      Entry := TAgentQuestionEntry(Entries[I]);
      Answer := '';
      SelectedCount := 0;
      for J := 0 to Entry.ChoiceList.Items.Count - 1 do
        if Entry.ChoiceList.Selected[J] then begin
          Inc(SelectedCount);
          if J = Entry.OtherIndex then begin
            if Trim(Entry.CustomAnswer.Text) = '' then begin
              MessageDlg(AgentUiText(#$E8#$AF#$B7#$E8#$BE#$93#$E5#$85#$A5#$E9#$97#$AE#$E9#$A2#$98#$20) + IntToStr(I + 1) + AgentUiText(#$20#$E7#$9A#$84#$E8#$87#$AA#$E5#$AE#$9A#$E4#$B9#$89#$E7#$AD#$94#$E6#$A1#$88#$E3#$80#$82), mtInformation, [mbOK], 0);
              Entry.CustomAnswer.SetFocus;
              Exit;
            end;
            if Answer <> '' then Answer := Answer + ', ';
            Answer := Answer + UTF8Decode(UTF8Encode(Entry.CustomAnswer.Text));
          end else begin
            if Answer <> '' then Answer := Answer + ', ';
            Answer := Answer + UTF8Decode(Entry.Labels[J]);
          end;
        end;
      if SelectedCount = 0 then begin
        MessageDlg(AgentUiText(#$E8#$AF#$B7#$E5#$9B#$9E#$E7#$AD#$94#$E6#$89#$80#$E6#$9C#$89#$E9#$97#$AE#$E9#$A2#$98#$E5#$90#$8E#$E5#$86#$8D#$E6#$8F#$90#$E4#$BA#$A4#$E3#$80#$82), mtInformation, [mbOK], 0);
        Entry.ChoiceList.SetFocus;
        Exit;
      end;
      Answers.Add(Entry.Question, TlkJSONstring.Generate(Answer));
    end;
    AnswersJSON := TlkJSON.GenerateText(Answers);
    ModalResult := mrYes;
  finally
    Answers.Free;
  end;
end;

function RequestAgentQuestion(const InputJSON: String;
  out AnswersJSON: String): Boolean;
var InputNode, Questions, QuestionNode, Options, OptionNode: TlkJSONbase;
  Dialog: TAgentQuestionDialog; Scroll: TScrollBox; Entry: TAgentQuestionEntry;
  Group: TGroupBox; Heading, Prompt: TLabel; Button: TButton;
  I, J, Y, ListHeight, GroupHeight: Integer; LabelText, Description,
  CaptionText: WideString;
begin
  Result := False;
  AnswersJSON := '';
  InputNode := nil;
  try
    // InputJSON is already UTF-8 as emitted by the agent protocol.
    try InputNode := TlkJSON.ParseText(InputJSON); except InputNode := nil; end;
    if not (InputNode is TlkJSONobject) then Exit;
    Questions := InputNode.Field['questions'];
    if not (Questions is TlkJSONlist) or (Questions.Count < 1) or
       (Questions.Count > 4) then Exit;
    Dialog := TAgentQuestionDialog.CreateNew(nil);
    try
      Dialog.Caption := AgentUiText(#$E5#$9B#$9E#$E7#$AD#$94#$20#$41#$49#$20#$E7#$9A#$84#$E9#$97#$AE#$E9#$A2#$98);
      Dialog.Position := poScreenCenter;
      Dialog.BorderStyle := bsDialog;
      Dialog.ClientWidth := 740;
      Dialog.ClientHeight := 560;
      Dialog.Font.Name := 'Segoe UI';
      Dialog.Font.Size := 10;
      Dialog.Entries := TList.Create;
      Heading := TLabel.Create(Dialog);
      Heading.Parent := Dialog;
      Heading.SetBounds(20, 14, 700, 28);
      Heading.AutoSize := False;
      Heading.Font.Style := [fsBold];
      Heading.Font.Size := 12;
      Heading.Caption := AgentUiText(#$41#$49#$20#$E9#$9C#$80#$E8#$A6#$81#$E8#$A1#$A5#$E5#$85#$85#$E4#$BF#$A1#$E6#$81#$AF#$E6#$89#$8D#$E8#$83#$BD#$E7#$BB#$A7#$E7#$BB#$AD);
      Scroll := TScrollBox.Create(Dialog);
      Scroll.Parent := Dialog;
      Scroll.SetBounds(20, 50, 700, 438);
      Scroll.Anchors := [akLeft, akTop, akRight, akBottom];
      Scroll.HorzScrollBar.Visible := False;
      Y := 8;
      for I := 0 to Questions.Count - 1 do begin
        QuestionNode := Questions.Child[I];
        if not (QuestionNode is TlkJSONobject) then Exit;
        Entry := TAgentQuestionEntry.Create;
        Entry.Question := JsonField(QuestionNode, 'question');
        Entry.MultiSelect := SameText(String(JsonField(QuestionNode, 'multiSelect')), 'true');
        Options := QuestionNode.Field['options'];
        if (Entry.Question = '') or not (Options is TlkJSONlist) or
           (Options.Count < 2) or (Options.Count > 4) then begin
          Entry.Free;
          Exit;
        end;
        Group := TGroupBox.Create(Scroll);
        Group.Parent := Scroll;
        LabelText := JsonField(QuestionNode, 'header');
        if LabelText = '' then LabelText := AgentUiText(#$E9#$97#$AE#$E9#$A2#$98#$20) + IntToStr(I + 1);
        Group.Caption := String(UTF8Decode(UTF8Encode(LabelText)));
        ListHeight := (Options.Count + 1) * 22 + 6;
        if ListHeight > 112 then ListHeight := 112;
        GroupHeight := 112 + ListHeight;
        Group.SetBounds(8, Y, 660, GroupHeight);
        Prompt := TLabel.Create(Group);
        Prompt.Parent := Group;
        Prompt.SetBounds(12, 20, 630, 36);
        Prompt.AutoSize := False;
        Prompt.WordWrap := True;
        Prompt.Caption := String(UTF8Decode(UTF8Encode(Entry.Question)));
        Entry.ChoiceList := TListBox.Create(Group);
        Entry.ChoiceList.Parent := Group;
        Entry.ChoiceList.SetBounds(12, 58, 630, ListHeight);
        Entry.ChoiceList.MultiSelect := Entry.MultiSelect;
        Entry.ChoiceList.ExtendedSelect := False;
        for J := 0 to Options.Count - 1 do begin
          OptionNode := Options.Child[J];
          LabelText := JsonField(OptionNode, 'label');
          Description := JsonField(OptionNode, 'description');
          if LabelText = '' then LabelText := AgentUiText(#$E9#$80#$89#$E9#$A1#$B9#$20) + IntToStr(J + 1);
          Entry.Labels.Add(UTF8Encode(LabelText));
          CaptionText := LabelText;
          if Description <> '' then CaptionText := CaptionText + '  -  ' + Description;
          Entry.ChoiceList.Items.Add(String(UTF8Decode(UTF8Encode(CaptionText))));
        end;
        Entry.OtherIndex := Entry.ChoiceList.Items.Add(AgentUiText(#$E5#$85#$B6#$E4#$BB#$96#$EF#$BC#$88#$E8#$87#$AA#$E5#$AE#$9A#$E4#$B9#$89#$E5#$9B#$9E#$E7#$AD#$94#$EF#$BC#$89));
        Entry.CustomAnswer := TEdit.Create(Group);
        Entry.CustomAnswer.Parent := Group;
        Entry.CustomAnswer.SetBounds(12, 58 + ListHeight + 4, 630, 23);
        Entry.CustomAnswer.Anchors := [akLeft, akTop, akRight];
        Entry.CustomAnswer.Text := '';
        Entry.CustomAnswer.Enabled := True;
        Entry.ChoiceList.Tag := I;
        Group.Tag := I;
        Dialog.Entries.Add(Entry);
        Inc(Y, GroupHeight + 8);
      end;
      Button := TButton.Create(Dialog);
      Button.Parent := Dialog;
      Button.SetBounds(492, 510, 104, 30);
      Button.Anchors := [akRight, akBottom];
      Button.Caption := AgentUiText(#$E5#$8F#$96#$E6#$B6#$88);
      Button.ModalResult := mrCancel;
      Button.Cancel := True;
      Button := TButton.Create(Dialog);
      Button.Parent := Dialog;
      Button.SetBounds(608, 510, 112, 30);
      Button.Anchors := [akRight, akBottom];
      Button.Caption := AgentUiText(#$E6#$8F#$90#$E4#$BA#$A4#$E5#$9B#$9E#$E7#$AD#$94);
      Button.OnClick := Dialog.AcceptAnswers;
      Button.Default := True;
      Result := (Dialog.ShowModal = mrYes);
      if Result then AnswersJSON := Dialog.AnswersJSON;
    finally
      Dialog.Free;
    end;
  finally
    InputNode.Free;
  end;
end;

end.
