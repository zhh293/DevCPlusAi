program AgentProtocolSmoke;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  AgentProtocol,
  AgentWebLinks;

procedure Require(Condition: Boolean; const Message: String);
begin
  if not Condition then
    raise Exception.Create('AgentProtocol smoke test failed: ' + Message);
end;

var
  Events: TAgentEventArray;
  Count: Integer;
  ChineseWide: WideString;
  ChineseUTF8, ChineseText: String;
begin
  Require(AgentIsSafeExternalUrl('https://en.cppreference.com/w/cpp/vector'),
    'HTTPS documentation link should be accepted');
  Require(AgentIsSafeExternalUrl('http://example.com/guide'),
    'HTTP documentation link should be accepted');
  Require(not AgentIsSafeExternalUrl('javascript:alert(1)'),
    'JavaScript URL must be blocked');
  Require(not AgentIsSafeExternalUrl('file:///C:/Windows/win.ini'),
    'local file URL must be blocked');
  Require(not AgentIsSafeExternalUrl('https:///missing-host'),
    'web URL without a host must be blocked');
  Require(not AgentIsSafeExternalUrl('https://user:pass@example.com/'),
    'credential-bearing URL must be blocked');
  Require(not AgentIsSafeExternalUrl('https://example.com' + #10 + 'evil'),
    'control characters must be blocked');

  ChineseWide := UTF8Decode(#$E4#$BD#$A0#$E5#$A5#$BD);
  ChineseUTF8 := UTF8Encode(ChineseWide);
  ChineseText := String(ChineseWide);
  Count := ParseLineEvents('{"type":"control_request","request_id":"approve-1","request":{"subtype":"can_use_tool","tool_name":"Bash","tool_use_id":"tool-1","input":{"command":"echo test"}}}', Events);
  Require((Count = 1) and (Events[0].EventType = aetPermission), 'approval not recognized');
  Require(Events[0].EventId = 'approve-1', 'approval request id lost');
  Require(Events[0].Command = 'echo test', 'approval command lost');
  Require(Pos('echo test', Events[0].ToolInput) > 0, 'approval original input lost');
  Count := ParseLineEvents(
    '{"type":"control_request","request_id":"question-1",' +
    '"request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion",' +
    '"tool_use_id":"question-tool","input":{"questions":[{"question":"Compiler?",' +
    '"header":"Compiler","options":[{"label":"GCC","description":"GNU"},' +
    '{"label":"Clang","description":"LLVM"}],"multiSelect":false}]}}}', Events);
  Require((Count = 1) and (Events[0].EventType = aetPermission) and
    (Events[0].ToolName = 'AskUserQuestion') and
    (Pos('"questions"', Events[0].ToolInput) > 0),
    'AskUserQuestion request was not preserved');
  Writeln('AgentProtocol smoke test: reset state');
  ResetProtocolState;

  Writeln('AgentProtocol smoke test: assistant blocks');
  Count := ParseLineEvents(
    '{"type":"assistant","message":{"id":"msg-1","model":"sonnet",' +
    '"content":[{"type":"text","text":"hello"},' +
    '{"type":"tool_use","id":"tool-1","name":"Write",' +
    '"input":{"file_path":"main.c","content":"x"}}]}}', Events);
  Require(Count = 2, 'assistant content blocks must be split');
  Require(Events[0].EventType = aetAssistant, 'assistant text event');
  Require(Events[1].EventType = aetToolUse, 'assistant tool event');
  Require(Events[1].FilePath = 'main.c', 'tool file path');

  Writeln('AgentProtocol smoke test: streamed tool input');
  ParseLineEvents(
    '{"type":"stream_event","event":{"type":"message_start",' +
    '"message":{"id":"msg-2","model":"sonnet"}}}', Events);
  Writeln('  message_start parsed');
  ParseLineEvents(
    '{"type":"stream_event","event":{"type":"content_block_start",' +
    '"index":0,"content_block":{"type":"tool_use","id":"tool-2",' +
    '"name":"Write","input":{}}}}', Events);
  if Length(Events) > 0 then
    Writeln('  content_block_start parsed, index=', Events[0].BlockIndex)
  else
    Writeln('  content_block_start parsed without an event');
  ParseLineEvents(
    '{"type":"stream_event","event":{"type":"content_block_delta",' +
    '"index":0,"delta":{"type":"input_json_delta",' +
    '"partial_json":"{\"file_path\":\"src/"}}}', Events);
  if Length(Events) > 0 then
    Writeln('  first input_json_delta parsed, index=', Events[0].BlockIndex,
      ', input=', Events[0].ToolInput)
  else
    Writeln('  first input_json_delta parsed without an event');
  ParseLineEvents(
    '{"type":"stream_event","event":{"type":"content_block_delta",' +
    '"index":0,"delta":{"type":"input_json_delta",' +
    '"partial_json":"main.c\"}"}}}', Events);
  if Length(Events) > 0 then
    Writeln('  second input_json_delta parsed, index=', Events[0].BlockIndex,
      ', input=', Events[0].ToolInput)
  else
    Writeln('  second input_json_delta parsed without an event');
  Count := ParseLineEvents(
    '{"type":"stream_event","event":{"type":"content_block_stop",' +
    '"index":0}}', Events);
  Writeln('  content_block_stop parsed');
  Require((Count = 1) and (Events[0].EventType = aetToolUse),
    'streamed tool completion event');
  Require(Events[0].FilePath = 'src/main.c', 'streamed tool path');
  Require(Events[0].IsUpdate, 'streamed tool update marker');

  Writeln('AgentProtocol smoke test: tool results');
  Count := ParseLineEvents(
    '{"type":"user","message":{"content":[' +
    '{"type":"tool_result","tool_use_id":"tool-a","content":"ok"},' +
    '{"type":"tool_result","tool_use_id":"tool-b","is_error":true,' +
    '"content":"failed"}]}}', Events);
  Require(Count = 2, 'multiple tool results');
  Require(Events[1].IsError, 'tool result error marker');

  Count := ParseLineEvents(
    '{"type":"user","message":{"content":[{"type":"tool_result",' +
    '"tool_use_id":"tool-c","is_error":true,"content":{"diagnostic":"' +
    ChineseUTF8 + '"}}]}}', Events);
  Require((Count = 1) and (Pos(ChineseText, Events[0].Content) > 0),
    'UTF-8 structured tool error was not decoded for display');

  Writeln('AgentProtocol smoke test: system event');
  Count := ParseLineEvents(
    '{"type":"system","subtype":"hook_response","hook_name":"lint",' +
    '"stdout":"done"}', Events);
  Require((Count = 1) and (Events[0].EventType = aetSystem), 'hook event');
  Require(Pos('done', Events[0].Content) > 0, 'hook output');

  Writeln('AgentProtocol smoke test: rate limit event');
  Count := ParseLineEvents('{"type":"rate_limit_event","status":"limited"}', Events);
  Require((Count = 1) and (Events[0].EventType = aetRateLimit), 'rate limit event');

  Writeln('AgentProtocol smoke test: API retry diagnostics');
  Count := ParseLineEvents('{"type":"system","subtype":"api_retry",' +
    '"attempt":2,"max_retries":10,"retry_delay_ms":1000,' +
    '"error_status":503,"error":"server_error"}', Events);
  Require((Count = 1) and (Events[0].EventType = aetSystem), 'retry event');
  Require(Pos('HTTP 503', Events[0].Summary) > 0, 'retry status missing');
  Require(Pos('server_error', Events[0].Summary) > 0, 'retry cause missing');
  Require(Pos('#2/10', Events[0].Summary) > 0, 'retry count missing');

  Writeln('AgentProtocol smoke test: malformed JSON');
  Count := ParseLineEvents('{not-json', Events);
  Require((Count = 1) and (Events[0].EventType = aetUnknown) and
    (Events[0].Content = '{not-json'), 'malformed JSON fallback');

  Writeln('AgentProtocol smoke test passed.');
end.
