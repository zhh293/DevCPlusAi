object AgentPanelFrame: TAgentPanelFrame
  Left = 0
  Top = 0
  Width = 400
  Height = 600
  Constraints.MinHeight = 300
  Constraints.MinWidth = 280
  HorzScrollBar.Visible = False
  VertScrollBar.Visible = False
  TabOrder = 0
  ShowHint = True
  object pnlHeader: TPanel
    Left = 0
    Top = 0
    Width = 400
    Height = 40
    Align = alTop
    BevelOuter = bvNone
    ParentColor = True
    TabOrder = 0
    object lblTitle: TLabel
      Left = 8
      Top = 11
      Width = 120
      Height = 17
      Caption = 'AI Assistant'
    end
    object btnSettings: TButton
      Left = 312
      Top = 8
      Width = 80
      Height = 24
      Anchors = [akTop, akRight]
      Caption = 'Settings...'
      TabOrder = 0
      OnClick = btnSettingsClick
    end
  end
  object StatusBar: TStatusBar
    Left = 0
    Top = 581
    Width = 400
    Height = 19
    Align = alBottom
    Panels = <
      item
        Text = 'Disconnected'
        Width = 112
      end
      item
        Width = 200
      end>
    ParentFont = True
  end
  object pnlChat: TPanel
    Left = 0
    Top = 40
    Width = 400
    Height = 395
    Align = alClient
    BevelOuter = bvNone
    BorderWidth = 12
    Color = clWindow
    TabOrder = 1
    object reChat: TRichEdit
      Left = 8
      Top = 8
      Width = 384
      Height = 379
      Align = alClient
      BorderStyle = bsNone
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 0
      OnKeyDown = reChatKeyDown
      WordWrap = True
    end
  end
  object pnlInput: TPanel
    Left = 0
    Top = 429
    Width = 400
    Height = 152
    Align = alBottom
    BevelOuter = bvNone
    BorderWidth = 12
    ParentColor = True
    TabOrder = 2
    object pnlAttachmentTools: TPanel
      Left = 12
      Top = 8
      Width = 376
      Height = 30
      Align = alTop
      BevelOuter = bvNone
      ParentColor = True
      TabOrder = 0
      object btnAttach: TButton
        Left = 0
        Top = 0
        Width = 74
        Height = 24
        Caption = 'Add file'
        TabOrder = 0
        OnClick = btnAttachClick
      end
      object btnPasteImage: TButton
        Left = 80
        Top = 0
        Width = 90
        Height = 24
        Caption = 'Paste image'
        TabOrder = 1
        OnClick = btnPasteImageClick
      end
      object btnRemoveAttachment: TButton
        Left = 304
        Top = 0
        Width = 72
        Height = 24
        Anchors = [akTop, akRight]
        Caption = 'Remove'
        Enabled = False
        TabOrder = 2
        OnClick = btnRemoveAttachmentClick
      end
    end
    object pnlAttachments: TPanel
      Left = 12
      Top = 38
      Width = 376
      Height = 44
      Align = alTop
      BevelOuter = bvNone
      ParentColor = True
      TabOrder = 1
      Visible = False
      object lbAttachments: TListBox
        Left = 0
        Top = 0
        Width = 376
        Height = 44
        Align = alClient
        ItemHeight = 16
        MultiSelect = True
        TabOrder = 0
      end
    end
    object pnlSendTools: TPanel
      Left = 12
      Top = 114
      Width = 376
      Height = 30
      Align = alBottom
      BevelOuter = bvNone
      ParentColor = True
      TabOrder = 3
      object lblSendHint: TLabel
        Left = 0
        Top = 10
        Width = 175
        Height = 17
        AutoSize = False
        Caption = 'Enter to send'
      end
      object btnSend: TButton
        Left = 296
        Top = 4
        Width = 80
        Height = 26
        Anchors = [akTop, akRight]
        Caption = 'Send'
        TabOrder = 0
        OnClick = btnSendClick
      end
      object btnStop: TButton
        Left = 296
        Top = 4
        Width = 80
        Height = 26
        Anchors = [akTop, akRight]
        Caption = 'Stop'
        TabOrder = 1
        Visible = False
        OnClick = btnStopClick
      end
    end
    object memoInput: TMemo
      Left = 12
      Top = 38
      Width = 376
      Height = 76
      Align = alClient
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      ScrollBars = ssVertical
      TabOrder = 2
      WantReturns = True
      OnKeyDown = memoInputKeyDown
    end
  end
end
