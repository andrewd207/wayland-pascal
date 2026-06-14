unit wayland_wire;



{





this is old. don't use this






}
























{$mode ObjFPC}{$H+}
{$ModeSwitch typehelpers on}

interface

uses
  Classes, SysUtils, ssockets, wayland_interface_reader, fgl, wayland_interfaces, wayland_core;


type


  { TWaylandConnection }

  TWaylandConnection = class(TWaylandBase, IWaylandDisplayCore)
  protected
    FProtocol: TWIProtocolNode;
    FSocket: TUnixSocket;
    //FProxyList: TWaylandProxyObjectList;
    FObjectList: TWaylandObjectList;
    FIdIndex: Integer;
    FDisplay: IWaylandDisplay;
    function NextObjectId: Integer;
  protected
    class function FindSocketName: String;
    //function CreateProxy(AConstructor : TWaylandConstructor; AObjectID: Integer; AObject: IWaylandBase): IWaylandProxy; // the connection saves this in a queue of expected events.
    procedure RegisterObject(AObject: IWaylandBase);
  public
    class function CreateConnection: TWaylandConnection;
  public
    constructor Create(ASocket: TUnixSocket);
    procedure SendRequest(AObjectID: DWord; ARequest: Word; Args: Array of Const);
    procedure ObjectDestroying(AObjectID: Integer);

    procedure Run;
    function WaitMessage(ATimeOut: Integer): Boolean;
    destructor Destroy; override;
    function GetDisplay: IWaylandDisplay;
  end;

implementation
uses
  wayland_strings, wayland_stream, wayland_errors;


{ TWaylandConnection }

class function TWaylandConnection.FindSocketName: String;
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

procedure TWaylandConnection.RegisterObject(AObject: IWaylandBase);
begin
  if AObject as TObject = Self then
    Exit;
  AObject.SetObjectId(NextObjectId);
  FObjectList.Add(AObject.GetObjectId, AObject);
end;

constructor TWaylandConnection.Create(ASocket: TUnixSocket);
begin
  Inherited Create(Self as IWaylandDisplay);
  FSocket := ASocket;
  FIdIndex:=1; // 0 invalid 1 always is display
  FProtocol := TWIProtocolNode.Create('/usr/share/wayland/wayland.xml');
  FObjectList := TWaylandObjectList.Create;
  FObjectList.Sorted:=True;
end;

function TWaylandConnection.NextObjectId: Integer;
begin
  Result := FIdIndex;
  Inc(FIdIndex);
end;

class function TWaylandConnection.CreateConnection: TWaylandConnection;
var
  lName: String;
  lFd: Longint;
  lSocket: TUnixSocket;
begin
  Result := nil;
  lName := FindSocketName;
  if Length(lName) = 0 then
    raise EWaylandConnectionError.Create(SErrWaylandNotFound);

  if TryStrToInt(lName, lFd) then
    lSocket := TUnixSocket.Create(lFd)
  else
    lSocket := TUnixSocket.Create(lName);

  Result := TWaylandConnection.Create(lSocket);

end;

procedure TWaylandConnection.SendRequest(AObjectID: DWord; ARequest: Word; Args: array of const);
const
  cSizeOffset = 6;
var
  lRequest: TWaylandStream;
  lNeedsPadding: Boolean;
  i: Integer;
begin
  lRequest := TWaylandStream.Create;
  lRequest.WriteDWord(AObjectID); // 4 bytes
  lRequest.WriteWord(ARequest); // 2 bytes
  lRequest.WriteWord(0); // Size. will equal the size of the TMemoryStream. Written last

  try
    for i := Low(Args) to High(Args) do
    begin
      lNeedsPadding := False;
      case Args[i].VType of
        vtBoolean: lRequest.WriteDWord(Ord(Args[i].VBoolean));
        vtInteger: lRequest.WriteDWord(Ord(Args[i].VInteger));
        //vtExtended: lRequest.WriteDWord(Ord(Args[i].VExtended)); // 24bit integer 8 bit decimal
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
        lRequest.WriteByte(0);
    end;

    if lRequest.Size > $FFFF then
      Raise EWaylandParamError.CreateFmt(SErrSizeTooLarge, [lRequest.Size, $FFFF]);

    lRequest.Position := cSizeOffset;
    lRequest.WriteWord(lRequest.Size);
    lRequest.Position:=0;

    {WriteLn('Requestor ', lRequest.ReadDWord);
    WriteLn('Opcode ', lRequest.ReadWord);
    WriteLn('Size ', lRequest.ReadWord);}

    lRequest.Position:=0;

    {$note later threadsafety}
    FSocket.CopyFrom(lRequest, lRequest.Size);
    FreeAndNil(lRequest);
  except
    FreeAndNil(lRequest);
  end;


end;

procedure TWaylandConnection.ObjectDestroying(AObjectID: Integer);
var
  lOutIndex: Integer;
begin
  // possibly notify we are destroying it to the server?
  if FObjectList.Find(AObjectId, lOutIndex) then
  begin
    FObjectList.Delete(lOutIndex);
  end;
end;

procedure TWaylandConnection.Run;
begin
  while True do
    WaitMessage(10);
end;

function TWaylandConnection.WaitMessage(ATimeOut: Integer): Boolean;
var
  Header: TWaylandMsgHeader;
  lSize: LongInt;
  lBaseObj: IWaylandBase;
  lStream: TWaylandStream;
  lMessageRec: TWaylandEventMessage;
  lProxyIndex: Integer;
begin
  Result := True;
  Fillchar(Header, SizeOf(Header), 0);
  lSize := FSocket.Read(Header, SizeOF(Header));
  {WriteLn('< Object Target = ', Header.Obj);
  WriteLn('< Object Opcode = ', Header.Index);
  WriteLn('< Object Size = ', Header.Index);}

  if Header.Obj = 0 then
  begin
    WriteLn('Got null');
    Raise Exception.Create('Null object not handled...disconnected?');
    // maybe read/seek data and hope for the best
  end;

  if FObjectList.Find(Header.Obj, lProxyIndex) then
    lBaseObj := FObjectList.Data[lProxyIndex]
  else
    lBaseObj := nil;
  WriteLn('< Object[',Header.Obj,'] = 0x', HexStr(pointer(lBaseObj)));

  if Assigned(lBaseObj) {and (lProxyObj.Obj is TWInterfaceNode)} then
  begin
    lStream := TWaylandStream.Create;
    lMessageRec.OpCode:=Header.Index;
    lMessageRec.Args := lStream;
    try
      lStream.CopyFrom(FSocket, Header.Size-8);
      lStream.Position:=0;
      (lBaseObj as TObject).Dispatch(lMessageRec);
      //TWInterfaceNode(lProxyObj.Obj).ReadEvent(Header.Index, lStream)
    finally
      lStream.Free;
    end;
  end
  else
  begin
    WriteLn('didn''t find object for message ', Header.Index);
    FSocket.Seek(Header.Size-8, fsFromCurrent);
  end;
end;

destructor TWaylandConnection.Destroy;
begin
  FObjectList.Free;
  FSocket.Free;
  inherited Destroy;
end;

function TWaylandConnection.GetDisplay: IWaylandDisplay;
begin
  if not Assigned(FDisplay) then
    FDisplay := TWaylandDisplay.Create(Self);

  Result := FDisplay;
end;

end.

