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

    AgentConfig.pas

    Sub-task P1.6: AI Agent configuration management.

    A TPersistent descendant following the project's RTTI three-stage config
    pattern (SettoDefaults / LoadSettings / SaveSettings). The global instance
    is created/saved/destroyed from devCFG.pas (CreateOptions / SaveOptions /
    DestroyOptions). The API key is kept in memory as plain text, but is
    encrypted with Windows DPAPI before it is written to the config file.
}
unit AgentConfig;

interface

uses
  Windows, Classes, SysUtils;

type
  TdevAgentConfig = class(TPersistent)
  private
    fEnabled: Boolean;
    fProvider: String;
    fApiKey: String;
    fModel: String;
    fBaseUrl: String;
    fCliPath: String;
    fPanelPosition: String;
    fPanelWidth: Integer;
    fFontSize: Integer;
    fSendKey: String;
    fPermissionMode: String;
    fMcpConfigFiles: String;
    fPluginDirs: String;
    // Kept for reading older configurations. New code uses PermissionMode,
    // because Claude CLI owns the permission policy as a single mode.
    fAutoAllowRead: Boolean;
    fAutoAllowWrite: Boolean;
    fAutoAllowExec: Boolean;
    fSystemPrompt: String;
  public
    constructor Create;
    procedure SettoDefaults;
    procedure LoadSettings;
    procedure SaveSettings;
  published
    property Enabled: Boolean read fEnabled write fEnabled;
    property Provider: String read fProvider write fProvider;
    property ApiKey: String read fApiKey write fApiKey;
    property Model: String read fModel write fModel;
    property BaseUrl: String read fBaseUrl write fBaseUrl;
    property CliPath: String read fCliPath write fCliPath;
    property PanelPosition: String read fPanelPosition write fPanelPosition;
    property PanelWidth: Integer read fPanelWidth write fPanelWidth;
    property FontSize: Integer read fFontSize write fFontSize;
    property SendKey: String read fSendKey write fSendKey;
    property PermissionMode: String read fPermissionMode write fPermissionMode;
    // Optional project/session-scoped Claude CLI extension inputs. Values are
    // semicolon-separated paths and are passed only to the Agent child.
    property McpConfigFiles: String read fMcpConfigFiles write fMcpConfigFiles;
    property PluginDirs: String read fPluginDirs write fPluginDirs;
    property AutoAllowRead: Boolean read fAutoAllowRead write fAutoAllowRead;
    property AutoAllowWrite: Boolean read fAutoAllowWrite write fAutoAllowWrite;
    property AutoAllowExec: Boolean read fAutoAllowExec write fAutoAllowExec;
    property SystemPrompt: String read fSystemPrompt write fSystemPrompt;
  end;

const
  DEEPSEEK_DEFAULT_MODEL = 'deepseek-v4-flash';
  DEEPSEEK_PRO_MODEL = 'deepseek-v4-pro';
  DEEPSEEK_ANTHROPIC_URL = 'https://api.deepseek.com/anthropic';

function NormalizeAgentModel(const Provider, Model: String): String;
function NormalizeAgentBaseUrl(const Provider, BaseUrl: String): String;
function AgentCliModel(const Provider, Model: String): String;

implementation

uses
  devCFG;

type
  TAgentDataBlob = record
    cbData: DWORD;
    pbData: PByte;
  end;
  PAgentDataBlob = ^TAgentDataBlob;
  PPWideChar = ^PWideChar;

function CryptProtectData(pDataIn: PAgentDataBlob; szDataDescr: PWideChar;
  pOptionalEntropy: PAgentDataBlob; pvReserved: Pointer;
  pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PAgentDataBlob): BOOL;
  stdcall; external 'crypt32.dll';

function CryptUnprotectData(pDataIn: PAgentDataBlob; ppszDataDescr: PPWideChar;
  pOptionalEntropy: PAgentDataBlob; pvReserved: Pointer;
  pPromptStruct: Pointer; dwFlags: DWORD; pDataOut: PAgentDataBlob): BOOL;
  stdcall; external 'crypt32.dll';

function AgentLocalFree(hMem: HLOCAL): HLOCAL; stdcall;
  external 'kernel32.dll' name 'LocalFree';

function NormalizeAgentModel(const Provider, Model: String): String;
begin
  Result := Trim(Model);
  if SameText(Trim(Provider), 'deepseek') and
     ((Result = '') or SameText(Result, 'deepseek-chat') or
      SameText(Result, 'deepseek-reasoner')) then
    Result := DEEPSEEK_DEFAULT_MODEL;
end;

function NormalizeAgentBaseUrl(const Provider, BaseUrl: String): String;
var
  Candidate: String;
begin
  Result := Trim(BaseUrl);
  if not SameText(Trim(Provider), 'deepseek') then
    Exit;
  Candidate := Result;
  while (Length(Candidate) > 0) and
      (Candidate[Length(Candidate)] = '/') do
    Delete(Candidate, Length(Candidate), 1);
  if (Candidate = '') or
     SameText(Candidate, 'https://api.deepseek.com') or
     SameText(Candidate, 'https://api.deepseek.com/v1') or
     SameText(Candidate, DEEPSEEK_ANTHROPIC_URL) then
    Result := DEEPSEEK_ANTHROPIC_URL;
end;

function AgentCliModel(const Provider, Model: String): String;
begin
  Result := NormalizeAgentModel(Provider, Model);
  // The CLI consumes [1m] locally and sends the canonical API model name.
  if SameText(Trim(Provider), 'deepseek') and
     (SameText(Result, DEEPSEEK_DEFAULT_MODEL) or
      SameText(Result, DEEPSEEK_PRO_MODEL)) then
    Result := Result + '[1m]';
end;

const
  AGENT_KEY_PREFIX = 'dpapi:';

function HexDigit(Value: Byte): AnsiChar;
begin
  if Value < 10 then
    Result := Chr(Ord('0') + Value)
  else
    Result := Chr(Ord('A') + Value - 10);
end;

function HexValue(Value: AnsiChar): Integer;
begin
  if (Value >= '0') and (Value <= '9') then
    Result := Ord(Value) - Ord('0')
  else if (Value >= 'a') and (Value <= 'f') then
    Result := Ord(Value) - Ord('a') + 10
  else if (Value >= 'A') and (Value <= 'F') then
    Result := Ord(Value) - Ord('A') + 10
  else
    Result := -1;
end;

function EncodeHex(const Value: AnsiString): AnsiString;
var
  I: Integer;
  B: Byte;
begin
  SetLength(Result, Length(Value) * 2);
  for I := 1 to Length(Value) do begin
    B := Byte(Value[I]);
    Result[I * 2 - 1] := HexDigit(B shr 4);
    Result[I * 2] := HexDigit(B and $0F);
  end;
end;

function DecodeHex(const Value: AnsiString; var Decoded: AnsiString): Boolean;
var
  I, HighNibble, LowNibble: Integer;
begin
  Result := False;
  Decoded := '';
  if (Length(Value) = 0) or ((Length(Value) mod 2) <> 0) then
    Exit;
  SetLength(Decoded, Length(Value) div 2);
  for I := 1 to Length(Decoded) do begin
    HighNibble := HexValue(Value[I * 2 - 1]);
    LowNibble := HexValue(Value[I * 2]);
    if (HighNibble < 0) or (LowNibble < 0) then begin
      Decoded := '';
      Exit;
    end;
    Decoded[I] := AnsiChar((HighNibble shl 4) or LowNibble);
  end;
  Result := True;
end;

function ProtectApiKey(const Value: AnsiString; var ProtectedValue: AnsiString): Boolean;
var
  InputBlob, OutputBlob: TAgentDataBlob;
begin
  Result := False;
  ProtectedValue := '';
  if Value = '' then begin
    Result := True;
    Exit;
  end;

  InputBlob.cbData := Length(Value);
  InputBlob.pbData := PByte(PAnsiChar(Value));
  FillChar(OutputBlob, SizeOf(OutputBlob), 0);
  if not CryptProtectData(@InputBlob, nil, nil, nil, nil, 0, @OutputBlob) then
    Exit;
  try
    SetLength(ProtectedValue, OutputBlob.cbData);
    Move(OutputBlob.pbData^, ProtectedValue[1], OutputBlob.cbData);
    ProtectedValue := AGENT_KEY_PREFIX + EncodeHex(ProtectedValue);
    Result := True;
  finally
    if OutputBlob.pbData <> nil then
      AgentLocalFree(HLOCAL(OutputBlob.pbData));
  end;
end;

function UnprotectApiKey(const Value: AnsiString; var PlainValue: AnsiString): Boolean;
var
  EncryptedValue, InputBytes: AnsiString;
  InputBlob, OutputBlob: TAgentDataBlob;
begin
  Result := False;
  PlainValue := '';
  if LowerCase(Copy(Value, 1, Length(AGENT_KEY_PREFIX))) <> AGENT_KEY_PREFIX then
    Exit;
  EncryptedValue := Copy(Value, Length(AGENT_KEY_PREFIX) + 1, MaxInt);
  if not DecodeHex(EncryptedValue, InputBytes) then
    Exit;

  InputBlob.cbData := Length(InputBytes);
  InputBlob.pbData := PByte(PAnsiChar(InputBytes));
  FillChar(OutputBlob, SizeOf(OutputBlob), 0);
  if not CryptUnprotectData(@InputBlob, nil, nil, nil, nil, 0, @OutputBlob) then
    Exit;
  try
    SetLength(PlainValue, OutputBlob.cbData);
    Move(OutputBlob.pbData^, PlainValue[1], OutputBlob.cbData);
    Result := True;
  finally
    if OutputBlob.pbData <> nil then
      AgentLocalFree(HLOCAL(OutputBlob.pbData));
  end;
end;

constructor TdevAgentConfig.Create;
begin
  inherited Create;
  SettoDefaults;
  LoadSettings;
end;

procedure TdevAgentConfig.SettoDefaults;
begin
  fEnabled := True;
  fProvider := 'anthropic';
  fApiKey := '';
  fModel := '';
  fBaseUrl := '';
  fCliPath := '';            // empty => AgentProcess resolves the bundled CLI
  fPanelPosition := 'right';
  fPanelWidth := 400;
  fFontSize := 10;
  fSendKey := 'enter';
  fPermissionMode := 'manual';
  fMcpConfigFiles := '';
  fPluginDirs := '';
  fAutoAllowRead := True;     // reading is non-destructive, allow by default
  fAutoAllowWrite := False;   // writing requires confirmation
  fAutoAllowExec := False;    // executing requires confirmation
  fSystemPrompt := '';
end;

procedure TdevAgentConfig.LoadSettings;
var
  StoredApiKey, PlainApiKey: AnsiString;
begin
  // An empty value lets old configurations migrate from the legacy boolean
  // flags without changing the meaning of a newly created configuration.
  fPermissionMode := '';
  devData.ReadObject('Agent', Self);
  if fPermissionMode = '' then begin
    if fAutoAllowExec then
      fPermissionMode := 'bypassPermissions'
    else if fAutoAllowWrite then
      fPermissionMode := 'acceptEdits'
    else if not fAutoAllowRead then
      fPermissionMode := 'dontAsk'
    else
      fPermissionMode := 'manual';
  end;
  // "default" was accepted by older Claude CLI builds but 2.1.211 documents
  // the equivalent safe mode as "manual". Normalize persisted legacy and
  // invalid values before they reach the process command line.
  if SameText(fPermissionMode, 'default') then
    fPermissionMode := 'manual'
  else if not SameText(fPermissionMode, 'manual') and
          not SameText(fPermissionMode, 'acceptEdits') and
          not SameText(fPermissionMode, 'auto') and
          not SameText(fPermissionMode, 'bypassPermissions') and
          not SameText(fPermissionMode, 'dontAsk') and
          not SameText(fPermissionMode, 'plan') then
    fPermissionMode := 'manual';
  if (fPanelWidth < 200) or (fPanelWidth > 1200) then
    fPanelWidth := 400;
  if (fFontSize < 8) or (fFontSize > 24) then
    fFontSize := 10;
  if not SameText(fSendKey, 'enter') and
     not SameText(fSendKey, 'ctrl+enter') then
    fSendKey := 'enter';
  if not SameText(fPanelPosition, 'right') then
    fPanelPosition := 'right';
  fModel := NormalizeAgentModel(fProvider, fModel);
  fBaseUrl := NormalizeAgentBaseUrl(fProvider, fBaseUrl);
  StoredApiKey := fApiKey;
  if Pos(AGENT_KEY_PREFIX, LowerCase(StoredApiKey)) = 1 then begin
    if UnprotectApiKey(StoredApiKey, PlainApiKey) then
      fApiKey := PlainApiKey
    else
      fApiKey := '';
  end;
end;

procedure TdevAgentConfig.SaveSettings;
var
  StoredApiKey, ProtectedApiKey: AnsiString;
begin
  fModel := NormalizeAgentModel(fProvider, fModel);
  fBaseUrl := NormalizeAgentBaseUrl(fProvider, fBaseUrl);
  StoredApiKey := fApiKey;
  if (StoredApiKey <> '') and not ProtectApiKey(StoredApiKey, ProtectedApiKey) then
    Exit;
  try
    if StoredApiKey <> '' then
      fApiKey := ProtectedApiKey;
    devData.WriteObject('Agent', Self);
  finally
    fApiKey := StoredApiKey;
  end;
end;

end.
