unit xdg_system_bell_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TXdgSystemBellV1Class = class of TXdgSystemBellV1;
  { TXdgSystemBellV1 }
  TXdgSystemBellV1 = class;

  IXdgSystemBellV1Listener = interface;

  [TWLIntfAttribute('destroy(),ring(?o)', '')]
  { TXdgSystemBellV1 }
  TXdgSystemBellV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _RING = 1);
  public
    destructor Destroy; override;
    procedure Ring(aSurface: TWlSurface);
  private
    FListeners: array of IXdgSystemBellV1Listener;
  public
    function AddListener(AIntf: IXdgSystemBellV1Listener): LongInt;
  end;

  IXdgSystemBellV1Listener = interface
  ['IXdgSystemBellV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TXdgSystemBellV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgSystemBellV1.GetInterfaceName: String;
begin
  Result := 'xdg_system_bell_v1';
end;

destructor TXdgSystemBellV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TXdgSystemBellV1.Ring(aSurface: TWlSurface);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RING), [WlObjectId(aSurface)]);
end;

function TXdgSystemBellV1.AddListener(AIntf: IXdgSystemBellV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.