object FindForm: TFindForm
  Left = 478
  Top = 184
  Margins.Left = 2
  Margins.Top = 2
  Margins.Right = 2
  Margins.Bottom = 2
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Find Text'
  ClientHeight = 360
  ClientWidth = 323
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  FormStyle = fsStayOnTop
  KeyPreview = True
  PopupMenu = FindPopup
  Position = poMainFormCenter
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  DesignSize = (
    323
    360)
  TextHeight = 13
  object btnExecute: TButton
    Left = 8
    Top = 331
    Width = 98
    Height = 24
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Anchors = [akLeft, akBottom]
    Caption = 'Find'
    Default = True
    ModalResult = 1
    TabOrder = 0
    OnClick = btnExecuteClick
  end
  object btnCancel: TButton
    Left = 218
    Top = 331
    Width = 99
    Height = 24
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Anchors = [akLeft, akBottom]
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 1
    OnClick = btnCancelClick
  end
  object FindTabs: TTabControl
    Left = 0
    Top = 0
    Width = 323
    Height = 321
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Align = alTop
    TabOrder = 2
    Tabs.Strings = (
      'Find'
      'Find in files'
      'Replace'
      'Replace in files')
    TabIndex = 0
    OnChange = FindTabsChange
    object lblFind: TLabel
      Left = 8
      Top = 29
      Width = 56
      Height = 13
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = '&Text to find:'
      FocusControl = cboFindText
    end
    object lblReplace: TLabel
      Left = 8
      Top = 70
      Width = 65
      Height = 13
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Replace with:'
      FocusControl = cboFindText
    end
    object cboFindText: TComboBox
      Left = 8
      Top = 46
      Width = 309
      Height = 21
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      AutoComplete = False
      TabOrder = 0
      OnKeyUp = cboFindTextKeyUp
    end
    object grpOptions: TGroupBox
      Left = 8
      Top = 116
      Width = 150
      Height = 115
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = '  Options:  '
      TabOrder = 2
      object cbMatchCase: TCheckBox
        Left = 8
        Top = 16
        Width = 118
        Height = 17
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = 'C&ase sensitive'
        TabOrder = 0
      end
      object cbWholeWord: TCheckBox
        Left = 8
        Top = 39
        Width = 119
        Height = 17
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = '&Whole words only'
        TabOrder = 1
      end
      object cbPrompt: TCheckBox
        Left = 8
        Top = 89
        Width = 118
        Height = 17
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = '&Prompt on Replace'
        TabOrder = 2
      end
      object cbRegExp: TCheckBox
        Left = 8
        Top = 65
        Width = 119
        Height = 17
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = 'Regular Expression'
        TabOrder = 3
      end
    end
    object grpDirection: TGroupBox
      Left = 166
      Top = 116
      Width = 150
      Height = 69
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = '  Direction:  '
      TabOrder = 3
      object rbBackward: TRadioButton
        Left = 8
        Top = 42
        Width = 119
        Height = 16
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = '&Backward'
        TabOrder = 0
      end
      object rbForward: TRadioButton
        Left = 8
        Top = 18
        Width = 119
        Height = 16
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = '&Forward'
        Checked = True
        TabOrder = 1
        TabStop = True
      end
    end
    object grpWhere: TGroupBox
      Left = 166
      Top = 116
      Width = 150
      Height = 115
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = '  Where:  '
      TabOrder = 4
      object rbProjectFiles: TRadioButton
        Left = 8
        Top = 18
        Width = 119
        Height = 16
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = 'Files in Project'
        Checked = True
        TabOrder = 0
        TabStop = True
      end
      object rbOpenFiles: TRadioButton
        Left = 8
        Top = 42
        Width = 119
        Height = 16
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = 'Open Files'
        TabOrder = 1
      end
      object rbCurFile: TRadioButton
        Left = 8
        Top = 63
        Width = 119
        Height = 17
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = 'Current file'
        TabOrder = 2
      end
    end
    object grpScope: TGroupBox
      Left = 8
      Top = 242
      Width = 150
      Height = 67
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = '  Scope:  '
      TabOrder = 5
      object rbGlobal: TRadioButton
        Left = 8
        Top = 18
        Width = 119
        Height = 16
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = '&Global'
        Checked = True
        TabOrder = 0
        TabStop = True
      end
      object rbSelectedOnly: TRadioButton
        Left = 8
        Top = 42
        Width = 119
        Height = 16
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = '&Selected only'
        TabOrder = 1
      end
    end
    object grpOrigin: TGroupBox
      Left = 166
      Top = 242
      Width = 150
      Height = 67
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = '  Origin:  '
      TabOrder = 6
      object rbFromCursor: TRadioButton
        Left = 8
        Top = 18
        Width = 119
        Height = 16
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = 'From &cursor'
        Checked = True
        TabOrder = 0
        TabStop = True
      end
      object rbEntireScope: TRadioButton
        Left = 8
        Top = 42
        Width = 119
        Height = 16
        Margins.Left = 2
        Margins.Top = 2
        Margins.Right = 2
        Margins.Bottom = 2
        Caption = 'Entire &scope'
        TabOrder = 1
      end
    end
    object cboReplaceText: TComboBox
      Left = 8
      Top = 86
      Width = 309
      Height = 21
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      AutoComplete = False
      TabOrder = 1
      OnKeyUp = cboReplaceTextKeyUp
    end
  end
  object FindPopup: TPopupMenu
    Left = 112
    Top = 296
    object FindCut: TMenuItem
      Caption = 'Cut'
      ShortCut = 16472
      OnClick = FindCutClick
    end
    object FindCopy: TMenuItem
      Caption = 'Copy'
      ShortCut = 16451
      OnClick = FindCopyClick
    end
    object FindPaste: TMenuItem
      Caption = 'Paste'
      ShortCut = 16470
      OnClick = FindPasteClick
    end
    object N1: TMenuItem
      Caption = '-'
    end
    object FindSelAll: TMenuItem
      Caption = 'Select All'
      ShortCut = 16449
      OnClick = FindSelAllClick
    end
  end
end
