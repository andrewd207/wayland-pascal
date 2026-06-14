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
  wayland_errors, wayland_strings;

function socket(__domain:longint; __type:longint; __protocol:longint):longint;cdecl;external 'c' name 'socket';
function connect(__fd:longint; __addr:Psockaddr; __len:Dword):longint;cdecl;external 'c' name 'connect';

{ TWaylandStream }

function TWaylandStream.ReadString: String;
var
  lLen: Cardinal;
begin
  lLen := ReadDWord;
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
  lSockfd := socket(AF_UNIX, SOCK_STREAM, 0);
  FillChar(addr, SizeOf(addr), 0);
  addr.sun_family:=AF_UNIX;
  move(AFileName[1], addr.sun_path[0], Length(AFileName));
  connect(lSockfd, @addr, SizeOf(addr));
  inherited Create(lSockfd, nil);

end;

end.

