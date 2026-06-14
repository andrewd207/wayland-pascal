unit xdg_toplevel_icon_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland, xdg_shell_protocol;

type
  TXdgToplevelIconV1Class = class of TXdgToplevelIconV1;
  { TXdgToplevelIconV1 }
  TXdgToplevelIconV1 = class;

  TXdgToplevelIconManagerV1Class = class of TXdgToplevelIconManagerV1;
  { TXdgToplevelIconManagerV1 }
  TXdgToplevelIconManagerV1 = class;

  IXdgToplevelIconManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),create_icon(n),set_icon(o?o)', 'icon_size(i),done()')]
  { TXdgToplevelIconManagerV1 }
  TXdgToplevelIconManagerV1 = class(TWaylandBase)
  public type
    TIconSizeEvent = procedure(Sender: TXdgToplevelIconManagerV1; aSize: Integer) of object;
    TDoneEvent = procedure(Sender: TXdgToplevelIconManagerV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _CREATE_ICON = 1, _SET_ICON = 2);
    TEvents = (EV_ICON_SIZE = 0, EV_DONE = 1);
  private
    FOnIconSizePriv: TIconSizeEvent;
    FOnDonePriv: TDoneEvent;
  protected
    procedure HandleIconSize(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ICON_SIZE); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
  published
    property OnIconSize: TIconSizeEvent read FOnIconSizePriv write FOnIconSizePriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
  public
    destructor Destroy; override;
    function CreateIcon(aClassType: TXdgToplevelIconV1Class = nil): TXdgToplevelIconV1;
    procedure SetIcon(aToplevel: TXdgToplevel; aIcon: TXdgToplevelIconV1);
  private
    FListeners: array of IXdgToplevelIconManagerV1Listener;
  public
    function AddListener(AIntf: IXdgToplevelIconManagerV1Listener): LongInt;
  end;

  IXdgToplevelIconManagerV1Listener = interface
  ['IXdgToplevelIconManagerV1Listener']
    procedure xdg_toplevel_icon_manager_v1_icon_size(AXdgToplevelIconManagerV1: TXdgToplevelIconManagerV1; aSize: Integer);
    procedure xdg_toplevel_icon_manager_v1_done(AXdgToplevelIconManagerV1: TXdgToplevelIconManagerV1);
  end;

  IXdgToplevelIconV1Listener = interface;

  [TWLIntfAttribute('destroy(),set_name(s),add_buffer(oi)', '')]
  { TXdgToplevelIconV1 }
  TXdgToplevelIconV1 = class(TWaylandBase)
  public type
    TError = (erInvalidbuffer = 1, erImmutable = 2, erNobuffer = 3);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _SET_NAME = 1, _ADD_BUFFER = 2);
  public
    destructor Destroy; override;
    procedure SetName(aIconName: String);
    procedure AddBuffer(aBuffer: TWlBuffer; aScale: Integer);
  private
    FListeners: array of IXdgToplevelIconV1Listener;
  public
    function AddListener(AIntf: IXdgToplevelIconV1Listener): LongInt;
  end;

  IXdgToplevelIconV1Listener = interface
  ['IXdgToplevelIconV1Listener']
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TXdgToplevelIconManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgToplevelIconManagerV1.GetInterfaceName: String;
begin
  Result := 'xdg_toplevel_icon_manager_v1';
end;

procedure TXdgToplevelIconManagerV1.HandleIconSize(var AMsg: TWaylandEventMessage);
var
  lSize: Integer;
  lListenerIdx: Integer;
begin
  lSize := AMsg.Args.ReadInteger;
  if Assigned(OnIconSize) then OnIconSize(Self,lSize);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_toplevel_icon_manager_v1_icon_size(Self,lSize);
  AMsg.SetHandled;
end;

procedure TXdgToplevelIconManagerV1.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_toplevel_icon_manager_v1_done(Self);
  AMsg.SetHandled;
end;

destructor TXdgToplevelIconManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TXdgToplevelIconManagerV1.CreateIcon(aClassType: TXdgToplevelIconV1Class = nil): TXdgToplevelIconV1;
begin
  if aClassType = nil then aClassType := TXdgToplevelIconV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_ICON), [Result.GetObjectId]);
end;

procedure TXdgToplevelIconManagerV1.SetIcon(aToplevel: TXdgToplevel; aIcon: TXdgToplevelIconV1);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_ICON), [aToplevel.GetObjectId,WlObjectId(aIcon)]);
end;

function TXdgToplevelIconManagerV1.AddListener(AIntf: IXdgToplevelIconManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TXdgToplevelIconV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgToplevelIconV1.GetInterfaceName: String;
begin
  Result := 'xdg_toplevel_icon_v1';
end;

destructor TXdgToplevelIconV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TXdgToplevelIconV1.SetName(aIconName: String);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_NAME), [aIconName]);
end;

procedure TXdgToplevelIconV1.AddBuffer(aBuffer: TWlBuffer; aScale: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._ADD_BUFFER), [aBuffer.GetObjectId,aScale]);
end;

function TXdgToplevelIconV1.AddListener(AIntf: IXdgToplevelIconV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.