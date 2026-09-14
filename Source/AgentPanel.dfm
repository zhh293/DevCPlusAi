object AgentPanelFrame: TAgentPanelFrame
  Left = 0
  Top = 0
  Width = 400
  Height = 600
  HorzScrollBar.Visible = False
  VertScrollBar.Visible = False
  TabOrder = 0
  object StatusBar: TStatusBar
    Left = 0
    Top = 581
    Width = 400
    Height = 19
    Align = alBottom
    Panels = <
      item
        Text = '[OFF] Disconnected'
        Width = 150
      end
      item
        Width = 50
      end>
  end
  object reChat: TRichEdit
    Left = 0
    Top = 0
    Width = 400
    Height = 471
    Align = alClient
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
  object pnlInput: TPanel
    Left = 0
    Top = 431
    Width = 400
    Height = 150
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object pnlAttachments: TPanel
      Left = 0
      Top = 0
      Width = 240
      Height = 70
      Align = alTop
      BevelOuter = bvNone
      TabOrder = 0
      object pnlAttachmentTools: TPanel
        Left = 0
        Top = 0
        Width = 240
        Height = 28
        Align = alTop
        BevelOuter = bvNone
        TabOrder = 0
        object btnAttach: TButton
          Left = 0
          Top = 0
          Width = 74
          Height = 28
          Caption = 'Add file'
          TabOrder = 0
          OnClick = btnAttachClick
        end
        object btnPasteImage: TButton
          Left = 74
          Top = 0
          Width = 82
          Height = 28
          Caption = 'Paste image'
          TabOrder = 1
          OnClick = btnPasteImageClick
        end
        object btnRemoveAttachment: TButton
          Left = 170
          Top = 0
          Width = 70
          Height = 28
          Caption = 'Remove'
          TabOrder = 2
          OnClick = btnRemoveAttachmentClick
        end
      end
      object lbAttachments: TListBox
        Left = 0
        Top = 28
        Width = 240
        Height = 42
        Align = alClient
        ItemHeight = 16
        MultiSelect = True
        TabOrder = 1
      end
    end
    object btnSend: TButton
      Left = 320
      Top = 0
      Width = 80
      Height = 150
      Caption = 'Send'
      Default = True
      TabOrder = 3
      OnClick = btnSendClick
    end
    object btnStop: TButton
      Left = 240
      Top = 0
      Width = 80
      Height = 150
      Caption = 'Stop'
      TabOrder = 4
      Visible = False
      OnClick = btnStopClick
    end
    object memoInput: TMemo
      Left = 0
      Top = 0
      Width = 240
      Height = 110
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
