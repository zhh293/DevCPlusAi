unit AgentWebView;

interface

uses Windows, SysUtils, Classes, Controls, ExtCtrls, Forms, ActiveX;

type
  TAgentWebEvent = procedure(Sender: TObject; const Text: WideString) of object;
  TAgentWebView = class(TPanel)
  private
    fInstance: Pointer;
    fReady: Boolean;
    fComInitialized: Boolean;
    fOnReady: TNotifyEvent;
    fOnMessage, fOnError: TAgentWebEvent;
    procedure Receive(Kind: Integer; const Text: WideString);
  protected
    procedure Resize; override;
    procedure DestroyWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Start(const LibraryPath: String; const Uri, Profile: WideString): Boolean;
    procedure Stop;
    procedure SyncWindow;
    function BrowserVisible: Boolean;
    function PostJSON(const Json: WideString): Boolean;
    property Ready: Boolean read fReady;
    property OnReady: TNotifyEvent read fOnReady write fOnReady;
    property OnMessage: TAgentWebEvent read fOnMessage write fOnMessage;
    property OnError: TAgentWebEvent read fOnError write fOnError;
  end;

implementation

type
  TBridgeNotify = procedure(Context: Pointer; Kind: Integer; Text: PWideChar); stdcall;
  TBridgeCreate = function(Parent: HWND; Uri, Profile: PWideChar;
    Notify: TBridgeNotify; Context: Pointer): Pointer; cdecl;
  TBridgeResize = procedure(Instance: Pointer); cdecl;
  TBridgePost = function(Instance: Pointer; Json: PWideChar): HRESULT; cdecl;
  TBridgeClose = procedure(Instance: Pointer); cdecl;
  TBridgeVisible = function(Instance: Pointer): Integer; cdecl;
var
  BridgeModule: HMODULE;
  BridgePath: String;
  BridgeCreate: TBridgeCreate;
  BridgeResize: TBridgeResize;
  BridgePost: TBridgePost;
  BridgeClose: TBridgeClose;
  BridgeVisible: TBridgeVisible;

function LoadBridge(const Path: String): Boolean;
begin
  if BridgeModule <> 0 then begin
    Result := SameText(BridgePath, ExpandFileName(Path));
    Exit;
  end;
  BridgeModule := LoadLibrary(PChar(ExpandFileName(Path)));
  Result := BridgeModule <> 0;
  if not Result then Exit;
  @BridgeCreate := GetProcAddress(BridgeModule, 'ABCreate');
  @BridgeResize := GetProcAddress(BridgeModule, 'ABResize');
  @BridgePost := GetProcAddress(BridgeModule, 'ABPost');
  @BridgeClose := GetProcAddress(BridgeModule, 'ABClose');
  @BridgeVisible := GetProcAddress(BridgeModule, 'ABIsVisible');
  Result := Assigned(BridgeCreate) and Assigned(BridgeResize) and
    Assigned(BridgePost) and Assigned(BridgeClose);
  if Result then BridgePath := ExpandFileName(Path)
  else begin
    FreeLibrary(BridgeModule);
    BridgeModule := 0;
  end;
end;

procedure BridgeNotification(Context: Pointer; Kind: Integer; Text: PWideChar); stdcall;
begin
  if Context = nil then Exit;
  try
    TAgentWebView(Context).Receive(Kind, WideString(Text));
  except
    { Never unwind a Delphi exception through a C++ COM callback. }
    Application.HandleException(TAgentWebView(Context));
  end;
end;

constructor TAgentWebView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  fComInitialized := CoInitialize(nil) >= 0;
  BevelOuter := bvNone;
  Caption := '';
end;

destructor TAgentWebView.Destroy;
begin
  Stop;
  if fComInitialized then CoUninitialize;
  inherited Destroy;
end;

procedure TAgentWebView.DestroyWnd;
begin
  Stop;
  inherited DestroyWnd;
end;

procedure TAgentWebView.Resize;
begin
  inherited Resize;
  if fInstance <> nil then BridgeResize(fInstance);
end;

procedure TAgentWebView.SyncWindow;
begin
  if fInstance <> nil then BridgeResize(fInstance);
end;

function TAgentWebView.BrowserVisible: Boolean;
begin
  Result := False;
  if (fInstance <> nil) and Assigned(BridgeVisible) then
    Result := BridgeVisible(fInstance) <> 0;
end;

function TAgentWebView.Start(const LibraryPath: String;
  const Uri, Profile: WideString): Boolean;
begin
  Stop;
  Result := False;
  if not fComInitialized then Exit;
  if (Parent = nil) or (csDestroying in ComponentState) then Exit;
  if not LoadBridge(LibraryPath) then begin
    if Assigned(fOnError) then fOnError(Self, 'WebView bridge could not be loaded');
    Exit;
  end;
  fInstance := BridgeCreate(Handle, PWideChar(Uri), PWideChar(Profile), BridgeNotification, Self);
  Result := fInstance <> nil;
  if not Result and Assigned(fOnError) then
    fOnError(Self, 'WebView initialization could not be started');
end;

procedure TAgentWebView.Stop;
var Instance: Pointer;
begin
  fReady := False;
  Instance := fInstance;
  fInstance := nil;
  if Instance <> nil then BridgeClose(Instance);
end;

function TAgentWebView.PostJSON(const Json: WideString): Boolean;
begin
  Result := False;
  if not fReady or (fInstance = nil) then Exit;
  Result := BridgePost(fInstance, PWideChar(Json)) >= 0;
end;

procedure TAgentWebView.Receive(Kind: Integer; const Text: WideString);
begin
  if csDestroying in ComponentState then Exit;
  case Kind of
    0: begin
      fReady := True;
      if Assigned(fOnReady) then fOnReady(Self);
    end;
    1: if Assigned(fOnMessage) then fOnMessage(Self, Text);
    2: begin
      fReady := False;
      if Assigned(fOnError) then fOnError(Self, Text);
    end;
  end;
end;

{ The DLL stays loaded until process exit: asynchronous COM callbacks may
  retain code pointers after individual views have closed. }
end.
