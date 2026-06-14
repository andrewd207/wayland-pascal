unit wayland_shm_impl;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BaseUnix, ctypes, wayland;

  function Create_shm_pool(shm: TWlShm; size: Integer; outdata: PPointer; outfd: PInteger): TWlShmPool;
  function Create_shm_buffer(shm: TWlShm; AWidth, AHeight: Integer; AFormat: TWlShm.TFormat; out data: Pointer; out fd: cint): TWlBuffer;

implementation


const
  FD_CLOEXEC = 1;

function mkstemp(filename: PChar):longint;cdecl;external 'libc' name 'mkstemp';
function mkostemp(filename: PChar; flags: cint):longint;cdecl;external 'libc' name 'mkostemp';
function shm_open(filename: PChar; flags: cint; __mode:mode_t):longint;cdecl;external 'libc' name 'shm_open';
function shm_unlink(filename: PChar):longint;cdecl;external 'libc' name 'shm_unlink';
function CreateAnonymousFile(ASize: PtrUint): cint; {fd} forward;

function __errno_location: PInteger; cdecl;external 'c' name '__errno_location';

function Create_shm_pool(shm: TWlShm; size: Integer; outdata: PPointer; outfd: PInteger): TWlShmPool;
var
  fd: cint;
  data: Pointer;
begin
  Result := nil;
  fd := CreateAnonymousFile(size);
  if fd < 0 then
    Exit;

  data := Fpmmap(nil, size, PROT_READ or PROT_WRITE, MAP_SHARED, fd, 0);
  if Assigned(outData) then
    outData^ := data;;
  if data = MAP_FAILED then
  begin
    fpclose(fd);
    Exit;
  end;

  Result := shm.CreatePool(fd, size);
  if outfd = nil then
    FpClose(fd)
  else
    outfd^ := fd;
end;

function Create_shm_buffer(shm: TWlShm; AWidth, AHeight: Integer; AFormat: TWlShm.TFormat; out data: Pointer; out fd: cint): TWlBuffer;
var
  pool: TWlShmPool;
  size, stride: cint;
begin
  Result := nil;
  stride := AWidth *4;
  size := stride * Aheight;

  pool := Create_shm_pool(shm, size, @Data, @fd);
  if pool = nil then
    Exit; // shm file / mmap failed; Result stays nil
  Result := pool.CreateBuffer(0, AWidth, AHeight, stride, AFormat);
  pool.Free // proxy will be destroyed after the buffer is destroyed

end;



function CreateAnonymousFile(ASize: PtrUint): cint; {fd}
const
  O_CLOEXEC = $80000;
var
  lName: String;
  retries: Integer;
  lErrno: cint;
begin
  for retries := 100 downto 0 do
  begin

    // mkostemp rewrites the XXXXXX template in place, so rebuild a fresh
    // template each attempt or a retry would call it on a consumed name.
    lName := GetEnvironmentVariable('XDG_RUNTIME_DIR') + '/weston-shared-XXXXXX';
    UniqueString(lName); // mkostemp writes into the buffer; must not be shared

    Result := mkostemp(PChar(lName), O_CLOEXEC);
    if Result >= 0 then
    begin
      FpUnlink(PChar(lName));
      Break;
    end;

    // mkostemp is a libc call, so the error lives in libc's errno
    // (__errno_location), NOT in the FPC RTL errno.
    lErrno := __errno_location^;
    if lErrno <> ESysEEXIST then
    begin
      Result := -1;
      Break;
    end;
  end;
  if (Result >= 0) and (FpFtruncate(Result, ASize) < 0) then
  begin
    WriteLn('ftruncate failed: ', __errno_location^);
    FpClose(Result);
    Result := -1;
  end;
end;



end.

