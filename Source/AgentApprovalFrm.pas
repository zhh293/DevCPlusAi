unit AgentApprovalFrm;
interface
uses Windows, SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls, Dialogs, Graphics;
function RequestAgentApproval(const ToolName, WorkDir, InputJSON: String): Boolean;
function RequestAgentQuestion(const InputJSON: String;
  out AnswersJSON: String): Boolean;
implementation
uses uLkJSON, Variants;

type
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

function PrettyApprovalInput(const ToolName, WorkDir, InputJSON: String):
  String;
var Node: TlkJSONbase; Target, Command, Content, OldText,
  NewText: WideString;
begin
  Result := '';
  Node := nil;
  try
    try Node := TlkJSON.ParseText(UTF8Encode(InputJSON)); except Node := nil; end;
    Target := JsonField(Node, 'file_path');
    if Target = '' then Target := JsonField(Node, 'path');
    Command := JsonField(Node, 'command');
    Content := JsonField(Node, 'content');
    OldText := JsonField(Node, 'old_string');
    NewText := JsonField(Node, 'new_string');
    if Target <> '' then begin
      Result := 'Target file:' + #13#10 + String(UTF8Decode(UTF8Encode(Target))) +
        #13#10#13#10 + 'Working directory:' + #13#10 + WorkDir;
      if Command = '' then begin
        if SameText(ToolName, 'Write') then
          Result := Result + #13#10#13#10 + 'Content to write:' + #13#10 +
            String(UTF8Decode(UTF8Encode(Content)))
        else if SameText(ToolName, 'Edit') then
          Result := Result + #13#10#13#10 + 'Replace this:' + #13#10 +
            String(UTF8Decode(UTF8Encode(OldText))) + #13#10#13#10 +
            'With this:' + #13#10 + String(UTF8Decode(UTF8Encode(NewText)));
      end;
    end else if Command <> '' then
      Result := 'Command:' + #13#10 + String(UTF8Decode(UTF8Encode(Command))) +
        #13#10#13#10 + 'Working directory:' + #13#10 + WorkDir
    else if Node <> nil then
      Result := String(UTF8Decode(UTF8Encode(TLKJSON.GenerateText(Node))));
    if (Result = '') and (InputJSON <> '') then
      Result := String(UTF8Decode(InputJSON));
  finally
    Node.Free;
  end;
end;

function RequestAgentApproval(const ToolName, WorkDir, InputJSON: String): Boolean;
var
  Dialog: TForm;
  Heading, TargetLabel: TLabel;
  Details: TMemo;
  DenyButton, AllowButton: TButton;
  PrettyText: String;
  P: Integer;
begin
  Dialog := TForm.CreateNew(nil);
  try
    Dialog.Caption := 'Review tool operation';
    Dialog.Position := poScreenCenter;
    Dialog.BorderStyle := bsDialog;
    Dialog.ClientWidth := 720;
    Dialog.ClientHeight := 520;
    Dialog.Font.Name := 'Segoe UI';
    Dialog.Font.Size := 10;
    Heading := TLabel.Create(Dialog);
    Heading.Parent := Dialog;
    Heading.SetBounds(20, 16, 680, 27);
    Heading.AutoSize := False;
    Heading.Font.Style := [fsBold];
    Heading.Font.Size := 12;
    Heading.Caption := 'Review this operation before it runs';
    TargetLabel := TLabel.Create(Dialog);
    TargetLabel.Parent := Dialog;
    TargetLabel.SetBounds(20, 48, 680, 40);
    TargetLabel.AutoSize := False;
    TargetLabel.WordWrap := True;
    TargetLabel.Caption := ToolName + '  |  ' + WorkDir;
    Details := TMemo.Create(Dialog);
    Details.Parent := Dialog;
    Details.SetBounds(20, 96, 680, 354);
    Details.Anchors := [akLeft, akTop, akRight, akBottom];
    Details.ReadOnly := True;
    Details.ScrollBars := ssBoth;
    Details.WordWrap := True;
    Details.Font.Name := 'Consolas';
    PrettyText := PrettyApprovalInput(ToolName, WorkDir, InputJSON);
    P := Pos('Target file:' + #13#10, PrettyText);
    if P > 0 then begin
      Delete(PrettyText, 1, P + Length('Target file:' + #13#10) - 1);
      P := Pos(#13#10, PrettyText);
      if P > 0 then begin
        TargetLabel.Caption := ToolName + '  |  ' + Copy(PrettyText, 1, P - 1);
        Delete(PrettyText, 1, P + 1);
      end;
    end;
    Details.Text := PrettyText;
    DenyButton := TButton.Create(Dialog);
    DenyButton.Parent := Dialog;
    DenyButton.SetBounds(484, 472, 104, 30);
    DenyButton.Anchors := [akRight, akBottom];
    DenyButton.Caption := 'Deny';
    DenyButton.ModalResult := mrNo;
    DenyButton.Cancel := True;
    AllowButton := TButton.Create(Dialog);
    AllowButton.Parent := Dialog;
    AllowButton.SetBounds(596, 472, 104, 30);
    AllowButton.Anchors := [akRight, akBottom];
    AllowButton.Caption := 'Allow once';
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
              MessageDlg('Enter a custom answer for question ' + IntToStr(I + 1) + '.', mtInformation, [mbOK], 0);
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
        MessageDlg('Please answer every question before submitting.', mtInformation, [mbOK], 0);
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
    try InputNode := TlkJSON.ParseText(UTF8Encode(InputJSON)); except InputNode := nil; end;
    if not (InputNode is TlkJSONobject) then Exit;
    Questions := InputNode.Field['questions'];
    if not (Questions is TlkJSONlist) or (Questions.Count < 1) or
       (Questions.Count > 4) then Exit;
    Dialog := TAgentQuestionDialog.CreateNew(nil);
    try
      Dialog.Caption := 'Answer the AI questions';
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
      Heading.Caption := 'The AI needs your input to continue';
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
        if LabelText = '' then LabelText := 'Question ' + IntToStr(I + 1);
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
          if LabelText = '' then LabelText := 'Option ' + IntToStr(J + 1);
          Entry.Labels.Add(UTF8Encode(LabelText));
          CaptionText := LabelText;
          if Description <> '' then CaptionText := CaptionText + '  -  ' + Description;
          Entry.ChoiceList.Items.Add(String(UTF8Decode(UTF8Encode(CaptionText))));
        end;
        Entry.OtherIndex := Entry.ChoiceList.Items.Add('Other (custom answer)');
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
      Button.Caption := 'Cancel';
      Button.ModalResult := mrCancel;
      Button.Cancel := True;
      Button := TButton.Create(Dialog);
      Button.Parent := Dialog;
      Button.SetBounds(608, 510, 112, 30);
      Button.Anchors := [akRight, akBottom];
      Button.Caption := 'Submit answers';
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
