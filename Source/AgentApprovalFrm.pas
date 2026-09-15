unit AgentApprovalFrm;
interface
uses Windows, SysUtils, Classes, Controls, Forms, StdCtrls, ExtCtrls;
function RequestAgentApproval(const ToolName, WorkDir, InputJSON: String): Boolean;
implementation
function RequestAgentApproval(const ToolName, WorkDir, InputJSON: String): Boolean;
var
  Dialog: TForm;
  Header: TLabel;
  Details: TMemo;
  Button: TButton;
begin
  Dialog := TForm.CreateNew(nil);
  try
    Dialog.Caption := 'AI tool approval';
    Dialog.Position := poScreenCenter;
    Dialog.BorderStyle := bsDialog;
    Dialog.ClientWidth := 620;
    Dialog.ClientHeight := 400;
    Dialog.Font.Name := 'Tahoma';
    Dialog.Font.Size := 10;
    Header := TLabel.Create(Dialog);
    Header.Parent := Dialog;
    Header.SetBounds(16, 16, 584, 56);
    Header.AutoSize := False;
    Header.WordWrap := True;
    Header.Caption := 'Allow this operation once?' + #13#10 + ToolName + '  |  ' + WorkDir;
    Details := TMemo.Create(Dialog);
    Details.Parent := Dialog;
    Details.SetBounds(16, 80, 588, 260);
    Details.ReadOnly := True;
    Details.ScrollBars := ssBoth;
    Details.WordWrap := False;
    Details.Text := String(UTF8Decode(InputJSON));
    Button := TButton.Create(Dialog);
    Button.Parent := Dialog;
    Button.SetBounds(388, 356, 104, 28);
    Button.Caption := 'Deny';
    Button.ModalResult := mrNo;
    Button.Cancel := True;
    Button.Default := True;
    Button := TButton.Create(Dialog);
    Button.Parent := Dialog;
    Button.SetBounds(500, 356, 104, 28);
    Button.Caption := 'Allow once';
    Button.ModalResult := mrYes;
    Result := Dialog.ShowModal = mrYes;
  finally
    Dialog.Free;
  end;
end;
end.
