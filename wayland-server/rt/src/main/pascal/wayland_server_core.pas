// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

unit wayland_server_core;

{ Server-side runtime base, the mirror image of Wayland_Core (the client core).

  Where the client connects one socket and sends *requests* / receives *events*,
  a server listens on a socket, accepts many clients, and for each one receives
  *requests* (incoming, dispatched to handler methods) and sends *events*
  (outgoing, marshalled the same way the client marshals requests).

  Three classes carry the runtime, paralleling the client's
  TWaylandBase / TWaylandDisplayBase split:

    TWaylandServerResource  one protocol object owned by a client (the
                            server-side analogue of a client proxy). Generated
                            server units subclass it; incoming requests are
                            routed to `message`-tagged handlers exactly as the
                            client routes events.
    TWaylandServerClient    one accepted connection: its own object map, its own
                            server-range id allocator, its own receive buffer.
    TWaylandServerDisplay   the listening socket + accept/poll loop.

  The wire transport (socket, SCM_RIGHTS fd passing, the stream codec, the
  event-message/fd-stream value types) is shared with the client and lives in
  wayland-common; this unit is compiled with that directory on its unit path.

  The small protocol value helpers below (TWaylandFixed, TBitfield,
  TWLIntfAttribute) are duplicated from Wayland_Core on purpose: the two cores
  are independent roots, and the server must not drag in the generated client
  proxies. They are candidates to hoist into a shared wayland-common unit later.

  -- Threading model ---------------------------------------------------------
  The design target is one event-loop thread plus one or more worker threads
  that push *events* out (e.g. an X11 backend translating input/configure into
  Wayland events). Concretely:

    * The receive side runs on a single thread: TWaylandServerDisplay.Run /
      Iterate, and therefore TWaylandServerClient.ProcessRequests and the whole
      receive buffer + fd FIFO, are NOT locked and must only ever be touched by
      that one loop thread. (Request *handlers* run on it too.)

    * Everything an outgoing path needs IS internally synchronised, so events
      may be sent from any thread concurrently with the loop:
        - SendMessage / SendEvent  — guarded by FSendLock (the pooled send
          buffer + the socket write are serialised).
        - the per-client object map + server-id allocator (RegisterResource,
          RemoveResource, GetObject, AllocServerId, NewResource) — guarded by
          FObjLock.
        - the display's client list (Clients enumeration / add / drop) —
          guarded by FClientsLock.
      The two per-client locks are never nested (a send takes FSendLock only; a
      resource create/lookup takes FObjLock only), so there is no lock-ordering
      hazard between them. Reading from and writing to one client socket on two
      threads is safe (full-duplex; SO_RCVTIMEO only affects recv).

    * Object lifetime is the caller's responsibility, exactly as in libwayland:
      a resource (or whole client) must not be freed on one thread while another
      thread is still sending to it. Drop clients only from the loop thread, and
      do not retain a TWaylandServerResource/Client reference in a worker past
      the point the loop thread may destroy it. }

{$mode ObjFPC}{$H+}
{$ModeSwitch typehelpers}

{.$DEFINE WL_SERVER_DEBUG}

interface

uses
  Classes, SysUtils, fgl, BaseUnix, ctypes, sockets, ssockets, TypInfo,
  wayland_stream, wayland_queue;

const
  // wl_display is always object id 1 on every connection — the implicit root the
  // client talks to before it has bound anything else.
  WL_DISPLAY_OBJECT_ID = DWord(1);
  // Server-allocated object ids live in the upper range [0xff000000 .. 0xffffffff];
  // client-allocated ids occupy [1 .. 0xfeffffff]. (wl_display is always id 1,
  // created by the client side, so the server's first allocation starts here.)
  WL_SERVER_ID_BASE = DWord($ff000000);
  WL_SERVER_ID_MAX  = DWord($ffffffff);

type
  EWaylandServer = class(Exception);

  TWaylandServerResource = class;
  TWaylandServerClient = class;
  TWaylandServerDisplay = class;

  // --- protocol value helpers (mirror of Wayland_Core) -----------------------

  // signed 24.8 fixed-point; see Wayland_Core.TWaylandFixedHelper for the why.
  TWaylandFixed = type Double;

  { TWaylandFixedHelper }

  TWaylandFixedHelper = type helper for TWaylandFixed
    function AsFixed: Integer;
    function AsInteger: Integer;
    class function FromFixed(AValue: Integer): TWaylandFixed; static;
  end;

  { TBitfield }

  TBitfield = object
  protected
    function GetValue(AIndex: Integer): Boolean;
    procedure SetValue(AIndex: Integer; AValue: Boolean);
  public
    Value: DWord;
  end;

  { TWLIntfAttribute }

  // Usage: [TWLIntfAttribute('<request_sig>,...', '<event_sig>,...')]
  // Carried by every generated resource class so the runtime can recover a
  // request's argument signature (to count its out-of-band 'h' fd args).
  TWLIntfAttribute = class(TCustomAttribute)
  private
    FRequests: TStringArray;
    FEvents: TStringArray;
    function GetEvent(AIndex: Integer): String;
    function GetRequest(AIndex: Integer): String;
  public
    constructor Create(ARequests, AEvents: String);
    property Request[AIndex: Integer]: String read GetRequest;
    property Event[AIndex: Integer]: String read GetEvent;
  end;

  // --- runtime --------------------------------------------------------------

  TWaylandServerResourceClass = class of TWaylandServerResource;

  { TWaylandServerResource }

  TWaylandServerResource = class(TObject)
  private
    FClient: TWaylandServerClient;
    FId: DWord;
    FVersion: Integer;
    FUserData: Pointer;
  protected
    class function GetInterfaceName: String; virtual; abstract;
    class function GetInterfaceVersion: Integer; virtual; abstract;
    function GetInterfaceAttribute: TWLIntfAttribute;
    // Marshal an event to this resource's client. AFdIndex marks the single
    // arg (if any) carried out-of-band as an fd. Mirrors the client's SendRequest.
    procedure SendEvent(AOpcode: Word; Args: array of const; AFdIndex: Integer = -1);
    // Allocate a fresh server-range id and create+register a child resource of
    // AClass on the same client. Used by events that carry a server-created
    // new_id (the outgoing new_id case).
    function NewResource(AClass: TWaylandServerResourceClass; AVersion: Integer): TWaylandServerResource;
  public
    constructor Create(AClient: TWaylandServerClient; AId: DWord; AVersion: Integer); virtual;
    destructor Destroy; override;
    // Routes an incoming request (carried in a TWaylandEventMessage, OpCode =
    // request opcode) to the matching `message`-tagged handler. A request with
    // no handler is a protocol error (unhandled).
    procedure Dispatch(var message); override;
    // Same value as the Id property; a method form the generator can call without
    // risking a name clash with a protocol member literally named "id" (which
    // becomes a method on the resource class and would shadow the property).
    function GetObjectId: DWord;
    property Client: TWaylandServerClient read FClient;
    property Id: DWord read FId;
    property Version: Integer read FVersion;
    property UserData: Pointer read FUserData write FUserData;
  end;

  TWaylandServerObjectMap = specialize TFPGMapObject<DWord, TWaylandServerResource>;

  { TWaylandServerClient }

  TWaylandServerClient = class
  private
    FDisplay: TWaylandServerDisplay;
    FSocket: TUnixSocket;
    FObjects: TWaylandServerObjectMap; // guarded by FObjLock
    FNextServerId: DWord;              // guarded by FObjLock
    FObjLock: TRTLCriticalSection;     // FObjects + FNextServerId
    FSendStream: TWaylandStream;       // pooled outgoing buffer, guarded by FSendLock
    FSendLock: TRTLCriticalSection;    // FSendStream + the socket write
    FShuttingDown: Boolean;            // true while FObjects is being freed
    FUserData: Pointer;
    // Receive buffer (parse cursor FRecvHead, valid-end FRecvTail), compacted on
    // each refill — same scheme as the client's TWaylandDisplayBase.
    FRecvBuf: TBytes;
    FRecvHead, FRecvTail: Integer;
    // FIFO of fds harvested out-of-band by recvmsg, in arrival (= signature) order.
    FRecvFds: array of cint;
    FRecvFdHead, FRecvFdTail: Integer;
    function FillRecvBuffer: Boolean;
    procedure PushRecvFd(AFd: cint);
    function PopRecvFd: cint;
    function CountFds(const ASignature: String): Integer;
    function HasCompleteMessage: Boolean;
    procedure DispatchBuffered;
  public
    constructor Create(ADisplay: TWaylandServerDisplay; ASocket: TUnixSocket);
    destructor Destroy; override;
    // Allocate the next server-range object id for this client.
    function AllocServerId: DWord;
    procedure RegisterResource(AResource: TWaylandServerResource; AId: DWord);
    procedure RemoveResource(AId: DWord; AFromDestructor: Boolean);
    function GetObject(AId: DWord): TWaylandServerResource;
    // Create the connection's root wl_display resource at the well-known id 1
    // (ADisplayClass is the generated TWlDisplay server class). Every client must
    // have exactly one; raises if id 1 is already bound. Return it to wire up its
    // request handlers (e.g. OnGetRegistry). The runtime can't name TWlDisplay
    // itself (it lives in a generated unit above this one), hence the class arg.
    function BindDisplay(ADisplayClass: TWaylandServerResourceClass; AVersion: Integer = 1): TWaylandServerResource;
    // Marshal one message (an event) onto this client's socket.
    procedure SendMessage(AObjectId: DWord; AOpcode: Word; Args: array of const; AFdIndex: Integer = -1);
    // Pull whatever is currently readable off the socket and dispatch every
    // complete request in it; a partial tail stays buffered for the next call.
    // Returns False once the peer has closed (the caller should drop the client).
    function ProcessRequests: Boolean;
    property Display: TWaylandServerDisplay read FDisplay;
    property Socket: TUnixSocket read FSocket;
    property UserData: Pointer read FUserData write FUserData;
  end;

  TWaylandServerClientList = specialize TFPGObjectList<TWaylandServerClient>;
  TWaylandClientEvent = procedure(AClient: TWaylandServerClient) of object;

  { TWaylandServerDisplay }

  TWaylandServerDisplay = class
  private
    FListenFd: cint;
    FSocketPath: String;
    FClients: TWaylandServerClientList;
    FClientsLock: TRTLCriticalSection; // guards FClients add/remove/enumerate
    FQuit: Boolean;
    FDisplayClass: TWaylandServerResourceClass;
    FOnConnect: TWaylandClientEvent;
    FOnDisconnect: TWaylandClientEvent;
    procedure AcceptClient;
    procedure DropClient(AClient: TWaylandServerClient);
  public
    constructor Create;
    destructor Destroy; override;
    // Bind $XDG_RUNTIME_DIR/<AName> (AName defaults to wayland-0). Raises on
    // failure. Returns the bound socket name.
    function AddSocket(const AName: String = 'wayland-0'): String;
    // Bind the first free wayland-N (N in [0..32]); returns the name, or '' if
    // every candidate was taken.
    function AddSocketAuto: String;
    // Single-threaded accept + per-client request pump. Blocks until Quit.
    procedure Run;
    // Service the socket once: accept pending clients and dispatch any requests
    // ready within ATimeoutMs (0 = poll and return immediately). Lets a caller
    // drive the server from its own event loop instead of Run.
    procedure Iterate(ATimeoutMs: Integer);
    procedure Quit;
    // Hold this around any enumeration of Clients from a thread other than the
    // loop thread (e.g. broadcasting an event to every client), so the loop
    // thread cannot add/drop a client mid-walk. Always pair Lock/Unlock.
    procedure LockClients;
    procedure UnlockClients;
    property SocketPath: String read FSocketPath;
    property Clients: TWaylandServerClientList read FClients;
    // When set, every accepted client gets its wl_display bound at id 1
    // automatically (via TWaylandServerClient.BindDisplay) BEFORE OnConnect
    // fires, so a handler can just fetch it with GetObject(WL_DISPLAY_OBJECT_ID)
    // and wire up its requests. Leave nil to bind it yourself in OnConnect.
    property DisplayClass: TWaylandServerResourceClass read FDisplayClass write FDisplayClass;
    property OnConnect: TWaylandClientEvent read FOnConnect write FOnConnect;
    property OnDisconnect: TWaylandClientEvent read FOnDisconnect write FOnDisconnect;
  end;

  // Returns AResource's object id, or 0 (the protocol null id) when nil. The
  // server-side counterpart of Wayland_Core.WlObjectId, for nullable object args.
  function WlResourceId(AResource: TWaylandServerResource): DWord;

implementation

uses
  unix_fd_socket;

const
  RECV_CHUNK = 4096;

function socket(__domain, __type, __protocol: cint): cint; cdecl; external 'c' name 'socket';
function bind(__fd: cint; __addr: psockaddr; __len: cuint): cint; cdecl; external 'c' name 'bind';
function listen(__fd: cint; __n: cint): cint; cdecl; external 'c' name 'listen';
function accept(__fd: cint; __addr: psockaddr; __addrlen: pcuint): cint; cdecl; external 'c' name 'accept';

type
  TWaylandMsgHeader = packed record
    Obj: DWord;
    Index: Word;
    Size: Word;
  end;

function WlResourceId(AResource: TWaylandServerResource): DWord;
begin
  if AResource = nil then
    Result := 0
  else
    Result := AResource.Id;
end;

{ TWaylandFixedHelper }

function TWaylandFixedHelper.AsFixed: Integer;
const
  cMax = 8388607.99609375;
  cMin = -8388608.0;
var
  v: Double;
begin
  v := Self;
  if v > cMax then v := cMax
  else if v < cMin then v := cMin;
  Result := Round(v * 256);
end;

function TWaylandFixedHelper.AsInteger: Integer;
begin
  Result := Trunc(Self);
end;

class function TWaylandFixedHelper.FromFixed(AValue: Integer): TWaylandFixed;
begin
  Result := AValue / 256.0;
end;

{ TBitfield }

function TBitfield.GetValue(AIndex: Integer): Boolean;
begin
  Result := AIndex and Value <> 0;
end;

procedure TBitfield.SetValue(AIndex: Integer; AValue: Boolean);
begin
  if AValue then Value := Value or AIndex
  else Value := Value and not DWord(AIndex);
end;

{ TWLIntfAttribute }

function TWLIntfAttribute.GetRequest(AIndex: Integer): String;
begin
  Result := Format('invalid_request_opcode:%d(?)', [AIndex]);
  if Self = nil then Exit;
  if (AIndex >= 0) and (AIndex <= High(FRequests)) then
    Result := Trim(FRequests[AIndex]);
end;

function TWLIntfAttribute.GetEvent(AIndex: Integer): String;
begin
  Result := Format('invalid_event_opcode:%d(?)', [AIndex]);
  if Self = nil then Exit;
  if (AIndex >= 0) and (AIndex <= High(FEvents)) then
    Result := Trim(FEvents[AIndex]);
end;

constructor TWLIntfAttribute.Create(ARequests, AEvents: String);
begin
  inherited Create;
  if Length(Trim(ARequests)) > 0 then
    FRequests := ARequests.Split(',');
  if Length(Trim(AEvents)) > 0 then
    FEvents := AEvents.Split(',');
end;

{ TWaylandServerResource }

constructor TWaylandServerResource.Create(AClient: TWaylandServerClient;
  AId: DWord; AVersion: Integer);
begin
  inherited Create;
  FClient := AClient;
  FId := AId;
  FVersion := AVersion;
  FClient.RegisterResource(Self, AId);
  {$IFDEF WL_SERVER_DEBUG}
  WriteLn('+ ', ClassName, ' id=', FId, ' v=', FVersion);
  {$ENDIF}
end;

destructor TWaylandServerResource.Destroy;
begin
  {$IFDEF WL_SERVER_DEBUG}
  WriteLn('- ', ClassName, ' id=', FId);
  {$ENDIF}
  if Assigned(FClient) then
    FClient.RemoveResource(FId, True);
  inherited Destroy;
end;

function TWaylandServerResource.GetInterfaceAttribute: TWLIntfAttribute;
var
  lTypeInf: PTypeInfo;
  lAttrTable: PAttributeTable;
  I: Integer;
  lAttr: TCustomAttribute;
begin
  Result := nil;
  lTypeInf := Self.ClassInfo;
  lAttrTable := GetAttributeTable(lTypeInf);
  if not Assigned(lAttrTable) then Exit;
  for I := 0 to lAttrTable^.AttributeCount - 1 do
  begin
    lAttr := GetAttribute(lAttrTable, I);
    if lAttr is TWLIntfAttribute then
      Result := TWLIntfAttribute(lAttr);
  end;
end;

procedure TWaylandServerResource.SendEvent(AOpcode: Word;
  Args: array of const; AFdIndex: Integer);
begin
  FClient.SendMessage(FId, AOpcode, Args, AFdIndex);
end;

function TWaylandServerResource.NewResource(AClass: TWaylandServerResourceClass;
  AVersion: Integer): TWaylandServerResource;
begin
  Result := AClass.Create(FClient, FClient.AllocServerId, AVersion);
end;

function TWaylandServerResource.GetObjectId: DWord;
begin
  Result := FId;
end;

procedure TWaylandServerResource.Dispatch(var message);
begin
  inherited Dispatch(message);
  with TWaylandEventMessage(message) do
    if not Handled then
      raise EWaylandServer.CreateFmt('%s: unhandled request %d', [ClassName, OpCode]);
end;

{ TWaylandServerClient }

constructor TWaylandServerClient.Create(ADisplay: TWaylandServerDisplay;
  ASocket: TUnixSocket);
begin
  inherited Create;
  InitCriticalSection(FObjLock);
  InitCriticalSection(FSendLock);
  FDisplay := ADisplay;
  FSocket := ASocket;
  // Non-owning: we free the resources ourselves in Destroy. (An owning map's
  // Delete would free the object, double-freeing one that removes itself from
  // its own destructor.)
  FObjects := TWaylandServerObjectMap.Create(False);
  FObjects.Sorted := True;
  FSendStream := TWaylandStream.Create;
  FNextServerId := WL_SERVER_ID_BASE;
end;

destructor TWaylandServerClient.Destroy;
var
  lFd, i: cint;
begin
  // Mark teardown under the lock so a concurrent RemoveResource either runs to
  // completion before us or sees the flag and bails before touching the map.
  EnterCriticalSection(FObjLock);
  FShuttingDown := True;
  LeaveCriticalSection(FObjLock);
  // Free the resources WITHOUT holding FObjLock: each destructor calls
  // RemoveResource, which now early-exits on FShuttingDown before it would try
  // to take the (non-recursive) lock.
  for i := 0 to FObjects.Count - 1 do
    FObjects.Data[i].Free;
  FObjects.Free;
  // close any received-but-unconsumed fds so they don't leak on disconnect.
  repeat
    lFd := PopRecvFd;
    if lFd >= 0 then FpClose(lFd);
  until lFd < 0;
  FSendStream.Free;
  FSocket.Free; // closes the connection fd
  DoneCriticalSection(FObjLock);
  DoneCriticalSection(FSendLock);
  inherited Destroy;
end;

function TWaylandServerClient.AllocServerId: DWord;
begin
  EnterCriticalSection(FObjLock);
  try
    if FNextServerId > WL_SERVER_ID_MAX then
      raise EWaylandServer.Create('server object id space exhausted');
    Result := FNextServerId;
    Inc(FNextServerId);
  finally
    LeaveCriticalSection(FObjLock);
  end;
end;

procedure TWaylandServerClient.RegisterResource(AResource: TWaylandServerResource;
  AId: DWord);
begin
  EnterCriticalSection(FObjLock);
  try
    FObjects.Add(AId, AResource);
  finally
    LeaveCriticalSection(FObjLock);
  end;
end;

procedure TWaylandServerClient.RemoveResource(AId: DWord; AFromDestructor: Boolean);
var
  lIndex: Integer;
begin
  // Unsynchronised read is intentional: during Destroy we must NOT take FObjLock
  // here (the destructor holds the teardown invariant, and the lock is
  // non-recursive). The flag is set under the lock in Destroy, so by the time
  // resources are being freed it is reliably visible to this thread's reads.
  if FShuttingDown then
    Exit; // FObjects is being freed; mutating it here would corrupt the walk
  EnterCriticalSection(FObjLock);
  try
    // The map is non-owning, so Delete just drops the entry — it does not free
    // the resource (whether or not we are inside that resource's destructor).
    if FObjects.Find(AId, lIndex) then
      FObjects.Delete(lIndex);
  finally
    LeaveCriticalSection(FObjLock);
  end;
end;

function TWaylandServerClient.GetObject(AId: DWord): TWaylandServerResource;
var
  lIndex: Integer;
begin
  EnterCriticalSection(FObjLock);
  try
    if FObjects.Find(AId, lIndex) then
      Result := FObjects.Data[lIndex]
    else
      Result := nil;
  finally
    LeaveCriticalSection(FObjLock);
  end;
end;

function TWaylandServerClient.BindDisplay(ADisplayClass: TWaylandServerResourceClass;
  AVersion: Integer): TWaylandServerResource;
begin
  if GetObject(WL_DISPLAY_OBJECT_ID) <> nil then
    raise EWaylandServer.Create('wl_display (id 1) is already bound on this client');
  // The constructor is virtual and registers the resource at the given id, so
  // this lands ADisplayClass at id 1 in the client's object map.
  Result := ADisplayClass.Create(Self, WL_DISPLAY_OBJECT_ID, AVersion);
end;

procedure TWaylandServerClient.SendMessage(AObjectId: DWord; AOpcode: Word;
  Args: array of const; AFdIndex: Integer);
const
  cSizeOffset = 6;
var
  lMsg: TWaylandStream;
  lNeedsPadding: Boolean;
  i: Integer;
  lFdStart: Int64 = -1;
  lMsgLen: Int64;
begin
  EnterCriticalSection(FSendLock);
  try
    lMsg := FSendStream;
    lMsg.Position := 0;
    lMsg.WriteDWord(AObjectId);
    lMsg.WriteWord(AOpcode);
    lMsg.WriteWord(0); // size placeholder, backpatched below

    for i := Low(Args) to High(Args) do
    begin
      if (AFdIndex <> -1) and (AFdIndex = i) then
      begin
        lFdStart := Args[i].VInteger;
        Continue;
      end;
      lNeedsPadding := False;
      case Args[i].VType of
        vtBoolean: lMsg.WriteDWord(Ord(Args[i].VBoolean));
        vtInteger: lMsg.WriteDWord(DWord(Args[i].VInteger));
        vtInt64:
          begin
            if Args[i].VInt64^ <= MaxInt then
              lMsg.WriteDWord(Args[i].VInt64^)
            else
              raise EWaylandServer.CreateFmt('int64 arg %d out of range', [i]);
          end;
        vtPointer:
          begin
            // wl_array: the generator passes (Length, Pointer); the count is the
            // preceding VInteger. Write the uint32 size header, then the bytes.
            lMsg.WriteDWord(DWord(Args[i-1].VInteger));
            if Args[i-1].VInteger > 0 then
              lMsg.Write(Args[i].VPointer^, Args[i-1].VInteger);
            lNeedsPadding := True;
          end;
        vtAnsiString:
          lMsg.WriteString(AnsiString(Args[i].VAnsiString));
        vtObject:
          begin
            if Args[i].VObject = nil then
              lMsg.WriteDWord(0) // nullable object arg
            else if Args[i].VObject.InheritsFrom(TStream) then
            begin
              lMsg.WriteDWord(TStream(Args[i].VObject).Size);
              TStream(Args[i].VObject).Position := 0;
              lMsg.CopyFrom(TStream(Args[i].VObject), TStream(Args[i].VObject).Size);
              lNeedsPadding := True;
            end
            else if Args[i].VObject is TWaylandServerResource then
              lMsg.WriteDWord(TWaylandServerResource(Args[i].VObject).Id)
            else
              raise EWaylandServer.CreateFmt('unsupported object arg %s at %d',
                [Args[i].VObject.ClassName, i]);
          end;
      else
        raise EWaylandServer.CreateFmt('unsupported arg type at %d', [i]);
      end;
      while lNeedsPadding and ((lMsg.Position mod 4) <> 0) do
        lMsg.WriteByte(0);
    end;

    lMsgLen := lMsg.Position;
    if lMsgLen > $FFFF then
      raise EWaylandServer.CreateFmt('event too large (%d > %d)', [lMsgLen, $FFFF]);

    lMsg.Position := cSizeOffset;
    lMsg.WriteWord(lMsgLen);
    lMsg.Position := 0;

    {$IFDEF WL_SERVER_DEBUG}
    WriteLn('> obj=', AObjectId, ' op=', AOpcode, ' size=', lMsgLen);
    {$ENDIF}

    if lFdStart >= 0 then
    begin
      if SendFD(FSocket.Handle, lFdStart, lMsg.Memory, lMsgLen) < 0 then
        raise EWaylandServer.CreateFmt('sendmsg(fd) failed (errno %d)', [c_errno]);
    end
    else
      FSocket.CopyFrom(lMsg, lMsgLen);
  finally
    LeaveCriticalSection(FSendLock);
  end;
end;

function TWaylandServerClient.FillRecvBuffer: Boolean;
var
  lFds: array[0..WL_MAX_FDS_PER_RECV - 1] of cint;
  lFdCount, i, lLeft, lErr: Integer;
  lRead: ssize_t;
begin
  if FRecvHead > 0 then
  begin
    lLeft := FRecvTail - FRecvHead;
    if lLeft > 0 then
      Move(FRecvBuf[FRecvHead], FRecvBuf[0], lLeft);
    FRecvTail := lLeft;
    FRecvHead := 0;
  end;
  if Length(FRecvBuf) - FRecvTail < RECV_CHUNK then
    SetLength(FRecvBuf, FRecvTail + RECV_CHUNK);

  while True do
  begin
    lFdCount := 0;
    lRead := RecvWithFds(FSocket.Handle, @FRecvBuf[FRecvTail],
                         Length(FRecvBuf) - FRecvTail,
                         @lFds[0], WL_MAX_FDS_PER_RECV, lFdCount);
    if lRead > 0 then
    begin
      for i := 0 to lFdCount - 1 do
        PushRecvFd(lFds[i]);
      Inc(FRecvTail, lRead);
      Exit(True);
    end
    else if lRead = 0 then
      Exit(False) // orderly shutdown: peer closed
    else
    begin
      lErr := c_errno;
      if lErr = ESysEINTR then Continue;
      if (lErr = ESysEAGAIN) or (lErr = ESysEWOULDBLOCK) then
        Exit(False); // SO_RCVTIMEO elapsed with no data
      Exit(False);   // broken connection: treat as closed
    end;
  end;
end;

procedure TWaylandServerClient.PushRecvFd(AFd: cint);
begin
  if FRecvFdTail >= Length(FRecvFds) then
    SetLength(FRecvFds, FRecvFdTail + 8);
  FRecvFds[FRecvFdTail] := AFd;
  Inc(FRecvFdTail);
end;

function TWaylandServerClient.PopRecvFd: cint;
begin
  if FRecvFdHead >= FRecvFdTail then
    Exit(-1);
  Result := FRecvFds[FRecvFdHead];
  Inc(FRecvFdHead);
  if FRecvFdHead = FRecvFdTail then
  begin
    FRecvFdHead := 0;
    FRecvFdTail := 0;
  end;
end;

function TWaylandServerClient.CountFds(const ASignature: String): Integer;
var
  i: Integer;
  lInArgs: Boolean;
begin
  // Signature looks like 'attach(oii)'; count 'h' (fd) args between the parens.
  Result := 0;
  lInArgs := False;
  for i := 1 to Length(ASignature) do
    case ASignature[i] of
      '(': lInArgs := True;
      ')': Break;
      'h': if lInArgs then Inc(Result);
    end;
end;

function TWaylandServerClient.HasCompleteMessage: Boolean;
var
  lAvail: Integer;
  lSize: Word;
begin
  lAvail := FRecvTail - FRecvHead;
  if lAvail < SizeOf(TWaylandMsgHeader) then
    Exit(False);
  // size field is the high Word of the header (offset 6), little-endian.
  lSize := PWord(@FRecvBuf[FRecvHead + 6])^;
  Result := (lSize >= SizeOf(TWaylandMsgHeader)) and (lAvail >= lSize);
end;

procedure TWaylandServerClient.DispatchBuffered;
var
  lHeader: TWaylandMsgHeader;
  lBodyLen, lFdCount, i: Integer;
  lResource: TWaylandServerResource;
  lMsg: TWaylandEventMessage;
  lStream: TWaylandStream;
begin
  Move(FRecvBuf[FRecvHead], lHeader, SizeOf(lHeader));
  Inc(FRecvHead, SizeOf(lHeader));
  lBodyLen := lHeader.Size - SizeOf(lHeader);

  lResource := GetObject(lHeader.Obj);
  if lResource = nil then
  begin
    // Unknown target: discard the body (a real compositor would post a protocol
    // error and disconnect; the higher-level server can add that policy).
    Inc(FRecvHead, lBodyLen);
    Exit;
  end;

  lStream := TWaylandStream.Create;
  lMsg.OpCode := lHeader.Index;
  lMsg.Args := lStream;
  lMsg.Handled := False;
  lMsg.FdPos := 0;
  lMsg.Fds := nil;
  lMsg.FdStreams := nil;
  try
    if lBodyLen > 0 then
    begin
      lStream.WriteBuffer(FRecvBuf[FRecvHead], lBodyLen);
      Inc(FRecvHead, lBodyLen);
      lStream.Position := 0;
    end;
  except
    lStream.Free;
    raise;
  end;

  // Attach this request's out-of-band fds, popped in arrival (= signature) order.
  lFdCount := CountFds(lResource.GetInterfaceAttribute.Request[lHeader.Index]);
  if lFdCount > 0 then
  begin
    SetLength(lMsg.Fds, lFdCount);
    for i := 0 to lFdCount - 1 do
      lMsg.Fds[i] := PopRecvFd;
  end;

  try
    lResource.Dispatch(lMsg);
  finally
    lMsg.Args.Free;
    lMsg.ReleaseFds;
  end;
end;

function TWaylandServerClient.ProcessRequests: Boolean;
begin
  // The caller polled us readable; pull one chunk (don't block long if it was a
  // spurious wakeup), then dispatch every complete request it completes.
  FSocket.IOTimeout := 1;
  if not FillRecvBuffer then
    // No bytes: either the peer closed or a spurious wakeup. If there's still a
    // complete buffered message, drain it; otherwise report closed only when
    // nothing remains buffered.
    if not HasCompleteMessage then
      Exit(FRecvTail > FRecvHead); // keep alive only if a partial msg is pending
  Result := True;
  while HasCompleteMessage do
    DispatchBuffered;
end;

{ TWaylandServerDisplay }

constructor TWaylandServerDisplay.Create;
begin
  inherited Create;
  InitCriticalSection(FClientsLock);
  FListenFd := -1;
  FClients := TWaylandServerClientList.Create(True);
end;

destructor TWaylandServerDisplay.Destroy;
begin
  FClients.Free; // owned: frees every client (and its resources)
  if FListenFd >= 0 then
    FpClose(FListenFd);
  if FSocketPath <> '' then
    FpUnlink(FSocketPath);
  DoneCriticalSection(FClientsLock);
  inherited Destroy;
end;

procedure TWaylandServerDisplay.LockClients;
begin
  EnterCriticalSection(FClientsLock);
end;

procedure TWaylandServerDisplay.UnlockClients;
begin
  LeaveCriticalSection(FClientsLock);
end;

function TWaylandServerDisplay.AddSocket(const AName: String): String;
var
  lDir: String;
  lAddr: sockaddr_un;
begin
  lDir := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if lDir = '' then
    raise EWaylandServer.Create('XDG_RUNTIME_DIR is not set');
  Result := IncludeTrailingPathDelimiter(lDir) + AName;
  if Length(Result) >= SizeOf(lAddr.sun_path) then
    raise EWaylandServer.CreateFmt('socket path too long: %s', [Result]);

  FListenFd := socket(AF_UNIX, SOCK_STREAM, 0);
  if FListenFd < 0 then
    raise EWaylandServer.CreateFmt('socket() failed (errno %d)', [c_errno]);

  // Clear any stale socket file left by a previous crashed run.
  FpUnlink(Result);

  FillChar(lAddr, SizeOf(lAddr), 0);
  lAddr.sun_family := AF_UNIX;
  Move(Result[1], lAddr.sun_path[0], Length(Result));

  if bind(FListenFd, @lAddr, SizeOf(lAddr)) < 0 then
  begin
    FpClose(FListenFd);
    FListenFd := -1;
    raise EWaylandServer.CreateFmt('bind(%s) failed (errno %d)', [Result, c_errno]);
  end;
  if listen(FListenFd, 16) < 0 then
  begin
    FpClose(FListenFd);
    FListenFd := -1;
    FpUnlink(Result);
    raise EWaylandServer.CreateFmt('listen(%s) failed (errno %d)', [Result, c_errno]);
  end;
  FSocketPath := Result;
end;

function TWaylandServerDisplay.AddSocketAuto: String;
var
  n: Integer;
begin
  for n := 0 to 32 do
    try
      Exit(AddSocket('wayland-' + IntToStr(n)));
    except
      on EWaylandServer do
        ; // taken / failed: try the next candidate
    end;
  Result := '';
end;

procedure TWaylandServerDisplay.AcceptClient;
var
  lFd: cint;
  lClient: TWaylandServerClient;
begin
  lFd := accept(FListenFd, nil, nil);
  if lFd < 0 then
    Exit;
  // Construct and fire OnConnect OUTSIDE FClientsLock (the handler may itself
  // enumerate clients under LockClients — holding it here would deadlock).
  lClient := TWaylandServerClient.Create(Self, TUnixSocket.Create(lFd, nil));
  EnterCriticalSection(FClientsLock);
  try
    FClients.Add(lClient);
  finally
    LeaveCriticalSection(FClientsLock);
  end;
  // Auto-bind the root wl_display before OnConnect, so the handler can fetch it
  // (GetObject(WL_DISPLAY_OBJECT_ID)) instead of open-coding id 1.
  if Assigned(FDisplayClass) then
    lClient.BindDisplay(FDisplayClass);
  if Assigned(FOnConnect) then
    FOnConnect(lClient);
end;

procedure TWaylandServerDisplay.DropClient(AClient: TWaylandServerClient);
begin
  // OnDisconnect before removal and outside the lock, for the same reason.
  if Assigned(FOnDisconnect) then
    FOnDisconnect(AClient);
  EnterCriticalSection(FClientsLock);
  try
    FClients.Remove(AClient); // owned list: also frees the client
  finally
    LeaveCriticalSection(FClientsLock);
  end;
end;

procedure TWaylandServerDisplay.Iterate(ATimeoutMs: Integer);
var
  lPoll: array of TPollfd;
  lSnap: array of TWaylandServerClient;
  i, lN: Integer;
begin
  // Snapshot the client set (refs + fds) under the lock, then poll without it so
  // a blocking poll never stalls a worker thread's broadcast. Only this loop
  // thread ever adds/drops clients, so the snapshot stays valid until we return:
  // no entry can be freed between the snapshot and the dispatch/drop pass below.
  EnterCriticalSection(FClientsLock);
  try
    lN := FClients.Count;
    SetLength(lSnap, lN);
    SetLength(lPoll, lN + 1);
    for i := 0 to lN - 1 do
    begin
      lSnap[i] := FClients[i];
      lPoll[i + 1].fd := lSnap[i].Socket.Handle;
      lPoll[i + 1].events := POLLIN;
      lPoll[i + 1].revents := 0;
    end;
  finally
    LeaveCriticalSection(FClientsLock);
  end;
  lPoll[0].fd := FListenFd;
  lPoll[0].events := POLLIN;
  lPoll[0].revents := 0;

  if FpPoll(@lPoll[0], lN + 1, ATimeoutMs) <= 0 then
    Exit;

  for i := 0 to lN - 1 do
    if (lPoll[i + 1].revents and (POLLHUP or POLLERR or POLLNVAL)) <> 0 then
      DropClient(lSnap[i])
    else if (lPoll[i + 1].revents and POLLIN) <> 0 then
      if not lSnap[i].ProcessRequests then
        DropClient(lSnap[i]);

  if (lPoll[0].revents and POLLIN) <> 0 then
    AcceptClient;
end;

procedure TWaylandServerDisplay.Run;
begin
  if FListenFd < 0 then
    raise EWaylandServer.Create('no socket bound; call AddSocket first');
  FQuit := False;
  while not FQuit do
    Iterate(100);
end;

procedure TWaylandServerDisplay.Quit;
begin
  FQuit := True;
end;

end.
