unit single_pixel_buffer_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpSinglePixelBufferManagerV1Class = class of TWpSinglePixelBufferManagerV1;
  { TWpSinglePixelBufferManagerV1 }
  TWpSinglePixelBufferManagerV1 = class;

  IWpSinglePixelBufferManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),create_u32_rgba_buffer(nuuuu)', '')]
  { TWpSinglePixelBufferManagerV1 }
  TWpSinglePixelBufferManagerV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _CREATE_U32_RGBA_BUFFER = 1);
  public
    destructor Destroy; override;
    function CreateU32RgbaBuffer(aR: DWord; aG: DWord; aB: DWord; aA: DWord; aClassType: TWlBufferClass = nil): TWlBuffer;
  private
    FListeners: array of IWpSinglePixelBufferManagerV1Listener;
  public
    function AddListener(AIntf: IWpSinglePixelBufferManagerV1Listener): LongInt;
  end;

  IWpSinglePixelBufferManagerV1Listener = interface
  ['IWpSinglePixelBufferManagerV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpSinglePixelBufferManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpSinglePixelBufferManagerV1.GetInterfaceName: String;
begin
  Result := 'wp_single_pixel_buffer_manager_v1';
end;

destructor TWpSinglePixelBufferManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpSinglePixelBufferManagerV1.CreateU32RgbaBuffer(aR: DWord; aG: DWord; aB: DWord; aA: DWord; aClassType: TWlBufferClass = nil): TWlBuffer;
begin
  if aClassType = nil then aClassType := TWlBuffer;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_U32_RGBA_BUFFER), [Result.GetObjectId,aR,aG,aB,aA]);
end;

function TWpSinglePixelBufferManagerV1.AddListener(AIntf: IWpSinglePixelBufferManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.