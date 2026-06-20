program wlproxy;
// A transparent Wayland proxy that also stress-tests our server binding.
//
// It advertises itself as a compositor on its own socket (default wayland-proxy)
// and connects each downstream client through to the REAL compositor
// ($WAYLAND_DISPLAY). Bytes (and their SCM_RIGHTS fds) are forwarded verbatim in
// both directions, so the client's object ids reach the compositor unchanged and
// real apps just work.
//
// The interesting part: every client->compositor chunk is ALSO teed into a
// per-connection TWaylandServerClient via FeedRequests, so our generated
// wayland_server handlers decode and dispatch the live request stream. A small
// interface->class table seeds bound globals so deeper requests (create_surface,
// get_xdg_surface, ...) dispatch through our handlers too. If our binding ever
// mis-parses real traffic it shows up here immediately; if it parses cleanly the
// app keeps running. The tee never sends anything (forwarding is raw), so it
// cannot perturb the session.
//
// SAFETY: the proxy refuses to bind the same name as $WAYLAND_DISPLAY, so it can
// never clobber the real compositor's socket.
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, BaseUnix, ctypes, sockets, ssockets,
  unix_fd_socket, wayland_stream,
  wayland_server_core, wayland_queue,
  wayland_server, xdg_shell_server,
  // Links every generated server interface so each self-registers — the bind
  // handler can then resolve ANY interface name via FindServerInterface.
  wayland_server_all;

const
  BUFSZ  = 65536;          // a whole max-size wayland message fits in one chunk
  MAXFDS = WL_MAX_FDS_PER_RECV;

function socket(d, t, p: cint): cint; cdecl; external 'c' name 'socket';
function bind(fd: cint; addr: psockaddr; len: cuint): cint; cdecl; external 'c' name 'bind';
function listen(fd, n: cint): cint; cdecl; external 'c' name 'listen';
function accept(fd: cint; addr: psockaddr; alen: pcuint): cint; cdecl; external 'c' name 'accept';

type
  { TConn — one downstream client and its upstream connection to the compositor. }
  TConn = class
    Up: TCUnixSocket;            // connection to the real compositor
    Srv: TWaylandServerClient;   // dispatch-only tee (owns the downstream socket)
    Tee: Boolean;                // disabled if our binding chokes on a message
    constructor Create(AUp: TCUnixSocket; ASrv: TWaylandServerClient);
    destructor Destroy; override;
    function DownFd: cint;
  end;

  { TProxy — the tee handlers: log key requests and seed bound globals so the
    rest of the session dispatches through our generated handlers. }
  TProxy = class
    SrvDisplay: TWaylandServerDisplay; // only to satisfy the client ctor
    procedure OnGetRegistry(Sender: TWlDisplay; aRegistry: TWlRegistry);
    procedure OnBind(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord; aId: DWord);
    procedure OnCreateSurface(Sender: TWlCompositor; aId: TWlSurface);
    procedure OnGetXdgSurface(Sender: TXdgWmBase; aId: TXdgSurface; aSurface: TWlSurface);
  end;

constructor TConn.Create(AUp: TCUnixSocket; ASrv: TWaylandServerClient);
begin
  Up := AUp; Srv := ASrv; Tee := True;
end;

destructor TConn.Destroy;
begin
  Srv.Free; // frees the downstream TUnixSocket (closes that fd) + leftover recv fds
  Up.Free;  // closes the upstream fd
  inherited Destroy;
end;

function TConn.DownFd: cint;
begin
  Result := Srv.Socket.Handle;
end;

procedure TProxy.OnGetRegistry(Sender: TWlDisplay; aRegistry: TWlRegistry);
begin
  WriteLn('[tee] get_registry (registry id=', aRegistry.GetObjectId, ')');
  aRegistry.OnBind := @OnBind;
end;

procedure TProxy.OnBind(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord; aId: DWord);
var
  cls: TWaylandServerResourceClass;
  r: TWaylandServerResource;
begin
  // Resolve the interface name to its server class via the global registry (every
  // generated interface self-registers — see the wayland_server_all uses above),
  // and seed the bound global as a real resource so requests TO it dispatch
  // through our handlers. The new_id requests those globals serve (get_keyboard,
  // create_surface, get_xdg_surface, ...) then auto-create their children.
  cls := FindServerInterface(aInterface);
  if cls = nil then
  begin
    WriteLn('[tee] bind ', aInterface, ' v', aVersion, ' -> id ', aId, '  (not in our protocols; tee skips it)');
    Exit;
  end;
  WriteLn('[tee] bind ', aInterface, ' v', aVersion, ' -> id ', aId, '  (', cls.ClassName, ')');
  r := cls.Create(Sender.Client, aId, aVersion);
  // Wire logging on the couple of globals whose children we want to announce.
  if r is TWlCompositor then TWlCompositor(r).OnCreateSurface := @OnCreateSurface
  else if r is TXdgWmBase then TXdgWmBase(r).OnGetXdgSurface := @OnGetXdgSurface;
end;

procedure TProxy.OnCreateSurface(Sender: TWlCompositor; aId: TWlSurface);
begin
  WriteLn('[tee] wl_compositor.create_surface -> wl_surface id=', aId.GetObjectId);
end;

procedure TProxy.OnGetXdgSurface(Sender: TXdgWmBase; aId: TXdgSurface; aSurface: TWlSurface);
begin
  WriteLn('[tee] xdg_wm_base.get_xdg_surface -> xdg_surface id=', aId.GetObjectId,
          ' (wl_surface id=', aSurface.GetObjectId, ')');
end;

// ---------------------------------------------------------------------------

procedure CloseFds(const AFds: array of cint; ACount: Integer);
var i: Integer;
begin
  for i := 0 to ACount - 1 do
    if AFds[i] >= 0 then FpClose(AFds[i]);
end;

var
  Proxy: TProxy;
  Conns: array of TConn;
  ListenFd: cint = -1;
  UpstreamPath: String;

procedure DropConn(AIndex: Integer);
var
  i: Integer;
begin
  WriteLn('[proxy] client disconnected');
  Conns[AIndex].Free;
  for i := AIndex to High(Conns) - 1 do
    Conns[i] := Conns[i + 1];
  SetLength(Conns, Length(Conns) - 1);
end;

procedure AcceptClient;
var
  lFd: cint;
  lUp: TCUnixSocket;
  lSrv: TWaylandServerClient;
  lConn: TConn;
begin
  lFd := accept(ListenFd, nil, nil);
  if lFd < 0 then Exit;
  try
    lUp := TCUnixSocket.Create(UpstreamPath); // connect to the real compositor
  except
    on E: Exception do
    begin
      WriteLn('[proxy] upstream connect failed: ', E.Message);
      FpClose(lFd);
      Exit;
    end;
  end;
  lSrv := TWaylandServerClient.Create(Proxy.SrvDisplay, TUnixSocket.Create(lFd, nil));
  lSrv.BindDisplay(TWlDisplay);
  (lSrv.GetObject(WL_DISPLAY_OBJECT_ID) as TWlDisplay).OnGetRegistry := @Proxy.OnGetRegistry;
  lConn := TConn.Create(lUp, lSrv);
  SetLength(Conns, Length(Conns) + 1);
  Conns[High(Conns)] := lConn;
  WriteLn('[proxy] client connected -> upstream ', UpstreamPath);
end;

// Forward one readable chunk from AFrom to ATo (with its fds). If ATee is set,
// also feed it into the connection's server binding. Returns False if the source
// closed (caller should drop the connection).
function Forward(AConn: TConn; AFromFd, AToFd: cint; ATee: Boolean): Boolean;
var
  buf: array[0..BUFSZ - 1] of Byte;
  fds: array[0..MAXFDS - 1] of cint;
  nfds: Integer;
  n: ssize_t;
begin
  nfds := 0;
  n := RecvWithFds(AFromFd, @buf[0], BUFSZ, @fds[0], MAXFDS, nfds);
  if n <= 0 then
    Exit(False); // peer closed (0) or error
  // Forward verbatim to the other side; sendmsg dups any fds into its kernel.
  SendWithFds(AToFd, @buf[0], n, @fds[0], nfds);
  if ATee then
  begin
    // Tee into our server binding. FeedRequests takes ownership of the fds (it
    // closes them via the message's ReleaseFds, or on client teardown), so we do
    // NOT close them here. On a parse error, leave them to the client and stop
    // teeing this connection (raw forwarding above keeps the app alive).
    try
      AConn.Srv.FeedRequests(@buf[0], n, @fds[0], nfds);
    except
      on E: Exception do
      begin
        WriteLn('[proxy] tee dispatch error (tee disabled for this client): ', E.Message);
        AConn.Tee := False;
      end;
    end;
  end
  else
    CloseFds(fds, nfds); // not teed: we own them, close after forwarding
  Result := True;
end;

procedure Run;
var
  lPoll: array of TPollfd;
  i, base: Integer;
begin
  while True do
  begin
    SetLength(lPoll, 1 + Length(Conns) * 2);
    lPoll[0].fd := ListenFd; lPoll[0].events := POLLIN; lPoll[0].revents := 0;
    for i := 0 to High(Conns) do
    begin
      lPoll[1 + i*2].fd := Conns[i].DownFd; lPoll[1 + i*2].events := POLLIN; lPoll[1 + i*2].revents := 0;
      lPoll[2 + i*2].fd := Conns[i].Up.Handle; lPoll[2 + i*2].events := POLLIN; lPoll[2 + i*2].revents := 0;
    end;

    if FpPoll(@lPoll[0], Length(lPoll), 1000) <= 0 then Continue;

    // Service clients high->low so a drop doesn't shift indices we still visit.
    for i := High(Conns) downto 0 do
    begin
      base := 1 + i*2;
      if (lPoll[base].revents and (POLLHUP or POLLERR or POLLNVAL)) <> 0 then
        DropConn(i)
      else if (lPoll[base].revents and POLLIN) <> 0 then
      begin
        // downstream client -> compositor (requests): forward + tee
        if not Forward(Conns[i], Conns[i].DownFd, Conns[i].Up.Handle, Conns[i].Tee) then
        begin DropConn(i); Continue; end;
        // also drain the upstream side if it became readable meanwhile
        if (lPoll[base+1].revents and POLLIN) <> 0 then
          if not Forward(Conns[i], Conns[i].Up.Handle, Conns[i].DownFd, False) then
            DropConn(i);
      end
      else if (lPoll[base+1].revents and POLLIN) <> 0 then
      begin
        // compositor -> downstream client (events): forward raw only
        if not Forward(Conns[i], Conns[i].Up.Handle, Conns[i].DownFd, False) then
          DropConn(i);
      end;
    end;

    if (lPoll[0].revents and POLLIN) <> 0 then
      AcceptClient;
    Flush(Output); // logs are useful even when the proxy is killed externally
  end;
end;

var
  lRuntimeDir, lDisplay, lProxyName, lListenPath: String;
  lAddr: sockaddr_un;
begin
  lRuntimeDir := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if lRuntimeDir = '' then begin WriteLn('XDG_RUNTIME_DIR not set'); Halt(1); end;
  lRuntimeDir := IncludeTrailingPathDelimiter(lRuntimeDir);

  lDisplay := GetEnvironmentVariable('WAYLAND_DISPLAY');
  if lDisplay = '' then lDisplay := 'wayland-0';
  UpstreamPath := lRuntimeDir + lDisplay;

  // proxy socket name: arg 1, else WLPROXY_NAME, else wayland-proxy
  if ParamCount >= 1 then lProxyName := ParamStr(1)
  else lProxyName := GetEnvironmentVariable('WLPROXY_NAME');
  if lProxyName = '' then lProxyName := 'wayland-proxy';

  if lProxyName = lDisplay then
  begin
    WriteLn('refusing to bind ''', lProxyName, ''': that is the real compositor ($WAYLAND_DISPLAY)');
    Halt(1);
  end;

  lListenPath := lRuntimeDir + lProxyName;
  ListenFd := socket(AF_UNIX, SOCK_STREAM, 0);
  if ListenFd < 0 then begin WriteLn('socket() failed'); Halt(1); end;
  FpUnlink(lListenPath); // clear a stale proxy socket (never the compositor's)
  FillChar(lAddr, SizeOf(lAddr), 0);
  lAddr.sun_family := AF_UNIX;
  Move(lListenPath[1], lAddr.sun_path[0], Length(lListenPath));
  if bind(ListenFd, @lAddr, SizeOf(lAddr)) < 0 then
  begin WriteLn('bind(', lListenPath, ') failed (errno ', c_errno, ')'); Halt(1); end;
  if listen(ListenFd, 16) < 0 then
  begin WriteLn('listen failed'); Halt(1); end;

  Proxy := TProxy.Create;
  Proxy.SrvDisplay := TWaylandServerDisplay.Create;
  WriteLn('[proxy] listening on ', lListenPath);
  WriteLn('[proxy] forwarding to ', UpstreamPath);
  WriteLn('[proxy] point clients at it with:  export WAYLAND_DISPLAY=', lProxyName);
  Run;
end.
