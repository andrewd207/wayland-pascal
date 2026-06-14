unit linux_drm_syncobj_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpLinuxDrmSyncobjTimelineV1Class = class of TWpLinuxDrmSyncobjTimelineV1;
  { TWpLinuxDrmSyncobjTimelineV1 }
  TWpLinuxDrmSyncobjTimelineV1 = class;

  TWpLinuxDrmSyncobjSurfaceV1Class = class of TWpLinuxDrmSyncobjSurfaceV1;
  { TWpLinuxDrmSyncobjSurfaceV1 }
  TWpLinuxDrmSyncobjSurfaceV1 = class;

  TWpLinuxDrmSyncobjManagerV1Class = class of TWpLinuxDrmSyncobjManagerV1;
  { TWpLinuxDrmSyncobjManagerV1 }
  TWpLinuxDrmSyncobjManagerV1 = class;

  IWpLinuxDrmSyncobjManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_surface(no),import_timeline(nh)', '')]
  { TWpLinuxDrmSyncobjManagerV1 }
  TWpLinuxDrmSyncobjManagerV1 = class(TWaylandBase)
  public type
    TError = (erSurfaceexists = 0, erInvalidtimeline = 1);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_SURFACE = 1, _IMPORT_TIMELINE = 2);
  public
    destructor Destroy; override;
    function GetSurface(aSurface: TWlSurface; aClassType: TWpLinuxDrmSyncobjSurfaceV1Class = nil): TWpLinuxDrmSyncobjSurfaceV1;
    function ImportTimeline(aFd: Integer; aClassType: TWpLinuxDrmSyncobjTimelineV1Class = nil): TWpLinuxDrmSyncobjTimelineV1;
  private
    FListeners: array of IWpLinuxDrmSyncobjManagerV1Listener;
  public
    function AddListener(AIntf: IWpLinuxDrmSyncobjManagerV1Listener): LongInt;
  end;

  IWpLinuxDrmSyncobjManagerV1Listener = interface
  ['IWpLinuxDrmSyncobjManagerV1Listener']
  end;

  IWpLinuxDrmSyncobjTimelineV1Listener = interface;

  [TWLIntfAttribute('destroy()', '')]
  { TWpLinuxDrmSyncobjTimelineV1 }
  TWpLinuxDrmSyncobjTimelineV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
  public
    destructor Destroy; override;
  private
    FListeners: array of IWpLinuxDrmSyncobjTimelineV1Listener;
  public
    function AddListener(AIntf: IWpLinuxDrmSyncobjTimelineV1Listener): LongInt;
  end;

  IWpLinuxDrmSyncobjTimelineV1Listener = interface
  ['IWpLinuxDrmSyncobjTimelineV1Listener']
  end;

  IWpLinuxDrmSyncobjSurfaceV1Listener = interface;

  [TWLIntfAttribute('destroy(),set_acquire_point(ouu),set_release_point(ouu)', '')]
  { TWpLinuxDrmSyncobjSurfaceV1 }
  TWpLinuxDrmSyncobjSurfaceV1 = class(TWaylandBase)
  public type
    TError = (erNosurface = 1, erUnsupportedbuffer = 2, erNobuffer = 3, erNoacquirepoint = 4, erNoreleasepoint = 5, erConflictingpoints = 6);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _SET_ACQUIRE_POINT = 1, _SET_RELEASE_POINT = 2);
  public
    destructor Destroy; override;
    procedure SetAcquirePoint(aTimeline: TWpLinuxDrmSyncobjTimelineV1; aPointHi: DWord; aPointLo: DWord);
    procedure SetReleasePoint(aTimeline: TWpLinuxDrmSyncobjTimelineV1; aPointHi: DWord; aPointLo: DWord);
  private
    FListeners: array of IWpLinuxDrmSyncobjSurfaceV1Listener;
  public
    function AddListener(AIntf: IWpLinuxDrmSyncobjSurfaceV1Listener): LongInt;
  end;

  IWpLinuxDrmSyncobjSurfaceV1Listener = interface
  ['IWpLinuxDrmSyncobjSurfaceV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpLinuxDrmSyncobjManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpLinuxDrmSyncobjManagerV1.GetInterfaceName: String;
begin
  Result := 'wp_linux_drm_syncobj_manager_v1';
end;

destructor TWpLinuxDrmSyncobjManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpLinuxDrmSyncobjManagerV1.GetSurface(aSurface: TWlSurface; aClassType: TWpLinuxDrmSyncobjSurfaceV1Class = nil): TWpLinuxDrmSyncobjSurfaceV1;
begin
  if aClassType = nil then aClassType := TWpLinuxDrmSyncobjSurfaceV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_SURFACE), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TWpLinuxDrmSyncobjManagerV1.ImportTimeline(aFd: Integer; aClassType: TWpLinuxDrmSyncobjTimelineV1Class = nil): TWpLinuxDrmSyncobjTimelineV1;
begin
  if aClassType = nil then aClassType := TWpLinuxDrmSyncobjTimelineV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._IMPORT_TIMELINE), [Result.GetObjectId,aFd], 1);
end;

function TWpLinuxDrmSyncobjManagerV1.AddListener(AIntf: IWpLinuxDrmSyncobjManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpLinuxDrmSyncobjTimelineV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpLinuxDrmSyncobjTimelineV1.GetInterfaceName: String;
begin
  Result := 'wp_linux_drm_syncobj_timeline_v1';
end;

destructor TWpLinuxDrmSyncobjTimelineV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpLinuxDrmSyncobjTimelineV1.AddListener(AIntf: IWpLinuxDrmSyncobjTimelineV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpLinuxDrmSyncobjSurfaceV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpLinuxDrmSyncobjSurfaceV1.GetInterfaceName: String;
begin
  Result := 'wp_linux_drm_syncobj_surface_v1';
end;

destructor TWpLinuxDrmSyncobjSurfaceV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWpLinuxDrmSyncobjSurfaceV1.SetAcquirePoint(aTimeline: TWpLinuxDrmSyncobjTimelineV1; aPointHi: DWord; aPointLo: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_ACQUIRE_POINT), [aTimeline.GetObjectId,aPointHi,aPointLo]);
end;

procedure TWpLinuxDrmSyncobjSurfaceV1.SetReleasePoint(aTimeline: TWpLinuxDrmSyncobjTimelineV1; aPointHi: DWord; aPointLo: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_RELEASE_POINT), [aTimeline.GetObjectId,aPointHi,aPointLo]);
end;

function TWpLinuxDrmSyncobjSurfaceV1.AddListener(AIntf: IWpLinuxDrmSyncobjSurfaceV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.