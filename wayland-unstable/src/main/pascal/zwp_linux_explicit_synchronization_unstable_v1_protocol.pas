unit zwp_linux_explicit_synchronization_unstable_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpLinuxBufferReleaseV1Class = class of TWpLinuxBufferReleaseV1;
  { TWpLinuxBufferReleaseV1 }
  TWpLinuxBufferReleaseV1 = class;

  TWpLinuxSurfaceSynchronizationV1Class = class of TWpLinuxSurfaceSynchronizationV1;
  { TWpLinuxSurfaceSynchronizationV1 }
  TWpLinuxSurfaceSynchronizationV1 = class;

  TWpLinuxExplicitSynchronizationV1Class = class of TWpLinuxExplicitSynchronizationV1;
  { TWpLinuxExplicitSynchronizationV1 }
  TWpLinuxExplicitSynchronizationV1 = class;

  IWpLinuxExplicitSynchronizationV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_synchronization(no)', '')]
  { TWpLinuxExplicitSynchronizationV1 }
  TWpLinuxExplicitSynchronizationV1 = class(TWaylandBase)
  public type
    TError = (erSynchronizationexists = 0);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_SYNCHRONIZATION = 1);
  public
    destructor Destroy; override;
    function GetSynchronization(aSurface: TWlSurface; aClassType: TWpLinuxSurfaceSynchronizationV1Class = nil): TWpLinuxSurfaceSynchronizationV1;
  private
    FListeners: array of IWpLinuxExplicitSynchronizationV1Listener;
  public
    function AddListener(AIntf: IWpLinuxExplicitSynchronizationV1Listener): LongInt;
  end;

  IWpLinuxExplicitSynchronizationV1Listener = interface
  ['IWpLinuxExplicitSynchronizationV1Listener']
  end;

  IWpLinuxSurfaceSynchronizationV1Listener = interface;

  [TWLIntfAttribute('destroy(),set_acquire_fence(h),get_release(n)', '')]
  { TWpLinuxSurfaceSynchronizationV1 }
  TWpLinuxSurfaceSynchronizationV1 = class(TWaylandBase)
  public type
    TError = (erInvalidfence = 0, erDuplicatefence = 1, erDuplicaterelease = 2, erNosurface = 3, erUnsupportedbuffer = 4, erNobuffer = 5);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _SET_ACQUIRE_FENCE = 1, _GET_RELEASE = 2);
  public
    destructor Destroy; override;
    procedure SetAcquireFence(aFd: Integer);
    function GetRelease(aClassType: TWpLinuxBufferReleaseV1Class = nil): TWpLinuxBufferReleaseV1;
  private
    FListeners: array of IWpLinuxSurfaceSynchronizationV1Listener;
  public
    function AddListener(AIntf: IWpLinuxSurfaceSynchronizationV1Listener): LongInt;
  end;

  IWpLinuxSurfaceSynchronizationV1Listener = interface
  ['IWpLinuxSurfaceSynchronizationV1Listener']
  end;

  IWpLinuxBufferReleaseV1Listener = interface;

  [TWLIntfAttribute('', 'fenced_release(h),immediate_release()')]
  { TWpLinuxBufferReleaseV1 }
  TWpLinuxBufferReleaseV1 = class(TWaylandBase)
  public type
    TFencedReleaseEvent = procedure(Sender: TWpLinuxBufferReleaseV1; aFence: Integer) of object;
    TImmediateReleaseEvent = procedure(Sender: TWpLinuxBufferReleaseV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TEvents = (EV_FENCED_RELEASE = 0, EV_IMMEDIATE_RELEASE = 1);
  private
    FOnFencedReleasePriv: TFencedReleaseEvent;
    FOnImmediateReleasePriv: TImmediateReleaseEvent;
  protected
    procedure HandleFencedRelease(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FENCED_RELEASE); virtual;
    procedure HandleImmediateRelease(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_IMMEDIATE_RELEASE); virtual;
  published
    property OnFencedRelease: TFencedReleaseEvent read FOnFencedReleasePriv write FOnFencedReleasePriv;
    property OnImmediateRelease: TImmediateReleaseEvent read FOnImmediateReleasePriv write FOnImmediateReleasePriv;
  private
    FListeners: array of IWpLinuxBufferReleaseV1Listener;
  public
    function AddListener(AIntf: IWpLinuxBufferReleaseV1Listener): LongInt;
  end;

  IWpLinuxBufferReleaseV1Listener = interface
  ['IWpLinuxBufferReleaseV1Listener']
    procedure wp_linux_buffer_release_v1_fenced_release(AWpLinuxBufferReleaseV1: TWpLinuxBufferReleaseV1; aFence: Integer);
    procedure wp_linux_buffer_release_v1_immediate_release(AWpLinuxBufferReleaseV1: TWpLinuxBufferReleaseV1);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpLinuxExplicitSynchronizationV1.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpLinuxExplicitSynchronizationV1.GetInterfaceName: String;
begin
  Result := 'zwp_linux_explicit_synchronization_v1';
end;

destructor TWpLinuxExplicitSynchronizationV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpLinuxExplicitSynchronizationV1.GetSynchronization(aSurface: TWlSurface; aClassType: TWpLinuxSurfaceSynchronizationV1Class = nil): TWpLinuxSurfaceSynchronizationV1;
begin
  if aClassType = nil then aClassType := TWpLinuxSurfaceSynchronizationV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_SYNCHRONIZATION), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TWpLinuxExplicitSynchronizationV1.AddListener(AIntf: IWpLinuxExplicitSynchronizationV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpLinuxSurfaceSynchronizationV1.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpLinuxSurfaceSynchronizationV1.GetInterfaceName: String;
begin
  Result := 'zwp_linux_surface_synchronization_v1';
end;

destructor TWpLinuxSurfaceSynchronizationV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWpLinuxSurfaceSynchronizationV1.SetAcquireFence(aFd: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_ACQUIRE_FENCE), [aFd], 0);
end;

function TWpLinuxSurfaceSynchronizationV1.GetRelease(aClassType: TWpLinuxBufferReleaseV1Class = nil): TWpLinuxBufferReleaseV1;
begin
  if aClassType = nil then aClassType := TWpLinuxBufferReleaseV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_RELEASE), [Result.GetObjectId]);
end;

function TWpLinuxSurfaceSynchronizationV1.AddListener(AIntf: IWpLinuxSurfaceSynchronizationV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpLinuxBufferReleaseV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpLinuxBufferReleaseV1.GetInterfaceName: String;
begin
  Result := 'zwp_linux_buffer_release_v1';
end;

procedure TWpLinuxBufferReleaseV1.HandleFencedRelease(var AMsg: TWaylandEventMessage);
var
  lFence: Integer;
  lListenerIdx: Integer;
begin
  lFence := AMsg.Args.ReadInteger;
  if Assigned(OnFencedRelease) then OnFencedRelease(Self,lFence);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_buffer_release_v1_fenced_release(Self,lFence);
  AMsg.SetHandled;
end;

procedure TWpLinuxBufferReleaseV1.HandleImmediateRelease(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnImmediateRelease) then OnImmediateRelease(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_buffer_release_v1_immediate_release(Self);
  AMsg.SetHandled;
end;

function TWpLinuxBufferReleaseV1.AddListener(AIntf: IWpLinuxBufferReleaseV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.