program AgentProviderSmoke;

{$APPTYPE CONSOLE}

uses
  Windows, SysUtils, Classes, AgentConfig, AgentProcess, devCFG;

procedure Require(Condition: Boolean; const Message: String);
begin
  if not Condition then
    raise Exception.Create('Agent provider smoke test failed: ' + Message);
end;

function EnvironmentValue(Block: PChar; const Name: String): String;
var
  P: PChar;
  Entry, Prefix: String;
begin
  Result := '';
  Prefix := Name + '=';
  P := Block;
  while P^ <> #0 do begin
    Entry := String(P);
    if SameText(Copy(Entry, 1, Length(Prefix)), Prefix) then begin
      Result := Copy(Entry, Length(Prefix) + 1, MaxInt);
      Exit;
    end;
    Inc(P, StrLen(P) + 1);
  end;
end;

procedure CheckModelEnvironment(const ExpectedModel: String);
var
  Block: PChar;
begin
  Block := BuildEnvironmentBlock('');
  try
    Require(EnvironmentValue(Block, 'ANTHROPIC_MODEL') = ExpectedModel + '[1m]',
      'primary CLI model mismatch');
    Require(EnvironmentValue(Block, 'ANTHROPIC_DEFAULT_OPUS_MODEL') =
      ExpectedModel + '[1m]', 'opus alias escaped the selected provider');
    Require(EnvironmentValue(Block, 'ANTHROPIC_DEFAULT_SONNET_MODEL') =
      ExpectedModel + '[1m]', 'sonnet alias escaped the selected provider');
    Require(EnvironmentValue(Block, 'ANTHROPIC_DEFAULT_HAIKU_MODEL') =
      ExpectedModel, 'haiku alias escaped the selected provider');
    Require(EnvironmentValue(Block, 'CLAUDE_CODE_SUBAGENT_MODEL') =
      ExpectedModel, 'subagent model mismatch');
    Require(EnvironmentValue(Block, 'ANTHROPIC_BASE_URL') =
      'https://api.deepseek.com/anthropic', 'wrong API format');
    Require(EnvironmentValue(Block, 'ANTHROPIC_AUTH_TOKEN') =
      'test-placeholder-token', 'configured authentication was not used');
    Require(EnvironmentValue(Block, 'ANTHROPIC_API_KEY') = '',
      'competing inherited API key was not removed');
    Require(EnvironmentValue(Block, 'CLAUDE_CODE_AUTO_COMPACT_WINDOW') =
      '786432', '1M context compaction threshold missing');
  finally
    FreeMem(Block);
  end;
end;

var
  SavedConfig: TdevAgentConfig;
  SavedModel, SavedKey, SavedBaseUrl: String;
  SavedCompilerSets: TdevCompilerSets;
  TestCompiler: TdevCompilerSet;
  TestCompilerRoot, TestCompilerBin, SearchPath, Prompt: String;
  TempPath: array[0..MAX_PATH] of Char;
  TestCompilerEnvironment: PChar;
begin
  try
    Writeln('Agent provider smoke test: default and legacy models');
    Require(NormalizeAgentModel('deepseek', '') = 'deepseek-v4-flash',
      'empty DeepSeek model did not select Flash');
    Require(NormalizeAgentModel('deepseek', 'deepseek-chat') = 'deepseek-v4-flash',
      'legacy chat model was not migrated');
    Require(NormalizeAgentModel('deepseek', 'deepseek-reasoner') = 'deepseek-v4-flash',
      'legacy reasoner model was not migrated');
    Require(NormalizeAgentModel('deepseek', 'deepseek-v4-pro') = 'deepseek-v4-pro',
      'explicit Pro model was changed');
    Require(NormalizeAgentModel('custom', 'deepseek-chat') = 'deepseek-chat',
      'custom gateway model was changed');
    Require(AgentCliModel('deepseek', 'deepseek-v4-flash') = 'deepseek-v4-flash[1m]',
      '1M context marker missing');
    Require(AgentCliModel('anthropic', 'sonnet') = 'sonnet',
      'another provider model was changed');
    Prompt := BuildAgentSystemPrompt('MinGW GCC 12.2', 'Keep answers concise.');
    Require(Pos('Preserve each source file''s existing encoding', Prompt) > 0,
      'IDE prompt does not preserve source encoding');
    Require(Pos('never introduce mojibake', Prompt) > 0,
      'IDE prompt does not guard against corrupted text');
    Require(Pos('Reply in the user''s language', Prompt) > 0,
      'IDE prompt does not follow the user language');
    Require(Pos('make the result buildable with the active Dev-C++ compiler', Prompt) > 0,
      'IDE prompt does not require buildable complete examples');
    Require(Pos('MinGW GCC 12.2', Prompt) > 0,
      'IDE prompt omitted the active compiler set');
    Require(Pos('Keep answers concise.', Prompt) > 0,
      'IDE prompt omitted additional user instructions');
    Require(NormalizeAgentBaseUrl('deepseek', 'https://api.deepseek.com/v1/') =
      'https://api.deepseek.com/anthropic', 'OpenAI URL was not normalized');
    Require(NormalizeAgentBaseUrl('deepseek', 'https://gateway.example/anthropic') =
      'https://gateway.example/anthropic', 'custom endpoint was changed');

    SavedConfig := devAgentConfig;
    SavedModel := GetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL');
    SavedKey := GetEnvironmentVariable('ANTHROPIC_API_KEY');
    SavedBaseUrl := GetEnvironmentVariable('ANTHROPIC_BASE_URL');
    // Allocate defaults without loading or writing the real IDE settings.
    devAgentConfig := TdevAgentConfig(TdevAgentConfig.NewInstance);
    try
      devAgentConfig.SettoDefaults;
      Require(devAgentConfig.AttachIdeContext,
        'IDE context attachment should default to enabled for existing installs');
      devAgentConfig.Provider := 'deepseek';
      devAgentConfig.ApiKey := 'test-placeholder-token';
      devAgentConfig.BaseUrl := 'https://api.deepseek.com/v1';
      SetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL', 'parent-sentinel');
      SetEnvironmentVariable('ANTHROPIC_API_KEY', 'parent-key-sentinel');
      SetEnvironmentVariable('ANTHROPIC_BASE_URL', 'https://parent.invalid');
      Writeln('Agent provider smoke test: Flash child environment');
      devAgentConfig.Model := '';
      CheckModelEnvironment('deepseek-v4-flash');
      Writeln('Agent provider smoke test: Pro child environment');
      devAgentConfig.Model := 'deepseek-v4-pro';
      CheckModelEnvironment('deepseek-v4-pro');
      Require(GetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL') = 'parent-sentinel',
        'parent model environment was modified');
      Require(GetEnvironmentVariable('ANTHROPIC_API_KEY') = 'parent-key-sentinel',
        'parent authentication was modified');
      Require(GetEnvironmentVariable('ANTHROPIC_BASE_URL') = 'https://parent.invalid',
        'parent endpoint was modified');
    finally
      devAgentConfig.Free;
      devAgentConfig := SavedConfig;
      SetEnvironmentVariable('ANTHROPIC_DEFAULT_OPUS_MODEL', PChar(SavedModel));
      SetEnvironmentVariable('ANTHROPIC_API_KEY', PChar(SavedKey));
      SetEnvironmentVariable('ANTHROPIC_BASE_URL', PChar(SavedBaseUrl));
    end;

    Writeln('Agent provider smoke test: selected compiler search path');
    SavedCompilerSets := devCompilerSets;
    TestCompilerRoot := '';
    TestCompilerBin := '';
    devCompilerSets := TdevCompilerSets.Create;
    try
      TestCompiler := devCompilerSets.AddSet;
      TestCompiler.Name := 'Selected compiler test';
      if GetTempPath(Length(TempPath), TempPath) = 0 then
        raise Exception.Create('could not locate the temporary directory');
      TestCompilerRoot := IncludeTrailingPathDelimiter(String(TempPath)) +
        'devcpp-agent-provider-' + IntToStr(GetCurrentProcessId);
      TestCompilerBin := IncludeTrailingPathDelimiter(TestCompilerRoot) + 'bin';
      if not ForceDirectories(TestCompilerBin) then
        raise Exception.Create('could not create a temporary compiler directory');
      TestCompiler.BinDir.Add(TestCompilerBin);
      devCompilerSets.DefaultSetIndex := 0;
      TestCompilerEnvironment := BuildEnvironmentBlock('');
      try
        SearchPath := EnvironmentValue(TestCompilerEnvironment, 'PATH');
        Require(Copy(SearchPath, 1, Length(TestCompilerBin) + 1) =
          TestCompilerBin + ';', 'PATH does not start with the selected compiler');
        Require(EnvironmentValue(TestCompilerEnvironment, 'DEVCPP_COMPILER_NAME') =
          TestCompiler.Name, 'active compiler name was not exposed to the child');
        Require(EnvironmentValue(TestCompilerEnvironment, 'DEVCPP_COMPILER_BINS') =
          TestCompilerBin, 'active compiler directory was not exposed to the child');
      finally
        FreeMem(TestCompilerEnvironment);
      end;
    finally
      devCompilerSets.Free;
      devCompilerSets := SavedCompilerSets;
      RemoveDir(TestCompilerBin);
      RemoveDir(TestCompilerRoot);
    end;
    Writeln('Agent provider smoke test passed.');
  except
    on E: Exception do begin
      Writeln(E.ClassName + ': ' + E.Message);
      Halt(1);
    end;
  end;
end.
