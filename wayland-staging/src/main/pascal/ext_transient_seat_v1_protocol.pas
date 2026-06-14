unit ext_transient_seat_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TExtTransientSeatV1Class = class of TExtTransientSeatV1;
  { TExtTransientSeatV1 }
  TExtTransientSeatV1 = class;

  TExtTransientSeatManagerV1Class = class of TExtTransientSeatManagerV1;
  { TExtTransientSeatManagerV1 }
  TExtTransientSeatManagerV1 = class;

  IExtTransientSeatManagerV1Listener = interface;

  [TWLIntfAttribute('create(n),destroy()', '')]
  { TExtTransientSeatManagerV1 }
  TExtTransientSeatManagerV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE = 0, _DESTROY = 1);
  public
    function Create_(aClassType: TExtTransientSeatV1Class = nil): TExtTransientSeatV1;
    destructor Destroy; override;
  private
    FListeners: array of IExtTransientSeatManagerV1Listener;
  public
    function AddListener(AIntf: IExtTransientSeatManagerV1Listener): LongInt;
  end;

  IExtTransientSeatManagerV1Listener = interface
  ['IExtTransientSeatManagerV1Listener']
  end;

  IExtTransientSeatV1Listener = interface;

  [TWLIntfAttribute('destroy()', 'ready(u),denied()')]
  { TExtTransientSeatV1 }
  TExtTransientSeatV1 = class(TWaylandBase)
  public type
    TReadyEvent = procedure(Sender: TExtTransientSeatV1; aGlobalName: DWord) of object;
    TDeniedEvent = procedure(Sender: TExtTransientSeatV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_READY = 0, EV_DENIED = 1);
  private
    FOnReadyPriv: TReadyEvent;
    FOnDeniedPriv: TDeniedEvent;
  protected
    procedure HandleReady(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_READY); virtual;
    procedure HandleDenied(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DENIED); virtual;
  published
    property OnReady: TReadyEvent read FOnReadyPriv write FOnReadyPriv;
    property OnDenied: TDeniedEvent read FOnDeniedPriv write FOnDeniedPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IExtTransientSeatV1Listener;
  public
    function AddListener(AIntf: IExtTransientSeatV1Listener): LongInt;
  end;

  IExtTransientSeatV1Listener = interface
  ['IExtTransientSeatV1Listener']
    procedure ext_transient_seat_v1_ready(AExtTransientSeatV1: TExtTransientSeatV1; aGlobalName: DWord);
    procedure ext_transient_seat_v1_denied(AExtTransientSeatV1: TExtTransientSeatV1);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TExtTransientSeatManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtTransientSeatManagerV1.GetInterfaceName: String;
begin
  Result := 'ext_transient_seat_manager_v1';
end;

function TExtTransientSeatManagerV1.Create_(aClassType: TExtTransientSeatV1Class = nil): TExtTransientSeatV1;
begin
  if aClassType = nil then aClassType := TExtTransientSeatV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE), [Result.GetObjectId]);
end;

destructor TExtTransientSeatManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TExtTransientSeatManagerV1.AddListener(AIntf: IExtTransientSeatManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TExtTransientSeatV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtTransientSeatV1.GetInterfaceName: String;
begin
  Result := 'ext_transient_seat_v1';
end;

procedure TExtTransientSeatV1.HandleReady(var AMsg: TWaylandEventMessage);
var
  lGlobalName: DWord;
  lListenerIdx: Integer;
begin
  lGlobalName := AMsg.Args.ReadDWord;
  if Assigned(OnReady) then OnReady(Self,lGlobalName);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_transient_seat_v1_ready(Self,lGlobalName);
  AMsg.SetHandled;
end;

procedure TExtTransientSeatV1.HandleDenied(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDenied) then OnDenied(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_transient_seat_v1_denied(Self);
  AMsg.SetHandled;
end;

destructor TExtTransientSeatV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TExtTransientSeatV1.AddListener(AIntf: IExtTransientSeatV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.