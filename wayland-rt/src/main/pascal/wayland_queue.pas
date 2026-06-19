unit wayland_queue;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, wayland_stream, BaseUnix, ctypes, ssockets;

type
  TWaylandDirection = (wdIncoming, wdOutgoing);

  { TWaylandFdStream }

  // A TStream over a Unix file descriptor received out-of-band (SCM_RIGHTS).
  // Read/Write go straight to the fd (read()/write()), so it works on the pipes
  // and sockets Wayland passes; Seek/Size are not meaningful. The stream owns the
  // fd and closes it when freed, unless ReleaseHandle is called to hand the raw
  // fd to code that will own it instead.
  TWaylandFdStream = class(THandleStream)
  private
    FOwnsHandle: Boolean;
  public
    // Wrap an already-open fd (the received-fd case). The stream owns it.
    constructor Create(AFd: cint);
    destructor Destroy; override;
    // Create a fresh OS pipe and wrap both ends — the send-side helper for
    // requests that take an fd to write into (e.g. wl_data_offer.receive: pass
    // the write end's Handle, read your data from the read end). False (and nil
    // ends) if the pipe could not be created. Caller frees both ends.
    class function CreatePipe(out AReadEnd, AWriteEnd: TWaylandFdStream): Boolean;
    // Relinquish ownership: returns the fd and stops Destroy from closing it.
    // Use when passing the raw fd to a consumer that will own it (e.g. a keymap
    // handler that mmaps then closes). Returns -1 if already released.
    function ReleaseHandle: cint;
  end;

  { TWaylandEventMessage }

  TWaylandEventMessage = object
    OpCode: Integer;
    Args: TWaylandStream;
    Handled: Boolean;
    // File descriptors carried out-of-band (SCM_RIGHTS) for this event, in the
    // order their 'h' args appear in the protocol signature. They are attached
    // here at parse time (not popped from a shared connection FIFO at dispatch
    // time) so they stay correctly paired with their event even when dispatch is
    // deferred to a non-default queue.
    Fds: array of cint;
    FdPos: Integer;
    // Streams handed out by NextFdStream. The message owns them and frees them
    // (closing their fds) in ReleaseFds after dispatch — listeners borrow, never
    // free. A handler that needs the raw fd instead calls stream.ReleaseHandle.
    FdStreams: array of TWaylandFdStream;
    procedure SetHandled;
    // Returns the next unconsumed fd (signature order), or -1 if none remain.
    // The caller owns the returned fd. Prefer NextFdStream for the idiomatic API.
    function NextFd: cint;
    // Wraps the next unconsumed fd in a message-owned TWaylandFdStream (borrowed
    // by the caller), or nil if none remain. This is what generated fd event
    // args are delivered as.
    function NextFdStream: TWaylandFdStream;
    // Frees the streams NextFdStream created and closes any fds no handler took,
    // so an event cannot leak descriptors. Called after dispatch. Idempotent.
    procedure ReleaseFds;
  end;

  TWaylandMessage = object
    Target: Integer;
    Direction: TWaylandDirection;
    Message: TWaylandEventMessage;
  end;



implementation

{ TWaylandEventMessage }

{ TWaylandFdStream }

constructor TWaylandFdStream.Create(AFd: cint);
begin
  inherited Create(THandle(AFd));
  FOwnsHandle := True;
end;

destructor TWaylandFdStream.Destroy;
begin
  if FOwnsHandle and (Handle >= 0) then
    FpClose(Handle);
  inherited Destroy;
end;

class function TWaylandFdStream.CreatePipe(out AReadEnd, AWriteEnd: TWaylandFdStream): Boolean;
var
  lFds: array[0..1] of cint; // [0]=read end, [1]=write end
begin
  AReadEnd := nil;
  AWriteEnd := nil;
  Result := FpPipe(lFds) = 0;
  if not Result then
    Exit;
  AReadEnd := TWaylandFdStream.Create(lFds[0]);
  AWriteEnd := TWaylandFdStream.Create(lFds[1]);
end;

function TWaylandFdStream.ReleaseHandle: cint;
begin
  if not FOwnsHandle then
    Exit(-1);
  Result := Handle;
  FOwnsHandle := False;
end;

{ TWaylandEventMessage }

procedure TWaylandEventMessage.SetHandled;
begin
  Handled:=True;
end;

function TWaylandEventMessage.NextFd: cint;
begin
  if FdPos <= High(Fds) then
  begin
    Result := Fds[FdPos];
    Inc(FdPos);
  end
  else
    Result := -1;
end;

function TWaylandEventMessage.NextFdStream: TWaylandFdStream;
var
  lFd: cint;
begin
  if FdPos > High(Fds) then
    Exit(nil);
  lFd := Fds[FdPos];
  Inc(FdPos);
  Result := TWaylandFdStream.Create(lFd);
  SetLength(FdStreams, Length(FdStreams) + 1);
  FdStreams[High(FdStreams)] := Result;
end;

procedure TWaylandEventMessage.ReleaseFds;
var
  i: Integer;
begin
  // Free the streams we created (each closes its fd unless ReleaseHandle ran).
  for i := 0 to High(FdStreams) do
    FreeAndNil(FdStreams[i]);
  FdStreams := nil;
  // Close any attached fds no handler consumed (neither NextFd nor NextFdStream).
  while FdPos <= High(Fds) do
  begin
    if Fds[FdPos] >= 0 then
      FpClose(Fds[FdPos]);
    Inc(FdPos);
  end;
end;

end.

