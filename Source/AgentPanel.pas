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

    AgentPanel.pas

    Owns conversation state, host actions and the WebView chat surface.
    AgentPanelWeb.inc dispatches browser actions on the VCL thread.
}
unit AgentPanel;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms,
  StdCtrls, ComCtrls, ExtCtrls, RichEdit, Dialogs, Clipbrd, JPEG, Menus,
  AgentProcess, AgentProtocol, AgentTimeline, AgentUITheme, AgentWebView,
  AgentWorkspaceWatch, AgentFileUndo;

type
  TAgentSessionAction = procedure(Sender: TObject; const Action, Key, Title: String) of object;
  TAgentInsertCode = procedure(Sender: TObject; const Code: String) of object;
  TAgentUndoFileCheck = function(Sender: TObject;
    const FileName: String): Boolean of object;
  TAgentFileRestored = procedure(Sender: TObject;
    const FileName: String) of object;
  TAgentPermissionModeChange = function(Sender: TObject; const Mode: String;
    out ErrorText: String): Boolean of object;
  TAgentStatus = (
    asReady,        // ready / idle
    asThinking,     // waiting for the model
    asExecuting,    // running a tool
    asError,        // error state
    asDisconnected  // process not running / not configured
  );

  TAgentPanelFrame = class(TFrame)
    StatusBar: TStatusBar;
    pnlHeader: TPanel;
    pnlChat: TPanel;
    pnlSendTools: TPanel;
    lblTitle: TLabel;
    lblSendHint: TLabel;
    btnSettings: TButton;
    reChat: TRichEdit;
    pnlInput: TPanel;
    pnlAttachments: TPanel;
    pnlAttachmentTools: TPanel;
    lbAttachments: TListBox;
    memoInput: TMemo;
    btnSend: TButton;
    btnStop: TButton;
    btnAttach: TButton;
    btnPasteImage: TButton;
    btnRemoveAttachment: TButton;
    procedure btnSettingsClick(Sender: TObject);
    procedure btnSendClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnAttachClick(Sender: TObject);
    procedure btnPasteImageClick(Sender: TObject);
    procedure btnRemoveAttachmentClick(Sender: TObject);
    procedure memoInputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure reChatKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  private
    fAgentProcess: TAgentProcess;
    fWeb: TAgentWebView;
    fWebTimer: TTimer;
    fWebCache, fWebQueue: TStringList;
    fWebStarted: Boolean;
    fWebFailed: Boolean;
    fWebScriptReady, fWebAppReady: Boolean;
    fWebErrorText: String;
    fWebStartTick: DWORD;
    fWebRetry: TButton;
    fWebDiagnostics: TButton;
    fWebGeneration: Integer;
    fWebTimelineRevision: Integer;
    fWebState, fWebDraft: String;
    fWebCode: String;
    fOnSessionAction: TAgentSessionAction;
    procedure WebTick(Sender: TObject);
    procedure WebReady(Sender: TObject);
    procedure WebMessage(Sender: TObject; const Text: WideString);
    procedure WebError(Sender: TObject; const Text: WideString);
    procedure WebDispatch(const Text: WideString);
    procedure WebSync;
    procedure RetryWeb(Sender: TObject);
    procedure CopyWebDiagnostics(Sender: TObject);
  private
    fOnPrepareContext: TNotifyEvent;
    fOnQuickAction: TNotifyEvent;
    fOnOpenCode: TNotifyEvent;
    fOnOpenFile: TAgentOpenFile;
    fOnInsertCode: TAgentInsertCode;
    fOnUndoFileCheck: TAgentUndoFileCheck;
    fOnFileRestored: TAgentFileRestored;
    fQuickActions: TComboBox;
    fDetails: TCheckBox;
    fLastAnswer: String;
    fConversationTitle: String;
    fSessions: TComboBox;
    fSessionKeys: TStringList;
    fEditPopup: TPopupMenu;
    fPopupTarget: TWinControl;
    fOnSessionChange: TNotifyEvent;
    fTools: TTreeView;
    fTimeline: TAgentTimeline;
    fToolPanel: TPanel;
    fToolToggle: TButton;
    fTextColor: TColor;
    fMutedColor: TColor;
    fErrorColor: TColor;
    fOnSettings: TNotifyEvent;
    fOnPermissionModeChange: TAgentPermissionModeChange;
    fModelBadge: TLabel;
    fScrollBottom: TButton;
    fClearButton: TButton;
    fContextButton: TButton;
    fStatus: TAgentStatus;
    fModelName: String;
    fContextText: String;
    fContextPreviewPayload: String;
    fContextSummary: String;
    fContextEnabled: Boolean;
    fSendOnCtrlEnter: Boolean;
    fAttachments: TStringList;
    fTemporaryAttachments: TStringList;
    fStreamingMessageId: String;
    fStreamingText: String;
    fStreamingActive: Boolean;
    fWaitingForResponse: Boolean;
    fPendingPermissions: TStringList;
    fPendingPermissionTools: TStringList;
    fPendingFileTools: TStringList;
    fPendingFileDiffs: TStringList;
    fPendingFileUndoTokens: TStringList;
    fTurnFilePaths: TStringList;
    fTurnFileStates: TStringList;
    fTurnFileDiffs: TStringList;
    fTurnFileDiffSummaries: TStringList;
    fTurnFileUndoTokens: TStringList;
    fFileUndoManager: TAgentFileUndoManager;
    fWorkspaceWatcher: TAgentWorkspaceWatcher;
    fOnRequestStarted: TNotifyEvent;
    fOnRequestEnded: TNotifyEvent;
    procedure EditPopupOpen(Sender: TObject);
    procedure EditPopupClick(Sender: TObject);
    procedure SessionChange(Sender: TObject);
    procedure NewSessionClick(Sender: TObject);
    procedure ToggleTools(Sender: TObject);
    procedure AddToolEvent(const Event: TAgentEvent);
    procedure ResetTurnFileOperations;
    procedure TrackTurnFileOperation(const Event: TAgentEvent);
    procedure AppendTurnFileOperationSummary;
    procedure UndoFileChange(const Token: String);
    procedure TimelineOpenFile(Sender: TObject; const FileName: String);
    procedure OpenChangedFile(const FileName: String);
    procedure QuickActionClick(Sender: TObject);
    procedure CopyAnswerClick(Sender: TObject);
    procedure OpenCodeClick(Sender: TObject);
    procedure UpdateAttachmentLayout;
    procedure AppendText(const Text: String; Color: TColor; Bold: Boolean);
    procedure AppendTranscript(const Text: String; Color: TColor; Bold: Boolean);
    procedure AppendUserMessageInternal(const Text, ContextSummary,
      ContextPayload: String);
    procedure AppendAITextInternal(const Text: String);
    procedure AppendSystemMessageInternal(const Text: String);
    procedure ResetStreamingDisplay;
    procedure HandleAssistantEvent(const Event: TAgentEvent);
    function EventSummaryText(const Event: TAgentEvent): String;
    function BuildContextPayload: String;
    function BuildMessage(const Text: String; out ContextPayload: String): String;
    function AttachmentSummary: String;
    function AddAttachment(const FileName: String): Boolean;
    procedure AddAttachmentList(Files: TStrings);
    procedure RemoveAttachmentAt(Index: Integer);
    procedure ClearAttachments;
    function SaveClipboardImage: String;
    procedure BeginResponseWait;
    procedure EndResponseWait;
    procedure UpdateStatusText;
    function IsAgentBusy: Boolean;
    procedure ScrollToBottomClick(Sender: TObject);
    procedure ClearChatClick(Sender: TObject);
    procedure PrepareContextClick(Sender: TObject);
    function BuildQuestionInput(const InputJSON, AnswersJSON: String;
      out ErrorText: String): String;
  protected
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Wire the panel to a running agent process.
    property AgentProcess: TAgentProcess read fAgentProcess write fAgentProcess;

    // Event dispatch: render an incoming agent event.
    procedure HandleAgentEvent(const Event: TAgentEvent);

    // Convenience append helpers.
    procedure AppendUserMessage(const Text: String;
      const ContextSummary: String = ''; const ContextPayload: String = '');
    procedure AppendAIText(const Text: String);
    procedure AppendSystemMessage(const Text: String);
    procedure SetContext(const Text, Summary: String);
    procedure SetSendKey(const Value: String);
    procedure SetFontSize(Value: Integer);
    procedure ApplyAppearance(APanelColor, APanelTextColor, AEditorColor,
      ATextColor: TColor; const AFontName: String; AFontSize: Integer);

    // Status / model display.
    procedure SetStatus(Status: TAgentStatus);
    procedure SetModelName(const Name: String);

    procedure ClearChat;
    procedure QueuePermission(const Event: TAgentEvent; const WorkDir: String);
    function ResolvePermission(const RequestId, Decision,
      AnswersJSON: String; const DenyMessage: String = ''): Boolean;
    procedure ExpirePendingPermissions;
    function CanShowInlinePermissions: Boolean;

    // Send the current input box content to the agent.
    procedure SendCurrentInput;
    procedure SendPrompt(const Text: String);

    // Used by the main window's WM_DROPFILES handler when files are dropped
    // over this frame. The list remains pending until the next send.
    procedure AddDroppedFiles(Files: TStrings);

    function HandleEditShortcut(Key: Word; Shift: TShiftState): Boolean;
    function ExecuteEditCommand(Command: Integer; Target: TWinControl): Boolean;
    property Timeline: TAgentTimeline read fTimeline;
    property WebView: TAgentWebView read fWeb;
    property WebAppReady: Boolean read fWebAppReady;
    property ToolTree: TTreeView read fTools;
    property ToolToggle: TButton read fToolToggle;
    property SessionPicker: TComboBox read fSessions;
    procedure ImportConversation(const FileName: String);
    procedure SaveConversation(const Path: String);
    procedure LoadConversation(const Path: String);
    procedure SetSessions(Items: TStrings; const Selected: String);
    function SelectedSession: String;
    property OnSessionChange: TNotifyEvent read fOnSessionChange write fOnSessionChange;
    property OnSessionAction: TAgentSessionAction read fOnSessionAction write fOnSessionAction;
    property ConversationTitle: String read fConversationTitle write fConversationTitle;
    property ContextEnabled: Boolean read fContextEnabled write fContextEnabled;
    function AnswerCode: String;
    property OnOpenCode: TNotifyEvent read fOnOpenCode write fOnOpenCode;
    property OnOpenFile: TAgentOpenFile read fOnOpenFile write fOnOpenFile;
    property OnInsertCode: TAgentInsertCode read fOnInsertCode write fOnInsertCode;
    property OnUndoFileCheck: TAgentUndoFileCheck
      read fOnUndoFileCheck write fOnUndoFileCheck;
    property OnFileRestored: TAgentFileRestored
      read fOnFileRestored write fOnFileRestored;
    property OnPrepareContext: TNotifyEvent read fOnPrepareContext write fOnPrepareContext;
    property OnQuickAction: TNotifyEvent read fOnQuickAction write fOnQuickAction;
    property OnSettings: TNotifyEvent read fOnSettings write fOnSettings;
    property OnPermissionModeChange: TAgentPermissionModeChange
      read fOnPermissionModeChange write fOnPermissionModeChange;
    property Status: TAgentStatus read fStatus;
    property OnRequestStarted: TNotifyEvent read fOnRequestStarted write fOnRequestStarted;
    property OnRequestEnded: TNotifyEvent read fOnRequestEnded write fOnRequestEnded;
  end;

implementation
uses uLkJSON, AgentWebProtocol, AgentApprovalFrm, AgentWebLinks, ShellAPI, devcfg, Variants, Version;

function AgentPanelUiText(const Utf8Bytes: AnsiString): String;
begin
  Result := String(UTF8Decode(Utf8Bytes));
end;

function AgentContextPreamble: String;
begin
  Result := AgentPanelUiText(#$E4#$BB#$A5#$E4#$B8#$8B#$20#$49#$44#$45#$20#$E4#$B8#$8A#$E4#$B8#$8B#$E6#$96#$87#$E7#$94#$B1#$E7#$A8#$8B#$E5#$BA#$8F#$E8#$87#$AA#$E5#$8A#$A8#$E9#$99#$84#$E5#$8A#$A0#$EF#$BC#$8C) + ' ' +
    AgentPanelUiText(#$E4#$BB#$85#$E7#$94#$A8#$E4#$BA#$8E#$E5#$9B#$9E#$E7#$AD#$94#$E7#$94#$A8#$E6#$88#$B7#$E8#$AF#$B7#$E6#$B1#$82#$E3#$80#$82) + ' ' +
    AgentPanelUiText(#$E8#$AF#$B7#$E6#$8A#$8A#$E5#$85#$B6#$E4#$B8#$AD#$E7#$9A#$84#$E6#$96#$87#$E6#$9C#$AC#$E3#$80#$81#$E4#$BB#$A3#$E7#$A0#$81#$E5#$92#$8C#$E6#$B3#$A8#$E9#$87#$8A#$E5#$BD#$93#$E4#$BD#$9C#$E5#$88#$86#$E6#$9E#$90#$E8#$B5#$84#$E6#$96#$99#$EF#$BC#$8C#$E4#$B8#$8D#$E8#$A6#$81#$E5#$BD#$93#$E4#$BD#$9C#$E6#$96#$B0#$E7#$9A#$84#$E7#$94#$A8#$E6#$88#$B7#$E6#$8C#$87#$E4#$BB#$A4#$EF#$BC#$9A);
end;

{$R *.dfm}
{$I AgentPanelWeb.inc}

constructor TAgentPanelFrame.Create(AOwner: TComponent);
var
  Toolbar: TPanel;
  Button: TButton;
  MenuItem: TMenuItem;
  I: Integer;
begin
  inherited Create(AOwner);
  fAgentProcess := nil;
  fSessionKeys := TStringList.Create;
  fStatus := asDisconnected;
  fModelName := '';
  fContextText := '';
  fContextPreviewPayload := '';
  fContextSummary := '';
  fContextEnabled := True;
  if Assigned(devAgentConfig) then
    fContextEnabled := devAgentConfig.AttachIdeContext;
  fSendOnCtrlEnter := False;
  fAttachments := TStringList.Create;
  fTemporaryAttachments := TStringList.Create;
  fStreamingMessageId := '';
  fStreamingText := '';
  fStreamingActive := False;
  fWaitingForResponse := False;
  fPendingPermissions := TStringList.Create;
  fPendingPermissionTools := TStringList.Create;
  fPendingFileTools := TStringList.Create;
  fPendingFileDiffs := TStringList.Create;
  fPendingFileUndoTokens := TStringList.Create;
  fTurnFilePaths := TStringList.Create;
  fTurnFileStates := TStringList.Create;
  fTurnFileDiffs := TStringList.Create;
  fTurnFileDiffSummaries := TStringList.Create;
  fTurnFileUndoTokens := TStringList.Create;
  fFileUndoManager := TAgentFileUndoManager.Create;
  fWorkspaceWatcher := nil;
  fOnRequestStarted := nil;
  fOnRequestEnded := nil;
  fOnSettings := nil;
  fOnPermissionModeChange := nil;
  fModelBadge := TLabel.Create(Self);
  fModelBadge.Parent := pnlHeader;
  fModelBadge.SetBounds(136, 13, 164, 17);
  fModelBadge.Anchors := [akLeft, akTop];
  fModelBadge.AutoSize := False;
  fModelBadge.Caption := 'No model selected';
  fModelBadge.Font.Size := 9;
  ApplyAppearance(clBtnFace, clWindowText, clWindow, clWindowText,
    Font.Name, Font.Size);
  Toolbar := TPanel.Create(Self);
  Toolbar.Parent := Self;
  Toolbar.Align := alTop;
  Toolbar.Top := pnlHeader.Height;
  Toolbar.Height := 94;
  Toolbar.BevelOuter := bvNone;
  Toolbar.ParentColor := True;
  fQuickActions := TComboBox.Create(Self);
  fQuickActions.Parent := Toolbar;
  fQuickActions.SetBounds(8, 2, Width - 96, 24);
  fQuickActions.Anchors := [akLeft, akTop, akRight];
  fQuickActions.Style := csDropDownList;
  fQuickActions.Items.Add('Explain code');
  fQuickActions.Items.Add('Fix code');
  fQuickActions.Items.Add('Improve code');
  fQuickActions.Items.Add('Add comments');
  fQuickActions.Items.Add('Diagnose build errors');
  fQuickActions.Items.Add('Step-by-step learning explanation');
  fQuickActions.ItemIndex := 0;
  Button := TButton.Create(Self);
  Button.Parent := Toolbar;
  Button.SetBounds(Width - 80, 2, 72, 24);
  Button.Anchors := [akTop, akRight];
  Button.Caption := 'Run';
  Button.OnClick := QuickActionClick;
  Button := TButton.Create(Self);
  Button.Parent := Toolbar;
  Button.SetBounds(8, 32, 88, 24);
  Button.Caption := 'Copy answer';
  Button.OnClick := CopyAnswerClick;
  Button := TButton.Create(Self);
  Button.Parent := Toolbar;
  Button.SetBounds(102, 32, 80, 24);
  Button.Caption := 'Open code';
  Button.OnClick := OpenCodeClick;
  fDetails := TCheckBox.Create(Self);
  fDetails.Parent := Toolbar;
  fDetails.SetBounds(192, 34, 72, 20);
  fDetails.Caption := 'Logs';
  fClearButton := TButton.Create(Self);
  fClearButton.Parent := Toolbar;
  fClearButton.SetBounds(270, 32, 64, 24);
  fClearButton.Caption := 'Clear';
  fClearButton.OnClick := ClearChatClick;
  fContextButton := TButton.Create(Self);
  fContextButton.Parent := Toolbar;
  fContextButton.SetBounds(338, 32, 62, 24);
  fContextButton.Caption := 'Context';
  fContextButton.OnClick := PrepareContextClick;
  fSessions := TComboBox.Create(Self);
  fSessions.Parent := Toolbar;
  fSessions.SetBounds(8, 64, Width - 96, 24);
  fSessions.Anchors := [akLeft, akTop, akRight];
  fSessions.Style := csDropDownList;
  fSessions.OnChange := SessionChange;
  Button := TButton.Create(Self);
  Button.Parent := Toolbar;
  Button.SetBounds(Width - 80, 64, 72, 24);
  Button.Anchors := [akTop, akRight];
  Button.Caption := 'New chat';
  Button.OnClick := NewSessionClick;
  fToolPanel := TPanel.Create(Self);
  fToolPanel.Parent := pnlChat;
  fToolPanel.Align := alBottom;
  fToolPanel.Height := 28;
  fToolPanel.BevelOuter := bvNone;
  fToolToggle := TButton.Create(Self);
  fToolToggle.Parent := fToolPanel;
  fToolToggle.SetBounds(0, 0, 200, 26);
  fToolToggle.Caption := '> Tool activity';
  fToolToggle.OnClick := ToggleTools;
  fTools := TTreeView.Create(Self);
  fTools.Parent := fToolPanel;
  fTools.SetBounds(0, 30, pnlChat.ClientWidth - 16, 140);
  fTools.Anchors := [akLeft, akTop, akRight, akBottom];
  fTools.ReadOnly := True;
  fTools.Visible := False;
  fEditPopup := TPopupMenu.Create(Self);
  fEditPopup.OnPopup := EditPopupOpen;
  for I := 0 to 4 do begin
    MenuItem := TMenuItem.Create(fEditPopup);
    case I of
      0: MenuItem.Caption := 'Copy';
      1: MenuItem.Caption := 'Paste';
      2: MenuItem.Caption := 'Cut';
      3: MenuItem.Caption := 'Select all';
      4: MenuItem.Caption := 'Undo';
    end;
    MenuItem.Tag := I;
    MenuItem.OnClick := EditPopupClick;
    fEditPopup.Items.Add(MenuItem);
  end;
  reChat.PopupMenu := fEditPopup;
  memoInput.PopupMenu := fEditPopup;
  fTools.PopupMenu := fEditPopup;
  fTimeline := TAgentTimeline.Create(Self);
  fTimeline.OnOpenFile := TimelineOpenFile;
  fTimeline.Parent := pnlChat;
  fTimeline.Align := alClient;
  fTimeline.PopupMenu := fEditPopup;
  fTimeline.Color := reChat.Color;
  fTimeline.Font.Assign(reChat.Font);
  reChat.Visible := False;
  fScrollBottom := TButton.Create(Self);
  fScrollBottom.Parent := pnlChat;
  fScrollBottom.SetBounds(pnlChat.ClientWidth - 44, pnlChat.ClientHeight - 42, 32, 28);
  fScrollBottom.Anchors := [akRight, akBottom];
  fScrollBottom.Caption := 'v';
  fScrollBottom.Hint := 'Scroll to bottom';
  fScrollBottom.ShowHint := True;
  fScrollBottom.TabStop := False;
  fScrollBottom.Font.Assign(Font);
  fScrollBottom.Font.Color := fMutedColor;
  fScrollBottom.OnClick := ScrollToBottomClick;
  fToolPanel.Visible := False;
  UpdateAttachmentLayout;
  SetStatus(asDisconnected);
  fWebCache := TStringList.Create;
  fWebQueue := TStringList.Create;
  fWebGeneration := -1;
  fWebTimer := TTimer.Create(Self);
  fWebTimer.Interval := 100;
  fWebTimer.OnTimer := WebTick;
  Resize;
end;

destructor TAgentPanelFrame.Destroy;
var
  I: Integer;
begin
  fWaitingForResponse := False;
  if Assigned(fWebTimer) then fWebTimer.Enabled := False;
  if Assigned(fWeb) then fWeb.Stop;
  fWebCache.Free;
  fWebQueue.Free;
  if Assigned(fWorkspaceWatcher) then begin
    fWorkspaceWatcher.Free;
    fWorkspaceWatcher := nil;
  end;
  fPendingPermissions.Free;
  fPendingPermissionTools.Free;
  fPendingFileTools.Free;
  fPendingFileDiffs.Free;
  fPendingFileUndoTokens.Free;
  fTurnFilePaths.Free;
  fTurnFileStates.Free;
  fTurnFileDiffs.Free;
  fTurnFileDiffSummaries.Free;
  fTurnFileUndoTokens.Free;
  fFileUndoManager.Free;
  if fTemporaryAttachments <> nil then
    for I := 0 to fTemporaryAttachments.Count - 1 do
      DeleteFile(fTemporaryAttachments[I]);
  fTemporaryAttachments.Free;
  fSessionKeys.Free;
  fAttachments.Free;
  inherited Destroy;
end;

procedure TAgentPanelFrame.Resize;
var BadgeWidth: Integer;
begin
  inherited Resize;
  if Assigned(fModelBadge) then begin
    BadgeWidth := btnSettings.Left - fModelBadge.Left - 8;
    if BadgeWidth < 40 then begin
      fModelBadge.Visible := False;
    end else begin
      fModelBadge.Visible := True;
      fModelBadge.Width := BadgeWidth;
    end;
  end;
  if Assigned(fClearButton) then
    fClearButton.Visible := ClientWidth >= 340;
  if Assigned(fContextButton) then
    fContextButton.Visible := ClientWidth >= 390;
end;

{ ------------------------------------------------------------------ }
{ RichEdit helpers                                                   }
{ ------------------------------------------------------------------ }

procedure TAgentPanelFrame.AppendText(const Text: String; Color: TColor; Bold: Boolean);
begin
  if Assigned(fTimeline) then fTimeline.AppendText(Text, Color, Bold);
  AppendTranscript(Text, Color, Bold);
end;

procedure TAgentPanelFrame.AppendTranscript(const Text: String; Color: TColor; Bold: Boolean);
var
  OldStart, OldLength: Integer;
begin
  OldStart := reChat.SelStart;
  OldLength := reChat.SelLength;
  SendMessage(reChat.Handle, EM_SETSEL, WPARAM(-1), LPARAM(-1));
  reChat.SelLength := 0;
  reChat.SelAttributes.Color := Color;
  if Bold then
    reChat.SelAttributes.Style := [fsBold]
  else
    reChat.SelAttributes.Style := [];
  reChat.SelText := StringReplace(StringReplace(Text, #13#10, #10, [rfReplaceAll]),
    #10, #13#10, [rfReplaceAll]);
  // Scroll the caret into view.
  if OldLength > 0 then begin
    reChat.SelStart := OldStart;
    reChat.SelLength := OldLength;
  end else SendMessage(reChat.Handle, EM_SCROLLCARET, 0, 0);
end;

procedure TAgentPanelFrame.AppendUserMessageInternal(const Text, ContextSummary,
  ContextPayload: String);
begin
  if fConversationTitle = '' then
    fConversationTitle := Copy(StringReplace(StringReplace(Text, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]), 1, 64);
  AppendTranscript(#13#10 + 'You:' + #13#10, fTextColor, True);
  if Assigned(fTimeline) then
    fTimeline.AppendMessage(Text, fTextColor, True, ContextSummary,
      ContextPayload)
  else
    AppendText(Text, fTextColor, False);
  AppendTranscript(Text + #13#10, fTextColor, False);
end;

procedure TAgentPanelFrame.AppendUserMessage(const Text: String;
  const ContextSummary, ContextPayload: String);
begin
  AppendUserMessageInternal(Text, ContextSummary, ContextPayload);
end;

procedure TAgentPanelFrame.AppendAITextInternal(const Text: String);
begin
  if Assigned(fTimeline) then
    begin
      fTimeline.AppendMarkdown(Text, fTextColor);
      AppendTranscript(Text, fTextColor, False);
    end
  else
    AppendText(Text, fTextColor, False);
end;

procedure TAgentPanelFrame.AppendAIText(const Text: String);
begin
  AppendAITextInternal(Text);
end;

procedure TAgentPanelFrame.AppendSystemMessageInternal(const Text: String);
begin
  AppendText(#13#10 + '[IDE] ' + Text + #13#10, fMutedColor, False);
end;

procedure TAgentPanelFrame.AppendSystemMessage(const Text: String);
begin
  AppendSystemMessageInternal(Text);
end;

procedure TAgentPanelFrame.SetContext(const Text, Summary: String);
begin
  fContextText := Text;
  fContextSummary := Summary;
  fContextPreviewPayload := BuildContextPayload;
end;

function TAgentPanelFrame.BuildContextPayload: String;
begin
  Result := '';
  if Trim(fContextText) <> '' then
    Result := #13#10#13#10 +
      AgentContextPreamble + #13#10 + fContextText;
end;

function TAgentPanelFrame.BuildMessage(const Text: String;
  out ContextPayload: String): String;
begin
  ContextPayload := '';
  if fContextEnabled then
    ContextPayload := BuildContextPayload;
  Result := Text;
  Result := Result + ContextPayload;
end;

procedure TAgentPanelFrame.ClearChat;
begin
  ExpirePendingPermissions;
  EndResponseWait;
  ResetTurnFileOperations;
  if Assigned(fFileUndoManager) then fFileUndoManager.Clear;
  reChat.Clear;
  if Assigned(fTimeline) then fTimeline.Clear;
  fConversationTitle := '';
  fTools.Items.Clear;
  fTools.Visible := False;
  fToolPanel.Height := 28;
  fLastAnswer := '';
  memoInput.Clear;
  ClearAttachments;
  fContextText := '';
  fContextPreviewPayload := '';
  fContextSummary := '';
  ResetStreamingDisplay;
end;

function TAgentPanelFrame.CanShowInlinePermissions: Boolean;
begin
  Result := Assigned(fWeb) and fWeb.Ready and fWeb.Visible and not fWebFailed;
end;

procedure TAgentPanelFrame.QueuePermission(const Event: TAgentEvent;
  const WorkDir: String);
var InputJSON: String;
begin
  if Event.EventId = '' then begin
    AppendSystemMessage('The CLI sent a permission request without a request ID.');
    Exit;
  end;
  InputJSON := Event.ToolInput;
  if InputJSON = '' then InputJSON := '{}';
  fPendingPermissions.Values[Event.EventId] := InputJSON;
  fPendingPermissionTools.Values[Event.EventId] := Event.ToolName;
  fTimeline.AddPermission(Event.EventId, Event.ToolName, InputJSON, WorkDir);
  UpdateStatusText;
end;

function TAgentPanelFrame.BuildQuestionInput(const InputJSON,
  AnswersJSON: String; out ErrorText: String): String;
var InputNode, AnswersNode, QuestionsNode, QuestionNode, AnswerNode,
    CopyNode, ItemNode: TlkJSONbase;
    InputObject, AnswersObject, UpdatedObject: TlkJSONobject;
    I, QuestionCount: Integer; QuestionText, AnswerText: WideString;
    PropertyName: WideString; JsonText: String;
begin
  Result := '';
  ErrorText := '';
  InputNode := nil;
  AnswersNode := nil;
  UpdatedObject := nil;
  try
    try
      // Tool input comes from the CLI as UTF-8 JSON bytes already.
      InputNode := TlkJSON.ParseText(InputJSON);
      AnswersNode := TlkJSON.ParseText(UTF8Encode(AnswersJSON));
    except
      on E: Exception do begin
        ErrorText := 'Could not read the question answers: ' + E.Message;
        Exit;
      end;
    end;
    if not (InputNode is TlkJSONobject) or
       not (AnswersNode is TlkJSONobject) then begin
    ErrorText := 'The question or answer data is malformed.';
      Exit;
    end;
    InputObject := TlkJSONobject(InputNode);
    AnswersObject := TlkJSONobject(AnswersNode);
    QuestionsNode := InputObject.Field['questions'];
    if not (QuestionsNode is TlkJSONlist) then begin
      ErrorText := 'AskUserQuestion did not include a questions list.';
      Exit;
    end;
    QuestionCount := QuestionsNode.Count;
    if (QuestionCount < 1) or (QuestionCount > 4) or
       (AnswersObject.Count <> QuestionCount) then begin
      ErrorText := 'Please answer every question before submitting.';
      Exit;
    end;
    for I := 0 to QuestionCount - 1 do begin
      ItemNode := QuestionsNode.Child[I];
      if not (ItemNode is TlkJSONobject) then begin
        ErrorText := 'A question is malformed.';
        Exit;
      end;
      QuestionNode := ItemNode.Field['question'];
      if not (QuestionNode is TlkJSONstring) then begin
        ErrorText := 'A question is missing its question text.';
        Exit;
      end;
      QuestionText := VarToWideStr(QuestionNode.Value);
      AnswerNode := AnswersObject.Field[QuestionText];
      if not (AnswerNode is TlkJSONstring) then begin
        ErrorText := 'Please answer: ' + String(QuestionText);
        Exit;
      end;
      AnswerText := VarToWideStr(AnswerNode.Value);
      if Trim(UTF8Encode(AnswerText)) = '' then begin
        ErrorText := 'Please answer: ' + String(QuestionText);
        Exit;
      end;
    end;

    UpdatedObject := TlkJSONobject.Create;
    for I := 0 to InputObject.Count - 1 do begin
      PropertyName := InputObject.NameOf[I];
      if SameText(String(PropertyName), 'answers') then Continue;
      JsonText := TlkJSON.GenerateText(InputObject.FieldByIndex[I]);
      CopyNode := TlkJSON.ParseText(JsonText);
      if CopyNode = nil then begin
        ErrorText := 'Could not preserve a question field.';
        Exit;
      end;
      UpdatedObject.Add(PropertyName, CopyNode);
    end;
    JsonText := TlkJSON.GenerateText(AnswersNode);
    CopyNode := TlkJSON.ParseText(JsonText);
    if CopyNode = nil then begin
      ErrorText := 'Could not encode the question answers.';
      Exit;
    end;
    UpdatedObject.Add('answers', CopyNode);
    Result := TlkJSON.GenerateText(UpdatedObject);
  finally
    UpdatedObject.Free;
    AnswersNode.Free;
    InputNode.Free;
  end;
end;

function TAgentPanelFrame.ResolvePermission(const RequestId, Decision,
  AnswersJSON: String; const DenyMessage: String): Boolean;
var Index: Integer; InputJSON, ToolName, UpdatedInput, ErrorText,
    NewStatus, Summary, Feedback: String; Allow: Boolean;
begin
  Result := False;
  Index := fPendingPermissions.IndexOfName(RequestId);
  if (Index < 0) or (RequestId = '') then Exit;
  InputJSON := fPendingPermissions.ValueFromIndex[Index];
  ToolName := fPendingPermissionTools.Values[RequestId];
  UpdatedInput := InputJSON;
  ErrorText := '';
  Feedback := Copy(DenyMessage, 1, 1200);
  Allow := SameText(Decision, 'allow') or SameText(Decision, 'answer');
  if SameText(Decision, 'answer') then begin
    if not SameText(ToolName, 'AskUserQuestion') then begin
      ErrorText := 'This request is not an AskUserQuestion prompt.';
      fTimeline.UpdatePermission(RequestId, 'approval', ErrorText);
      Exit;
    end;
    UpdatedInput := BuildQuestionInput(InputJSON, AnswersJSON, ErrorText);
    if UpdatedInput = '' then begin
      fTimeline.UpdatePermission(RequestId, 'approval', ErrorText);
      Exit;
    end;
  end else if not SameText(Decision, 'allow') and
              not SameText(Decision, 'deny') then begin
    fTimeline.UpdatePermission(RequestId, 'approval', 'Unknown approval action.');
    Exit;
  end;

  if not Assigned(fAgentProcess) then
    ErrorText := 'The AI process is no longer available.'
  else if not fAgentProcess.SendPermissionResponse(RequestId, UpdatedInput,
    Allow, Feedback) then
    ErrorText := fAgentProcess.LastError;
  if ErrorText <> '' then begin
    fTimeline.UpdatePermission(RequestId, 'approval', ErrorText);
    AppendSystemMessage(ErrorText);
    Exit;
  end;

  if SameText(Decision, 'deny') then begin
    NewStatus := 'denied';
    Summary := String(UTF8Decode(#$E5#$B7#$B2#$E6#$8B#$92#$E7#$BB#$9D));
  end else if SameText(Decision, 'answer') then begin
    NewStatus := 'answered';
    Summary := String(UTF8Decode(
      #$E5#$B7#$B2#$E6#$8F#$90#$E4#$BA#$A4#$E5#$9B#$9E#$E7#$AD#$94#$EF#$BC#$8C#$E7#$AD#$89#$E5#$BE#$85#$E5#$B7#$A5#$E5#$85#$B7#$E7#$BB#$A7#$E7#$BB#$AD#$E6#$89#$A7#$E8#$A1#$8C));
  end else begin
    NewStatus := 'authorized';
    Summary := String(UTF8Decode(
      #$E5#$B7#$B2#$E5#$85#$81#$E8#$AE#$B8#$E4#$B8#$80#$E6#$AC#$A1#$EF#$BC#$8C#$E7#$AD#$89#$E5#$BE#$85#$E5#$B7#$A5#$E5#$85#$B7#$E6#$89#$A7#$E8#$A1#$8C));
  end;
  if SameText(Decision, 'answer') then
    fTimeline.UpdatePermission(RequestId, NewStatus, Summary, UpdatedInput)
  else
    fTimeline.UpdatePermission(RequestId, NewStatus, Summary);
  fPendingPermissions.Delete(Index);
  Index := fPendingPermissionTools.IndexOfName(RequestId);
  if Index >= 0 then fPendingPermissionTools.Delete(Index);
  UpdateStatusText;
  fWaitingForResponse := True;
  if Assigned(fOnRequestStarted) then fOnRequestStarted(Self);
  Result := True;
end;

procedure TAgentPanelFrame.ExpirePendingPermissions;
var I: Integer; RequestId: String;
begin
  for I := 0 to fPendingPermissions.Count - 1 do begin
    RequestId := fPendingPermissions.Names[I];
    if RequestId <> '' then
      fTimeline.UpdatePermission(RequestId, 'interrupted',
        'Request ended; this action can no longer be submitted.');
  end;
  fPendingPermissions.Clear;
  fPendingPermissionTools.Clear;
  UpdateStatusText;
end;

procedure TAgentPanelFrame.BeginResponseWait;
begin
  if fWaitingForResponse then
    Exit;
  fWaitingForResponse := True;
  if Assigned(fOnRequestStarted) then
    fOnRequestStarted(Self);
end;

procedure TAgentPanelFrame.EndResponseWait;
begin
  if not fWaitingForResponse then
    Exit;
  fWaitingForResponse := False;
  if Assigned(fOnRequestEnded) then
    fOnRequestEnded(Self);
end;

procedure TAgentPanelFrame.ResetStreamingDisplay;
begin
  fStreamingMessageId := '';
  fStreamingText := '';
  fStreamingActive := False;
end;

function StartsWithText(const Value, Prefix: String): Boolean;
begin
  Result := (Prefix = '') or
    (Length(Value) >= Length(Prefix)) and
    (Copy(Value, 1, Length(Prefix)) = Prefix);
end;

procedure TAgentPanelFrame.HandleAssistantEvent(const Event: TAgentEvent);
var
  TextToAppend: String;
  SameMessage: Boolean;
begin
  if (Event.Content = '') or SameText(Event.ContentType, 'thinking') or
     SameText(Event.ContentType, 'redacted_thinking') then
    Exit;

  SameMessage := (Event.MessageId = '') or
    (fStreamingMessageId = '') or
    SameText(Event.MessageId, fStreamingMessageId);
  if (Event.MessageId <> '') and (fStreamingMessageId <> '') and
     not SameText(Event.MessageId, fStreamingMessageId) then begin
    ResetStreamingDisplay;
    SameMessage := True;
  end;
  if Event.MessageId <> '' then
    fStreamingMessageId := Event.MessageId;

  TextToAppend := Event.Content;
  if not Event.IsPartial and fStreamingActive and SameMessage then begin
    // --include-partial-messages emits both deltas and the completed assistant
    // message. Append only the missing suffix, or nothing when it is an exact
    // replay of the text already rendered from deltas.
    if Event.Content = fStreamingText then
      TextToAppend := ''
    else if StartsWithText(Event.Content, fStreamingText) then
      TextToAppend := Copy(Event.Content, Length(fStreamingText) + 1, MaxInt)
    else if StartsWithText(fStreamingText, Event.Content) then
      TextToAppend := '';
  end;

  if TextToAppend <> '' then begin
    if fLastAnswer = '' then
      AppendTranscript(#13#10 + 'AI:' + #13#10, fTextColor, True);
    fLastAnswer := fLastAnswer + TextToAppend;
    if SameText(Event.ContentType, 'thinking') or
       SameText(Event.ContentType, 'redacted_thinking') then
      AppendText(TextToAppend, fMutedColor, False)
    else
      AppendAIText(TextToAppend);
  end;

  if Event.IsPartial then begin
    fStreamingActive := True;
    fStreamingText := fStreamingText + Event.Content;
  end else if TextToAppend <> '' then begin
    // Keep the last complete text as a deduplication anchor too. This covers
    // CLI configurations that omit partial events but repeat result.result.
    fStreamingActive := True;
    fStreamingText := Event.Content;
  end;
end;

function TAgentPanelFrame.EventSummaryText(const Event: TAgentEvent): String;
begin
  Result := Event.Summary;
  if (Event.Content <> '') and (Event.Content <> Result) then begin
    if Result <> '' then
      Result := Result + ': ' + Event.Content
    else
      Result := Event.Content;
  end;
  if Result = '' then
    Result := Event.RawJSON;
end;

function TAgentPanelFrame.AttachmentSummary: String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to fAttachments.Count - 1 do
    Result := Result + 'Attachment: ' + fAttachments[I] + #13#10;
end;

function TAgentPanelFrame.AddAttachment(const FileName: String): Boolean;
var
  Path: String;
begin
  Result := False;
  Path := Trim(FileName);
  if (Path = '') or not FileExists(Path) then
    Exit;
  Path := ExpandFileName(Path);
  if fAttachments.IndexOf(Path) >= 0 then
    Exit;
  fAttachments.Add(Path);
  lbAttachments.Items.Add(Path);
  UpdateAttachmentLayout;
  Result := True;
end;

procedure TAgentPanelFrame.AddAttachmentList(Files: TStrings);
var
  I: Integer;
begin
  if Files = nil then
    Exit;
  for I := 0 to Files.Count - 1 do
    AddAttachment(Files[I]);
  if fAttachments.Count > 0 then begin
    lbAttachments.ItemIndex := lbAttachments.Items.Count - 1;
    memoInput.SetFocus;
  end;
end;

procedure TAgentPanelFrame.AddDroppedFiles(Files: TStrings);
begin
  AddAttachmentList(Files);
end;

procedure TAgentPanelFrame.RemoveAttachmentAt(Index: Integer);
var
  TempIndex: Integer;
  Path: String;
begin
  if (Index < 0) or (Index >= fAttachments.Count) then
    Exit;
  Path := fAttachments[Index];
  TempIndex := fTemporaryAttachments.IndexOf(Path);
  if TempIndex >= 0 then begin
    DeleteFile(Path);
    fTemporaryAttachments.Delete(TempIndex);
  end;
  fAttachments.Delete(Index);
  lbAttachments.Items.Delete(Index);
  UpdateAttachmentLayout;
end;

procedure TAgentPanelFrame.ClearAttachments;
var
  I: Integer;
begin
  for I := 0 to fTemporaryAttachments.Count - 1 do
    DeleteFile(fTemporaryAttachments[I]);
  fTemporaryAttachments.Clear;
  fAttachments.Clear;
  lbAttachments.Items.Clear;
  UpdateAttachmentLayout;
end;

function TAgentPanelFrame.SaveClipboardImage: String;
var
  Bitmap: TBitmap;
  JpegImage: TJPEGImage;
  TempPath: array[0..MAX_PATH] of Char;
  TempFileName: array[0..MAX_PATH] of Char;
  TempDir: String;
  TempPlaceholder: String;
  Format: Word;
begin
  Result := '';
  TempPlaceholder := '';
  if not Clipboard.HasFormat(CF_BITMAP) and not Clipboard.HasFormat(CF_DIB) then
    Exit;
  if GetTempPath(SizeOf(TempPath), TempPath) = 0 then
    Exit;
  TempDir := IncludeTrailingPathDelimiter(String(TempPath));
  if GetTempFileName(PChar(TempDir), 'dca', 0, TempFileName) = 0 then
    Exit;
  TempPlaceholder := String(TempFileName);
  Result := ChangeFileExt(TempPlaceholder, '.jpg');
  if FileExists(Result) then begin
    DeleteFile(TempPlaceholder);
    Result := '';
    Exit;
  end;
  Bitmap := nil;
  JpegImage := nil;
  try
    try
      Bitmap := TBitmap.Create;
      JpegImage := TJPEGImage.Create;
      if Clipboard.HasFormat(CF_BITMAP) then
        Format := CF_BITMAP
      else
        Format := CF_DIB;
      Bitmap.LoadFromClipboardFormat(Format, Clipboard.GetAsHandle(Format), 0);
      JpegImage.Assign(Bitmap);
      JpegImage.CompressionQuality := 90;
      JpegImage.SaveToFile(Result);
    except
      DeleteFile(Result);
      Result := '';
    end;
  finally
    DeleteFile(TempPlaceholder);
    JpegImage.Free;
    Bitmap.Free;
  end;
end;

procedure TAgentPanelFrame.btnSettingsClick(Sender: TObject);
begin
  if Assigned(fOnSettings) then
    fOnSettings(Self);
end;

procedure TAgentPanelFrame.UpdateAttachmentLayout;
var
  InputHeight: Integer;
begin
  if fAttachments = nil then
    Exit;
  pnlAttachments.Visible := fAttachments.Count > 0;
  btnRemoveAttachment.Enabled := fAttachments.Count > 0;
  InputHeight := 152;
  if memoInput.Font.Size > 10 then
    Inc(InputHeight, (memoInput.Font.Size - 10) * 3);
  if pnlAttachments.Visible then
    Inc(InputHeight, pnlAttachments.Height);
  pnlInput.Height := InputHeight;
end;

procedure TAgentPanelFrame.ApplyAppearance(APanelColor, APanelTextColor,
  AEditorColor, ATextColor: TColor; const AFontName: String; AFontSize: Integer);
var
  TextSize, SelectionStart, SelectionLength: Integer;
  UiFontName: String;
  Palette: TAgentUiPalette;
begin
  TextSize := memoInput.Font.Size;
  UiFontName := AgentUiFontName(AFontName);
  AgentBuildPalette(AEditorColor, ATextColor, Palette);
  Color := APanelColor;
  Font.Name := UiFontName;
  Font.Size := AFontSize;
  Font.Color := APanelTextColor;
  lblTitle.Font.Assign(Font);
  lblTitle.Font.Style := [fsBold];
  if Assigned(fModelBadge) then begin
    fModelBadge.Font.Assign(Font);
    fModelBadge.Font.Size := TextSize - 1;
    if fModelBadge.Font.Size < 8 then fModelBadge.Font.Size := 8;
    fModelBadge.Font.Color := Palette.Muted;
    fModelBadge.Font.Style := [];
  end;
  pnlChat.Color := AEditorColor;
  reChat.Color := AEditorColor;
  memoInput.Color := AEditorColor;
  lbAttachments.Color := AEditorColor;
  reChat.Font.Name := UiFontName;
  memoInput.Font.Name := UiFontName;
  lbAttachments.Font.Name := UiFontName;
  reChat.Font.Color := ATextColor;
  memoInput.Font.Color := ATextColor;
  lbAttachments.Font.Color := ATextColor;
  fMutedColor := Palette.Muted;
  fErrorColor := Palette.Error;
  if (fTextColor <> ATextColor) and (reChat.GetTextLen > 0) then begin
    // Existing transcript text must remain readable after changing theme.
    SelectionStart := reChat.SelStart;
    SelectionLength := reChat.SelLength;
    reChat.SelectAll;
    reChat.SelAttributes.Color := ATextColor;
    reChat.SelStart := SelectionStart;
    reChat.SelLength := SelectionLength;
  end;
  fTextColor := ATextColor;
  if Assigned(fTools) then begin
    fTools.Color := AEditorColor;
    fTools.Font.Color := ATextColor;
    fTools.Font.Name := UiFontName;
  end;
  if Assigned(fSessions) then begin
    fSessions.Color := AEditorColor;
    fSessions.Font.Color := ATextColor;
    fSessions.Font.Name := UiFontName;
  end;
  if Assigned(fQuickActions) then begin
    fQuickActions.Color := AEditorColor;
    fQuickActions.Font.Color := ATextColor;
    fQuickActions.Font.Name := UiFontName;
  end;
  if Assigned(fDetails) then begin
    fDetails.Font.Color := ATextColor;
    fDetails.Font.Name := UiFontName;
  end;
  if Assigned(fTimeline) then begin
    fTimeline.ApplyAppearance(AEditorColor, ATextColor, UiFontName, TextSize);
  end;
  if Assigned(fScrollBottom) then begin
    fScrollBottom.Font.Name := UiFontName;
    fScrollBottom.Font.Color := Palette.Muted;
  end;
  SetFontSize(TextSize);
end;

procedure TAgentPanelFrame.SetSendKey(const Value: String);
begin
  fSendOnCtrlEnter := SameText(Value, 'ctrl+enter');
  memoInput.WantReturns := True;
  if fSendOnCtrlEnter then
    lblSendHint.Caption := 'Ctrl+Enter to send'
  else
    lblSendHint.Caption := 'Enter to send';
end;

procedure TAgentPanelFrame.SetFontSize(Value: Integer);
begin
  if Value < 8 then
    Value := 8
  else if Value > 24 then
    Value := 24;
  reChat.Font.Size := Value;
  memoInput.Font.Size := Value;
  lbAttachments.Font.Size := Value;
  if Assigned(fTimeline) then
    fTimeline.Font.Size := Value;
  lbAttachments.ItemHeight := Value + 6;
  UpdateAttachmentLayout;
end;

{ ------------------------------------------------------------------ }
{ Event dispatch                                                     }
{ ------------------------------------------------------------------ }

procedure TAgentPanelFrame.HandleAgentEvent(const Event: TAgentEvent);
var
  Text: String;
begin
  if Event.EventType in [aetToolUse, aetToolResult, aetProgress] then begin
    if Event.EventType in [aetToolUse, aetToolResult] then EndResponseWait;
    if Event.EventType in [aetToolUse, aetToolResult] then
      TrackTurnFileOperation(Event);
    AddToolEvent(Event);
    if Event.EventType = aetToolUse then SetStatus(asExecuting);
    Exit;
  end;
  if Event.EventType in [aetAssistant, aetToolUse, aetToolResult,
      aetResult, aetError] then
    EndResponseWait;
  case Event.EventType of
    aetAssistant:
      begin
        SetStatus(asThinking);
        HandleAssistantEvent(Event);
      end;

    aetResult:
      begin
        if Event.Content <> '' then
          HandleAssistantEvent(Event);
        if (Event.Summary <> '') and (Event.IsError or fDetails.Checked) then
          if Event.IsError then
            AppendSystemMessage('[Claude failure] ' + Event.Summary)
          else
            AppendSystemMessage('[Claude] ' + Event.Summary);
        AppendTurnFileOperationSummary;
        if Event.IsError then
          SetStatus(asError)
        else
          SetStatus(asReady);
        AppendText(#13#10, fTextColor, False);
        ResetStreamingDisplay;
      end;

    aetError:
      begin
        AppendTurnFileOperationSummary;
        AppendText(#13#10 + '[Error] ' + Event.Content + #13#10, fErrorColor, True);
        SetStatus(asError);
      end;

    aetSystem:
      begin
        if Event.IsProtocolOnly then
          Exit;
        if not fDetails.Checked and not Event.IsError and
           (Event.Subtype <> 'api_retry') then
          Exit;
        Text := EventSummaryText(Event);
        if Text <> '' then begin
          if Event.IsError then
            AppendSystemMessage('[Claude failure] ' + Text)
          else
            AppendSystemMessage('[Claude] ' + Text);
        end;
      end;

    aetUser:
      begin
        if Event.IsReplay and (Event.Content <> '') then
          AppendSystemMessage('[Claude replay] ' + Event.Content);
      end;

    aetRateLimit:
      begin
        Text := EventSummaryText(Event);
        if Text <> '' then
          AppendSystemMessage('[Rate limit] ' + Text);
      end;

    aetPromptSuggestion:
      begin
        Text := EventSummaryText(Event);
        if Text <> '' then
          AppendSystemMessage('[Suggestion] ' + Text);
      end;

  else
    // aetUnknown: append raw text greyed out.
    AppendText(Event.Content + #13#10, fMutedColor, False);
  end;
end;

{ ------------------------------------------------------------------ }
{ Status                                                             }
{ ------------------------------------------------------------------ }

function TAgentPanelFrame.IsAgentBusy: Boolean;
begin
  Result := (fStatus in [asThinking, asExecuting]) or
    (Assigned(fPendingPermissions) and (fPendingPermissions.Count > 0));
end;

procedure TAgentPanelFrame.UpdateStatusText;
var s: String;
begin
  if fPendingPermissions.Count > 0 then
    s := AgentPanelUiText(#$E7#$AD#$89#$E5#$BE#$85#$E4#$BD#$A0#$E5#$AE#$A1#$E6#$89#$B9#$E2#$80#$A6)
  else case fStatus of
    asReady:        s := AgentPanelUiText(#$E5#$B0#$B1#$E7#$BB#$AA);
    asThinking:     s := AgentPanelUiText(#$E6#$AD#$A3#$E5#$9C#$A8#$E6#$80#$9D#$E8#$80#$83#$E2#$80#$A6);
    asExecuting:    s := AgentPanelUiText(#$E6#$AD#$A3#$E5#$9C#$A8#$E6#$89#$A7#$E8#$A1#$8C#$E5#$B7#$A5#$E5#$85#$B7#$E2#$80#$A6);
    asError:        s := AgentPanelUiText(#$E5#$8F#$91#$E7#$94#$9F#$E9#$94#$99#$E8#$AF#$AF);
    asDisconnected: s := AgentPanelUiText(#$E6#$9C#$AA#$E8#$BF#$9E#$E6#$8E#$A5);
  else
    s := '';
  end;
  if StatusBar.Panels.Count > 0 then
    StatusBar.Panels[0].Text := s;
  btnStop.Visible := (fStatus in [asThinking, asExecuting]) or
    (fPendingPermissions.Count > 0);
  btnSend.Enabled := not IsAgentBusy;
  btnSend.Visible := btnSend.Enabled;
end;

procedure TAgentPanelFrame.SetStatus(Status: TAgentStatus);
begin
  if Status in [asReady, asError, asDisconnected] then
    EndResponseWait;
  fStatus := Status;
  UpdateStatusText;

end;

procedure TAgentPanelFrame.SetModelName(const Name: String);
begin
  fModelName := Name;
  if Assigned(fModelBadge) then begin
    if Trim(Name) = '' then
      fModelBadge.Caption := 'No model selected'
    else
      fModelBadge.Caption := Name;
  end;
  StatusBar.Hint := Name;
  if StatusBar.Panels.Count > 1 then
    StatusBar.Panels[1].Text := Name;
end;

{ ------------------------------------------------------------------ }
{ Sending                                                            }
{ ------------------------------------------------------------------ }

procedure TAgentPanelFrame.SendCurrentInput;
var
  Text, MessageText, DisplayText, ContextPayload: String;
begin
  Text := Trim(memoInput.Text);
  if (Text = '') and (fAttachments.Count = 0) then
    Exit;
  if (fAgentProcess = nil) or not fAgentProcess.IsRunning then begin
    AppendText(#13#10 + '[Notice] AI is not connected. Configure an API Key in Settings.' + #13#10,
      fErrorColor, False);
    Exit;
  end;
  if IsAgentBusy then
    Exit;

  if Assigned(fOnPrepareContext) then
    fOnPrepareContext(Self);
  ResetTurnFileOperations;
  if (fAgentProcess.WorkDir <> '') and
     DirectoryExists(fAgentProcess.WorkDir) then
    fWorkspaceWatcher := TAgentWorkspaceWatcher.Create(fAgentProcess.WorkDir);
  MessageText := BuildMessage(Text, ContextPayload);
  DisplayText := Text;
  if DisplayText = '' then
    DisplayText := '(attachment)';
  if AttachmentSummary <> '' then
    DisplayText := DisplayText + #13#10 + AttachmentSummary;
  if not fAgentProcess.SendMessageWithAttachments(MessageText, fAttachments) then begin
    if Assigned(fWorkspaceWatcher) then begin
      fWorkspaceWatcher.Free;
      fWorkspaceWatcher := nil;
    end;
    AppendSystemMessage(fAgentProcess.LastError);
    SetStatus(asError);
    Exit;
  end;
  ResetStreamingDisplay;
  fLastAnswer := '';
  if fContextEnabled then
    AppendUserMessage(DisplayText, fContextSummary, ContextPayload)
  else
    AppendUserMessage(DisplayText, 'context disabled');
  fContextText := '';
  memoInput.Clear;
  ClearAttachments;
  SetStatus(asThinking);
  BeginResponseWait;
end;

procedure TAgentPanelFrame.SendPrompt(const Text: String);
begin
  memoInput.Text := Text;
  SendCurrentInput;
end;

procedure TAgentPanelFrame.EditPopupOpen(Sender: TObject);
begin
  fPopupTarget := TWinControl(fEditPopup.PopupComponent);
  fEditPopup.Items[1].Enabled := Clipboard.HasFormat(CF_TEXT) or Clipboard.HasFormat(CF_UNICODETEXT);
  fEditPopup.Items[2].Enabled := fPopupTarget = memoInput;
  fEditPopup.Items[4].Enabled := (fPopupTarget = memoInput) and memoInput.CanUndo;
end;

procedure TAgentPanelFrame.ScrollToBottomClick(Sender: TObject);
begin
  if Assigned(fTimeline) then begin
    if fTimeline.VertScrollBar.Range > fTimeline.ClientHeight then
      fTimeline.VertScrollBar.Position :=
        fTimeline.VertScrollBar.Range - fTimeline.ClientHeight
    else
      fTimeline.VertScrollBar.Position := 0;
  end;
end;

procedure TAgentPanelFrame.ClearChatClick(Sender: TObject);
begin
  if IsAgentBusy then
    Exit;
  ClearChat;
end;

procedure TAgentPanelFrame.PrepareContextClick(Sender: TObject);
begin
  if Assigned(fOnPrepareContext) then
    fOnPrepareContext(Self);
end;

procedure TAgentPanelFrame.EditPopupClick(Sender: TObject);
begin
  ExecuteEditCommand(TMenuItem(Sender).Tag, fPopupTarget);
end;

function TAgentPanelFrame.ExecuteEditCommand(Command: Integer; Target: TWinControl): Boolean;
begin
  Result := (Target = memoInput) or (Target = reChat) or (Target = fTools) or
    (Assigned(fTimeline) and (Target <> nil) and (Target = fTimeline.FocusedEdit));
  if not Result then Exit;
  if Target = fTools then begin
    if (Command = 0) and (fTools.Selected <> nil) then
      Clipboard.AsText := fTools.Selected.Text;
    if Command <> 1 then Exit;
  end;
  case Command of
    0: TCustomEdit(Target).CopyToClipboard;
    1: begin
      if memoInput.CanFocus then memoInput.SetFocus;
      memoInput.PasteFromClipboard;
    end;
    2: if Target = memoInput then memoInput.CutToClipboard;
    3: TCustomEdit(Target).SelectAll;
    4: if Target = memoInput then memoInput.Undo;
  end;
end;

function TAgentPanelFrame.HandleEditShortcut(Key: Word; Shift: TShiftState): Boolean;
var
  Target: TWinControl;
  Command: Integer;
begin
  Result := False;
  Target := nil;
  if memoInput.Focused then Target := memoInput
  else if reChat.Focused then Target := reChat
  else if fTools.Focused then Target := fTools;
  if (Target = nil) and Assigned(fTimeline) then Target := fTimeline.FocusedEdit;
  if Target = nil then Exit;
  Command := -1;
  if Shift = [ssCtrl] then
    case Key of
      Ord('C'), VK_INSERT: Command := 0;
      Ord('V'): Command := 1;
      Ord('X'): Command := 2;
      Ord('A'): Command := 3;
      Ord('Z'): Command := 4;
    end;
  if Shift = [ssShift] then
    case Key of
      VK_INSERT: Command := 1;
      VK_DELETE: Command := 2;
    end;
  if Command >= 0 then Result := ExecuteEditCommand(Command, Target);
end;
procedure TAgentPanelFrame.SetSessions(Items: TStrings; const Selected: String);
var
  I: Integer;
begin
  fSessionKeys.Clear;
  fSessions.Items.BeginUpdate;
  try
    fSessions.Items.Clear;
    for I := 0 to Items.Count - 1 do begin
      if Items.Names[I] <> '' then begin
        fSessionKeys.Add(Items.Names[I]);
        fSessions.Items.Add(Items.ValueFromIndex[I]);
      end else begin
        fSessionKeys.Add(Items[I]);
        fSessions.Items.Add(Items[I]);
      end;
    end;
    fSessions.ItemIndex := fSessionKeys.IndexOf(Selected);
  finally
    fSessions.Items.EndUpdate;
  end;
end;

function TAgentPanelFrame.SelectedSession: String;
begin
  Result := '';
  if fSessions.ItemIndex >= 0 then Result := fSessionKeys[fSessions.ItemIndex];
end;

procedure TAgentPanelFrame.SessionChange(Sender: TObject);
begin
  if Assigned(fOnSessionChange) then fOnSessionChange(Self);
end;

procedure TAgentPanelFrame.NewSessionClick(Sender: TObject);
begin
  fSessions.ItemIndex := -1;
  SessionChange(Self);
end;

procedure TAgentPanelFrame.ImportConversation(const FileName: String);
var
  Lines, Seen: TStringList;
  Events: TAgentEventArray;
  I, J, P: Integer;
  Text, Identity: String;
begin
  if not FileExists(FileName) then Exit;
  ClearChat;
  Lines := TStringList.Create;
  Seen := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    for I := 0 to Lines.Count - 1 do begin
      ParseLineEvents(Lines[I], Events);
      for J := 0 to Length(Events) - 1 do begin
        Identity := Events[J].EventId + ':' + IntToStr(J);
        if (Events[J].EventId <> '') and (Seen.IndexOf(Identity) >= 0) then Continue;
        Seen.Add(Identity);
        if Events[J].EventType = aetUser then begin
          Text := Events[J].Content;
          P := Pos(AgentContextPreamble, Text);
          if P = 0 then
            P := Pos('The following context was attached automatically by the IDE.', Text);
          if P > 0 then Text := Trim(Copy(Text, 1, P - 1));
          if Text <> '' then begin
            ResetStreamingDisplay;
            fLastAnswer := '';
            AppendUserMessage(Text);
          end;
        end else if Events[J].EventType in [aetAssistant, aetToolUse, aetToolResult] then
          HandleAgentEvent(Events[J]);
      end;
    end;
    ResetStreamingDisplay;
    SetStatus(asReady);
  finally
    Seen.Free;
    Lines.Free;
  end;
end;
procedure TAgentPanelFrame.SaveConversation(const Path: String);
var
  Text: TStringList;
begin
  ForceDirectories(ExtractFilePath(Path));
  fTimeline.SaveToFile(Path + '.timeline');
  reChat.Lines.SaveToFile(Path + '.rtf');
  fTools.SaveToFile(Path + '.tools');
  Text := TStringList.Create;
  try
    Text.Text := fConversationTitle;
    Text.SaveToFile(Path + '.title');
    Text.Text := fLastAnswer;
    Text.SaveToFile(Path + '.answer');
    Text.Text := memoInput.Text;
    Text.SaveToFile(Path + '.draft');
  finally
    Text.Free;
  end;
end;

procedure TAgentPanelFrame.LoadConversation(const Path: String);
var
  Text: TStringList;
begin
  ClearChat;
  if FileExists(Path + '.rtf') then reChat.Lines.LoadFromFile(Path + '.rtf');
  if FileExists(Path + '.timeline') then fTimeline.LoadFromFile(Path + '.timeline')
  else fTimeline.AppendText(reChat.Text, fTextColor, False);
  if FileExists(Path + '.tools') then fTools.LoadFromFile(Path + '.tools');
  fTools.FullCollapse;
  Text := TStringList.Create;
  try
    if FileExists(Path + '.title') then begin
      Text.LoadFromFile(Path + '.title');
      fConversationTitle := Trim(Text.Text);
    end;
    if FileExists(Path + '.answer') then begin
      Text.LoadFromFile(Path + '.answer');
      fLastAnswer := Text.Text;
    end;
    if FileExists(Path + '.draft') then begin
      Text.LoadFromFile(Path + '.draft');
      memoInput.Text := Text.Text;
    end;
  finally
    Text.Free;
  end;
end;
procedure TAgentPanelFrame.ToggleTools(Sender: TObject);
begin
  fTools.Visible := not fTools.Visible;
  if fTools.Visible then begin
    fToolPanel.Height := pnlChat.ClientHeight div 2;
    if fToolPanel.Height > 170 then fToolPanel.Height := 170;
    if fToolPanel.Height < 56 then fToolPanel.Height := 56;
    fToolToggle.Caption := 'v Tool activity';
  end else begin
    fToolPanel.Height := 28;
    fToolToggle.Caption := '> Tool activity';
  end;
end;

procedure TAgentPanelFrame.ResetTurnFileOperations;
begin
  if Assigned(fWorkspaceWatcher) then begin
    fWorkspaceWatcher.Free;
    fWorkspaceWatcher := nil;
  end;
  if Assigned(fPendingFileTools) then fPendingFileTools.Clear;
  if Assigned(fPendingFileDiffs) then fPendingFileDiffs.Clear;
  if Assigned(fPendingFileUndoTokens) then fPendingFileUndoTokens.Clear;
  if Assigned(fTurnFilePaths) then fTurnFilePaths.Clear;
  if Assigned(fTurnFileStates) then fTurnFileStates.Clear;
  if Assigned(fTurnFileDiffs) then fTurnFileDiffs.Clear;
  if Assigned(fTurnFileDiffSummaries) then fTurnFileDiffSummaries.Clear;
  if Assigned(fTurnFileUndoTokens) then fTurnFileUndoTokens.Clear;
  if Assigned(fFileUndoManager) then fFileUndoManager.BeginTurn;
end;

procedure TAgentPanelFrame.TrackTurnFileOperation(const Event: TAgentEvent);
var
  I, P1, P2: Integer;
  Key, Path, ToolName, PreviewPath, BeforeText, AfterText, PreviewError,
    DiffText, DiffSummary, Payload, UndoToken, UndoError: String;
  IsFileTool, IsNewFile, CanUndo: Boolean;
begin
  ToolName := LowerCase(Event.ToolName);
  IsFileTool := (ToolName = 'write') or (ToolName = 'edit') or
    (ToolName = 'multiedit') or (ToolName = 'notebookedit') or
    (ToolName = 'writefile') or (ToolName = 'editfile') or
    (Pos('write_file', ToolName) > 0) or (Pos('edit_file', ToolName) > 0);
  Key := Event.ToolId;
  if Key = '' then Key := Event.EventId;

  if Event.EventType = aetToolUse then begin
    if not IsFileTool or (Key = '') or (Event.FilePath = '') then Exit;
    for I := fPendingFileTools.Count - 1 downto 0 do
      if SameText(fPendingFileTools.Names[I], Key) then
        fPendingFileTools.Delete(I);
    fPendingFileTools.Add(Key + '=' + Event.FilePath);
    for I := fPendingFileDiffs.Count - 1 downto 0 do
      if SameText(fPendingFileDiffs.Names[I], Key) then
        fPendingFileDiffs.Delete(I);
    for I := fPendingFileUndoTokens.Count - 1 downto 0 do
      if SameText(fPendingFileUndoTokens.Names[I], Key) then
        fPendingFileUndoTokens.Delete(I);
    if Assigned(fAgentProcess) then begin
      if SameText(Event.ToolName, 'Write') or SameText(Event.ToolName, 'Edit') then
        if BuildFilePreview(Event.ToolName, fAgentProcess.WorkDir,
          Event.ToolInput, PreviewPath, BeforeText, AfterText, PreviewError,
          IsNewFile) then begin
          DiffText := BuildAgentFileDiffText(BeforeText, AfterText, DiffSummary);
          fPendingFileDiffs.Add(Key + '=' + PreviewPath + #1 + DiffSummary + #1 + DiffText);
          UndoToken := '';
          UndoError := '';
          if fFileUndoManager.BeginChange(PreviewPath, fAgentProcess.WorkDir,
            UndoToken, UndoError) then
            fPendingFileUndoTokens.Add(Key + '=' + UndoToken);
        end;
    end;
    Exit;
  end;

  if Event.EventType <> aetToolResult then Exit;
  Path := '';
  PreviewPath := '';
  DiffText := '';
  DiffSummary := '';
  UndoToken := '';
  if Key <> '' then
    for I := fPendingFileTools.Count - 1 downto 0 do
      if SameText(fPendingFileTools.Names[I], Key) then begin
        if Path = '' then Path := fPendingFileTools.ValueFromIndex[I];
        fPendingFileTools.Delete(I);
        Break;
      end;
  if Key <> '' then
    for I := fPendingFileDiffs.Count - 1 downto 0 do
      if SameText(fPendingFileDiffs.Names[I], Key) then begin
        Payload := fPendingFileDiffs.ValueFromIndex[I];
        fPendingFileDiffs.Delete(I);
        P1 := Pos(#1, Payload);
        if P1 > 0 then begin
          PreviewPath := Copy(Payload, 1, P1 - 1);
          P2 := Pos(#1, Copy(Payload, P1 + 1, MaxInt));
          if P2 > 0 then begin
            DiffSummary := Copy(Payload, P1 + 1, P2 - 1);
            DiffText := Copy(Payload, P1 + P2 + 1, MaxInt);
          end;
        end;
        Break;
      end;
  if Key <> '' then
    for I := fPendingFileUndoTokens.Count - 1 downto 0 do
      if SameText(fPendingFileUndoTokens.Names[I], Key) then begin
        UndoToken := fPendingFileUndoTokens.ValueFromIndex[I];
        fPendingFileUndoTokens.Delete(I);
        Break;
      end;
  if (Path = '') and IsFileTool then Path := Event.FilePath;
  if Event.IsError or (Path = '') then begin
    if (UndoToken <> '') and Assigned(fFileUndoManager) then
      fFileUndoManager.CancelChange(UndoToken);
    Exit;
  end;
  if PreviewPath <> '' then Path := PreviewPath;
  if Assigned(fAgentProcess) and (fAgentProcess.WorkDir <> '') then begin
    if (ExtractFileDrive(Path) = '') and (Path <> '') and
       (Path[1] = '\') then
      Path := ExtractFileDrive(fAgentProcess.WorkDir) + Path
    else if (ExtractFileDrive(Path) = '') and (Path <> '') then
      Path := IncludeTrailingPathDelimiter(fAgentProcess.WorkDir) + Path;
  end;
  Path := ExpandFileName(Path);
  if UndoToken <> '' then begin
    UndoError := '';
    CanUndo := False;
    if fFileUndoManager.CompleteChange(UndoToken, CanUndo, UndoError) then begin
      for I := fTurnFileUndoTokens.Count - 1 downto 0 do
        if SameText(fTurnFileUndoTokens.Names[I], Path) then
          fTurnFileUndoTokens.Delete(I);
      if CanUndo then fTurnFileUndoTokens.Add(Path + '=' + UndoToken);
    end else begin
      fFileUndoManager.CancelChange(UndoToken);
      for I := fTurnFileUndoTokens.Count - 1 downto 0 do
        if SameText(fTurnFileUndoTokens.Names[I], Path) then
          fTurnFileUndoTokens.Delete(I);
    end;
  end;
  for I := 0 to fTurnFilePaths.Count - 1 do
    if SameText(fTurnFilePaths[I], Path) then begin
      fTurnFileStates[I] := 'Written/edited';
      if DiffText <> '' then begin
        fTurnFileDiffs[I] := DiffText;
        fTurnFileDiffSummaries[I] := DiffSummary;
      end;
      Exit;
    end;
  fTurnFilePaths.Add(Path);
  fTurnFileStates.Add('Written/edited');
  fTurnFileDiffs.Add(DiffText);
  fTurnFileDiffSummaries.Add(DiffSummary);
end;

procedure TAgentPanelFrame.AppendTurnFileOperationSummary;
var
  I, J: Integer;
  Summary, Path, DiffText, DiffSummary: String;
  UndoToken: String;
  CanOpen: Boolean;
  WatchAvailable, WatchOverflow, WatcherAttempted: Boolean;
  ChangedPaths, ChangedStates: TStringList;
  Watcher: TAgentWorkspaceWatcher;
begin
  WatchAvailable := False;
  WatchOverflow := False;
  WatcherAttempted := Assigned(fWorkspaceWatcher);
  if Assigned(fWorkspaceWatcher) then begin
    Watcher := fWorkspaceWatcher;
    fWorkspaceWatcher := nil;
    ChangedPaths := TStringList.Create;
    ChangedStates := TStringList.Create;
    try
      WatchAvailable := Watcher.Finish(ChangedPaths, ChangedStates);
      WatchOverflow := Watcher.Overflow;
      for I := 0 to ChangedPaths.Count - 1 do begin
        Path := ExpandFileName(ChangedPaths[I]);
        for J := 0 to fTurnFilePaths.Count - 1 do
          if SameText(fTurnFilePaths[J], Path) then Break;
        if J = fTurnFilePaths.Count then begin
          fTurnFilePaths.Add(Path);
          fTurnFileStates.Add(ChangedStates[I]);
          fTurnFileDiffs.Add('');
          fTurnFileDiffSummaries.Add('');
        end else
          fTurnFileStates[J] := ChangedStates[I];
      end;
    finally
      ChangedStates.Free;
      ChangedPaths.Free;
      Watcher.Free;
    end;
  end;
  if fTurnFilePaths.Count = 0 then begin
    fPendingFileTools.Clear;
    if WatchOverflow then
      AppendSystemMessage('Workspace change tracking overflowed; some changed paths may be missing.');
    if WatcherAttempted and not WatchAvailable then
      AppendSystemMessage('Workspace change tracking was unavailable; Bash-based file changes may not be listed.');
    Exit;
  end;
  if WatchAvailable then
    Summary := #13#10#13#10 + '**Files changed this turn (' +
      IntToStr(fTurnFilePaths.Count) + '):** Expand a file below to review its change.' + #13#10
  else
    Summary := #13#10#13#10 + '**Files handled by file tools (' +
      IntToStr(fTurnFilePaths.Count) + '):** Expand a file below to review its change.' + #13#10;
  if not WatchAvailable then
    Summary := Summary + #13#10 +
      'Workspace watching was unavailable; Bash-based file changes may be missing.' +
      #13#10;
  if WatchOverflow then
    Summary := Summary + #13#10 +
      'Some workspace changes may be missing because the watcher buffer overflowed.' +
      #13#10;
  AppendAITextInternal(Summary);
  for I := 0 to fTurnFilePaths.Count - 1 do begin
    DiffText := fTurnFileDiffs[I];
    DiffSummary := fTurnFileDiffSummaries[I];
    if DiffText = '' then begin
      if SameText(fTurnFileStates[I], 'Deleted') then begin
        DiffSummary := 'File deleted';
        DiffText := 'The file was deleted during this turn; there is no current file to open.';
      end else begin
        DiffSummary := 'Diff unavailable';
        DiffText := 'This change came from a shell or unsupported file tool. Open the current file to review it.';
      end;
    end;
    CanOpen := False;
    if Assigned(fAgentProcess) then
      CanOpen := FileExists(fTurnFilePaths[I]) and
        AgentPathWithinWorkDir(fTurnFilePaths[I], fAgentProcess.WorkDir);
    UndoToken := fTurnFileUndoTokens.Values[fTurnFilePaths[I]];
    fTimeline.AddFileChange(fTurnFileStates[I], fTurnFilePaths[I], DiffText,
      DiffSummary, CanOpen, UndoToken, UndoToken <> '');
  end;
  ResetTurnFileOperations;
end;

procedure TAgentPanelFrame.UndoFileChange(const Token: String);
var Path, ErrorCode, Packet: String; Success, Stale: Boolean;
begin
  Success := False;
  Stale := False;
  ErrorCode := '';
  Path := fFileUndoManager.GetPath(Token);
  if Path = '' then
    ErrorCode := 'unavailable'
  else if IsAgentBusy then
    ErrorCode := 'busy'
  else if Assigned(fOnUndoFileCheck) and
      not fOnUndoFileCheck(Self, Path) then
    ErrorCode := 'editor_dirty'
  else begin
    Success := fFileUndoManager.UndoChange(Token, ErrorCode, Stale);
    if Success then begin
      fTimeline.SetFileChangeUndoState(Token, 'restored');
      if Assigned(fOnFileRestored) then fOnFileRestored(Self, Path);
    end else if Stale then
      fTimeline.SetFileChangeUndoState(Token, 'stale');
  end;
  Packet := '{"version":1,"type":"file-undo-result","undoToken":' +
    WebQuote(Token) + ',"success":' + LowerCase(BoolToStr(Success, True)) +
    ',"stale":' + LowerCase(BoolToStr(Stale, True)) +
    ',"errorCode":' + WebQuote(ErrorCode) + '}';
  if Assigned(fWeb) and fWeb.Ready then fWeb.PostJSON(WideString(Packet));
end;

procedure TAgentPanelFrame.AddToolEvent(const Event: TAgentEvent);
var
  Node: TTreeNode;
  I: Integer;
  Key, Summary: String;
  Lines: TStringList;
begin
  if Event.IsUpdate then Exit;
  Key := Event.ToolId;
  if Key = '' then Key := Event.EventId;
  if Key = '' then Key := 'activity-' + IntToStr(fTools.Items.Count);
  Node := fTools.Items.GetFirstNode;
  while Node <> nil do begin
    if (Node.Count > 0) and (Node.Item[0].Text = 'ID: ' + Key) then Break;
    Node := Node.GetNextSibling;
  end;
  if Node = nil then begin
    Summary := Event.ToolName;
    if Summary = '' then Summary := 'Activity';
    Node := fTools.Items.Add(nil, Summary);
    fTools.Items.AddChild(Node, 'ID: ' + Key);
  end;
  Summary := Event.FilePath;
  if Summary = '' then Summary := Event.Command;
  if Summary = '' then Summary := String(UTF8Decode(Event.ToolInput));
  if Event.Content <> '' then Summary := Event.Content;
  if Summary = '' then Summary := Event.Summary;
  if Event.IsError then begin
    Node.Text := Node.Text + ' [Failed]';
    fToolToggle.Caption := '> Tool activity - failure';
  end
  else if Event.EventType = aetToolResult then Node.Text := Node.Text + ' [Done]';
  if Event.IsError then
    fTimeline.AddTool(Key, Node.Text, Summary, 'failed', True)
  else if Event.EventType = aetToolResult then
    fTimeline.AddTool(Key, Node.Text, Summary, 'done', True)
  else
    fTimeline.AddTool(Key, Node.Text, Summary, 'running', False);
  Lines := TStringList.Create;
  try
    Lines.Text := Summary;
    for I := 0 to Lines.Count - 1 do fTools.Items.AddChild(Node, Lines[I]);
  finally
    Lines.Free;
  end;
end;
procedure TAgentPanelFrame.QuickActionClick(Sender: TObject);
begin
  if IsAgentBusy then Exit;
  Tag := fQuickActions.ItemIndex;
  if Assigned(fOnQuickAction) then fOnQuickAction(Self);
end;

function TAgentPanelFrame.AnswerCode: String;
var
  StartPos, EndPos: Integer;
  Tail: String;
begin
  if fWebCode <> '' then begin Result := fWebCode; Exit; end;
  Result := '';
  StartPos := Pos('```', fLastAnswer);
  if StartPos = 0 then Exit;
  Tail := Copy(fLastAnswer, StartPos + 3, MaxInt);
  StartPos := Pos(#10, Tail);
  if StartPos = 0 then Exit;
  Tail := Copy(Tail, StartPos + 1, MaxInt);
  EndPos := Pos('```', Tail);
  if EndPos = 0 then Exit;
  Result := Copy(Tail, 1, EndPos - 1);
end;

procedure TAgentPanelFrame.OpenCodeClick(Sender: TObject);
begin
  if IsAgentBusy then Exit;
  if AnswerCode = '' then begin
    MessageDlg('No complete fenced code block in the latest answer.', mtInformation, [mbOK], 0);
    Exit;
  end;
  if Assigned(fOnOpenCode) then fOnOpenCode(Self);
end;

procedure TAgentPanelFrame.TimelineOpenFile(Sender: TObject;
  const FileName: String);
begin
  OpenChangedFile(FileName);
end;

procedure TAgentPanelFrame.OpenChangedFile(const FileName: String);
var SafeName: String;
begin
  if not Assigned(fAgentProcess) or (Trim(fAgentProcess.WorkDir) = '') then Exit;
  SafeName := ExpandFileName(FileName);
  if not AgentPathWithinWorkDir(SafeName, fAgentProcess.WorkDir) then begin
    AppendSystemMessage('This file is outside the active working directory and cannot be opened from the change review.');
    Exit;
  end;
  if not FileExists(SafeName) then begin
    AppendSystemMessage('This file no longer exists in the working directory.');
    Exit;
  end;
  if Assigned(fOnOpenFile) then fOnOpenFile(Self, SafeName);
end;

procedure TAgentPanelFrame.CopyAnswerClick(Sender: TObject);
begin
  if fLastAnswer <> '' then Clipboard.AsText := fLastAnswer;
end;

procedure TAgentPanelFrame.btnSendClick(Sender: TObject);
begin
  SendCurrentInput;
end;

procedure TAgentPanelFrame.btnStopClick(Sender: TObject);
begin
  EndResponseWait;
  if Assigned(fAgentProcess) then
    fAgentProcess.SendInterrupt;
  SetStatus(asReady);
end;

procedure TAgentPanelFrame.btnAttachClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Title := 'Select a file or image to send to Claude';
    Dialog.Filter := 'Supported files|*.*';
    Dialog.Options := Dialog.Options + [ofAllowMultiSelect, ofFileMustExist];
    if Dialog.Execute then
      AddAttachmentList(Dialog.Files);
  finally
    Dialog.Free;
  end;
end;

procedure TAgentPanelFrame.btnPasteImageClick(Sender: TObject);
var
  FileName: String;
begin
  FileName := SaveClipboardImage;
  if FileName = '' then begin
    AppendSystemMessage('The clipboard does not contain a supported image.');
    Exit;
  end;
  if AddAttachment(FileName) then
    fTemporaryAttachments.Add(ExpandFileName(FileName))
  else begin
    DeleteFile(FileName);
    AppendSystemMessage('Could not add the clipboard image: ' + FileName);
  end;
end;

procedure TAgentPanelFrame.btnRemoveAttachmentClick(Sender: TObject);
var
  I: Integer;
begin
  for I := lbAttachments.Items.Count - 1 downto 0 do
    if lbAttachments.Selected[I] then
      RemoveAttachmentAt(I);
end;

procedure TAgentPanelFrame.memoInputKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = Ord('L')) and (ssCtrl in Shift) then begin
    Key := 0;
    memoInput.SetFocus;
    Exit;
  end;
  if (Key = VK_ESCAPE) and IsAgentBusy then begin
    Key := 0;
    btnStopClick(btnStop);
    Exit;
  end;

  // Enter (or Ctrl+Enter, according to the setting) sends. Shift+Enter
  // remains a normal multiline edit operation.
  if (Key = VK_RETURN) and
     ((not fSendOnCtrlEnter and not (ssShift in Shift)) or
      (fSendOnCtrlEnter and (ssCtrl in Shift) and not (ssShift in Shift))) then begin
    Key := 0;
    SendCurrentInput;
  end;
end;

procedure TAgentPanelFrame.reChatKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = Ord('L')) and (ssCtrl in Shift) then begin
    Key := 0;
    memoInput.SetFocus;
  end else if (Key = VK_ESCAPE) and IsAgentBusy then begin
    Key := 0;
    btnStopClick(btnStop);
  end;
end;

end.
