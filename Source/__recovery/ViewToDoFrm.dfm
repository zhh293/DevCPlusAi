object ViewToDoForm: TViewToDoForm
  Left = 486
  Top = 308
  Margins.Left = 2
  Margins.Top = 2
  Margins.Right = 2
  Margins.Bottom = 2
  BorderStyle = bsSizeToolWin
  Caption = 'To-Do list'
  ClientHeight = 502
  ClientWidth = 623
  Color = clBtnFace
  Constraints.MinHeight = 109
  Constraints.MinWidth = 315
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 15
  object lv: TListView
    Left = 0
    Top = 33
    Width = 623
    Height = 442
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Align = alClient
    Checkboxes = True
    Columns = <
      item
        Caption = 'Done'
        Width = 45
      end
      item
        Caption = 'Priority'
        Width = 49
      end
      item
        Caption = 'Description'
        Width = 281
      end
      item
        Caption = 'Filename'
        Width = 154
      end
      item
        Caption = 'User'
        Width = 96
      end>
    ReadOnly = True
    RowSelect = True
    SortType = stBoth
    TabOrder = 0
    ViewStyle = vsReport
    OnColumnClick = lvColumnClick
    OnCompare = lvCompare
    OnCustomDrawItem = lvCustomDrawItem
    OnCustomDrawSubItem = lvCustomDrawSubItem
    OnDblClick = lvDblClick
    OnMouseDown = lvMouseDown
  end
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 623
    Height = 33
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 1
    DesignSize = (
      623
      33)
    object lblFilter: TLabel
      Left = 22
      Top = 6
      Width = 29
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Anchors = [akLeft, akBottom]
      Caption = 'Filter:'
    end
    object cmbFilter: TComboBox
      Left = 109
      Top = 6
      Width = 359
      Height = 28
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Style = csDropDownList
      Anchors = [akLeft, akBottom]
      TabOrder = 0
      OnChange = cmbFilterChange
      Items.Strings = (
        'All files (in project and not)'
        'Open files only (in project and not)'
        'All project files'
        'Open project files only'
        'Non-project open files'
        'Current file only')
    end
  end
  object Panel2: TPanel
    Left = 0
    Top = 475
    Width = 623
    Height = 27
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 2
    DesignSize = (
      623
      27)
    object chkNoDone: TCheckBox
      Left = 9
      Top = 7
      Width = 308
      Height = 14
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Anchors = [akLeft, akBottom]
      Caption = 'Don'#39't show items marked as done'
      TabOrder = 0
      OnClick = chkNoDoneClick
      ExplicitTop = 6
    end
    object btnClose: TButton
      Left = 532
      Top = 0
      Width = 80
      Height = 27
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Anchors = [akRight, akBottom]
      Cancel = True
      Caption = 'Close'
      TabOrder = 1
      OnClick = btnCloseClick
      ExplicitTop = -1
    end
  end
end
