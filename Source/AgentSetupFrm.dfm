object AgentSetupForm: TAgentSetupForm
  Left = 400
  Top = 300
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'AI Setup'
  ClientHeight = 698
  ClientWidth = 380
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  OldCreateOrder = True
  Position = poMainFormCenter
  OnClose = FormClose
  OnCreate = FormCreate
  OnKeyUp = FormKeyUp
  PixelsPerInch = 96
  TextHeight = 15
  object lblTitle: TLabel
    Left = 16
    Top = 12
    Width = 60
    Height = 15
    Caption = 'Welcome'
  end
  object lblApiKey: TLabel
    Left = 16
    Top = 132
    Width = 50
    Height = 15
    Caption = 'API Key:'
  end
  object lblBaseUrl: TLabel
    Left = 16
    Top = 188
    Width = 90
    Height = 15
    Caption = 'Base URL:'
  end
  object lblModel: TLabel
    Left = 16
    Top = 244
    Width = 40
    Height = 15
    Caption = 'Model:'
  end
  object lblFontSize: TLabel
    Left = 252
    Top = 244
    Width = 90
    Height = 15
    Caption = 'Panel font size:'
  end
  object lblCliPath: TLabel
    Left = 16
    Top = 300
    Width = 240
    Height = 15
    Caption = 'Claude CLI path (empty uses bundled runtime):'
  end
  object lblPermissionMode: TLabel
    Left = 16
    Top = 356
    Width = 100
    Height = 15
    Caption = 'Permission mode:'
  end
  object lblSendKey: TLabel
    Left = 252
    Top = 356
    Width = 60
    Height = 15
    Caption = 'Send key:'
  end
  object lblMcpConfig: TLabel
    Left = 16
    Top = 406
    Width = 230
    Height = 15
    Caption = 'MCP config files (semicolon separated):'
  end
  object edtMcpConfig: TEdit
    Left = 16
    Top = 424
    Width = 348
    Height = 23
    TabOrder = 9
  end
  object lblPluginDirs: TLabel
    Left = 16
    Top = 456
    Width = 230
    Height = 15
    Caption = 'Plugin dirs or ZIP files (semicolon separated):'
  end
  object edtPluginDirs: TEdit
    Left = 16
    Top = 474
    Width = 348
    Height = 23
    TabOrder = 10
  end
  object lblSystemPrompt: TLabel
    Left = 16
    Top = 506
    Width = 150
    Height = 15
    Caption = 'Additional system prompt:'
  end
  object memoSystemPrompt: TMemo
    Left = 16
    Top = 524
    Width = 348
    Height = 60
    ScrollBars = ssVertical
    TabOrder = 11
  end
  object lblSkillInfo: TLabel
    Left = 16
    Top = 592
    Width = 348
    Height = 30
    AutoSize = False
    Caption = 'Skills are discovered from the project .claude\skills directory.'
    WordWrap = True
  end
  object cboPermissionMode: TComboBox
    Left = 16
    Top = 374
    Width = 230
    Height = 23
    Style = csDropDownList
    ItemIndex = 0
    TabOrder = 7
    Text = 'manual'
    Items.Strings = (
      'manual'
      'acceptEdits'
      'auto'
      'bypassPermissions'
      'dontAsk'
      'plan')
  end
  object cboSendKey: TComboBox
    Left = 252
    Top = 374
    Width = 112
    Height = 23
    Style = csDropDownList
    ItemIndex = 0
    TabOrder = 8
    Text = 'Enter'
    Items.Strings = (
      'Enter'
      'Ctrl+Enter')
  end
  object lblHelp: TLabel
    Left = 240
    Top = 132
    Width = 120
    Height = 15
    Cursor = crHandPoint
    Caption = 'How to get a key?'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clBlue
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = [fsUnderline]
    ParentFont = False
    OnClick = lblHelpClick
  end
  object lblStatus: TLabel
    Left = 16
    Top = 628
    Width = 348
    Height = 24
    AutoSize = False
    Caption = ''
    WordWrap = True
  end
  object rgProvider: TRadioGroup
    Left = 16
    Top = 36
    Width = 348
    Height = 84
    Caption = 'Provider'
    Columns = 2
    ItemIndex = 0
    Items.Strings = (
      'Anthropic'
      'OpenAI'
      'DeepSeek'
      'Custom')
    TabOrder = 0
    OnClick = rgProviderClick
  end
  object edtApiKey: TEdit
    Left = 16
    Top = 150
    Width = 280
    Height = 23
    PasswordChar = '*'
    TabOrder = 1
  end
  object btnValidate: TButton
    Left = 302
    Top = 150
    Width = 62
    Height = 23
    Caption = 'Validate'
    TabOrder = 2
    OnClick = btnValidateClick
  end
  object edtBaseUrl: TEdit
    Left = 16
    Top = 206
    Width = 348
    Height = 23
    TabOrder = 3
  end
  object edtModel: TComboBox
    Left = 16
    Top = 262
    Width = 230
    Height = 23
    ItemHeight = 15
    TabOrder = 4
  end
  object edtFontSize: TEdit
    Left = 252
    Top = 262
    Width = 112
    Height = 23
    TabOrder = 5
    Text = '10'
  end
  object edtCliPath: TEdit
    Left = 16
    Top = 318
    Width = 348
    Height = 23
    TabOrder = 6
  end
  object btnOK: TButton
    Left = 200
    Top = 660
    Width = 75
    Height = 25
    Caption = 'OK'
    Default = True
    TabOrder = 12
    OnClick = btnOKClick
  end
  object btnSkip: TButton
    Left = 289
    Top = 660
    Width = 75
    Height = 25
    Caption = 'Skip'
    TabOrder = 13
    OnClick = btnSkipClick
  end
end
