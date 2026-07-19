{
    This file is part of Red Panda Dev-C++ (AI Agent Integration)

    Red Panda Dev-C++ is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    AgentProtocol.pas

    Claude Code stream-json protocol parsing.

    Claude emits a JSON object per line, but one line can contain several
    Anthropic content blocks. The parser therefore exposes ParseLineEvents,
    while ParseLine remains as a compatibility helper for older callers.
    Parsing is deliberately tolerant: malformed input becomes an unknown
    event with the original line preserved.
}
unit AgentProtocol;

interface

uses
  Classes, SysUtils, uLkJSON;

type
  TAgentEventType = (
    aetAssistant,       // assistant text or thinking content
    aetToolUse,         // tool call started or completed input
    aetToolResult,      // tool result returned by Claude/tool runtime
    aetResult,          // end of a turn
    aetError,           // error message
    aetSystem,          // lifecycle, init, hook and extension status
    aetUser,            // replayed user message
    aetProgress,        // tool/task progress
    aetRateLimit,       // rate-limit status
    aetPromptSuggestion,// suggested next prompt
    aetUnknown          // unrecognized type (fallback)
  );

  TAgentEvent = record
    EventType: TAgentEventType;
    TopLevelType: String;    // original top-level JSON type
    Subtype: String;         // system/result/stream subtype
    SessionId: String;       // Claude session id
    EventId: String;         // event uuid when supplied
    MessageId: String;       // Anthropic message id
    ParentToolUseId: String; // parent tool/sub-agent correlation id
    Model: String;            // model name when supplied by Claude
    ContentType: String;     // text, thinking, tool_use, image, document ...
    BlockIndex: String;      // stream content-block index
    Content: String;         // display text or tool result text
    Summary: String;         // compact human-readable status summary
    ToolName: String;        // tool name
    ToolId: String;          // tool_use id, used to correlate result events
    ToolInput: String;       // complete or partial tool input JSON
    FilePath: String;        // path involved in a tool call
    Command: String;         // command involved in a tool call
    StopReason: String;      // end_turn, tool_use, max_tokens ...
    Usage: String;            // usage object preserved as JSON
    PermissionDenials: String;// permission denials preserved as JSON
    CostUSD: String;          // total_cost_usd when supplied
    DurationMs: String;       // duration_ms when supplied
    RawJSON: String;          // original JSON line
    IsError: Boolean;         // tool/result/rate-limit error flag
    IsPartial: Boolean;       // stream delta or partial tool input
    IsUpdate: Boolean;        // update to an already displayed tool call
    IsProtocolOnly: Boolean;  // framing event with no user-facing content
    IsReplay: Boolean;        // user message replayed by Claude CLI
  end;

  TAgentEventArray = array of TAgentEvent;

// Parse one JSONL line. A line may produce multiple events (for example an
// assistant message containing text plus two tool_use blocks).
function ParseLineEvents(const Line: String; var Events: TAgentEventArray): Integer;

// Compatibility helper. It returns the first event from ParseLineEvents.
function ParseLine(const Line: String): TAgentEvent;

// Clear stream/tool correlation state when the Claude child process changes.
procedure ResetProtocolState;

// True when the event marks the end of a turn.
function IsStreamComplete(const Event: TAgentEvent): Boolean;

// Extract the file path referenced by a tool_use event (if any).  Keep this
// name distinct from SysUtils.ExtractFilePath because units importing both
// APIs otherwise resolve ordinary string paths to the event overload.
function ExtractEventFilePath(const Event: TAgentEvent): String;

implementation

uses
  Variants;

type
  TAgentToolInputState = class
    ToolId: String;
    ToolName: String;
    BlockIndex: String;
    PartialJSON: String;
  end;

var
  GToolInputs: TList;
  GStreamMessageId: String;

function GetStr(Node: TlkJSONbase; const Name: WideString): String;
var
  FieldNode: TlkJSONbase;
begin
  Result := '';
  if Node = nil then
    Exit;
  FieldNode := Node.Field[Name];
  if Assigned(FieldNode) and not (FieldNode is TlkJSONobject) and
     not (FieldNode is TlkJSONlist) then
    Result := VarToStr(FieldNode.Value);
end;

function GetObj(Node: TlkJSONbase; const Name: WideString): TlkJSONbase;
begin
  Result := nil;
  if Node <> nil then
    Result := Node.Field[Name];
end;

function GetJSONText(Node: TlkJSONbase): String;
begin
  Result := '';
  if Node <> nil then
    Result := TlkJSON.GenerateText(Node);
end;

function GetNodeText(Node: TlkJSONbase): String;
begin
  Result := '';
  if Node = nil then
    Exit;
  if Node is TlkJSONobject then begin
    Result := GetStr(Node, 'text');
    if Result = '' then
      Result := GetStr(Node, 'content');
    if Result = '' then
      Result := GetJSONText(Node);
  end else if Node is TlkJSONlist then
    Result := GetJSONText(Node)
  else
    Result := VarToStr(Node.Value);
end;

function GetContentText(Node: TlkJSONbase): String;
var
  I: Integer;
  Child: TlkJSONbase;
  BlockType: String;
begin
  Result := '';
  if Node = nil then
    Exit;

  if Node is TlkJSONlist then begin
    for I := 0 to Node.Count - 1 do begin
      Child := Node.Child[I];
      if Child <> nil then
        Result := Result + GetContentText(Child);
    end;
    Exit;
  end;

  if not (Node is TlkJSONobject) then begin
    Result := VarToStr(Node.Value);
    Exit;
  end;

  BlockType := LowerCase(GetStr(Node, 'type'));
  if (BlockType = 'image') or (BlockType = 'document') then begin
    Result := '[' + BlockType + ' content]';
    Exit;
  end;
  if (BlockType = 'text') or (BlockType = 'thinking') or
     (BlockType = 'redacted_thinking') then begin
    Result := GetStr(Node, 'text');
    if Result = '' then
      Result := GetStr(Node, 'thinking');
    Exit;
  end;
  if BlockType = 'tool_result' then begin
    Result := GetContentText(GetObj(Node, 'content'));
    if Result = '' then
      Result := GetStr(Node, 'result');
    Exit;
  end;

  Result := GetContentText(GetObj(Node, 'content'));
  if Result = '' then
    Result := GetStr(Node, 'text');
  if Result = '' then
    Result := GetStr(Node, 'message');
  if Result = '' then
    Result := GetJSONText(Node);
end;

function ReadBoolean(Node: TlkJSONbase; const Name: String): Boolean;
var
  Value: String;
begin
  Value := LowerCase(GetStr(Node, Name));
  Result := (Value = 'true') or (Value = '1') or (Value = 'yes');
end;

procedure InitEvent(var Event: TAgentEvent; const Line: String);
begin
  Event.EventType := aetUnknown;
  Event.TopLevelType := '';
  Event.Subtype := '';
  Event.SessionId := '';
  Event.EventId := '';
  Event.MessageId := '';
  Event.ParentToolUseId := '';
  Event.Model := '';
  Event.ContentType := '';
  Event.BlockIndex := '';
  Event.Content := '';
  Event.Summary := '';
  Event.ToolName := '';
  Event.ToolId := '';
  Event.ToolInput := '';
  Event.FilePath := '';
  Event.Command := '';
  Event.StopReason := '';
  Event.Usage := '';
  Event.PermissionDenials := '';
  Event.CostUSD := '';
  Event.DurationMs := '';
  Event.RawJSON := Line;
  Event.IsError := False;
  Event.IsPartial := False;
  Event.IsUpdate := False;
  Event.IsProtocolOnly := False;
  Event.IsReplay := False;
end;

procedure FillMessageMetadata(MessageNode: TlkJSONbase; var Event: TAgentEvent);
begin
  if MessageNode = nil then
    Exit;
  if Event.MessageId = '' then
    Event.MessageId := GetStr(MessageNode, 'id');
  if Event.Model = '' then
    Event.Model := GetStr(MessageNode, 'model');
  if Event.StopReason = '' then
    Event.StopReason := GetStr(MessageNode, 'stop_reason');
  if Event.Usage = '' then
    Event.Usage := GetJSONText(GetObj(MessageNode, 'usage'));
  if Event.SessionId = '' then begin
    Event.SessionId := GetStr(MessageNode, 'session_id');
    if Event.SessionId = '' then
      Event.SessionId := GetStr(MessageNode, 'sessionId');
  end;
end;

procedure FillMetadata(Node: TlkJSONbase; var Event: TAgentEvent);
var
  MessageNode: TlkJSONbase;
begin
  if Node = nil then
    Exit;
  if Event.TopLevelType = '' then
    Event.TopLevelType := GetStr(Node, 'type');
  if Event.Subtype = '' then
    Event.Subtype := GetStr(Node, 'subtype');
  if Event.SessionId = '' then begin
    Event.SessionId := GetStr(Node, 'session_id');
    if Event.SessionId = '' then
      Event.SessionId := GetStr(Node, 'sessionId');
  end;
  Event.EventId := GetStr(Node, 'uuid');
  if Event.EventId = '' then
    Event.EventId := GetStr(Node, 'event_id');
  Event.ParentToolUseId := GetStr(Node, 'parent_tool_use_id');
  if Event.ParentToolUseId = '' then
    Event.ParentToolUseId := GetStr(Node, 'parentToolUseId');
  Event.Model := GetStr(Node, 'model');
  Event.StopReason := GetStr(Node, 'stop_reason');
  Event.Usage := GetJSONText(GetObj(Node, 'usage'));
  Event.PermissionDenials := GetJSONText(GetObj(Node, 'permission_denials'));
  Event.CostUSD := GetStr(Node, 'total_cost_usd');
  Event.DurationMs := GetStr(Node, 'duration_ms');
  Event.IsError := ReadBoolean(Node, 'is_error');

  MessageNode := GetObj(Node, 'message');
  if MessageNode <> nil then
    FillMessageMetadata(MessageNode, Event);
end;

procedure AppendEvent(var Events: TAgentEventArray; const Event: TAgentEvent);
var
  N: Integer;
begin
  N := Length(Events);
  SetLength(Events, N + 1);
  Events[N] := Event;
end;

function FindToolInput(const ToolId, BlockIndex: String): TAgentToolInputState;
var
  I: Integer;
  State: TAgentToolInputState;
begin
  Result := nil;
  if GToolInputs = nil then
    Exit;
  for I := 0 to GToolInputs.Count - 1 do begin
    State := TAgentToolInputState(GToolInputs[I]);
    if (ToolId <> '') and SameText(State.ToolId, ToolId) then begin
      Result := State;
      Exit;
    end;
    if (BlockIndex <> '') and SameText(State.BlockIndex, BlockIndex) then begin
      Result := State;
      Exit;
    end;
  end;
end;

procedure RememberToolInput(const Event: TAgentEvent);
var
  State: TAgentToolInputState;
begin
  if GToolInputs = nil then
    GToolInputs := TList.Create;
  State := FindToolInput(Event.ToolId, Event.BlockIndex);
  if State = nil then begin
    State := TAgentToolInputState.Create;
    GToolInputs.Add(State);
  end;
  State.ToolId := Event.ToolId;
  State.ToolName := Event.ToolName;
  State.BlockIndex := Event.BlockIndex;
  if Event.ToolInput <> '' then
    State.PartialJSON := Event.ToolInput;
end;

procedure RemoveToolInput(State: TAgentToolInputState);
var
  I: Integer;
begin
  if (State = nil) or (GToolInputs = nil) then
    Exit;
  I := GToolInputs.IndexOf(State);
  if I >= 0 then begin
    GToolInputs.Delete(I);
    State.Free;
  end;
end;

procedure ExtractToolInput(Node: TlkJSONbase; var Event: TAgentEvent);
begin
  if Node = nil then
    Exit;
  Event.ToolInput := GetJSONText(Node);
  if Node is TlkJSONobject then begin
    Event.FilePath := GetStr(Node, 'path');
    if Event.FilePath = '' then
      Event.FilePath := GetStr(Node, 'file_path');
    if Event.FilePath = '' then
      Event.FilePath := GetStr(Node, 'filePath');
    Event.Command := GetStr(Node, 'command');
    if Event.Command = '' then
      Event.Command := GetStr(Node, 'cmd');
  end;
end;

procedure ParseToolBlock(Block: TlkJSONbase; var Event: TAgentEvent);
var
  InputNode: TlkJSONbase;
begin
  if Block = nil then
    Exit;
  Event.EventType := aetToolUse;
  Event.ContentType := 'tool_use';
  Event.ToolId := GetStr(Block, 'id');
  if Event.ToolId = '' then
    Event.ToolId := GetStr(Block, 'tool_use_id');
  Event.ToolName := GetStr(Block, 'name');
  if Event.ToolName = '' then
    Event.ToolName := GetStr(Block, 'tool');
  InputNode := GetObj(Block, 'input');
  if InputNode = nil then
    InputNode := GetObj(Block, 'parameters');
  ExtractToolInput(InputNode, Event);
end;

procedure ParseToolInputJSON(const Text: String; var Event: TAgentEvent);
var
  Node: TlkJSONbase;
begin
  if Text = '' then
    Exit;
  Node := nil;
  try
    try
      Node := TlkJSON.ParseText(Text);
    except
      Node := nil;
    end;
    if Node <> nil then
      ExtractToolInput(Node, Event);
  finally
    if Node <> nil then
      Node.Free;
  end;
end;

procedure ParseAssistantMessage(Node, MessageNode: TlkJSONbase;
  var Events: TAgentEventArray);
var
  Base, Event: TAgentEvent;
  ContentNode, Block: TlkJSONbase;
  I: Integer;
  BlockType: String;
begin
  InitEvent(Base, GetJSONText(Node));
  Base.EventType := aetAssistant;
  Base.TopLevelType := GetStr(Node, 'type');
  FillMetadata(Node, Base);
  FillMessageMetadata(MessageNode, Base);
  ContentNode := GetObj(MessageNode, 'content');
  if ContentNode = nil then
    ContentNode := GetObj(Node, 'content');

  if (ContentNode = nil) or not (ContentNode is TlkJSONlist) then begin
    if ContentNode <> nil then begin
      Event := Base;
      BlockType := LowerCase(GetStr(ContentNode, 'type'));
      Event.ContentType := BlockType;
      if BlockType = 'tool_use' then begin
        ParseToolBlock(ContentNode, Event);
        AppendEvent(Events, Event);
      end else begin
        if Event.ContentType = '' then
          Event.ContentType := 'text';
        Event.Content := GetContentText(ContentNode);
        if Event.Content <> '' then
          AppendEvent(Events, Event);
      end;
    end;
    Exit;
  end;

  for I := 0 to ContentNode.Count - 1 do begin
    Block := ContentNode.Child[I];
    if Block = nil then
      Continue;
    Event := Base;
    Event.BlockIndex := IntToStr(I);
    BlockType := LowerCase(GetStr(Block, 'type'));
    Event.ContentType := BlockType;
    if BlockType = 'tool_use' then begin
      ParseToolBlock(Block, Event);
      AppendEvent(Events, Event);
    end else if (BlockType = 'text') or (BlockType = 'thinking') or
                (BlockType = 'redacted_thinking') then begin
      Event.Content := GetContentText(Block);
      if Event.Content <> '' then
        AppendEvent(Events, Event);
    end else if (BlockType = 'image') or (BlockType = 'document') then begin
      Event.Content := '[' + BlockType + ' content]';
      Event.Summary := Event.Content;
      AppendEvent(Events, Event);
    end else begin
      Event.EventType := aetUnknown;
      Event.Content := GetJSONText(Block);
      AppendEvent(Events, Event);
    end;
  end;
end;

procedure ParseToolResultBlock(Node: TlkJSONbase; const Base: TAgentEvent;
  var Event: TAgentEvent);
var
  ContentNode: TlkJSONbase;
begin
  Event := Base;
  Event.EventType := aetToolResult;
  Event.ContentType := 'tool_result';
  Event.ToolId := GetStr(Node, 'tool_use_id');
  if Event.ToolId = '' then
    Event.ToolId := GetStr(Node, 'id');
  Event.IsError := ReadBoolean(Node, 'is_error');
  ContentNode := GetObj(Node, 'content');
  if ContentNode <> nil then
    Event.Content := GetContentText(ContentNode)
  else begin
    Event.Content := GetStr(Node, 'result');
    if Event.Content = '' then
      Event.Content := GetNodeText(Node);
  end;
  if Event.Content = '' then
    Event.Content := '[tool returned no text]';
end;

procedure ParseUserMessage(Node, MessageNode: TlkJSONbase;
  var Events: TAgentEventArray);
var
  Base, Event: TAgentEvent;
  ContentNode, Block: TlkJSONbase;
  I: Integer;
begin
  InitEvent(Base, GetJSONText(Node));
  Base.EventType := aetUser;
  Base.IsReplay := True;
  FillMetadata(Node, Base);
  FillMessageMetadata(MessageNode, Base);
  ContentNode := GetObj(MessageNode, 'content');
  if ContentNode = nil then
    ContentNode := GetObj(Node, 'content');

  if (ContentNode <> nil) and (ContentNode is TlkJSONlist) then begin
    for I := 0 to ContentNode.Count - 1 do begin
      Block := ContentNode.Child[I];
      if (Block <> nil) and SameText(GetStr(Block, 'type'), 'tool_result') then begin
        ParseToolResultBlock(Block, Base, Event);
        AppendEvent(Events, Event);
      end else if Block <> nil then begin
        Event := Base;
        Event.ContentType := GetStr(Block, 'type');
        Event.Content := GetContentText(Block);
        if Event.Content <> '' then
          AppendEvent(Events, Event);
      end;
    end;
  end else if ContentNode <> nil then begin
    Event := Base;
    Event.Content := GetContentText(ContentNode);
    AppendEvent(Events, Event);
  end;
end;

function SystemSummary(const Event: TAgentEvent; Node: TlkJSONbase): String;
var
  Name, HookEvent, ToolName, TaskId: String;
begin
  Name := Event.Subtype;
  HookEvent := GetStr(Node, 'hook_event');
  ToolName := GetStr(Node, 'tool_name');
  if ToolName = '' then
    ToolName := GetStr(Node, 'tool');
  TaskId := GetStr(Node, 'task_id');

  if SameText(Name, 'init') then begin
    Result := 'Claude 会话已初始化';
    if Event.Model <> '' then
      Result := Result + '（模型：' + Event.Model + '）';
  end
  else if Pos('hook_', LowerCase(Name)) = 1 then begin
    Result := 'Hook ' + Name;
    if HookEvent <> '' then
      Result := Result + ' (' + HookEvent + ')';
    if GetStr(Node, 'hook_name') <> '' then
      Result := Result + ': ' + GetStr(Node, 'hook_name');
  end else if (Name = 'task_started') or (Name = 'task_progress') or
              (Name = 'task_notification') then begin
    Result := '子任务 ' + Name;
    if TaskId <> '' then
      Result := Result + ': ' + TaskId;
  end else if Name = 'compact_boundary' then
    Result := 'Claude 已压缩上下文'
  else if Name = 'stop_hook_summary' then
    Result := 'Hook 执行汇总'
  else if Name = 'status' then
    Result := 'Claude 状态：' + GetStr(Node, 'status')
  else if Name <> '' then
    Result := Name
  else if ToolName <> '' then
    Result := ToolName
  else
    Result := 'Claude 系统事件';
end;

procedure ParseStreamEvent(Node: TlkJSONbase; var Events: TAgentEventArray);
var
  Nested, MessageNode, DeltaNode, BlockNode, UsageNode: TlkJSONbase;
  Base, Event: TAgentEvent;
  NestedType, DeltaType, BlockType, PartialJSON: String;
  State: TAgentToolInputState;
begin
  InitEvent(Base, GetJSONText(Node));
  Base.TopLevelType := 'stream_event';
  Base.EventType := aetSystem;
  FillMetadata(Node, Base);
  Nested := GetObj(Node, 'event');
  if Nested = nil then
    Nested := Node;
  NestedType := LowerCase(GetStr(Nested, 'type'));
  Base.Subtype := NestedType;
  Base.BlockIndex := GetStr(Nested, 'index');
  // uLkJSON represents a numeric zero with an empty Variant value in some
  // Delphi 7 builds.  Its serialized form is still correct and keeps block
  // correlation stable for the common index=0 stream.
  if Base.BlockIndex = '' then
    Base.BlockIndex := GetJSONText(GetObj(Nested, 'index'));

  if NestedType = 'message_start' then begin
    MessageNode := GetObj(Nested, 'message');
    FillMessageMetadata(MessageNode, Base);
    GStreamMessageId := Base.MessageId;
    Event := Base;
    Event.Summary := '消息开始';
    Event.IsProtocolOnly := True;
    AppendEvent(Events, Event);
    Exit;
  end;

  if Base.MessageId = '' then
    Base.MessageId := GStreamMessageId;

  if NestedType = 'content_block_start' then begin
    BlockNode := GetObj(Nested, 'content_block');
    BlockType := LowerCase(GetStr(BlockNode, 'type'));
    if BlockType = 'tool_use' then begin
      Event := Base;
      ParseToolBlock(BlockNode, Event);
      RememberToolInput(Event);
      Event.IsPartial := True;
      AppendEvent(Events, Event);
    end else begin
      Event := Base;
      Event.ContentType := BlockType;
      Event.Summary := '内容块开始：' + BlockType;
      Event.IsProtocolOnly := True;
      AppendEvent(Events, Event);
    end;
    Exit;
  end;

  if NestedType = 'content_block_delta' then begin
    DeltaNode := GetObj(Nested, 'delta');
    DeltaType := LowerCase(GetStr(DeltaNode, 'type'));
    Event := Base;
    Event.ContentType := StringReplace(DeltaType, '_delta', '', []);
    if DeltaType = 'text_delta' then begin
      Event.EventType := aetAssistant;
      Event.Content := GetStr(DeltaNode, 'text');
      Event.IsPartial := True;
      if Event.Content <> '' then
        AppendEvent(Events, Event);
    end else if DeltaType = 'thinking_delta' then begin
      Event.EventType := aetAssistant;
      Event.Content := GetStr(DeltaNode, 'thinking');
      if Event.Content = '' then
        Event.Content := GetStr(DeltaNode, 'text');
      Event.IsPartial := True;
      if Event.Content <> '' then
        AppendEvent(Events, Event);
    end else if DeltaType = 'input_json_delta' then begin
      PartialJSON := GetStr(DeltaNode, 'partial_json');
      State := FindToolInput('', Base.BlockIndex);
      if State <> nil then begin
        // content_block_start normally carries an empty input object.  The
        // following deltas contain the actual JSON document, so keeping the
        // serialized empty object would produce an invalid "{}{...}" stream.
        if State.PartialJSON = '{}' then
          State.PartialJSON := '';
        State.PartialJSON := State.PartialJSON + PartialJSON;
        Event.ToolId := State.ToolId;
        Event.ToolName := State.ToolName;
        Event.ToolInput := State.PartialJSON;
      end;
      Event.IsPartial := True;
      Event.IsProtocolOnly := True;
      AppendEvent(Events, Event);
    end else begin
      Event.Summary := '流式增量：' + DeltaType;
      Event.IsProtocolOnly := True;
      AppendEvent(Events, Event);
    end;
    Exit;
  end;

  if NestedType = 'content_block_stop' then begin
    State := FindToolInput('', Base.BlockIndex);
    if State <> nil then begin
      Event := Base;
      Event.EventType := aetToolUse;
      Event.ContentType := 'tool_use';
      Event.ToolId := State.ToolId;
      Event.ToolName := State.ToolName;
      Event.ToolInput := State.PartialJSON;
      ParseToolInputJSON(State.PartialJSON, Event);
      Event.IsUpdate := True;
      Event.IsPartial := False;
      AppendEvent(Events, Event);
      RemoveToolInput(State);
    end else begin
      Event := Base;
      Event.Summary := '内容块结束';
      Event.IsProtocolOnly := True;
      AppendEvent(Events, Event);
    end;
    Exit;
  end;

  if NestedType = 'message_delta' then begin
    DeltaNode := GetObj(Nested, 'delta');
    Event := Base;
    Event.StopReason := GetStr(DeltaNode, 'stop_reason');
    UsageNode := GetObj(Nested, 'usage');
    if UsageNode = nil then
      UsageNode := GetObj(DeltaNode, 'usage');
    Event.Usage := GetJSONText(UsageNode);
    Event.Summary := '消息增量结束';
    Event.IsProtocolOnly := True;
    AppendEvent(Events, Event);
    Exit;
  end;

  if NestedType = 'message_stop' then begin
    Event := Base;
    Event.Summary := '消息结束';
    Event.IsProtocolOnly := True;
    AppendEvent(Events, Event);
    Exit;
  end;

  Event := Base;
  Event.Summary := '未识别的流式事件：' + NestedType;
  Event.Content := GetJSONText(Nested);
  AppendEvent(Events, Event);
end;

procedure ParseSystemEvent(Node: TlkJSONbase; var Events: TAgentEventArray);
var
  Event: TAgentEvent;
  ContentNode: TlkJSONbase;
begin
  InitEvent(Event, GetJSONText(Node));
  Event.EventType := aetSystem;
  FillMetadata(Node, Event);
  if Event.Subtype = '' then
    Event.Subtype := Event.TopLevelType;
  if SameText(Event.Subtype, 'hook_response') and
     (GetStr(Node, 'exit_code') <> '') and
     (GetStr(Node, 'exit_code') <> '0') then
    Event.IsError := True;
  Event.Summary := SystemSummary(Event, Node);
  ContentNode := GetObj(Node, 'content');
  if ContentNode <> nil then
    Event.Content := GetContentText(ContentNode);
  if Event.Content = '' then
    Event.Content := GetStr(Node, 'message');
  if Event.Content = '' then
    Event.Content := GetStr(Node, 'output');
  if Event.Content = '' then
    Event.Content := GetStr(Node, 'stdout');
  if GetStr(Node, 'stderr') <> '' then begin
    if Event.Content <> '' then
      Event.Content := Event.Content + #13#10;
    Event.Content := Event.Content + GetStr(Node, 'stderr');
  end;
  AppendEvent(Events, Event);
end;

procedure ParseResultEvent(Node: TlkJSONbase; var Events: TAgentEventArray);
var
  Event: TAgentEvent;
  ResultNode: TlkJSONbase;
begin
  InitEvent(Event, GetJSONText(Node));
  Event.EventType := aetResult;
  FillMetadata(Node, Event);
  ResultNode := GetObj(Node, 'result');
  if ResultNode = nil then
    ResultNode := GetObj(Node, 'content');
  Event.Content := GetContentText(ResultNode);
  Event.IsError := Event.IsError or ((Event.Subtype <> '') and
    not SameText(Event.Subtype, 'success'));
  Event.Summary := '本轮结束';
  if Event.Subtype <> '' then
    Event.Summary := Event.Summary + '：' + Event.Subtype;
  if Event.DurationMs <> '' then
    Event.Summary := Event.Summary + '，耗时 ' + Event.DurationMs + ' ms';
  if Event.CostUSD <> '' then
    Event.Summary := Event.Summary + '，费用 $' + Event.CostUSD;
  if (Event.PermissionDenials <> '') and
     (Event.PermissionDenials <> '[]') then
    Event.Summary := Event.Summary + '，存在权限拒绝';
  AppendEvent(Events, Event);
end;

procedure ParseErrorEvent(Node: TlkJSONbase; var Events: TAgentEventArray);
var
  Event: TAgentEvent;
  ErrorNode: TlkJSONbase;
begin
  InitEvent(Event, GetJSONText(Node));
  Event.EventType := aetError;
  FillMetadata(Node, Event);
  Event.IsError := True;
  ErrorNode := GetObj(Node, 'error');
  if ErrorNode <> nil then
    Event.Content := GetContentText(ErrorNode);
  if Event.Content = '' then
    Event.Content := GetStr(Node, 'message');
  if Event.Content = '' then
    Event.Content := GetJSONText(Node);
  AppendEvent(Events, Event);
end;

procedure ParseGenericEvent(Node: TlkJSONbase; EventType: TAgentEventType;
  const Summary: String; var Events: TAgentEventArray);
var
  Event: TAgentEvent;
  ContentNode: TlkJSONbase;
begin
  InitEvent(Event, GetJSONText(Node));
  Event.EventType := EventType;
  FillMetadata(Node, Event);
  Event.Summary := Summary;
  if Event.Subtype <> '' then
    Event.Summary := Event.Summary + ': ' + Event.Subtype;
  if EventType = aetRateLimit then begin
    if GetStr(Node, 'status') <> '' then
      Event.Summary := Event.Summary + ' (' + GetStr(Node, 'status') + ')';
    if GetStr(Node, 'rate_limit_type') <> '' then
      Event.Summary := Event.Summary + ' ' + GetStr(Node, 'rate_limit_type');
  end else if EventType = aetProgress then begin
    if GetStr(Node, 'tool_name') <> '' then
      Event.Summary := Event.Summary + ': ' + GetStr(Node, 'tool_name');
    if GetStr(Node, 'tool_use_id') <> '' then
      Event.Summary := Event.Summary + ' [' + GetStr(Node, 'tool_use_id') + ']';
  end;
  ContentNode := GetObj(Node, 'content');
  if ContentNode = nil then
    ContentNode := GetObj(Node, 'output');
  if ContentNode = nil then
    ContentNode := GetObj(Node, 'text');
  if ContentNode <> nil then
    Event.Content := GetContentText(ContentNode);
  if Event.Content = '' then
    Event.Content := GetStr(Node, 'suggestedReply');
  if Event.Content = '' then
    Event.Content := GetStr(Node, 'suggestion');
  if Event.Content = '' then
    Event.Content := GetStr(Node, 'message');
  AppendEvent(Events, Event);
end;

function IsSystemLikeType(const TypeName: String): Boolean;
begin
  Result := SameText(TypeName, 'status') or
    SameText(TypeName, 'auth_status') or
    SameText(TypeName, 'compact_boundary') or
    SameText(TypeName, 'hook_started') or
    SameText(TypeName, 'hook_progress') or
    SameText(TypeName, 'hook_response') or
    SameText(TypeName, 'stop_hook_summary') or
    SameText(TypeName, 'task_started') or
    SameText(TypeName, 'task_progress') or
    SameText(TypeName, 'task_notification') or
    SameText(TypeName, 'files_persisted');
end;

function ParseLineEvents(const Line: String; var Events: TAgentEventArray): Integer;
var
  JS, MessageNode, ContentNode, Block, ResultNode: TlkJSONbase;
  TypeName, LowerType: String;
  Base, Event: TAgentEvent;
  I: Integer;
begin
  SetLength(Events, 0);
  Result := 0;
  if Trim(Line) = '' then
    Exit;

  JS := nil;
  try
    try
      JS := TlkJSON.ParseText(Line);
    except
      JS := nil;
    end;

    if (JS = nil) or not (JS is TlkJSONobject) then begin
      InitEvent(Event, Line);
      Event.Content := Line;
      AppendEvent(Events, Event);
      Result := Length(Events);
      Exit;
    end;

    TypeName := GetStr(JS, 'type');
    LowerType := LowerCase(TypeName);
    if LowerType = 'stream_event' then
      ParseStreamEvent(JS, Events)
    else if LowerType = 'assistant' then begin
      MessageNode := GetObj(JS, 'message');
      if MessageNode = nil then
        MessageNode := JS;
      ParseAssistantMessage(JS, MessageNode, Events);
    end else if LowerType = 'user' then begin
      MessageNode := GetObj(JS, 'message');
      if MessageNode = nil then
        MessageNode := JS;
      ParseUserMessage(JS, MessageNode, Events);
      if Length(Events) = 0 then begin
        InitEvent(Event, Line);
        Event.EventType := aetUser;
        Event.IsReplay := True;
        FillMetadata(JS, Event);
        ContentNode := GetObj(JS, 'content');
        Event.Content := GetContentText(ContentNode);
        AppendEvent(Events, Event);
      end;
    end else if (LowerType = 'tool_use') or (LowerType = 'tool-use') then begin
      InitEvent(Event, Line);
      Event.EventType := aetToolUse;
      FillMetadata(JS, Event);
      ParseToolBlock(JS, Event);
      AppendEvent(Events, Event);
    end else if (LowerType = 'tool_result') or (LowerType = 'tool-result') then begin
      InitEvent(Base, Line);
      FillMetadata(JS, Base);
      ParseToolResultBlock(JS, Base, Event);
      AppendEvent(Events, Event);
    end else if LowerType = 'system' then
      ParseSystemEvent(JS, Events)
    else if LowerType = 'result' then
      ParseResultEvent(JS, Events)
    else if LowerType = 'error' then
      ParseErrorEvent(JS, Events)
    else if LowerType = 'tool_progress' then
      ParseGenericEvent(JS, aetProgress, '工具执行进度', Events)
    else if LowerType = 'rate_limit_event' then
      ParseGenericEvent(JS, aetRateLimit, 'Claude 限流状态', Events)
    else if LowerType = 'prompt_suggestion' then
      ParseGenericEvent(JS, aetPromptSuggestion, 'Claude 建议', Events)
    else if IsSystemLikeType(TypeName) then
      ParseSystemEvent(JS, Events)
    else begin
      InitEvent(Event, Line);
      Event.TopLevelType := TypeName;
      Event.Content := Line;
      Event.Summary := '未识别的 Claude 事件：' + TypeName;
      AppendEvent(Events, Event);
    end;

    // A valid event with no display payload is still returned to preserve
    // protocol observability and allow the caller to inspect its metadata.
    if Length(Events) = 0 then begin
      InitEvent(Event, Line);
      Event.TopLevelType := TypeName;
      Event.IsProtocolOnly := True;
      AppendEvent(Events, Event);
    end;
    for I := 0 to Length(Events) - 1 do
      Events[I].RawJSON := Line;
    Result := Length(Events);
  finally
    if JS <> nil then
      JS.Free;
  end;
end;

function ParseLine(const Line: String): TAgentEvent;
var
  Events: TAgentEventArray;
begin
  InitEvent(Result, Line);
  if ParseLineEvents(Line, Events) > 0 then
    Result := Events[0];
  SetLength(Events, 0);
end;

procedure ResetProtocolState;
var
  I: Integer;
begin
  GStreamMessageId := '';
  if GToolInputs = nil then
    Exit;
  for I := GToolInputs.Count - 1 downto 0 do
    TObject(GToolInputs[I]).Free;
  GToolInputs.Clear;
end;

function IsStreamComplete(const Event: TAgentEvent): Boolean;
begin
  Result := Event.EventType = aetResult;
end;

function ExtractEventFilePath(const Event: TAgentEvent): String;
begin
  Result := Event.FilePath;
end;

initialization
  GToolInputs := nil;
  GStreamMessageId := '';

finalization
  ResetProtocolState;
  GToolInputs.Free;

end.
