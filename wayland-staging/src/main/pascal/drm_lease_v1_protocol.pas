unit drm_lease_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpDrmLeaseV1Class = class of TWpDrmLeaseV1;
  { TWpDrmLeaseV1 }
  TWpDrmLeaseV1 = class;

  TWpDrmLeaseRequestV1Class = class of TWpDrmLeaseRequestV1;
  { TWpDrmLeaseRequestV1 }
  TWpDrmLeaseRequestV1 = class;

  TWpDrmLeaseConnectorV1Class = class of TWpDrmLeaseConnectorV1;
  { TWpDrmLeaseConnectorV1 }
  TWpDrmLeaseConnectorV1 = class;

  TWpDrmLeaseDeviceV1Class = class of TWpDrmLeaseDeviceV1;
  { TWpDrmLeaseDeviceV1 }
  TWpDrmLeaseDeviceV1 = class;

  IWpDrmLeaseDeviceV1Listener = interface;

  [TWLIntfAttribute('create_lease_request(n),release()', 'drm_fd(h),connector(n),done(),released()')]
  { TWpDrmLeaseDeviceV1 }
  TWpDrmLeaseDeviceV1 = class(TWaylandBase)
  public type
    TDrmFdEvent = procedure(Sender: TWpDrmLeaseDeviceV1; aFd: TWaylandFdStream) of object;
    TConnectorEvent = procedure(Sender: TWpDrmLeaseDeviceV1; aId: TWpDrmLeaseConnectorV1) of object;
    TDoneEvent = procedure(Sender: TWpDrmLeaseDeviceV1) of object;
    TReleasedEvent = procedure(Sender: TWpDrmLeaseDeviceV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE_LEASE_REQUEST = 0, _RELEASE = 1);
    TEvents = (EV_DRM_FD = 0, EV_CONNECTOR = 1, EV_DONE = 2, EV_RELEASED = 3);
  private
    FOnDrmFdPriv: TDrmFdEvent;
    FOnConnectorPriv: TConnectorEvent;
    FOnDonePriv: TDoneEvent;
    FOnReleasedPriv: TReleasedEvent;
  protected
    procedure HandleDrmFd(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DRM_FD); virtual;
    procedure HandleConnector(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CONNECTOR); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleReleased(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_RELEASED); virtual;
  published
    property OnDrmFd: TDrmFdEvent read FOnDrmFdPriv write FOnDrmFdPriv;
    property OnConnector: TConnectorEvent read FOnConnectorPriv write FOnConnectorPriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnReleased: TReleasedEvent read FOnReleasedPriv write FOnReleasedPriv;
  public
    function CreateLeaseRequest(aClassType: TWpDrmLeaseRequestV1Class = nil): TWpDrmLeaseRequestV1;
    procedure Release;
  private
    FListeners: array of IWpDrmLeaseDeviceV1Listener;
  public
    function AddListener(AIntf: IWpDrmLeaseDeviceV1Listener): LongInt;
  end;

  IWpDrmLeaseDeviceV1Listener = interface
  ['IWpDrmLeaseDeviceV1Listener']
    procedure wp_drm_lease_device_v1_drm_fd(AWpDrmLeaseDeviceV1: TWpDrmLeaseDeviceV1; aFd: TWaylandFdStream);
    procedure wp_drm_lease_device_v1_connector(AWpDrmLeaseDeviceV1: TWpDrmLeaseDeviceV1; aId: TWpDrmLeaseConnectorV1);
    procedure wp_drm_lease_device_v1_done(AWpDrmLeaseDeviceV1: TWpDrmLeaseDeviceV1);
    procedure wp_drm_lease_device_v1_released(AWpDrmLeaseDeviceV1: TWpDrmLeaseDeviceV1);
  end;

  IWpDrmLeaseConnectorV1Listener = interface;

  [TWLIntfAttribute('destroy()', 'name(s),description(s),connector_id(u),done(),withdrawn()')]
  { TWpDrmLeaseConnectorV1 }
  TWpDrmLeaseConnectorV1 = class(TWaylandBase)
  public type
    TNameEvent = procedure(Sender: TWpDrmLeaseConnectorV1; aName: String) of object;
    TDescriptionEvent = procedure(Sender: TWpDrmLeaseConnectorV1; aDescription: String) of object;
    TConnectorIdEvent = procedure(Sender: TWpDrmLeaseConnectorV1; aConnectorId: DWord) of object;
    TDoneEvent = procedure(Sender: TWpDrmLeaseConnectorV1) of object;
    TWithdrawnEvent = procedure(Sender: TWpDrmLeaseConnectorV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_NAME = 0, EV_DESCRIPTION = 1, EV_CONNECTOR_ID = 2, EV_DONE = 3, EV_WITHDRAWN = 4);
  private
    FOnNamePriv: TNameEvent;
    FOnDescriptionPriv: TDescriptionEvent;
    FOnConnectorIdPriv: TConnectorIdEvent;
    FOnDonePriv: TDoneEvent;
    FOnWithdrawnPriv: TWithdrawnEvent;
  protected
    procedure HandleName(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_NAME); virtual;
    procedure HandleDescription(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DESCRIPTION); virtual;
    procedure HandleConnectorId(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CONNECTOR_ID); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleWithdrawn(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_WITHDRAWN); virtual;
  published
    property OnName: TNameEvent read FOnNamePriv write FOnNamePriv;
    property OnDescription: TDescriptionEvent read FOnDescriptionPriv write FOnDescriptionPriv;
    property OnConnectorId: TConnectorIdEvent read FOnConnectorIdPriv write FOnConnectorIdPriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnWithdrawn: TWithdrawnEvent read FOnWithdrawnPriv write FOnWithdrawnPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWpDrmLeaseConnectorV1Listener;
  public
    function AddListener(AIntf: IWpDrmLeaseConnectorV1Listener): LongInt;
  end;

  IWpDrmLeaseConnectorV1Listener = interface
  ['IWpDrmLeaseConnectorV1Listener']
    procedure wp_drm_lease_connector_v1_name(AWpDrmLeaseConnectorV1: TWpDrmLeaseConnectorV1; aName: String);
    procedure wp_drm_lease_connector_v1_description(AWpDrmLeaseConnectorV1: TWpDrmLeaseConnectorV1; aDescription: String);
    procedure wp_drm_lease_connector_v1_connector_id(AWpDrmLeaseConnectorV1: TWpDrmLeaseConnectorV1; aConnectorId: DWord);
    procedure wp_drm_lease_connector_v1_done(AWpDrmLeaseConnectorV1: TWpDrmLeaseConnectorV1);
    procedure wp_drm_lease_connector_v1_withdrawn(AWpDrmLeaseConnectorV1: TWpDrmLeaseConnectorV1);
  end;

  IWpDrmLeaseRequestV1Listener = interface;

  [TWLIntfAttribute('request_connector(o),submit(n)', '')]
  { TWpDrmLeaseRequestV1 }
  TWpDrmLeaseRequestV1 = class(TWaylandBase)
  public type
    TError = (erWrongdevice = 0, erDuplicateconnector = 1, erEmptylease = 2);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_REQUEST_CONNECTOR = 0, _SUBMIT = 1);
  public
    procedure RequestConnector(aConnector: TWpDrmLeaseConnectorV1);
    function Submit(aClassType: TWpDrmLeaseV1Class = nil): TWpDrmLeaseV1;
  private
    FListeners: array of IWpDrmLeaseRequestV1Listener;
  public
    function AddListener(AIntf: IWpDrmLeaseRequestV1Listener): LongInt;
  end;

  IWpDrmLeaseRequestV1Listener = interface
  ['IWpDrmLeaseRequestV1Listener']
  end;

  IWpDrmLeaseV1Listener = interface;

  [TWLIntfAttribute('destroy()', 'lease_fd(h),finished()')]
  { TWpDrmLeaseV1 }
  TWpDrmLeaseV1 = class(TWaylandBase)
  public type
    TLeaseFdEvent = procedure(Sender: TWpDrmLeaseV1; aLeasedFd: TWaylandFdStream) of object;
    TFinishedEvent = procedure(Sender: TWpDrmLeaseV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_LEASE_FD = 0, EV_FINISHED = 1);
  private
    FOnLeaseFdPriv: TLeaseFdEvent;
    FOnFinishedPriv: TFinishedEvent;
  protected
    procedure HandleLeaseFd(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LEASE_FD); virtual;
    procedure HandleFinished(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FINISHED); virtual;
  published
    property OnLeaseFd: TLeaseFdEvent read FOnLeaseFdPriv write FOnLeaseFdPriv;
    property OnFinished: TFinishedEvent read FOnFinishedPriv write FOnFinishedPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWpDrmLeaseV1Listener;
  public
    function AddListener(AIntf: IWpDrmLeaseV1Listener): LongInt;
  end;

  IWpDrmLeaseV1Listener = interface
  ['IWpDrmLeaseV1Listener']
    procedure wp_drm_lease_v1_lease_fd(AWpDrmLeaseV1: TWpDrmLeaseV1; aLeasedFd: TWaylandFdStream);
    procedure wp_drm_lease_v1_finished(AWpDrmLeaseV1: TWpDrmLeaseV1);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpDrmLeaseDeviceV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpDrmLeaseDeviceV1.GetInterfaceName: String;
begin
  Result := 'wp_drm_lease_device_v1';
end;

procedure TWpDrmLeaseDeviceV1.HandleDrmFd(var AMsg: TWaylandEventMessage);
var
  lFd: TWaylandFdStream;
  lListenerIdx: Integer;
begin
  lFd := AMsg.NextFdStream;
  if Assigned(OnDrmFd) then OnDrmFd(Self,lFd);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_device_v1_drm_fd(Self,lFd);
  AMsg.SetHandled;
end;

procedure TWpDrmLeaseDeviceV1.HandleConnector(var AMsg: TWaylandEventMessage);
var
  lId: TWpDrmLeaseConnectorV1;
  lListenerIdx: Integer;
begin
  lId := TWpDrmLeaseConnectorV1.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnConnector) then OnConnector(Self,lId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_device_v1_connector(Self,lId);
  AMsg.SetHandled;
end;

procedure TWpDrmLeaseDeviceV1.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_device_v1_done(Self);
  AMsg.SetHandled;
end;

procedure TWpDrmLeaseDeviceV1.HandleReleased(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnReleased) then OnReleased(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_device_v1_released(Self);
  AMsg.SetHandled;
end;

function TWpDrmLeaseDeviceV1.CreateLeaseRequest(aClassType: TWpDrmLeaseRequestV1Class = nil): TWpDrmLeaseRequestV1;
begin
  if aClassType = nil then aClassType := TWpDrmLeaseRequestV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_LEASE_REQUEST), [Result.GetObjectId]);
end;

procedure TWpDrmLeaseDeviceV1.Release;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RELEASE), []);
end;

function TWpDrmLeaseDeviceV1.AddListener(AIntf: IWpDrmLeaseDeviceV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpDrmLeaseConnectorV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpDrmLeaseConnectorV1.GetInterfaceName: String;
begin
  Result := 'wp_drm_lease_connector_v1';
end;

procedure TWpDrmLeaseConnectorV1.HandleName(var AMsg: TWaylandEventMessage);
var
  lName: String;
  lListenerIdx: Integer;
begin
  lName := AMsg.Args.ReadString;
  if Assigned(OnName) then OnName(Self,lName);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_connector_v1_name(Self,lName);
  AMsg.SetHandled;
end;

procedure TWpDrmLeaseConnectorV1.HandleDescription(var AMsg: TWaylandEventMessage);
var
  lDescription: String;
  lListenerIdx: Integer;
begin
  lDescription := AMsg.Args.ReadString;
  if Assigned(OnDescription) then OnDescription(Self,lDescription);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_connector_v1_description(Self,lDescription);
  AMsg.SetHandled;
end;

procedure TWpDrmLeaseConnectorV1.HandleConnectorId(var AMsg: TWaylandEventMessage);
var
  lConnectorId: DWord;
  lListenerIdx: Integer;
begin
  lConnectorId := AMsg.Args.ReadDWord;
  if Assigned(OnConnectorId) then OnConnectorId(Self,lConnectorId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_connector_v1_connector_id(Self,lConnectorId);
  AMsg.SetHandled;
end;

procedure TWpDrmLeaseConnectorV1.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_connector_v1_done(Self);
  AMsg.SetHandled;
end;

procedure TWpDrmLeaseConnectorV1.HandleWithdrawn(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnWithdrawn) then OnWithdrawn(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_connector_v1_withdrawn(Self);
  AMsg.SetHandled;
end;

destructor TWpDrmLeaseConnectorV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpDrmLeaseConnectorV1.AddListener(AIntf: IWpDrmLeaseConnectorV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpDrmLeaseRequestV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpDrmLeaseRequestV1.GetInterfaceName: String;
begin
  Result := 'wp_drm_lease_request_v1';
end;

procedure TWpDrmLeaseRequestV1.RequestConnector(aConnector: TWpDrmLeaseConnectorV1);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._REQUEST_CONNECTOR), [aConnector.GetObjectId]);
end;

function TWpDrmLeaseRequestV1.Submit(aClassType: TWpDrmLeaseV1Class = nil): TWpDrmLeaseV1;
begin
  if aClassType = nil then aClassType := TWpDrmLeaseV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._SUBMIT), [Result.GetObjectId]);
end;

function TWpDrmLeaseRequestV1.AddListener(AIntf: IWpDrmLeaseRequestV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpDrmLeaseV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpDrmLeaseV1.GetInterfaceName: String;
begin
  Result := 'wp_drm_lease_v1';
end;

procedure TWpDrmLeaseV1.HandleLeaseFd(var AMsg: TWaylandEventMessage);
var
  lLeasedFd: TWaylandFdStream;
  lListenerIdx: Integer;
begin
  lLeasedFd := AMsg.NextFdStream;
  if Assigned(OnLeaseFd) then OnLeaseFd(Self,lLeasedFd);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_v1_lease_fd(Self,lLeasedFd);
  AMsg.SetHandled;
end;

procedure TWpDrmLeaseV1.HandleFinished(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnFinished) then OnFinished(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_drm_lease_v1_finished(Self);
  AMsg.SetHandled;
end;

destructor TWpDrmLeaseV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpDrmLeaseV1.AddListener(AIntf: IWpDrmLeaseV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.