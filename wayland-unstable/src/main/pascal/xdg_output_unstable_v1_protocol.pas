unit xdg_output_unstable_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TXdgOutputV1Class = class of TXdgOutputV1;
  { TXdgOutputV1 }
  TXdgOutputV1 = class;

  TXdgOutputManagerV1Class = class of TXdgOutputManagerV1;
  { TXdgOutputManagerV1 }
  TXdgOutputManagerV1 = class;

  IXdgOutputManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_xdg_output(no)', '')]
  { TXdgOutputManagerV1 }
  TXdgOutputManagerV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_XDG_OUTPUT = 1);
  public
    destructor Destroy; override;
    function GetXdgOutput(aOutput: TWlOutput; aClassType: TXdgOutputV1Class = nil): TXdgOutputV1;
  private
    FListeners: array of IXdgOutputManagerV1Listener;
  public
    function AddListener(AIntf: IXdgOutputManagerV1Listener): LongInt;
  end;

  IXdgOutputManagerV1Listener = interface
  ['IXdgOutputManagerV1Listener']
  end;

  IXdgOutputV1Listener = interface;

  [TWLIntfAttribute('destroy()', 'logical_position(ii),logical_size(ii),done(),name(s),description(s)')]
  { TXdgOutputV1 }
  TXdgOutputV1 = class(TWaylandBase)
  public type
    TLogicalPositionEvent = procedure(Sender: TXdgOutputV1; aX: Integer; aY: Integer) of object;
    TLogicalSizeEvent = procedure(Sender: TXdgOutputV1; aWidth: Integer; aHeight: Integer) of object;
    TDoneEvent = procedure(Sender: TXdgOutputV1) of object;
    TNameEvent = procedure(Sender: TXdgOutputV1; aName: String) of object;
    TDescriptionEvent = procedure(Sender: TXdgOutputV1; aDescription: String) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_LOGICAL_POSITION = 0, EV_LOGICAL_SIZE = 1, EV_DONE = 2, EV_NAME = 3, EV_DESCRIPTION = 4);
  private
    FOnLogicalPositionPriv: TLogicalPositionEvent;
    FOnLogicalSizePriv: TLogicalSizeEvent;
    FOnDonePriv: TDoneEvent;
    FOnNamePriv: TNameEvent;
    FOnDescriptionPriv: TDescriptionEvent;
  protected
    procedure HandleLogicalPosition(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LOGICAL_POSITION); virtual;
    procedure HandleLogicalSize(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LOGICAL_SIZE); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleName(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_NAME); virtual;
    procedure HandleDescription(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DESCRIPTION); virtual;
  published
    property OnLogicalPosition: TLogicalPositionEvent read FOnLogicalPositionPriv write FOnLogicalPositionPriv;
    property OnLogicalSize: TLogicalSizeEvent read FOnLogicalSizePriv write FOnLogicalSizePriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnName: TNameEvent read FOnNamePriv write FOnNamePriv;
    property OnDescription: TDescriptionEvent read FOnDescriptionPriv write FOnDescriptionPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IXdgOutputV1Listener;
  public
    function AddListener(AIntf: IXdgOutputV1Listener): LongInt;
  end;

  IXdgOutputV1Listener = interface
  ['IXdgOutputV1Listener']
    procedure xdg_output_v1_logical_position(AXdgOutputV1: TXdgOutputV1; aX: Integer; aY: Integer);
    procedure xdg_output_v1_logical_size(AXdgOutputV1: TXdgOutputV1; aWidth: Integer; aHeight: Integer);
    procedure xdg_output_v1_done(AXdgOutputV1: TXdgOutputV1);
    procedure xdg_output_v1_name(AXdgOutputV1: TXdgOutputV1; aName: String);
    procedure xdg_output_v1_description(AXdgOutputV1: TXdgOutputV1; aDescription: String);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TXdgOutputManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 3;
end;

class function TXdgOutputManagerV1.GetInterfaceName: String;
begin
  Result := 'zxdg_output_manager_v1';
end;

destructor TXdgOutputManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TXdgOutputManagerV1.GetXdgOutput(aOutput: TWlOutput; aClassType: TXdgOutputV1Class = nil): TXdgOutputV1;
begin
  if aClassType = nil then aClassType := TXdgOutputV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_XDG_OUTPUT), [Result.GetObjectId,aOutput.GetObjectId]);
end;

function TXdgOutputManagerV1.AddListener(AIntf: IXdgOutputManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TXdgOutputV1.GetInterfaceVersion: Integer;
begin
  Result := 3;
end;

class function TXdgOutputV1.GetInterfaceName: String;
begin
  Result := 'zxdg_output_v1';
end;

procedure TXdgOutputV1.HandleLogicalPosition(var AMsg: TWaylandEventMessage);
var
  lX: Integer;
  lY: Integer;
  lListenerIdx: Integer;
begin
  lX := AMsg.Args.ReadInteger;
  lY := AMsg.Args.ReadInteger;
  if Assigned(OnLogicalPosition) then OnLogicalPosition(Self,lX,lY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_output_v1_logical_position(Self,lX,lY);
  AMsg.SetHandled;
end;

procedure TXdgOutputV1.HandleLogicalSize(var AMsg: TWaylandEventMessage);
var
  lWidth: Integer;
  lHeight: Integer;
  lListenerIdx: Integer;
begin
  lWidth := AMsg.Args.ReadInteger;
  lHeight := AMsg.Args.ReadInteger;
  if Assigned(OnLogicalSize) then OnLogicalSize(Self,lWidth,lHeight);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_output_v1_logical_size(Self,lWidth,lHeight);
  AMsg.SetHandled;
end;

procedure TXdgOutputV1.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_output_v1_done(Self);
  AMsg.SetHandled;
end;

procedure TXdgOutputV1.HandleName(var AMsg: TWaylandEventMessage);
var
  lName: String;
  lListenerIdx: Integer;
begin
  lName := AMsg.Args.ReadString;
  if Assigned(OnName) then OnName(Self,lName);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_output_v1_name(Self,lName);
  AMsg.SetHandled;
end;

procedure TXdgOutputV1.HandleDescription(var AMsg: TWaylandEventMessage);
var
  lDescription: String;
  lListenerIdx: Integer;
begin
  lDescription := AMsg.Args.ReadString;
  if Assigned(OnDescription) then OnDescription(Self,lDescription);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_output_v1_description(Self,lDescription);
  AMsg.SetHandled;
end;

destructor TXdgOutputV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TXdgOutputV1.AddListener(AIntf: IXdgOutputV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.