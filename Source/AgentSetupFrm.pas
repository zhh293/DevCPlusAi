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

    AgentSetupFrm.pas

    Sub-task P1.6 (part b): the first-run AI configuration wizard.

    Shown the first time the IDE starts with an empty ApiKey. Lets the user pick
    a provider, enter an API key (masked), optionally enter a custom endpoint,
    validate the CLI, or skip for now. On OK it writes through to devAgentConfig
    and persists via SaveSettings.
}
unit AgentSetupFrm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ExtCtrls, ShellAPI;

type
  TAgentSetupForm = class(TForm)
    lblTitle: TLabel;
    rgProvider: TRadioGroup;
    lblApiKey: TLabel;
    edtApiKey: TEdit;
    lblBaseUrl: TLabel;
    edtBaseUrl: TEdit;
    lblModel: TLabel;
    edtModel: TEdit;
    lblPermissionMode: TLabel;
    cboPermissionMode: TComboBox;
    lblMcpConfig: TLabel;
    edtMcpConfig: TEdit;
    lblPluginDirs: TLabel;
    edtPluginDirs: TEdit;
    lblSkillInfo: TLabel;
    btnValidate: TButton;
    lblHelp: TLabel;
    lblStatus: TLabel;
    btnOK: TButton;
    btnSkip: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure rgProviderClick(Sender: TObject);
    procedure btnValidateClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure btnSkipClick(Sender: TObject);
    procedure lblHelpClick(Sender: TObject);
  private
    function ProviderId: String;
    function PermissionModeId: String;
    procedure ApplyProviderDefaults;
    procedure LoadFromConfig;
  public
    procedure LoadText;
  end;

implementation

uses
  AgentConfig, AgentProcess, devCFG;

{$R *.dfm}

const
  PROVIDER_ANTHROPIC = 0;
  PROVIDER_OPENAI    = 1;
  PROVIDER_DEEPSEEK  = 2;
  PROVIDER_CUSTOM    = 3;

procedure TAgentSetupForm.FormCreate(Sender: TObject);
begin
  LoadText;
  LoadFromConfig;
  ApplyProviderDefaults;
end;

procedure TAgentSetupForm.LoadText;
begin
  // Match the IDE interface font where available.
  // devData is a singleton accessor that creates the instance on demand.
  Font.Name := devData.InterfaceFont;
  Font.Size := devData.InterfaceFontSize;

  Caption := 'AI 助手配置向导';
  lblTitle.Caption := '欢迎使用 AI 助手！请先完成基础配置。';
  rgProvider.Caption := '服务商';
  lblApiKey.Caption := 'API Key：';
  lblBaseUrl.Caption := '自定义端点（Base URL）：';
  lblModel.Caption := '模型：';
  lblPermissionMode.Caption := 'CLI 权限模式：';
  lblMcpConfig.Caption := 'MCP 配置文件（多个路径用 ; 分隔）：';
  lblPluginDirs.Caption := 'Plugin 目录或 ZIP（多个路径用 ; 分隔）：';
  lblSkillInfo.Caption := 'Skill：Claude 会自动读取项目 .claude\skills，以及已加载插件中的 Skill。';
  btnValidate.Caption := '验证';
  lblHelp.Caption := '如何获取 API Key？';
  lblStatus.Caption := '';
  btnOK.Caption := '确定';
  btnSkip.Caption := '跳过';
end;

function TAgentSetupForm.ProviderId: String;
begin
  case rgProvider.ItemIndex of
    PROVIDER_ANTHROPIC: Result := 'anthropic';
    PROVIDER_OPENAI:    Result := 'openai';
    PROVIDER_DEEPSEEK:  Result := 'deepseek';
    PROVIDER_CUSTOM:    Result := 'custom';
  else
    Result := 'anthropic';
  end;
end;

function TAgentSetupForm.PermissionModeId: String;
begin
  case cboPermissionMode.ItemIndex of
    1: Result := 'acceptEdits';
    2: Result := 'auto';
    3: Result := 'bypassPermissions';
    4: Result := 'dontAsk';
    5: Result := 'plan';
  else
    Result := 'default';
  end;
end;

procedure TAgentSetupForm.LoadFromConfig;
begin
  if not Assigned(devAgentConfig) then
    Exit;

  if SameText(devAgentConfig.Provider, 'openai') then
    rgProvider.ItemIndex := PROVIDER_OPENAI
  else if SameText(devAgentConfig.Provider, 'deepseek') then
    rgProvider.ItemIndex := PROVIDER_DEEPSEEK
  else if SameText(devAgentConfig.Provider, 'custom') then
    rgProvider.ItemIndex := PROVIDER_CUSTOM
  else
    rgProvider.ItemIndex := PROVIDER_ANTHROPIC;

  edtApiKey.Text := devAgentConfig.ApiKey;
  edtBaseUrl.Text := devAgentConfig.BaseUrl;
  edtModel.Text := devAgentConfig.Model;
  edtMcpConfig.Text := devAgentConfig.McpConfigFiles;
  edtPluginDirs.Text := devAgentConfig.PluginDirs;
  if SameText(devAgentConfig.PermissionMode, 'acceptEdits') then
    cboPermissionMode.ItemIndex := 1
  else if SameText(devAgentConfig.PermissionMode, 'auto') then
    cboPermissionMode.ItemIndex := 2
  else if SameText(devAgentConfig.PermissionMode, 'bypassPermissions') then
    cboPermissionMode.ItemIndex := 3
  else if SameText(devAgentConfig.PermissionMode, 'dontAsk') then
    cboPermissionMode.ItemIndex := 4
  else if SameText(devAgentConfig.PermissionMode, 'plan') then
    cboPermissionMode.ItemIndex := 5
  else
    cboPermissionMode.ItemIndex := 0;
end;

procedure TAgentSetupForm.ApplyProviderDefaults;
var
  custom: Boolean;
begin
  // All non-Anthropic providers need an endpoint understood by the Claude
  // CLI. Native OpenAI endpoints are not interchangeable with Anthropic ones,
  // so keep the endpoint visible instead of silently using the wrong API.
  custom := rgProvider.ItemIndex <> PROVIDER_ANTHROPIC;
  lblBaseUrl.Visible := custom;
  edtBaseUrl.Visible := custom;

  // Suggest a sensible default model / endpoint per provider when empty.
  if (edtModel.Text = '') or
     SameText(edtModel.Text, 'sonnet') or
     SameText(edtModel.Text, 'claude-3-5-sonnet-latest') or
     SameText(edtModel.Text, 'gpt-4o') or
     SameText(edtModel.Text, 'deepseek-chat') then
    case rgProvider.ItemIndex of
      PROVIDER_ANTHROPIC: edtModel.Text := 'sonnet';
      PROVIDER_OPENAI:    edtModel.Text := 'gpt-4o';
      PROVIDER_DEEPSEEK:  edtModel.Text := 'deepseek-chat';
    end;

  if (rgProvider.ItemIndex = PROVIDER_DEEPSEEK) and (edtBaseUrl.Text = '') then
    edtBaseUrl.Text := 'https://api.deepseek.com/anthropic';
end;

procedure TAgentSetupForm.rgProviderClick(Sender: TObject);
begin
  ApplyProviderDefaults;
end;

procedure TAgentSetupForm.btnValidateClick(Sender: TObject);
var
  proc: TAgentProcess;
  OldProvider, OldApiKey, OldBaseUrl, OldModel, OldPermissionMode: String;
  OldMcpConfigFiles, OldPluginDirs: String;
begin
  lblStatus.Font.Color := clNavy;
  lblStatus.Caption := '正在检测 CLI...';
  Update;

  // Validate the values currently visible in the dialog, without mutating the
  // saved configuration when the user later chooses Skip or Cancel.
  OldProvider := '';
  OldApiKey := '';
  OldBaseUrl := '';
  OldModel := '';
  OldPermissionMode := '';
  OldMcpConfigFiles := '';
  OldPluginDirs := '';
  if Assigned(devAgentConfig) then begin
    OldProvider := devAgentConfig.Provider;
    OldApiKey := devAgentConfig.ApiKey;
    OldBaseUrl := devAgentConfig.BaseUrl;
    OldModel := devAgentConfig.Model;
    OldPermissionMode := devAgentConfig.PermissionMode;
    OldMcpConfigFiles := devAgentConfig.McpConfigFiles;
    OldPluginDirs := devAgentConfig.PluginDirs;
    devAgentConfig.Provider := ProviderId;
    devAgentConfig.ApiKey := Trim(edtApiKey.Text);
    devAgentConfig.BaseUrl := Trim(edtBaseUrl.Text);
    devAgentConfig.Model := Trim(edtModel.Text);
    devAgentConfig.PermissionMode := PermissionModeId;
    devAgentConfig.McpConfigFiles := Trim(edtMcpConfig.Text);
    devAgentConfig.PluginDirs := Trim(edtPluginDirs.Text);
  end;

  proc := TAgentProcess.Create;
  try
    if Assigned(devAgentConfig) and (devAgentConfig.CliPath <> '') then
      proc.CliPath := devAgentConfig.CliPath;
    if proc.Start(ExtractFilePath(ParamStr(0))) then begin
      proc.Stop;
      lblStatus.Font.Color := clGreen;
      lblStatus.Caption := '[OK] CLI 可启动（未验证网络）';
    end else begin
      lblStatus.Font.Color := clRed;
      lblStatus.Caption := '[ERR] 无法启动 CLI：' + proc.LastError;
    end;
  finally
    proc.Free;
    if Assigned(devAgentConfig) then begin
      devAgentConfig.Provider := OldProvider;
      devAgentConfig.ApiKey := OldApiKey;
      devAgentConfig.BaseUrl := OldBaseUrl;
      devAgentConfig.Model := OldModel;
      devAgentConfig.PermissionMode := OldPermissionMode;
      devAgentConfig.McpConfigFiles := OldMcpConfigFiles;
      devAgentConfig.PluginDirs := OldPluginDirs;
    end;
  end;
end;

procedure TAgentSetupForm.btnOKClick(Sender: TObject);
begin
  if Trim(edtApiKey.Text) = '' then begin
    lblStatus.Font.Color := clRed;
    lblStatus.Caption := '请填写 API Key，或点击「跳过」。';
    edtApiKey.SetFocus;
    Exit;
  end;
  if (rgProvider.ItemIndex <> PROVIDER_ANTHROPIC) and
     (Trim(edtBaseUrl.Text) = '') then begin
    lblStatus.Font.Color := clRed;
    lblStatus.Caption := '该服务商需要填写兼容 Anthropic API 的 Base URL。';
    edtBaseUrl.SetFocus;
    Exit;
  end;

  if Assigned(devAgentConfig) then begin
    devAgentConfig.Enabled := True;
    devAgentConfig.Provider := ProviderId;
    devAgentConfig.ApiKey := Trim(edtApiKey.Text);
    devAgentConfig.Model := Trim(edtModel.Text);
    devAgentConfig.PermissionMode := PermissionModeId;
    devAgentConfig.McpConfigFiles := Trim(edtMcpConfig.Text);
    devAgentConfig.PluginDirs := Trim(edtPluginDirs.Text);
    if edtBaseUrl.Visible then
      devAgentConfig.BaseUrl := Trim(edtBaseUrl.Text);
    if not edtBaseUrl.Visible then
      devAgentConfig.BaseUrl := '';
    devAgentConfig.SaveSettings;
  end;

  ModalResult := mrOk;
end;

procedure TAgentSetupForm.btnSkipClick(Sender: TObject);
begin
  // Leave ApiKey empty; the panel will show a "not configured" state.
  ModalResult := mrCancel;
end;

procedure TAgentSetupForm.lblHelpClick(Sender: TObject);
var
  url: String;
begin
  case rgProvider.ItemIndex of
    PROVIDER_OPENAI:   url := 'https://platform.openai.com/api-keys';
    PROVIDER_DEEPSEEK: url := 'https://platform.deepseek.com/api_keys';
  else
    url := 'https://console.anthropic.com/settings/keys';
  end;
  ShellExecute(0, 'open', PChar(url), nil, nil, SW_SHOWNORMAL);
end;

procedure TAgentSetupForm.FormKeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    btnSkip.Click;
end;

procedure TAgentSetupForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
end;

end.
