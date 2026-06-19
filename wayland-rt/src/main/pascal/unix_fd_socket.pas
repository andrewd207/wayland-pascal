// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

unit unix_fd_socket;

{$mode ObjFPC}{$H+}
{$PackRecords c}

interface

uses
  Classes, SysUtils, BaseUnix, ctypes, sockets, ssockets;

const
  // Matches libwayland's MAX_FDS_OUT: the most file descriptors we accept on a
  // single recvmsg. Wayland events carry at most a handful, so this is ample.
  WL_MAX_FDS_PER_RECV = 28;

function SendFD(socket: cint; fd_to_send: cint; data: Pointer; datalen: cint): cint;
function RecvFD(socket: cint): cint;

// Receives up to ADataLen bytes into AData AND captures any SCM_RIGHTS file
// descriptors carried out-of-band on the same datagram. Captured fds are written
// to AFds[0..AFdCount-1] (up to AMaxFds; extras are silently dropped). Honors the
// socket's SO_RCVTIMEO (set via TUnixSocket.IOTimeout): returns -1 with errno
// EAGAIN/EWOULDBLOCK on timeout, 0 on orderly shutdown, or the byte count read.
// This is the receive counterpart to SendFD and the only correct way to read a
// Wayland stream: a plain read() silently discards the ancillary fds.
function RecvWithFds(socket: cint; AData: Pointer; ADataLen: cint;
  AFds: pcint; AMaxFds: Integer; out AFdCount: Integer): ssize_t;

function c_errno: Integer;

implementation

//var  errno: Integer; external name 'errno';

const
  SOL_SOCKET  =   1;
  SCM_RIGHTS  =   $01;

type
  Pmsghdr = ^msghdr;
  msghdr = record
     msg_name : pointer;
     msg_namelen : socklen_t;
     msg_iov : piovec;
     msg_iovlen : size_t;  // cint
     msg_control : pointer;
     msg_controllen : size_t;
     msg_flags : cInt;
  end;

  Pcmsghdr = ^cmsghdr;
  cmsghdr = record
    cmsg_len   : size_t;
    cmsg_level : cInt;
    cmsg_type  : cInt;
  end;

  function sendmsg(__fd: cInt; __message: pmsghdr; __flags: cInt): ssize_t; cdecl; external 'c' name 'sendmsg';
  function recvmsg(__fd: cInt; __message: pmsghdr; __flags: cInt): ssize_t; cdecl; external 'c' name 'recvmsg';
  function __errno_location: PInteger; cdecl;external 'c' name '__errno_location';
  function __cmsg_nxthdr(__mhdr:Pmsghdr; __cmsg:Pcmsghdr):Pcmsghdr;cdecl;external 'c' name '__cmsg_nxthdr';
function fpSendmsg(s:longint; _para2:Pmsghdr; flags:longint):ssize_t;cdecl;external 'c' name 'sendmsg';
function fpRecvmsg(s:longint; msg:Pmsghdr; flags:longint):ssize_t;cdecl;external 'c' name 'recvmsg';


function CMSG_FIRSTHDR(mhdr: Pmsghdr): Pcmsghdr;
begin
  if mhdr^.msg_controllen >= SizeOf(cmsghdr) then
    Result:=mhdr^.msg_control
  else
    Result:=nil;
end;

function CMSG_NXTHDR(mhdr: Pmsghdr; cmsg: Pcmsghdr): Pcmsghdr;
begin
   Result:=__cmsg_nxthdr(mhdr, cmsg);
end;

function CMSG_ALIGN(len: size_t): size_t;
begin
  Result:=(len+SizeOf(size_t)-1) and (not(SizeOf(size_t)-1));
end;

function CMSG_SPACE(len: size_t): size_t;
begin
  Result:=CMSG_ALIGN(len)+CMSG_ALIGN(SizeOf(cmsghdr));
end;

function CMSG_LEN(len: size_t): size_t;
begin
  Result:=CMSG_ALIGN(SizeOf(cmsghdr))+len;
end;

function CMSG_DATA(cmsg: Pointer): PByte;
begin
  Result:=PByte(Ptruint(cmsg) + SizeOf(cmsghdr));
end;

function SendFD(socket: cint; fd_to_send: cint; data: Pointer; datalen: cint
  ): cint;
var
  msg: msghdr;
  cmsg: PCmsghdr;
  buf: TBytes;//}array[0..5] of integer;
  io: iovec;
  io_buf: byte = 0;
  fdptr: pcint;
  iovbuf: Byte = 0;
begin
  SetLength(buf, CMSG_SPACE(SizeOf(cint)));
  FillChar(msg, SizeOf(msg), 0);
  //FillChar(buf[0], Length(buf)*sizeof(integer), 0);
 { buf[0] := $14;
  buf[2] := 1;
  buf[3] := 1;
  buf[4] := SizeOf(Integer);
  buf[5] := fd_to_send;}


  io.iov_len:=datalen;
  io.iov_base:=data;//@io_buf;

  msg.msg_control := @buf[0];
  msg.msg_controllen := Length(buf);//*sizeof(integer);

  msg.msg_iov:=@io;
  msg.msg_iovlen:=1;

  cmsg := CMSG_FIRSTHDR(@msg);
  cmsg^.cmsg_len := CMSG_LEN(SizeOf(cint));
  cmsg^.cmsg_level := SOL_SOCKET;
  cmsg^.cmsg_type := SCM_RIGHTS;
  fdptr := pcint(CMSG_DATA(cmsg));
  fdptr^ := fd_to_send;


  // Returns the number of bytes sent, or -1 on error (errno set by sendmsg).
  // Callers must check the result.
  Result := fpSendMsg(socket, @msg, 0);
end;

function RecvFD(socket: cint): cint;
var
  msg: Msghdr;
  cmsg: PCmsghdr;
  buf: TBytes;
  fdptr: pcint;
begin
  SetLength(buf,CMSG_SPACE(SizeOf(cint)));

  FillChar(msg, SizeOf(msg), 0);
  FillChar(buf[0], Length(buf), 0);

  msg.msg_control := @buf[0];
  msg.msg_controllen := Length(buf);

  if fpRecvMsg(socket, @msg, 0) < 0 then
  begin
    Result := -1;
    Exit;
  end;

  cmsg := CMSG_FIRSTHDR(@msg);
  if (cmsg <> nil) and (cmsg^.cmsg_level = SOL_SOCKET) and (cmsg^.cmsg_type = SCM_RIGHTS) then
  begin
    fdptr := pcint(CMSG_DATA(cmsg));
    Result := fdptr^;
  end
  else
    Result := -1;
end;

function RecvWithFds(socket: cint; AData: Pointer; ADataLen: cint;
  AFds: pcint; AMaxFds: Integer; out AFdCount: Integer): ssize_t;
var
  msg: msghdr;
  io: iovec;
  cmsg: PCmsghdr;
  ctrl: TBytes;
  lNFds, i: Integer;
  lSrc: pcint;
begin
  AFdCount := 0;
  // Control buffer big enough for AMaxFds descriptors in one SCM_RIGHTS message.
  SetLength(ctrl, CMSG_SPACE(AMaxFds * SizeOf(cint)));
  FillChar(msg, SizeOf(msg), 0);
  FillChar(ctrl[0], Length(ctrl), 0);

  io.iov_base := AData;
  io.iov_len := ADataLen;
  msg.msg_iov := @io;
  msg.msg_iovlen := 1;
  msg.msg_control := @ctrl[0];
  msg.msg_controllen := Length(ctrl);

  Result := fpRecvMsg(socket, @msg, 0);
  if Result <= 0 then
    Exit; // error (errno set) or orderly shutdown; no ancillary data to harvest

  // Walk every SCM_RIGHTS control message and append its fds in arrival order.
  cmsg := CMSG_FIRSTHDR(@msg);
  while cmsg <> nil do
  begin
    if (cmsg^.cmsg_level = SOL_SOCKET) and (cmsg^.cmsg_type = SCM_RIGHTS) then
    begin
      // payload length = cmsg_len minus the aligned header; one cint per fd.
      lNFds := (cmsg^.cmsg_len - CMSG_LEN(0)) div SizeOf(cint);
      lSrc := pcint(CMSG_DATA(cmsg));
      for i := 0 to lNFds - 1 do
        if AFdCount < AMaxFds then
        begin
          AFds[AFdCount] := lSrc[i];
          Inc(AFdCount);
        end;
    end;
    cmsg := CMSG_NXTHDR(@msg, cmsg);
  end;
end;

function c_errno: Integer;
begin

  REsult := __errno_location^;
end;


end.

