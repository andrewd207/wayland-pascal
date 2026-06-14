unit tearing_control_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpTearingControlV1Class = class of TWpTearingControlV1;
  { TWpTearingControlV1 }
  TWpTearingControlV1 = class;

  TWpTearingControlManagerV1Class = class of TWpTearingControlManagerV1;
  { TWpTearingControlManagerV1 }
  TWpTearingControlManagerV1 = class;

  IWpTearingControlManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_tearing_control(no)', '')]
  { TWpTearingControlManagerV1 }
  TWpTearingControlManagerV1 = class(TWaylandBase)
  public type
    TError = (erTearingcontrolexists = 0);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_TEARING_CONTROL = 1);
  public
    destructor Destroy; override;
    function GetTearingControl(aSurface: TWlSurface; aClassType: TWpTearingControlV1Class = nil): TWpTearingControlV1;
  private
    FListeners: array of IWpTearingControlManagerV1Listener;
  public
    function AddListener(AIntf: IWpTearingControlManagerV1Listener): LongInt;
  end;

  IWpTearingControlManagerV1Listener = interface
  ['IWpTearingControlManagerV1Listener']
  end;

  IWpTearingControlV1Listener = interface;

  [TWLIntfAttribute('set_presentation_hint(u),destroy()', '')]
  { TWpTearingControlV1 }
  TWpTearingControlV1 = class(TWaylandBase)
  public type
    TPresentationHint = (prVsync = 0, prAsync = 1);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_SET_PRESENTATION_HINT = 0, _DESTROY = 1);
  public
    procedure SetPresentationHint(aHint: TPresentationHint);
    destructor Destroy; override;
  private
    FListeners: array of IWpTearingControlV1Listener;
  public
    function AddListener(AIntf: IWpTearingControlV1Listener): LongInt;
  end;

  IWpTearingControlV1Listener = interface
  ['IWpTearingControlV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpTearingControlManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpTearingControlManagerV1.GetInterfaceName: String;
begin
  Result := 'wp_tearing_control_manager_v1';
end;

destructor TWpTearingControlManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTearingControlManagerV1.GetTearingControl(aSurface: TWlSurface; aClassType: TWpTearingControlV1Class = nil): TWpTearingControlV1;
begin
  if aClassType = nil then aClassType := TWpTearingControlV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_TEARING_CONTROL), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TWpTearingControlManagerV1.AddListener(AIntf: IWpTearingControlManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpTearingControlV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpTearingControlV1.GetInterfaceName: String;
begin
  Result := 'wp_tearing_control_v1';
end;

procedure TWpTearingControlV1.SetPresentationHint(aHint: TPresentationHint);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_PRESENTATION_HINT), [DWord(aHint)]);
end;

destructor TWpTearingControlV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTearingControlV1.AddListener(AIntf: IWpTearingControlV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.