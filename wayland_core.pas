unit Wayland_Core;

{$mode ObjFPC}{$H+}
{$ModeSwitch typehelpers}

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
    FReader: TReadThread;
    //FProxyList: TWaylandProxyObjectList;
    FObjectList: TWaylandObjectList;
    FNextId: Integer;
    FDisplay: TWaylandDisplayBase;


    function NextObjectId: Integer;
    procedure ReadNextMessage;
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
  wayland_errors, wayland_strings, wayland, unix_fd_socket;

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
  lReadCount: Int64;
  lTmpObject: TWaylandBase;
  lTmpOpcode: Word;
  lSent: LongInt;

begin
  lRequest := TWaylandStream.Create;
  lRequest.WriteDWord(AObjectID); // 4 bytes
  lRequest.WriteWord(ARequest); // 2 bytes
  lRequest.WriteWord(0); // Size. will equal the size of the TMemoryStream. Written last

  try
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
        //vtExtended: lRequest.WriteBuffer(TWaylandFixed(Args[i].VExtended).AsBytes[0], 4); // 24bit integer 8 bit decimal
        vtInt64:
          begin
            if Args[i].VInt64^ <= MaxInt then
              lRequest.WriteDWord(Args[i].VInt64^)
            else
              raise EWaylandParamError.CreateFmt(SErrInt64ParamNotSupported, [Args[i].VInt64^]);
          end;
        vtPointer:
          begin
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
      // pad to 32bit boundary
      while lNeedsPadding and ((lRequest.Size mod 4) <> 0) do
      begin
        lRequest.WriteByte(0);
        WriteLn('wrote padding');
      end;
    end;

    if lRequest.Size > $FFFF then
      Raise EWaylandParamError.CreateFmt(SErrSizeTooLarge, [lRequest.Size, $FFFF]);

    lRequest.Position := cSizeOffset;
    lRequest.WriteWord(lRequest.Size);
    lRequest.Position:=0;



    try
      EnterCriticalSection(FCrit);

      lTmpObject := (GetObject(lRequest.ReadDWord)) as TWaylandBase;
      lTmpOpcode := lRequest.ReadWord;

      if Assigned(lTmpObject) then
      begin
        WriteLn('> Requestor ', lTmpObject.ClassName);
        WriteLn('> Opcode [', lTmpOpcode ,'] ', lTmpObject.GetInterfaceAttribute.Request[lTmpOpcode]);
      end
      else
        WriteLn('> Requestor <unknown object ', AObjectID, '> opcode [', lTmpOpcode, ']');
      WriteLn('> Size ', lRequest.ReadWord);

      // file descriptors must be sent with sendmsg and can't be in a regular data packet
      if (lFdStart >= 0)  then
      begin
        lSent := SendFD(FSocket.Handle, lFdStart, lRequest.Memory, lRequest.Size);
        if lSent < 0 then
          // SendFD wraps libc sendmsg; the error is in libc's errno (c_errno),
          // not the FPC RTL errno.
          raise EWaylandConnectionError.CreateFmt(SErrSendFdFailed, [lFdStart, c_errno]);
        lFdStart:=-2;
        Exit;
      end;

      lRequest.Position:=0;
      repeat
        if (lFdStart >= 0)  then
          lReadCount := lFdStart
        else
          lReadCount := lRequest.Size - lRequest.Position ;

        FSocket.CopyFrom(lRequest, lReadCount);
        if (lFdStart >= 0) then
        begin

          //lFdStart := SendFD(FSocket.Handle, lRequest.ReadInteger);
          lFdstart := -2;

         //         lRequest.Seek(-4, soFromCurrent);
          lRequest.WriteByte(00);
          lRequest.WriteByte(00);
        end;

      until lRequest.Position >= lRequest.Size;
      if lFdStart = -2 then
        begin


        end;
    finally

      LeaveCriticalSection(FCrit);
      FreeAndNil(lRequest);
    end;
  except
    // lRequest is freed by the inner finally above before the exception can
    // reach here; FreeAndNil is a safe no-op if it is already nil. Re-raise so
    // request failures (oversized message, unsupported param, etc.) are not
    // silently dropped.
    FreeAndNil(lRequest);
    raise;
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
  FNextId:=2; // 0 invalid 1 always is display. 2 will be the registry
  //FProtocol := TWIProtocolNode.Create('/usr/share/wayland/wayland.xml');
  FObjectList := TWaylandObjectList.Create;
  FObjectList.Sorted:=True;
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

function TWaylandDisplayBase.WaitMessage(ATimeOut: Integer): Boolean;
var
  Header: TWaylandMsgHeader;
  lSize: LongInt;
  lBaseObj: TWaylandBase;
  lStream: TWaylandStream;
  lMessageRec: TWaylandEventMessage;
  lObjectIndex: Integer;
  lQueue: IWaylandEventQueue;
  lReadSize: Word;
begin
  Result := True;
  Fillchar(Header, SizeOf(Header), 0);

  FSocket.IOTimeout:=ATimeOut;
  if FSocket.PeerClosed then
    Raise EConnectionReset.Create('connection reset');

  lSize := FSocket.Read(Header, SizeOF(Header));
  if lSize <= 0 then
  begin
    lSize := c_errno;
    Exit(False);
  end;

  if Header.Size > 8 then
    FSocket.IOTimeout:=0;


  if Header.Obj = 0 then
  begin
    WriteLn('< Object Target = ', Header.Obj);
    WriteLn('< Object Opcode = ', Header.Index);
    WriteLn('< Object Size = ', Header.Index);

    //WriteLn('Got null');
    Raise Exception.Create('Null object not handled...disconnected?');
    // maybe read/seek data and hope for the best
  end;

  if Header.Obj = 1 then
    lBaseObj := Self
  else if FObjectList.Find(Header.Obj, lObjectIndex) then
    lBaseObj := FObjectList.Data[lObjectIndex]
  else
    lBaseObj := nil;
  //WriteLn('Object[',Header.Obj,'] = 0x', HexStr(pointer(lBaseObj)));

  if Assigned(lBaseObj) {and (lProxyObj.Obj is TWInterfaceNode)} then
  begin
    //if not lBaseObj.InheritsFrom(TWlPointer) then
    begin
      WriteLn('< Object Target = [', HEader.Obj, '] ', lBaseObj.ClassName);
      WriteLn('< Object Opcode = [', Header.Index, '] ', lBaseObj.GetInterfaceAttribute.Event[Header.Index]);
      WriteLn('< Object Size = ', Header.Size);
    end;

    ///WriteLn(lBaseObj.ClassName);
    lStream := TWaylandStream.Create;
    lMessageRec.OpCode:=Header.Index;
    lMessageRec.Args := lStream;
    // Read the payload into the stream. If this fails before the message is
    // enqueued we still own the stream and must free it ourselves.
    try
      lReadSize := Header.Size-8;
      // if lReadsize = 0 then CopyFrom will default to $20000 bytes, this causes a hang until it can read that many bytes of messages.
      if lReadSize > 0 then
        lStream.CopyFrom(FSocket, lReadSize);
      lStream.Position:=0;
    except
      lStream.Free;
      raise;
    end;
    // Ownership of lStream now transfers to the queue. The stream is freed by
    // DispatchEvent once the event has been dispatched (which may be deferred
    // if it belongs to a queue other than the display's), so we must NOT free
    // it here.
    lQueue := (lBaseObj as IWaylandBase).GetQueue;
    lQueue.Enqueue(lMessageRec, lBaseObj);
    if lQueue = FEventQueue then // the queue of the display
      Result := lQueue.DispatchEvent;
    lQueue := nil;
  end
  else
  begin
    WriteLn('didn''t find object for message ', Header.Index);
    FSocket.Seek(Header.Size-8, fsFromCurrent);
  end;


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
begin
  FObjectList.Free;
  FSocket.Free;
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
  if FObjectList.Find(AObjectId, lOutIndex) then
  begin
    if AFromDestructor then
      FObjectList.Extract(FObjectList.Items[lOutIndex], @lObject)
    else
      FObjectList.Delete(lOutIndex);
  //  WriteLn('Extracted ', lObject.ClassName);
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
  WriteLn('Created ', ClassName,' id = ', GetObjectId);
end;

constructor TWaylandBase.Create(ADisplay: IWaylandDisplayCore; AQueue: IWaylandEventQueue);
begin
  Create(ADisplay, AQueue, -1);

end;

destructor TWaylandBase.Destroy;
begin
  WriteLn('Destroying ', ClassName , '[',FObjectId,']');
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
  end;
end;


end.

