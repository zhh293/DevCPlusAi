program AgentProtocolSmoke;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  AgentProtocol;

procedure Require(Condition: Boolean; const Message: String);
begin
  if not Condition then
    raise Exception.Create('AgentProtocol smoke test failed: ' + Message);
end;

var
  Events: TAgentEventArray;
  Count: Integer;
begin
  ResetProtocolState;

  Count := ParseLineEvents(
    '{"type":"assistant","message":{"id":"msg-1","model":"sonnet",' +
    '"content":[{"type":"text","text":"hello"},' +
    '{"type":"tool_use","id":"tool-1","name":"Write",' +
    '"input":{"file_path":"main.c","content":"x"}}]}}', Events);
  Require(Count = 2, 'assistant content blocks must be split');
  Require(Events[0].EventType = aetAssistant, 'assistant text event');
  Require(Events[1].EventType = aetToolUse, 'assistant tool event');
  Require(Events[1].FilePath = 'main.c', 'tool file path');

  ParseLineEvents(
    '{"type":"stream_event","event":{"type":"message_start",' +
    '"message":{"id":"msg-2","model":"sonnet"}}}', Events);
  ParseLineEvents(
    '{"type":"stream_event","event":{"type":"content_block_start",' +
    '"index":0,"content_block":{"type":"tool_use","id":"tool-2",' +
    '"name":"Write","input":{}}}}', Events);
  ParseLineEvents(
    '{"type":"stream_event","event":{"type":"content_block_delta",' +
    '"index":0,"delta":{"type":"input_json_delta",' +
    '"partial_json":"{\\"file_path\\":\\"src/"}}}', Events);
  ParseLineEvents(
    '{"type":"stream_event","event":{"type":"content_block_delta",' +
    '"index":0,"delta":{"type":"input_json_delta",' +
    '"partial_json":"main.c\\"}"}}}', Events);
  Count := ParseLineEvents(
    '{"type":"stream_event","event":{"type":"content_block_stop",' +
    '"index":0}}', Events);
  Require((Count = 1) and (Events[0].EventType = aetToolUse),
    'streamed tool completion event');
  Require(Events[0].FilePath = 'src/main.c', 'streamed tool path');
  Require(Events[0].IsUpdate, 'streamed tool update marker');

  Count := ParseLineEvents(
    '{"type":"user","message":{"content":[' +
    '{"type":"tool_result","tool_use_id":"tool-a","content":"ok"},' +
    '{"type":"tool_result","tool_use_id":"tool-b","is_error":true,' +
    '"content":"failed"}]}}', Events);
  Require(Count = 2, 'multiple tool results');
  Require(Events[1].IsError, 'tool result error marker');

  Count := ParseLineEvents(
    '{"type":"system","subtype":"hook_response","hook_name":"lint",' +
    '"stdout":"done"}', Events);
  Require((Count = 1) and (Events[0].EventType = aetSystem), 'hook event');
  Require(Pos('done', Events[0].Content) > 0, 'hook output');

  Count := ParseLineEvents('{"type":"rate_limit_event","status":"limited"}', Events);
  Require((Count = 1) and (Events[0].EventType = aetRateLimit), 'rate limit event');

  Count := ParseLineEvents('{not-json', Events);
  Require((Count = 1) and (Events[0].EventType = aetUnknown) and
    (Events[0].Content = '{not-json'), 'malformed JSON fallback');

  Writeln('AgentProtocol smoke test passed.');
end.
