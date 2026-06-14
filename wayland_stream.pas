unit wayland_stream;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, ssockets, sockets;

type

  { TWaylandStream }

  TWaylandStream = class(TMemoryStream)
    function ReadString: String;
    function ReadInteger: Integer;
    procedure WriteString(const AString: String);
    function ReadBlob: TBytes;
    procedure ReadBlob(AStream: TStream);
  end;

  { TCUnixSocket }

  TCUnixSocket = class(TUnixSocket)
    Constructor Create(const AFileName : String); Overload;

  end;

implementation
uses
  wayland_errors, wayland_strings, BaseUnix, unix_fd_socket;

function socket(__domain:longint; __type:longint; __protocol:longint):longint;cdecl;external 'c' name 'socket';
function connect(__fd:longint; __addr:Psockaddr; __len:Dword):longint;cdecl;external 'c' name 'connect';

{ TWaylandStream }

function TWaylandStream.ReadString: String;
var
  lLen: Cardinal;
begin
  lLen := ReadDWord;
  // lLen is the byte count including the null terminator, so it must be >= 1.
  // Guard against underflow: lLen-1 on a Cardinal would wrap to ~4G otherwise.
  if lLen = 0 then
    raise EWaylandError.CreateFmt(SErrStringTooShort, [lLen]);
  SetLength(Result, lLen-1);
  Read(Result[1], lLen-1);
  ReadByte; // null char

  if Position mod 4 <> 0 then
    Seek(4-(Position mod 4), fsFromCurrent);
end;

function TWaylandStream.ReadInteger: Integer;
begin
  ReadBuffer(Result, 4);
end;

procedure TWaylandStream.WriteString(const AString: String);
begin
  // because of +1 we cannot use WriteAnsistring and also we need to pad it to
  // a 32bit boundary
  WriteDWord(Length(AString)+1);
  Write(AString[1], Length(AString));
  WriteByte(0); // null char
  while (Size mod 4) <> 0 do
    WriteByte(0); // Padding
end;

function TWaylandStream.ReadBlob: TBytes;
var
  lLen: Cardinal;
begin
  lLen := ReadDWord;
  SetLength(Result, lLen);
  Read(Result[0], lLen);
  // padding

  //Seek(((Position) mod 4), fsFromCurrent);
  // needs testing. string is ok but has null char.
  if Position mod 4 <> 0 then
    Seek(4-(Position mod 4), fsFromCurrent);
end;

procedure TWaylandStream.ReadBlob(AStream: TStream);
var
  lLen: Cardinal;
begin
  if not Assigned(AStream) then
    raise EWaylandError.CreateFmt(SErrNilParam, ['AStream']);


  lLen := ReadDWord;
  AStream.CopyFrom(Self, lLen);
  // padding
  if Position mod 4 <> 0 then
    Seek(4-(Position mod 4), fsFromCurrent);
end;

{ TCUnixSocket }

constructor TCUnixSocket.Create(const AFileName: String);
var
  addr: sockaddr_un;
  lSockfd: LongInt;
begin
  // sun_path must hold the path plus a null terminator.
  if Length(AFileName) >= SizeOf(addr.sun_path) then
    raise EWaylandConnectionError.CreateFmt(SErrSocketPathTooLong,
      [AFileName, Length(AFileName), SizeOf(addr.sun_path) - 1]);

  lSockfd := socket(AF_UNIX, SOCK_STREAM, 0);
  // socket/connect are libc calls (external 'c'); they set libc's thread-local
  // errno, which the FPC RTL's fpGetErrno does NOT observe. c_errno reads it via
  // __errno_location(). (Verified: fpGetErrno returns 0 here, c_errno the real code.)
  if lSockfd < 0 then
    raise EWaylandConnectionError.CreateFmt(SErrSocketCreate, [c_errno]);

  FillChar(addr, SizeOf(addr), 0);
  addr.sun_family:=AF_UNIX;
  move(AFileName[1], addr.sun_path[0], Length(AFileName));
  if connect(lSockfd, @addr, SizeOf(addr)) < 0 then
  begin
    fpClose(lSockfd);
    raise EWaylandConnectionError.CreateFmt(SErrSocketConnect, [AFileName, c_errno]);
  end;
  inherited Create(lSockfd, nil);

end;

end.

