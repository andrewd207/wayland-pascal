unit ext_session_lock_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TExtSessionLockSurfaceV1Class = class of TExtSessionLockSurfaceV1;
  { TExtSessionLockSurfaceV1 }
  TExtSessionLockSurfaceV1 = class;

  TExtSessionLockV1Class = class of TExtSessionLockV1;
  { TExtSessionLockV1 }
  TExtSessionLockV1 = class;

  TExtSessionLockManagerV1Class = class of TExtSessionLockManagerV1;
  { TExtSessionLockManagerV1 }
  TExtSessionLockManagerV1 = class;

  IExtSessionLockManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),lock(n)', '')]
  { TExtSessionLockManagerV1 }
  TExtSessionLockManagerV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _LOCK = 1);
  public
    destructor Destroy; override;
    function Lock(aClassType: TExtSessionLockV1Class = nil): TExtSessionLockV1;
  private
    FListeners: array of IExtSessionLockManagerV1Listener;
  public
    function AddListener(AIntf: IExtSessionLockManagerV1Listener): LongInt;
  end;

  IExtSessionLockManagerV1Listener = interface
  ['IExtSessionLockManagerV1Listener']
  end;

  IExtSessionLockV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_lock_surface(noo),unlock_and_destroy()', 'locked(),finished()')]
  { TExtSessionLockV1 }
  TExtSessionLockV1 = class(TWaylandBase)
  public type
    TError = (erInvaliddestroy = 0, erInvalidunlock = 1, erRole = 2, erDuplicateoutput = 3, erAlreadyconstructed = 4);
    TLockedEvent = procedure(Sender: TExtSessionLockV1) of object;
    TFinishedEvent = procedure(Sender: TExtSessionLockV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_LOCK_SURFACE = 1, _UNLOCK_AND_DESTROY = 2);
    TEvents = (EV_LOCKED = 0, EV_FINISHED = 1);
  private
    FOnLockedPriv: TLockedEvent;
    FOnFinishedPriv: TFinishedEvent;
  protected
    procedure HandleLocked(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LOCKED); virtual;
    procedure HandleFinished(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FINISHED); virtual;
  published
    property OnLocked: TLockedEvent read FOnLockedPriv write FOnLockedPriv;
    property OnFinished: TFinishedEvent read FOnFinishedPriv write FOnFinishedPriv;
  public
    destructor Destroy; override;
    function GetLockSurface(aSurface: TWlSurface; aOutput: TWlOutput; aClassType: TExtSessionLockSurfaceV1Class = nil): TExtSessionLockSurfaceV1;
    procedure UnlockAndDestroy;
  private
    FListeners: array of IExtSessionLockV1Listener;
  public
    function AddListener(AIntf: IExtSessionLockV1Listener): LongInt;
  end;

  IExtSessionLockV1Listener = interface
  ['IExtSessionLockV1Listener']
    procedure ext_session_lock_v1_locked(AExtSessionLockV1: TExtSessionLockV1);
    procedure ext_session_lock_v1_finished(AExtSessionLockV1: TExtSessionLockV1);
  end;

  IExtSessionLockSurfaceV1Listener = interface;

  [TWLIntfAttribute('destroy(),ack_configure(u)', 'configure(uuu)')]
  { TExtSessionLockSurfaceV1 }
  TExtSessionLockSurfaceV1 = class(TWaylandBase)
  public type
    TError = (erCommitbeforefirstack = 0, erNullbuffer = 1, erDimensionsmismatch = 2, erInvalidserial = 3);
    TConfigureEvent = procedure(Sender: TExtSessionLockSurfaceV1; aSerial: DWord; aWidth: DWord; aHeight: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _ACK_CONFIGURE = 1);
    TEvents = (EV_CONFIGURE = 0);
  private
    FOnConfigurePriv: TConfigureEvent;
  protected
    procedure HandleConfigure(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CONFIGURE); virtual;
  published
    property OnConfigure: TConfigureEvent read FOnConfigurePriv write FOnConfigurePriv;
  public
    destructor Destroy; override;
    procedure AckConfigure(aSerial: DWord);
  private
    FListeners: array of IExtSessionLockSurfaceV1Listener;
  public
    function AddListener(AIntf: IExtSessionLockSurfaceV1Listener): LongInt;
  end;

  IExtSessionLockSurfaceV1Listener = interface
  ['IExtSessionLockSurfaceV1Listener']
    procedure ext_session_lock_surface_v1_configure(AExtSessionLockSurfaceV1: TExtSessionLockSurfaceV1; aSerial: DWord; aWidth: DWord; aHeight: DWord);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TExtSessionLockManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtSessionLockManagerV1.GetInterfaceName: String;
begin
  Result := 'ext_session_lock_manager_v1';
end;

destructor TExtSessionLockManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TExtSessionLockManagerV1.Lock(aClassType: TExtSessionLockV1Class = nil): TExtSessionLockV1;
begin
  if aClassType = nil then aClassType := TExtSessionLockV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._LOCK), [Result.GetObjectId]);
end;

function TExtSessionLockManagerV1.AddListener(AIntf: IExtSessionLockManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TExtSessionLockV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtSessionLockV1.GetInterfaceName: String;
begin
  Result := 'ext_session_lock_v1';
end;

procedure TExtSessionLockV1.HandleLocked(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnLocked) then OnLocked(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_session_lock_v1_locked(Self);
  AMsg.SetHandled;
end;

procedure TExtSessionLockV1.HandleFinished(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnFinished) then OnFinished(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_session_lock_v1_finished(Self);
  AMsg.SetHandled;
end;

destructor TExtSessionLockV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TExtSessionLockV1.GetLockSurface(aSurface: TWlSurface; aOutput: TWlOutput; aClassType: TExtSessionLockSurfaceV1Class = nil): TExtSessionLockSurfaceV1;
begin
  if aClassType = nil then aClassType := TExtSessionLockSurfaceV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_LOCK_SURFACE), [Result.GetObjectId,aSurface.GetObjectId,aOutput.GetObjectId]);
end;

procedure TExtSessionLockV1.UnlockAndDestroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._UNLOCK_AND_DESTROY), []);
end;

function TExtSessionLockV1.AddListener(AIntf: IExtSessionLockV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TExtSessionLockSurfaceV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtSessionLockSurfaceV1.GetInterfaceName: String;
begin
  Result := 'ext_session_lock_surface_v1';
end;

procedure TExtSessionLockSurfaceV1.HandleConfigure(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lWidth: DWord;
  lHeight: DWord;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lWidth := AMsg.Args.ReadDWord;
  lHeight := AMsg.Args.ReadDWord;
  if Assigned(OnConfigure) then OnConfigure(Self,lSerial,lWidth,lHeight);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_session_lock_surface_v1_configure(Self,lSerial,lWidth,lHeight);
  AMsg.SetHandled;
end;

destructor TExtSessionLockSurfaceV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TExtSessionLockSurfaceV1.AckConfigure(aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._ACK_CONFIGURE), [aSerial]);
end;

function TExtSessionLockSurfaceV1.AddListener(AIntf: IExtSessionLockSurfaceV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.