unit cursor_shape_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland, tablet_unstable_v2_protocol;

type
  TWpCursorShapeDeviceV1Class = class of TWpCursorShapeDeviceV1;
  { TWpCursorShapeDeviceV1 }
  TWpCursorShapeDeviceV1 = class;

  TWpCursorShapeManagerV1Class = class of TWpCursorShapeManagerV1;
  { TWpCursorShapeManagerV1 }
  TWpCursorShapeManagerV1 = class;

  IWpCursorShapeManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_pointer(no),get_tablet_tool_v2(no)', '')]
  { TWpCursorShapeManagerV1 }
  TWpCursorShapeManagerV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_POINTER = 1, _GET_TABLET_TOOL_V2 = 2);
  public
    destructor Destroy; override;
    function GetPointer(aPointer: TWlPointer; aClassType: TWpCursorShapeDeviceV1Class = nil): TWpCursorShapeDeviceV1;
    function GetTabletToolV2(aTabletTool: TWpTabletToolV2; aClassType: TWpCursorShapeDeviceV1Class = nil): TWpCursorShapeDeviceV1;
  private
    FListeners: array of IWpCursorShapeManagerV1Listener;
  public
    function AddListener(AIntf: IWpCursorShapeManagerV1Listener): LongInt;
  end;

  IWpCursorShapeManagerV1Listener = interface
  ['IWpCursorShapeManagerV1Listener']
  end;

  IWpCursorShapeDeviceV1Listener = interface;

  [TWLIntfAttribute('destroy(),set_shape(uu)', '')]
  { TWpCursorShapeDeviceV1 }
  TWpCursorShapeDeviceV1 = class(TWaylandBase)
  public type
    TShape = (shDefault = 1, shContextmenu = 2, shHelp = 3, shPointer = 4, shProgress = 5, shWait = 6, shCell = 7, shCrosshair = 8, shText = 9, shVerticaltext = 10, shAlias = 11, shCopy = 12, shMove = 13, shNodrop = 14, shNotallowed = 15, shGrab = 16, shGrabbing = 17, shEresize = 18, shNresize = 19, shNeresize = 20, shNwresize = 21, shSresize = 22, shSeresize = 23, shSwresize = 24, shWresize = 25, shEwresize = 26, shNsresize = 27, shNeswresize = 28, shNwseresize = 29, shColresize = 30, shRowresize = 31, shAllscroll = 32, shZoomin = 33, shZoomout = 34, shDndask = 35, shAllresize = 36);
    TError = (erInvalidshape = 1);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _SET_SHAPE = 1);
  public
    destructor Destroy; override;
    procedure SetShape(aSerial: DWord; aShape: TShape);
  private
    FListeners: array of IWpCursorShapeDeviceV1Listener;
  public
    function AddListener(AIntf: IWpCursorShapeDeviceV1Listener): LongInt;
  end;

  IWpCursorShapeDeviceV1Listener = interface
  ['IWpCursorShapeDeviceV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpCursorShapeManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpCursorShapeManagerV1.GetInterfaceName: String;
begin
  Result := 'wp_cursor_shape_manager_v1';
end;

destructor TWpCursorShapeManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpCursorShapeManagerV1.GetPointer(aPointer: TWlPointer; aClassType: TWpCursorShapeDeviceV1Class = nil): TWpCursorShapeDeviceV1;
begin
  if aClassType = nil then aClassType := TWpCursorShapeDeviceV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_POINTER), [Result.GetObjectId,aPointer.GetObjectId]);
end;

function TWpCursorShapeManagerV1.GetTabletToolV2(aTabletTool: TWpTabletToolV2; aClassType: TWpCursorShapeDeviceV1Class = nil): TWpCursorShapeDeviceV1;
begin
  if aClassType = nil then aClassType := TWpCursorShapeDeviceV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_TABLET_TOOL_V2), [Result.GetObjectId,aTabletTool.GetObjectId]);
end;

function TWpCursorShapeManagerV1.AddListener(AIntf: IWpCursorShapeManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpCursorShapeDeviceV1.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpCursorShapeDeviceV1.GetInterfaceName: String;
begin
  Result := 'wp_cursor_shape_device_v1';
end;

destructor TWpCursorShapeDeviceV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWpCursorShapeDeviceV1.SetShape(aSerial: DWord; aShape: TShape);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_SHAPE), [aSerial,DWord(aShape)]);
end;

function TWpCursorShapeDeviceV1.AddListener(AIntf: IWpCursorShapeDeviceV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.