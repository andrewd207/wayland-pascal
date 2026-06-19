unit Wayland_Core;

{$mode ObjFPC}{$H+}
{$ModeSwitch typehelpers}

{ Define WL_DEBUG (or build with -dWL_DEBUG) for verbose protocol tracing.
  It is off by default so the request/event hot paths carry no logging cost. }
{.$DEFINE WL_DEBUG}

interface

uses
  Classes, SysUtils, wayland_stream, wayland_interfaces, ssockets, fgl,
  wayland_queue, wayland_internal_interfaces, syncobjs, BaseUnix, TypInfo, rtti;


type

  EConnectionReset = class(Exception);

  TWaylandBase = class;

  TWaylandObjectList = specialize TFPGMapObject<Integer, TWaylandBase>;

  // 24bit integer + 8bits decimal

  { TWaylandFixed }

  { TWLIntfAttribute }

  // Usage: [TWLIntfAttribute('<name>(<arg_sig>),<name_n>(<arg_sig)', '<name(<argsig>),...n')]
  //
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

  TWaylandFixed = type Double;

  { TWaylandFixedHelper }

  TWaylandFixedHelper = type helper for TWaylandFixed
    function AsFixed: Integer; // 24/8 bits
    function AsInteger: Integer;
    class function FromFixed(AValue: Integer): TWaylandFixed; static;
  end;

  { TMessageQueue }


  generic TMessageQueue<D, T> = class(TInterfacedObject)
  private
    type
      PNode = ^TNode;
      TNode = record
        Data: TWaylandEventMessage;
        Dest: IWaylandBase;
        Next: PNode;
      end;
  private
    FLock: TRTLCriticalSection;
    FHead, FTail: PNode;
    FEvent: TEvent;
    FCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Enqueue(const Data: T; Dest: D);
    function  Dequeue(var Data: T; var Dest: D; ATimeout: Integer = INFINITE): Boolean;
    property Count: Integer read FCount;
  end;

  { TWaylandMessageQueue }

  TWaylandMessageQueue = class(specialize TMessageQueue<IWaylandBase, TWaylandEventMessage>, IWaylandEventQueue)
  private
    FObjects:  TWaylandObjectList;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AssignObject(AObject: IWaylandBase); // events recieved for this object will come to this queue
    procedure RemoveObject(AObject: IWaylandBase);
    function DispatchEvent(ATimeOut: Integer = 0): Boolean;
    procedure Flush;
  end;


  { TWaylandBase }

  TWaylandBaseClass = class of TWaylandBase;
  TWaylandBase = class(TInterfacedObject, IWaylandBase)
  private
    FConnection: IWaylandDisplayCore;
    FObjectId: Integer;
    FUserData: Pointer;
    FEventQueue: IWaylandEventQueue;
  protected
    FProtocolVersion: Integer;
    property Connection: IWaylandDisplayCore read FConnection;

    procedure SetObjectId(AValue: Integer);
    procedure SetQueue(AQueue: IWaylandEventQueue);
    function GetQueue: IWaylandEventQueue;
    class function GetInterfaceName: String; virtual; abstract;
    class function GetInterfaceVersion: Integer; virtual; abstract;
    procedure SetProtocolVersion(AValue: Integer);
    function _AddRef: longint; cdecl;
    function _Release: longint; cdecl;
    function GetInterfaceAttribute: TWLIntfAttribute;
  public
    constructor Create(ADisplay: IWaylandDisplayCore); virtual;
    constructor Create(ADisplay: IWaylandDisplayCore; AQueue: IWaylandEventQueue); virtual;
    constructor Create(ADisplay: IWaylandDisplayCore; AQueue: IWaylandEventQueue; AObjectID: Integer); virtual;
    destructor Destroy; override;
    class function CreateInstance(AConnection: IWaylandDisplayCore): IWaylandBase; virtual;
    procedure Dispatch(var message); override;
    function GetObjectId: Integer;
    property ObjectID: Integer read GetObjectId write SetObjectId;
    property UserData: Pointer read FUserData write FUserData;
  end;

  { TWaylandDisplayBase }
  // perhaps move GetRegistry here. as virtual? Sync also?
  // GetRegistry should be a singleton...so maybe
  TWaylandDisplayBase = class(TWaylandBase, IWaylandDisplayCore)
  private
  type

    { TReadThread }

    TReadThread = class(TThread)
    private
      FSocket: TUnixSocket;
      FProc: TThreadMethod;
      FInterruptFlag: Boolean;
    public
      constructor Create(Socket: TUnixSocket; Proc: TThreadMethod);
      procedure Execute; override;
    end;
  protected
    //FProtocol: TWIProtocolNode;
    FCrit: TRTLCriticalSection;
    FObjectListLock: TRTLCriticalSection;
    FQuit: Boolean;
    FSocket: TUnixSocket;
    FRequestStream: TWaylandStream; // pooled outgoing buffer, guarded by FCrit
    FReader: TReadThread;
    //FProxyList: TWaylandProxyObjectList;
    FObjectList: TWaylandObjectList;
    FNextId: Integer;
    FDisplay: TWaylandDisplayBase;
    // Self-pipe used to interrupt a blocked MessagesPending/WaitEvent from
    // another thread (see Wakeup). Read end is polled alongside the socket; the
    // write end is signalled by Wakeup. -1 until the pipe is created.
    FWakeupRead: cint;
    FWakeupWrite: cint;

    // Receive buffer: bytes pulled off the socket via recvmsg but not yet parsed
    // into messages. FRecvHead is the parse cursor, FRecvTail the end of valid
    // data; the [Head..Tail) window is compacted to the front on each refill.
    FRecvBuf: TBytes;
    FRecvHead: Integer;
    FRecvTail: Integer;
    // FIFO of file descriptors harvested (out-of-band, SCM_RIGHTS) by recvmsg,
    // in arrival order. Drained as each event's 'h' args are parsed in
    // WaitMessage. Head..Tail window; reset to 0 when emptied.
    FRecvFds: array of cint;
    FRecvFdHead: Integer;
    FRecvFdTail: Integer;

    function NextObjectId: Integer;
    procedure ReadNextMessage;
    procedure CreateWakeupPipe;
    // recvmsg one chunk into FRecvBuf, harvesting any fds into FRecvFds. True if
    // bytes were read, False on timeout (EAGAIN); raises EConnectionReset on a
    // closed/broken connection. Honors the socket's current IOTimeout.
    function FillRecvBuffer: Boolean;
    // Block (subject to IOTimeout) until at least ACount unparsed bytes are
    // buffered. False if a refill timed out before reaching ACount.
    function EnsureUnread(ACount: Integer): Boolean;
    // Copy ACount already-buffered bytes out of FRecvBuf, advancing the cursor.
    procedure ReadRecv(out Buf; ACount: Integer);
    procedure PushRecvFd(AFd: cint);
    function PopRecvFd: cint; // -1 if the FIFO is empty
    // Count the 'h' (fd) args in an event signature like 'keymap(uhu)'.
    function CountEventFds(const ASignature: String): Integer;
  protected
    class function FindSocketName: String;
    procedure RegisterObject(AObject: IWaylandBase; AUseID: Integer = -1);
    procedure ObjectDestroying(AObjectID: Integer; AFromDestructor: Boolean);
    procedure SendRequest(AObjectID: DWord; ARequest: Word; Args: Array of Const; AFdIndex: Integer = -1);
    function GetObject(AObjectID: DWord): IWaylandBase;
  public
    class function TryCreateConnection(var aWLDisplay): Boolean;
    constructor Create(ASocket: TUnixSocket); reintroduce;
    procedure Run;
    procedure Quit;
    function WaitMessage(ATimeOut: Integer): Boolean;
    // Non-consuming readiness check: True if at least one byte is waiting on the
    // connection socket within ATimeoutMs (0 = poll and return immediately). Lets
    // a caller integrate with its own event loop ("are there messages?" / "wait up
    // to N ms for one") without us exposing the raw fd. Does not read or dispatch;
    // follow a True result with WaitMessage to actually consume the message.
    // A pending Wakeup also makes this return early, but returns False (a wakeup
    // is not a protocol message) after draining the wakeup signal.
    function MessagesPending(ATimeoutMs: Integer = 0): Boolean;
    // Thread-safe: interrupt a MessagesPending/WaitEvent that is currently
    // blocked (or about to block) so the caller's loop iterates promptly — e.g.
    // after another thread posts work or requests a redraw. Safe to call from any
    // thread; coalesces (many Wakeups before the next poll cost one wake).
    procedure Wakeup;
    procedure SyncAndWait;
    destructor Destroy; override;
  end;

  { TBitfield }

  TBitfield = object
  protected
    function GetValue(AIndex: Integer): Boolean; // aindex is the actual integer value so index 4 = b100 = 1 shl 2
    procedure SetValue(AIndex: Integer; AValue: Boolean);
  public
    Value: DWord;
  end;

  operator := (A: TBitfield): DWord;
  operator := (A: DWord): TBitfield;

  // Returns the wayland object id for AObject, or 0 (the protocol's null object
  // id) when AObject is nil. Used for nullable (allow-null) object request args
  // so a nil argument is sent as a null id instead of crashing.
  function WlObjectId(AObject: TObject): Integer;



implementation
uses
  wayland_errors, wayland_strings, wayland, unix_fd_socket, ctypes;

const
  // Amount of socket data pulled per recvmsg into the receive buffer. Wayland's
  // max message is 64KiB; a smaller chunk just means more (cheap) recvmsg calls.
  RECV_CHUNK = 4096;

type
  TWaylandMsgHeader = record
    Obj: DWord;
    Index: Word;
    Size: Word;
  end;

operator:=(A: TBitfield): DWord;
begin
  Result := A.Value;
end;

operator:=(A: DWord): TBitfield;
begin
  Result.Value:=A;
end;

function WlObjectId(AObject: TObject): Integer;
begin
  if AObject = nil then
    Result := 0
  else
    Result := (AObject as IWaylandBase).GetObjectId;
end;

{ TWaylandDisplayBase }


procedure TWaylandDisplayBase.ReadNextMessage;
begin
  WaitMessage(0);
end;

procedure TWaylandDisplayBase.SendRequest(AObjectID: DWord; ARequest: Word; Args: array of const; AFdIndex: Integer);
const
  cSizeOffset = 6;
var
  lRequest: TWaylandStream;
  lNeedsPadding: Boolean;
  i: Integer;
  lFdStart: Int64 = -1;
  lMsgLen: Int64;
  lSent: LongInt;
  {$IFDEF WL_DEBUG}
  lObj: TWaylandBase;
  {$ENDIF}
begin
  // Serialize the whole build+send under FCrit: FRequestStream is a pooled
  // per-connection buffer (no per-request heap alloc / buffer regrow), and
  // concurrent writers would corrupt the socket byte stream anyway.
  EnterCriticalSection(FCrit);
  try
    lRequest := FRequestStream;
    lRequest.Position := 0; // reuse buffer; capacity is retained (never shrunk)
    lRequest.WriteDWord(AObjectID); // 4 bytes
    lRequest.WriteWord(ARequest);   // 2 bytes
    lRequest.WriteWord(0);          // size placeholder; backpatched below

    for i := Low(Args) to High(Args) do
    begin
      if (AFdIndex <> -1) and (AFdIndex = i) then
      begin
        lFdStart:=Args[i].VInteger;
        continue;
      end;
      lNeedsPadding := False;
      case Args[i].VType of
        vtBoolean: lRequest.WriteDWord(Ord(Args[i].VBoolean));
        vtInteger: lRequest.WriteDWord(Ord(Args[i].VInteger));
        vtInt64:
          begin
            if Args[i].VInt64^ <= MaxInt then
              lRequest.WriteDWord(Args[i].VInt64^)
            else
              raise EWaylandParamError.CreateFmt(SErrInt64ParamNotSupported, [Args[i].VInt64^]);
          end;
        vtPointer:
          begin
            // wl_array: length-prefixed byte blob. The generator passes the
            // array as the pair (Length(x), Pointer(x)), so the count is in the
            // preceding VInteger. Write the uint32 size header, then the bytes.
            lRequest.WriteDWord(DWord(Args[i-1].VInteger));
            if Args[i-1].VInteger > 0 then
              lRequest.Write(Args[i].VPointer^, Args[i-1].VInteger);
            lNeedsPadding := True;
          end;
        vtAnsiString:
          begin
            lRequest.WriteString(AnsiString(Args[i].VAnsiString));
          end;
        vtInterface:
          begin
            if IUnknown(Args[i].VInterface) is IWaylandBase then
             lRequest.WriteDWord((IUnknown(Args[i].VInterface) as IWaylandBase).GetObjectId)
            else
              Raise EWaylandParamError.CreateFmt(SErrUnsupportedObjectForParam, [SErrInvalidInterface, i]);
          end;
        vtObject:
          begin
            if Args[i].VObject.InheritsFrom(TStream) then
            begin
              lRequest.WriteDWord(TStream(Args[i].VObject).Size);
              TStream(Args[i].VObject).Position:=0;
              lRequest.CopyFrom(TStream(Args[i].VObject), TStream(Args[i].VObject).Size);
              lNeedsPadding:=True;
            end
            else if Args[i].VObject is IWaylandBase then
              lRequest.WriteDWord((Args[i].VObject as IWaylandBase).GetObjectId)
            else
              Raise EWaylandParamError.CreateFmt(SErrUnsupportedObjectForParam, [Args[i].VObject.ClassName, i]);
          end;
      end;
      // pad to 32bit boundary (use Position, not Size: the pooled buffer may be
      // larger than this message from a previous, longer request)
      while lNeedsPadding and ((lRequest.Position mod 4) <> 0) do
        lRequest.WriteByte(0);
    end;

    // Exact message length. The buffer's Size may exceed it (stale tail from a
    // previous request); only the first lMsgLen bytes are this message.
    lMsgLen := lRequest.Position;
    if lMsgLen > $FFFF then
      Raise EWaylandParamError.CreateFmt(SErrSizeTooLarge, [lMsgLen, $FFFF]);

    // backpatch the size field, then rewind for sending
    lRequest.Position := cSizeOffset;
    lRequest.WriteWord(lMsgLen);
    lRequest.Position := 0;

    {$IFDEF WL_DEBUG}
    lObj := GetObject(AObjectID) as TWaylandBase;
    if Assigned(lObj) then
      WriteLn('> ', lObj.ClassName, '.', lObj.GetInterfaceAttribute.Request[ARequest],
              ' size=', lMsgLen)
    else
      WriteLn('> <unknown object ', AObjectID, '> opcode [', ARequest, '] size=', lMsgLen);
    {$ENDIF}

    // file descriptors must be sent with sendmsg out-of-band, not inline
    if lFdStart >= 0 then
    begin
      lSent := SendFD(FSocket.Handle, lFdStart, lRequest.Memory, lMsgLen);
      if lSent < 0 then
        // SendFD wraps libc sendmsg; the error is in libc's errno (c_errno),
        // not the FPC RTL errno.
        raise EWaylandConnectionError.CreateFmt(SErrSendFdFailed, [lFdStart, c_errno]);
    end
    else
      FSocket.CopyFrom(lRequest, lMsgLen); // Position is 0
  finally
    LeaveCriticalSection(FCrit);
  end;
end;

function TWaylandDisplayBase.GetObject(AObjectID: DWord): IWaylandBase;
var
  lIndex: Integer;
begin
  if AObjectID = 1 then
  begin
    Result := Self as IWaylandBase;
    Exit;
  end;
  EnterCriticalSection(FObjectListLock);
  try
    Result := nil;
    lIndex := FObjectList.IndexOf(AObjectID);
    if lIndex <> -1 then
      Result := FObjectList.Data[lIndex] as IWaylandBase;

  finally
    LeaveCriticalSection(FObjectListLock);
  end;
end;

class function TWaylandDisplayBase.TryCreateConnection(var aWLDisplay): Boolean;
var
  lName: String;
  lFd: Longint;
  lSocket: TUnixSocket;
begin
  Result := False;
  lName := FindSocketName;
  if Length(lName) = 0 then
    raise EWaylandConnectionError.Create(SErrWaylandNotFound);

  if TryStrToInt(lName, lFd) then
    lSocket := TUnixSocket.Create(lFd, nil)
  else
    lSocket := TUnixSocket.Create(lName);

  TWlDisplay(aWLDisplay) := TWlDisplay.Create(lSocket);
  Result := True;
end;

constructor TWaylandDisplayBase.Create(ASocket: TUnixSocket);
begin
  InitCriticalSection(FCrit);
  InitCriticalSection(FObjectListLock);
  Inherited Create(Self as IWaylandDisplayCore, TWaylandMessageQueue.Create, 1);
  FSocket := ASocket;
  FRequestStream := TWaylandStream.Create; // pooled across all SendRequest calls
  FNextId:=2; // 0 invalid 1 always is display. 2 will be the registry
  //FProtocol := TWIProtocolNode.Create('/usr/share/wayland/wayland.xml');
  FObjectList := TWaylandObjectList.Create;
  FObjectList.Sorted:=True;
  CreateWakeupPipe;
end;

procedure TWaylandDisplayBase.CreateWakeupPipe;
var
  lPipe: TFilDes; // [0]=read end, [1]=write end
begin
  FWakeupRead := -1;
  FWakeupWrite := -1;
  if FpPipe(lPipe) <> 0 then
    Exit; // wakeup unavailable; polls simply won't be interruptible
  FWakeupRead := lPipe[0];
  FWakeupWrite := lPipe[1];
  // Non-blocking both ends: Wakeup must never block a worker thread, and the
  // reader drains opportunistically without stalling the event loop.
  FpFcntl(FWakeupRead, F_SETFL, FpFcntl(FWakeupRead, F_GETFL) or O_NONBLOCK);
  FpFcntl(FWakeupWrite, F_SETFL, FpFcntl(FWakeupWrite, F_GETFL) or O_NONBLOCK);
end;

procedure TWaylandDisplayBase.Run;
begin
  while not FQuit do
   WaitMessage(100);
end;

procedure TWaylandDisplayBase.Quit;
begin
  FQuit := True;
end;

function TWaylandDisplayBase.FillRecvBuffer: Boolean;
var
  lFds: array[0..WL_MAX_FDS_PER_RECV - 1] of cint;
  lFdCount, i, lLeft, lErr: Integer;
  lRead: ssize_t;
begin
  // Compact the consumed prefix to the front so the buffer does not grow without
  // bound across reads.
  if FRecvHead > 0 then
  begin
    lLeft := FRecvTail - FRecvHead;
    if lLeft > 0 then
      Move(FRecvBuf[FRecvHead], FRecvBuf[0], lLeft);
    FRecvTail := lLeft;
    FRecvHead := 0;
  end;
  // Guarantee room for one more chunk.
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
      raise EConnectionReset.Create('connection reset')
    else
    begin
      lErr := c_errno;
      if lErr = ESysEINTR then
        Continue; // interrupted before any data; just retry
      if (lErr = ESysEAGAIN) or (lErr = ESysEWOULDBLOCK) then
        Exit(False); // SO_RCVTIMEO elapsed: no data within the timeout
      raise EConnectionReset.CreateFmt('recvmsg failed (errno %d)', [lErr]);
    end;
  end;
end;

function TWaylandDisplayBase.EnsureUnread(ACount: Integer): Boolean;
begin
  while (FRecvTail - FRecvHead) < ACount do
    if not FillRecvBuffer then
      Exit(False);
  Result := True;
end;

procedure TWaylandDisplayBase.ReadRecv(out Buf; ACount: Integer);
begin
  Move(FRecvBuf[FRecvHead], Buf, ACount);
  Inc(FRecvHead, ACount);
end;

procedure TWaylandDisplayBase.PushRecvFd(AFd: cint);
begin
  if FRecvFdTail >= Length(FRecvFds) then
    SetLength(FRecvFds, FRecvFdTail + 8);
  FRecvFds[FRecvFdTail] := AFd;
  Inc(FRecvFdTail);
end;

function TWaylandDisplayBase.PopRecvFd: cint;
begin
  if FRecvFdHead >= FRecvFdTail then
    Exit(-1);
  Result := FRecvFds[FRecvFdHead];
  Inc(FRecvFdHead);
  if FRecvFdHead = FRecvFdTail then // emptied: reset to reuse from the front
  begin
    FRecvFdHead := 0;
    FRecvFdTail := 0;
  end;
end;

function TWaylandDisplayBase.CountEventFds(const ASignature: String): Integer;
var
  i: Integer;
  lInArgs: Boolean;
begin
  // Signature looks like 'keymap(uhu)'; count 'h' (fd) args between the parens.
  Result := 0;
  lInArgs := False;
  for i := 1 to Length(ASignature) do
    case ASignature[i] of
      '(': lInArgs := True;
      ')': Break;
      'h': if lInArgs then Inc(Result);
    end;
end;

function TWaylandDisplayBase.WaitMessage(ATimeOut: Integer): Boolean;
var
  Header: TWaylandMsgHeader;
  lBaseObj: TWaylandBase;
  lStream: TWaylandStream;
  lMessageRec: TWaylandEventMessage;
  lObjectIndex: Integer;
  lQueue: IWaylandEventQueue;
  lReadSize: Word;
  lFdCount, i: Integer;
begin
  Result := True;
  Fillchar(Header, SizeOf(Header), 0);

  FSocket.IOTimeout:=ATimeOut;
  if FSocket.PeerClosed then
    Raise EConnectionReset.Create('connection reset');

  // Wait (up to ATimeOut) for a full 8-byte header. A partial read stays buffered
  // for the next call, so a timeout here never loses bytes.
  if not EnsureUnread(SizeOf(Header)) then
    Exit(False);
  ReadRecv(Header, SizeOf(Header));

  if Header.Obj = 0 then
    // maybe read/seek data and hope for the best
    Raise Exception.Create('Null object not handled...disconnected?');

  // We are committed to this message: block (IOTimeout 0) for the rest of the
  // body, including any out-of-band fds, which arrive on the same recvmsg.
  lReadSize := Header.Size - 8;
  if lReadSize > 0 then
  begin
    FSocket.IOTimeout := 0;
    EnsureUnread(lReadSize);
  end;

  if Header.Obj = 1 then
    lBaseObj := Self
  else
  begin
    // Look the target proxy up under the object-list lock so this is consistent
    // with RegisterObject/ObjectDestroying running on another thread. The lock is
    // released before dispatch, so a listener that creates/destroys objects (and
    // re-enters the list) cannot deadlock on this non-recursive mutex.
    EnterCriticalSection(FObjectListLock);
    try
      if FObjectList.Find(Header.Obj, lObjectIndex) then
        lBaseObj := FObjectList.Data[lObjectIndex]
      else
        lBaseObj := nil;
    finally
      LeaveCriticalSection(FObjectListLock);
    end;
  end;
  //WriteLn('Object[',Header.Obj,'] = 0x', HexStr(pointer(lBaseObj)));

  if Assigned(lBaseObj) {and (lProxyObj.Obj is TWInterfaceNode)} then
  begin
    {$IFDEF WL_DEBUG}
    WriteLn('< ', lBaseObj.ClassName, '.', lBaseObj.GetInterfaceAttribute.Event[Header.Index],
            ' [obj ', Header.Obj, '] size=', Header.Size);
    {$ENDIF}
    lStream := TWaylandStream.Create;
    lMessageRec.OpCode:=Header.Index;
    lMessageRec.Args := lStream;
    // Copy the payload out of the receive buffer into the message stream. If this
    // fails before the message is enqueued we still own the stream and must free
    // it ourselves.
    try
      if lReadSize > 0 then
      begin
        lStream.WriteBuffer(FRecvBuf[FRecvHead], lReadSize);
        Inc(FRecvHead, lReadSize);
        lStream.Position:=0;
      end;
    except
      lStream.Free;
      raise;
    end;
    // Attach this event's out-of-band fds (popped from the connection FIFO in
    // arrival order = signature order) so they travel with the message and stay
    // correctly paired even if dispatch is deferred to another queue.
    lFdCount := CountEventFds(lBaseObj.GetInterfaceAttribute.Event[Header.Index]);
    if lFdCount > 0 then
    begin
      SetLength(lMessageRec.Fds, lFdCount);
      for i := 0 to lFdCount - 1 do
        lMessageRec.Fds[i] := PopRecvFd;
    end;
    // Ownership of lStream now transfers to the queue. The stream is freed (and
    // any unconsumed fds closed) by DispatchEvent once the event has been
    // dispatched (which may be deferred if it belongs to a queue other than the
    // display's), so we must NOT free it here.
    lQueue := (lBaseObj as IWaylandBase).GetQueue;
    lQueue.Enqueue(lMessageRec, lBaseObj);
    if lQueue = FEventQueue then // the queue of the display
      Result := lQueue.DispatchEvent;
    lQueue := nil;
  end
  else
  begin
    {$IFDEF WL_DEBUG}
    WriteLn('didn''t find object for message ', Header.Index);
    {$ENDIF}
    // Discard the body; the cursor was already advanced past the header.
    Inc(FRecvHead, lReadSize);
  end;


end;

function TWaylandDisplayBase.MessagesPending(ATimeoutMs: Integer = 0): Boolean;
var
  lPoll: array[0..1] of TPollfd;
  lCount: Integer;
  lDrain: array[0..63] of Byte;
begin
  lPoll[0].fd := FSocket.Handle;
  lPoll[0].events := POLLIN;
  lPoll[0].revents := 0;
  lCount := 1;
  if FWakeupRead >= 0 then
  begin
    lPoll[1].fd := FWakeupRead;
    lPoll[1].events := POLLIN;
    lPoll[1].revents := 0;
    lCount := 2;
  end;

  if FpPoll(@lPoll[0], lCount, ATimeoutMs) <= 0 then
    Exit(False); // timed out / interrupted: nothing ready

  // A wakeup only serves to return early; drain every queued byte so it does not
  // re-trigger the poll on the next pass, and report it as "no message".
  if (lCount = 2) and ((lPoll[1].revents and POLLIN) <> 0) then
    while FpRead(FWakeupRead, lDrain, SizeOf(lDrain)) > 0 do
      ; // keep reading until EAGAIN

  Result := (lPoll[0].revents and POLLIN) <> 0;
end;

procedure TWaylandDisplayBase.Wakeup;
var
  lByte: Byte;
begin
  if FWakeupWrite < 0 then
    Exit;
  lByte := 1;
  // Non-blocking write; if the pipe is already full a wakeup is pending anyway,
  // so an EAGAIN is harmless (coalesced). Atomic for a single byte across threads.
  FpWrite(FWakeupWrite, lByte, 1);
end;

procedure TWaylandDisplayBase.SyncAndWait;
var
  lCallback: TWlCallback;
begin
  lCallback := (Self as TWlDisplay).Sync();
  while not lCallback.IsDone do
    WaitMessage(100);
  lCallback.Free;
end;

destructor TWaylandDisplayBase.Destroy;
var
  lFd: cint;
begin
  if FWakeupRead >= 0 then FpClose(FWakeupRead);
  if FWakeupWrite >= 0 then FpClose(FWakeupWrite);
  // Close any received-but-unconsumed fds so they don't leak on shutdown.
  repeat
    lFd := PopRecvFd;
    if lFd >= 0 then FpClose(lFd);
  until lFd < 0;
  FObjectList.Free;
  FSocket.Free;
  FRequestStream.Free;
  FEventQueue := nil;
  DoneCriticalSection(FCrit);
  DoneCriticalSection(FObjectListLock);
  inherited Destroy;
end;

{ TWaylandDisplayBase.TReadThread }

constructor TWaylandDisplayBase.TReadThread.Create(Socket: TUnixSocket;
  Proc: TThreadMethod);
begin
  FSocket := Socket;
  FProc := Proc;
  inherited Create(False);
end;

procedure TWaylandDisplayBase.TReadThread.Execute;
var
  ReadSet: TFDSet;
  TimeVal: TTimeVal;
begin
  while not Terminated do
  begin
    fpFD_ZERO(ReadSet);
    fpFD_SET(FSocket.Handle, ReadSet);
    TimeVal.tv_sec := 1;
    TimeVal.tv_usec := 0;
    if fpSelect(FSocket.Handle + 1, @ReadSet, nil, nil, @TimeVal) > 0 then
    begin
      if fpFD_ISSET(FSocket.Handle, ReadSet) <> 0 then
      begin
        if Assigned(FProc) then
          FProc();
      end;
    end;
  end;
end;

{ TBitfield }

function TBitfield.GetValue(AIndex: Integer): Boolean;
begin
  Result := AIndex and Value <> 0;
end;

procedure TBitfield.SetValue(AIndex: Integer; AValue: Boolean);
begin
  if AValue then Value:=Value or AIndex
  else Value := Value and not DWord(AIndex);

end;

{ TWaylandDisplayBase }

function TWaylandDisplayBase.NextObjectId: Integer;
begin
  Result := FNextId;
  Inc(FNextId);

  if REsult > $feffffff then
  begin
    raise exception.Create('TODO look for released used id''s');
  end;
end;

class function TWaylandDisplayBase.FindSocketName: String;
var
  lSocketFd, lXDG: UnicodeString;
begin
  lSocketFd := GetEnvironmentVariable('WAYLAND_SOCKET');
  if lSocketFD <> '' then
    Exit(lSocketFd);

  lXDG := GetEnvironmentVariable('XDG_RUNTIME_DIR');
  if lXDG <> '' then
  begin
    lXDG := IncludeTrailingPathDelimiter(lXDG);
    lSocketFd:=GetEnvironmentVariable('WAYLAND_DISPLAY');
    if lSocketFd = '' then
      lSocketFd:='wayland-0';
    Exit(lXDG+lSocketFd)
  end;
  Result := '';
end;

procedure TWaylandDisplayBase.RegisterObject(AObject: IWaylandBase;
  AUseID: Integer);
var
  lObjectID: Integer;
begin
  if AObject as TObject = Self then
    FObjectId:=1
  else
    begin
      EnterCriticalSection(FObjectListLock);
      try
        lObjectID := AUseID; // if AUseId <> -1 the the object id is from the server.  0xff000000, 0xffffffff]
        if lObjectID = -1 then
         lObjectID := NextObjectId;

        AObject.SetObjectId(lObjectID);
        FObjectList.Add(AObject.GetObjectId, AObject as TWaylandBase);
      finally
        LeaveCriticalSection(FObjectListLock);
      end;
    end;
end;

procedure TWaylandDisplayBase.ObjectDestroying(AObjectID: Integer;
  AFromDestructor: Boolean);
var
  lOutIndex: Integer;
  lObject: TObject = nil;
begin
  // possibly notify we are destroying it to the server?
  // Guard the list mutation with the same lock as RegisterObject/GetObject and
  // the WaitMessage dispatch lookup, so removal is race-free across threads.
  EnterCriticalSection(FObjectListLock);
  try
    if FObjectList.Find(AObjectId, lOutIndex) then
    begin
      if AFromDestructor then
        FObjectList.Extract(FObjectList.Items[lOutIndex], @lObject)
      else
        FObjectList.Delete(lOutIndex);
    //  WriteLn('Extracted ', lObject.ClassName);
    end;
  finally
    LeaveCriticalSection(FObjectListLock);
  end;
end;

{ TWaylandBase }

function TWaylandBase.GetObjectId: Integer;
begin
  Result := FObjectId;
end;

procedure TWaylandBase.SetObjectId(AValue: Integer);
begin
  FObjectId:=AValue;
end;

procedure TWaylandBase.SetQueue(AQueue: IWaylandEventQueue);
begin
  if FEventQueue = AQueue then
    Exit;

  FEventQueue := AQueue;
  if Assigned(FEventQueue) then
    FEventQueue.AssignObject(Self);
end;

function TWaylandBase.GetQueue: IWaylandEventQueue;
begin
  Result := FEventQueue as IWaylandEventQueue;
end;

procedure TWaylandBase.SetProtocolVersion(AValue: Integer);
begin
  FprotocolVersion := AValue;
end;

function TWaylandBase._AddRef: longint; cdecl;
begin
  Result := 1;
end;

function TWaylandBase._Release: longint; cdecl;
begin
  Result := 1;
end;

function TWaylandBase.GetInterfaceAttribute: TWLIntfAttribute;
var
  lTypeInf: PTypeInfo;
  lTypeData: PTypeData;
  lAttrTable: PAttributeTable;
  lAttrCount, I: Integer;
  lAttr: TCustomAttribute;
begin
  Result := nil;
  lTypeInf := Self.ClassInfo;
  lTypeData := GetTypeData(lTypeInf);
  lAttrTable := GetAttributeTable(lTypeInf);

  if Assigned(lAttrTable) then
  begin
    lAttrCount := lAttrTable^.AttributeCount;

    for I := 0 to lAttrCount - 1 do
    begin
      lAttr := GetAttribute(lAttrTable, I);
      if lAttr is TWLIntfAttribute then
        Result := TWLIntfAttribute(lAttr);
    end;
  end
  else
    Result := nil;
end;

constructor TWaylandBase.Create(ADisplay: IWaylandDisplayCore);
begin
  Create(ADisplay, nil);
end;

constructor TWaylandBase.Create(ADisplay: IWaylandDisplayCore;
  AQueue: IWaylandEventQueue; AObjectID: Integer);
begin

  if Assigned(AQueue) then
    FEventQueue := AQueue
  else
    FEventQueue := ADisplay.GetQueue;

  FConnection := ADisplay;
  FConnection.RegisterObject(Self, AObjectID);
  {$IFDEF WL_DEBUG}
  WriteLn('Created ', ClassName,' id = ', GetObjectId);
  {$ENDIF}
end;

constructor TWaylandBase.Create(ADisplay: IWaylandDisplayCore; AQueue: IWaylandEventQueue);
begin
  Create(ADisplay, AQueue, -1);

end;

destructor TWaylandBase.Destroy;
begin
  {$IFDEF WL_DEBUG}
  WriteLn('Destroying ', ClassName , '[',FObjectId,']');
  {$ENDIF}
  Connection.ObjectDestroying(Self.GetObjectId, True);
  inherited Destroy;
end;

class function TWaylandBase.CreateInstance(AConnection: IWaylandDisplayCore
  ): IWaylandBase;
begin
  Result := nil;
end;

procedure TWaylandBase.Dispatch(var message);
begin
  inherited Dispatch(message);
  with TWaylandEventMessage(message) do
  if not Handled then
    Raise Exception.CreateFmt('%s Unhandled Message %d', [Classname, OPcode]);
end;

{ TWLIntfAttribute }

function TWLIntfAttribute.GetRequest(AIndex: Integer): String;
begin
  Result := Format('invalid_request_opcode:%d(?)', [AIndex]);
  if Self = nil then
    Exit;
  if (AIndex >=0) and (AIndex <= High(FRequests)) then
    Result := Trim(FRequests[AIndex]);
end;

function TWLIntfAttribute.GetEvent(AIndex: Integer): String;
begin
  Result := Format('invalid_event_opcode:%d(?)', [AIndex]);
  if Self = nil then
    Exit;
  if (AIndex >=0) and (AIndex <= High(FEvents)) then
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

{ TWaylandFixed }

function TWaylandFixedHelper.AsFixed: Integer;
var
  lInt: Integer;
  lDec: Integer;
begin
  lInt := Trunc(Self);
  if (lInt > $7FFFFF) then
    lInt := $7FFFFF
  else if lInt < -$800000 then
    lInt := -$800000;

  lDec := Round(Frac(Abs(Self)) * $100);
  if lDec = $100 then
    lDec := $FF;

  lInt := (lInt shl 8) or lDec;
  Result := lInt;
end;

function TWaylandFixedHelper.AsInteger: Integer;
begin
  Result := Trunc(Self);
end;

class function TWaylandFixedHelper.FromFixed(AValue: Integer): TWaylandFixed;
begin
  Result := ((AValue shr 8) and $FFFFFF) + (AValue and $ff) / $100;
end;


constructor TMessageQueue.Create;
begin
  InitCriticalSection(FLock);
  FHead := nil;
  FTail := nil;
  FEvent := TEvent.Create(nil, False, False, '');
end;

destructor TMessageQueue.Destroy;
begin
  while FHead <> nil do
  begin
    FTail := FHead^.Next;
    Dispose(FHead);
    FHead := FTail;
  end;
  DoneCriticalSection(FLock);
  FEvent.Free;
  inherited;
end;

procedure TWaylandMessageQueue.Flush;
var
  lSanity: Integer;
begin
  lSanity := 10000;
  while DispatchEvent and (lSanity > 0 )do
    Dec(lSanity);
end;

constructor TWaylandMessageQueue.Create;
begin
  inherited Create;
  FObjects := TWaylandObjectList.Create;
end;

destructor TWaylandMessageQueue.Destroy;
begin
  FObjects.Free;
  inherited Destroy;
end;

procedure TWaylandMessageQueue.AssignObject(AObject: IWaylandBase);
var
  lId: Integer;
begin
  lId := AObject.GetObjectId;

  // this is called from a locked context - threadsafe

  if FObjects.IndexOf(lId) = -1 then
  begin
    FObjects.Add(lId, AObject As TWaylandBase);
    AObject.SetQueue(Self);
  end;
end;

procedure TWaylandMessageQueue.RemoveObject(AObject: IWaylandBase);
var
  lIndex: Integer;
begin
  lIndex := FObjects.IndexOf(AObject.GetObjectId);
  if lIndex <> -1 then
    FObjects.Delete(lIndex);
end;

procedure TMessageQueue.Enqueue(const Data: T; Dest: D);
var
  NewNode: ^TNode;
begin
  New(NewNode);
  NewNode^.Data := Data;
  NewNode^.Dest := Dest;
  NewNode^.Next := nil;
  EnterCriticalSection(FLock);
  if FCount = 0 then
    FEvent.SetEvent;
  Inc(FCount);
  try
    if FTail <> nil then
      FTail^.Next := NewNode
    else
      FHead := NewNode;
    FTail := NewNode;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

function TMessageQueue.Dequeue(var Data: T; var Dest: D; ATimeout: Integer): Boolean;
var
  Temp: PNode;
begin
  if (FCount > 0) or (FEvent.WaitFor(ATimeout) = wrSignaled) then
  begin
    EnterCriticalSection(FLock);
    try
      if FCount = 0 then
        Exit(False);
      Result := FHead <> nil;
      if Result then
      begin
        Dec(FCount);
        Data := FHead^.Data;
        Dest := FHead^.Dest;
        Temp := FHead;
        FHead := FHead^.Next;
        if FHead = nil then
        begin
          FTail := nil;
          FEvent.ResetEvent;
        end;
        Dispose(Temp);
      end;
    finally
      LeaveCriticalSection(FLock);
    end;
  end
  else
    Result := False;
end;

function TWaylandMessageQueue.DispatchEvent(ATimeOut: Integer): Boolean;
var
  lData: TWaylandEventMessage;
  lDest: IWaylandBase;
begin
  Result := Dequeue(lData, lDest, ATimeOut);
  if Result then
  try
    (lDest as TObject).Dispatch(lData);
  finally
    // The stream was created by WaitMessage and ownership was transferred to
    // the queue on enqueue; free it now that the event has been dispatched.
    lData.Args.Free;
    // Close any fds the handler did not take ownership of (via NextFd).
    lData.CloseUnusedFds;
  end;
end;


end.

