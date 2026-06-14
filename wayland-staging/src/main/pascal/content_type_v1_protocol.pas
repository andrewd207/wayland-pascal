unit content_type_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpContentTypeV1Class = class of TWpContentTypeV1;
  { TWpContentTypeV1 }
  TWpContentTypeV1 = class;

  TWpContentTypeManagerV1Class = class of TWpContentTypeManagerV1;
  { TWpContentTypeManagerV1 }
  TWpContentTypeManagerV1 = class;

  IWpContentTypeManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_surface_content_type(no)', '')]
  { TWpContentTypeManagerV1 }
  TWpContentTypeManagerV1 = class(TWaylandBase)
  public type
    TError = (erAlreadyconstructed = 0);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_SURFACE_CONTENT_TYPE = 1);
  public
    destructor Destroy; override;
    function GetSurfaceContentType(aSurface: TWlSurface; aClassType: TWpContentTypeV1Class = nil): TWpContentTypeV1;
  private
    FListeners: array of IWpContentTypeManagerV1Listener;
  public
    function AddListener(AIntf: IWpContentTypeManagerV1Listener): LongInt;
  end;

  IWpContentTypeManagerV1Listener = interface
  ['IWpContentTypeManagerV1Listener']
  end;

  IWpContentTypeV1Listener = interface;

  [TWLIntfAttribute('destroy(),set_content_type(u)', '')]
  { TWpContentTypeV1 }
  TWpContentTypeV1 = class(TWaylandBase)
  public type
    TType = (tyNone = 0, tyPhoto = 1, tyVideo = 2, tyGame = 3);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _SET_CONTENT_TYPE = 1);
  public
    destructor Destroy; override;
    procedure SetContentType(aContentType: TType);
  private
    FListeners: array of IWpContentTypeV1Listener;
  public
    function AddListener(AIntf: IWpContentTypeV1Listener): LongInt;
  end;

  IWpContentTypeV1Listener = interface
  ['IWpContentTypeV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpContentTypeManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpContentTypeManagerV1.GetInterfaceName: String;
begin
  Result := 'wp_content_type_manager_v1';
end;

destructor TWpContentTypeManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpContentTypeManagerV1.GetSurfaceContentType(aSurface: TWlSurface; aClassType: TWpContentTypeV1Class = nil): TWpContentTypeV1;
begin
  if aClassType = nil then aClassType := TWpContentTypeV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_SURFACE_CONTENT_TYPE), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TWpContentTypeManagerV1.AddListener(AIntf: IWpContentTypeManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpContentTypeV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpContentTypeV1.GetInterfaceName: String;
begin
  Result := 'wp_content_type_v1';
end;

destructor TWpContentTypeV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWpContentTypeV1.SetContentType(aContentType: TType);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_CONTENT_TYPE), [DWord(aContentType)]);
end;

function TWpContentTypeV1.AddListener(AIntf: IWpContentTypeV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.