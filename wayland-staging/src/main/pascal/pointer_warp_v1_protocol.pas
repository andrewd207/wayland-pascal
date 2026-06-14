unit pointer_warp_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpPointerWarpV1Class = class of TWpPointerWarpV1;
  { TWpPointerWarpV1 }
  TWpPointerWarpV1 = class;

  IWpPointerWarpV1Listener = interface;

  [TWLIntfAttribute('destroy(),warp_pointer(ooffu)', '')]
  { TWpPointerWarpV1 }
  TWpPointerWarpV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _WARP_POINTER = 1);
  public
    destructor Destroy; override;
    procedure WarpPointer(aSurface: TWlSurface; aPointer: TWlPointer; aX: TWaylandFixed; aY: TWaylandFixed; aSerial: DWord);
  private
    FListeners: array of IWpPointerWarpV1Listener;
  public
    function AddListener(AIntf: IWpPointerWarpV1Listener): LongInt;
  end;

  IWpPointerWarpV1Listener = interface
  ['IWpPointerWarpV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpPointerWarpV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpPointerWarpV1.GetInterfaceName: String;
begin
  Result := 'wp_pointer_warp_v1';
end;

destructor TWpPointerWarpV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWpPointerWarpV1.WarpPointer(aSurface: TWlSurface; aPointer: TWlPointer; aX: TWaylandFixed; aY: TWaylandFixed; aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._WARP_POINTER), [aSurface.GetObjectId,aPointer.GetObjectId,aX.AsFixed,aY.AsFixed,aSerial]);
end;

function TWpPointerWarpV1.AddListener(AIntf: IWpPointerWarpV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.