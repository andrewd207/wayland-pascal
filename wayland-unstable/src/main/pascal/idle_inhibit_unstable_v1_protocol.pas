unit idle_inhibit_unstable_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpIdleInhibitorV1Class = class of TWpIdleInhibitorV1;
  { TWpIdleInhibitorV1 }
  TWpIdleInhibitorV1 = class;

  TWpIdleInhibitManagerV1Class = class of TWpIdleInhibitManagerV1;
  { TWpIdleInhibitManagerV1 }
  TWpIdleInhibitManagerV1 = class;

  IWpIdleInhibitManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),create_inhibitor(no)', '')]
  { TWpIdleInhibitManagerV1 }
  TWpIdleInhibitManagerV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _CREATE_INHIBITOR = 1);
  public
    destructor Destroy; override;
    function CreateInhibitor(aSurface: TWlSurface; aClassType: TWpIdleInhibitorV1Class = nil): TWpIdleInhibitorV1;
  private
    FListeners: array of IWpIdleInhibitManagerV1Listener;
  public
    function AddListener(AIntf: IWpIdleInhibitManagerV1Listener): LongInt;
  end;

  IWpIdleInhibitManagerV1Listener = interface
  ['IWpIdleInhibitManagerV1Listener']
  end;

  IWpIdleInhibitorV1Listener = interface;

  [TWLIntfAttribute('destroy()', '')]
  { TWpIdleInhibitorV1 }
  TWpIdleInhibitorV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
  public
    destructor Destroy; override;
  private
    FListeners: array of IWpIdleInhibitorV1Listener;
  public
    function AddListener(AIntf: IWpIdleInhibitorV1Listener): LongInt;
  end;

  IWpIdleInhibitorV1Listener = interface
  ['IWpIdleInhibitorV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpIdleInhibitManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpIdleInhibitManagerV1.GetInterfaceName: String;
begin
  Result := 'zwp_idle_inhibit_manager_v1';
end;

destructor TWpIdleInhibitManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpIdleInhibitManagerV1.CreateInhibitor(aSurface: TWlSurface; aClassType: TWpIdleInhibitorV1Class = nil): TWpIdleInhibitorV1;
begin
  if aClassType = nil then aClassType := TWpIdleInhibitorV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_INHIBITOR), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TWpIdleInhibitManagerV1.AddListener(AIntf: IWpIdleInhibitManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpIdleInhibitorV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpIdleInhibitorV1.GetInterfaceName: String;
begin
  Result := 'zwp_idle_inhibitor_v1';
end;

destructor TWpIdleInhibitorV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpIdleInhibitorV1.AddListener(AIntf: IWpIdleInhibitorV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.