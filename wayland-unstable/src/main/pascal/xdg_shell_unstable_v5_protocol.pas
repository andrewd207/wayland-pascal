unit xdg_shell_unstable_v5_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TXdgPopupClass = class of TXdgPopup;
  { TXdgPopup }
  TXdgPopup = class;

  TXdgSurfaceClass = class of TXdgSurface;
  { TXdgSurface }
  TXdgSurface = class;

  TXdgShellClass = class of TXdgShell;
  { TXdgShell }
  TXdgShell = class;

  IXdgShellListener = interface;

  [TWLIntfAttribute('destroy(),use_unstable_version(i),get_xdg_surface(no),get_xdg_popup(nooouii),pong(u)', 'ping(u)')]
  { TXdgShell }
  TXdgShell = class(TWaylandBase)
  public type
    TVersion = (veCurrent = 5);
    TError = (erRole = 0, erDefunctsurfaces = 1, erNotthetopmostpopup = 2, erInvalidpopupparent = 3);
    TPingEvent = procedure(Sender: TXdgShell; aSerial: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _USE_UNSTABLE_VERSION = 1, _GET_XDG_SURFACE = 2, _GET_XDG_POPUP = 3, _PONG = 4);
    TEvents = (EV_PING = 0);
  private
    FOnPingPriv: TPingEvent;
  protected
    procedure HandlePing(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PING); virtual;
  published
    property OnPing: TPingEvent read FOnPingPriv write FOnPingPriv;
  public
    destructor Destroy; override;
    procedure UseUnstableVersion(aVersion: Integer);
    function GetXdgSurface(aSurface: TWlSurface; aClassType: TXdgSurfaceClass = nil): TXdgSurface;
    function GetXdgPopup(aSurface: TWlSurface; aParent: TWlSurface; aSeat: TWlSeat; aSerial: DWord; aX: Integer; aY: Integer; aClassType: TXdgPopupClass = nil): TXdgPopup;
    procedure Pong(aSerial: DWord);
  private
    FListeners: array of IXdgShellListener;
  public
    function AddListener(AIntf: IXdgShellListener): LongInt;
  end;

  IXdgShellListener = interface
  ['IXdgShellListener']
    procedure xdg_shell_ping(AXdgShell: TXdgShell; aSerial: DWord);
  end;

  IXdgSurfaceListener = interface;

  [TWLIntfAttribute('destroy(),set_parent(?o),set_title(s),set_app_id(s),show_window_menu(ouii),move(ou),resize(ouu),ack_configure(u),set_window_geometry(iiii),set_maximized(),unset_maximized(),set_fullscreen(?o),unset_fullscreen(),set_minimized()', 'configure(iiau),close()')]
  { TXdgSurface }
  TXdgSurface = class(TWaylandBase)
  public type
    TResizeEdge = (reNone = 0, reTop = 1, reBottom = 2, reLeft = 4, reTopleft = 5, reBottomleft = 6, reRight = 8, reTopright = 9, reBottomright = 10);
    TState = (stMaximized = 1, stFullscreen = 2, stResizing = 3, stActivated = 4);
    TConfigureEvent = procedure(Sender: TXdgSurface; aWidth: Integer; aHeight: Integer; aStates: TBytes; aSerial: DWord) of object;
    TCloseEvent = procedure(Sender: TXdgSurface) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _SET_PARENT = 1, _SET_TITLE = 2, _SET_APP_ID = 3, _SHOW_WINDOW_MENU = 4, _MOVE = 5, _RESIZE = 6, _ACK_CONFIGURE = 7, _SET_WINDOW_GEOMETRY = 8, _SET_MAXIMIZED = 9, _UNSET_MAXIMIZED = 10, _SET_FULLSCREEN = 11, _UNSET_FULLSCREEN = 12, _SET_MINIMIZED = 13);
    TEvents = (EV_CONFIGURE = 0, EV_CLOSE = 1);
  private
    FOnConfigurePriv: TConfigureEvent;
    FOnClosePriv: TCloseEvent;
  protected
    procedure HandleConfigure(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CONFIGURE); virtual;
    procedure HandleClose(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CLOSE); virtual;
  published
    property OnConfigure: TConfigureEvent read FOnConfigurePriv write FOnConfigurePriv;
    property OnClose: TCloseEvent read FOnClosePriv write FOnClosePriv;
  public
    destructor Destroy; override;
    procedure SetParent(aParent: TXdgSurface);
    procedure SetTitle(aTitle: String);
    procedure SetAppId(aAppId: String);
    procedure ShowWindowMenu(aSeat: TWlSeat; aSerial: DWord; aX: Integer; aY: Integer);
    procedure Move(aSeat: TWlSeat; aSerial: DWord);
    procedure Resize(aSeat: TWlSeat; aSerial: DWord; aEdges: DWord);
    procedure AckConfigure(aSerial: DWord);
    procedure SetWindowGeometry(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
    procedure SetMaximized;
    procedure UnsetMaximized;
    procedure SetFullscreen(aOutput: TWlOutput);
    procedure UnsetFullscreen;
    procedure SetMinimized;
  private
    FListeners: array of IXdgSurfaceListener;
  public
    function AddListener(AIntf: IXdgSurfaceListener): LongInt;
  end;

  IXdgSurfaceListener = interface
  ['IXdgSurfaceListener']
    procedure xdg_surface_configure(AXdgSurface: TXdgSurface; aWidth: Integer; aHeight: Integer; aStates: TBytes; aSerial: DWord);
    procedure xdg_surface_close(AXdgSurface: TXdgSurface);
  end;

  IXdgPopupListener = interface;

  [TWLIntfAttribute('destroy()', 'popup_done()')]
  { TXdgPopup }
  TXdgPopup = class(TWaylandBase)
  public type
    TPopupDoneEvent = procedure(Sender: TXdgPopup) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_POPUP_DONE = 0);
  private
    FOnPopupDonePriv: TPopupDoneEvent;
  protected
    procedure HandlePopupDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_POPUP_DONE); virtual;
  published
    property OnPopupDone: TPopupDoneEvent read FOnPopupDonePriv write FOnPopupDonePriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IXdgPopupListener;
  public
    function AddListener(AIntf: IXdgPopupListener): LongInt;
  end;

  IXdgPopupListener = interface
  ['IXdgPopupListener']
    procedure xdg_popup_popup_done(AXdgPopup: TXdgPopup);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TXdgShell.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgShell.GetInterfaceName: String;
begin
  Result := 'xdg_shell';
end;

procedure TXdgShell.HandlePing(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  if Assigned(OnPing) then OnPing(Self,lSerial);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_shell_ping(Self,lSerial);
  AMsg.SetHandled;
end;

destructor TXdgShell.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TXdgShell.UseUnstableVersion(aVersion: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._USE_UNSTABLE_VERSION), [aVersion]);
end;

function TXdgShell.GetXdgSurface(aSurface: TWlSurface; aClassType: TXdgSurfaceClass = nil): TXdgSurface;
begin
  if aClassType = nil then aClassType := TXdgSurface;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_XDG_SURFACE), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TXdgShell.GetXdgPopup(aSurface: TWlSurface; aParent: TWlSurface; aSeat: TWlSeat; aSerial: DWord; aX: Integer; aY: Integer; aClassType: TXdgPopupClass = nil): TXdgPopup;
begin
  if aClassType = nil then aClassType := TXdgPopup;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_XDG_POPUP), [Result.GetObjectId,aSurface.GetObjectId,aParent.GetObjectId,aSeat.GetObjectId,aSerial,aX,aY]);
end;

procedure TXdgShell.Pong(aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._PONG), [aSerial]);
end;

function TXdgShell.AddListener(AIntf: IXdgShellListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TXdgSurface.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgSurface.GetInterfaceName: String;
begin
  Result := 'xdg_surface';
end;

procedure TXdgSurface.HandleConfigure(var AMsg: TWaylandEventMessage);
var
  lWidth: Integer;
  lHeight: Integer;
  lStates: TBytes;
  lSerial: DWord;
  lListenerIdx: Integer;
begin
  lWidth := AMsg.Args.ReadInteger;
  lHeight := AMsg.Args.ReadInteger;
  lStates := AMsg.Args.ReadBlob;
  lSerial := AMsg.Args.ReadDWord;
  if Assigned(OnConfigure) then OnConfigure(Self,lWidth,lHeight,lStates,lSerial);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_surface_configure(Self,lWidth,lHeight,lStates,lSerial);
  AMsg.SetHandled;
end;

procedure TXdgSurface.HandleClose(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnClose) then OnClose(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_surface_close(Self);
  AMsg.SetHandled;
end;

destructor TXdgSurface.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TXdgSurface.SetParent(aParent: TXdgSurface);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_PARENT), [WlObjectId(aParent)]);
end;

procedure TXdgSurface.SetTitle(aTitle: String);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_TITLE), [aTitle]);
end;

procedure TXdgSurface.SetAppId(aAppId: String);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_APP_ID), [aAppId]);
end;

procedure TXdgSurface.ShowWindowMenu(aSeat: TWlSeat; aSerial: DWord; aX: Integer; aY: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SHOW_WINDOW_MENU), [aSeat.GetObjectId,aSerial,aX,aY]);
end;

procedure TXdgSurface.Move(aSeat: TWlSeat; aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._MOVE), [aSeat.GetObjectId,aSerial]);
end;

procedure TXdgSurface.Resize(aSeat: TWlSeat; aSerial: DWord; aEdges: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RESIZE), [aSeat.GetObjectId,aSerial,aEdges]);
end;

procedure TXdgSurface.AckConfigure(aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._ACK_CONFIGURE), [aSerial]);
end;

procedure TXdgSurface.SetWindowGeometry(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_WINDOW_GEOMETRY), [aX,aY,aWidth,aHeight]);
end;

procedure TXdgSurface.SetMaximized;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_MAXIMIZED), []);
end;

procedure TXdgSurface.UnsetMaximized;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._UNSET_MAXIMIZED), []);
end;

procedure TXdgSurface.SetFullscreen(aOutput: TWlOutput);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_FULLSCREEN), [WlObjectId(aOutput)]);
end;

procedure TXdgSurface.UnsetFullscreen;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._UNSET_FULLSCREEN), []);
end;

procedure TXdgSurface.SetMinimized;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_MINIMIZED), []);
end;

function TXdgSurface.AddListener(AIntf: IXdgSurfaceListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TXdgPopup.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TXdgPopup.GetInterfaceName: String;
begin
  Result := 'xdg_popup';
end;

procedure TXdgPopup.HandlePopupDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnPopupDone) then OnPopupDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].xdg_popup_popup_done(Self);
  AMsg.SetHandled;
end;

destructor TXdgPopup.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TXdgPopup.AddListener(AIntf: IXdgPopupListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.