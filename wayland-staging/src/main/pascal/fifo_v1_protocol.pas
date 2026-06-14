unit fifo_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpFifoV1Class = class of TWpFifoV1;
  { TWpFifoV1 }
  TWpFifoV1 = class;

  TWpFifoManagerV1Class = class of TWpFifoManagerV1;
  { TWpFifoManagerV1 }
  TWpFifoManagerV1 = class;

  IWpFifoManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_fifo(no)', '')]
  { TWpFifoManagerV1 }
  TWpFifoManagerV1 = class(TWaylandBase)
  public type
    TError = (erAlreadyexists = 0);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_FIFO = 1);
  public
    destructor Destroy; override;
    function GetFifo(aSurface: TWlSurface; aClassType: TWpFifoV1Class = nil): TWpFifoV1;
  private
    FListeners: array of IWpFifoManagerV1Listener;
  public
    function AddListener(AIntf: IWpFifoManagerV1Listener): LongInt;
  end;

  IWpFifoManagerV1Listener = interface
  ['IWpFifoManagerV1Listener']
  end;

  IWpFifoV1Listener = interface;

  [TWLIntfAttribute('set_barrier(),wait_barrier(),destroy()', '')]
  { TWpFifoV1 }
  TWpFifoV1 = class(TWaylandBase)
  public type
    TError = (erSurfacedestroyed = 0);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_SET_BARRIER = 0, _WAIT_BARRIER = 1, _DESTROY = 2);
  public
    procedure SetBarrier;
    procedure WaitBarrier;
    destructor Destroy; override;
  private
    FListeners: array of IWpFifoV1Listener;
  public
    function AddListener(AIntf: IWpFifoV1Listener): LongInt;
  end;

  IWpFifoV1Listener = interface
  ['IWpFifoV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpFifoManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpFifoManagerV1.GetInterfaceName: String;
begin
  Result := 'wp_fifo_manager_v1';
end;

destructor TWpFifoManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpFifoManagerV1.GetFifo(aSurface: TWlSurface; aClassType: TWpFifoV1Class = nil): TWpFifoV1;
begin
  if aClassType = nil then aClassType := TWpFifoV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_FIFO), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TWpFifoManagerV1.AddListener(AIntf: IWpFifoManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpFifoV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpFifoV1.GetInterfaceName: String;
begin
  Result := 'wp_fifo_v1';
end;

procedure TWpFifoV1.SetBarrier;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_BARRIER), []);
end;

procedure TWpFifoV1.WaitBarrier;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._WAIT_BARRIER), []);
end;

destructor TWpFifoV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpFifoV1.AddListener(AIntf: IWpFifoV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.