unit wayland_queue;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, wayland_stream, BaseUnix, ctypes, ssockets;

type
  TWaylandDirection = (wdIncoming, wdOutgoing);

  { TWaylandEventMessage }

  TWaylandEventMessage = object
    OpCode: Integer;
    Args: TWaylandStream;
    Handled: Boolean;
    // File descriptors carried out-of-band (SCM_RIGHTS) for this event, in the
    // order their 'h' args appear in the protocol signature. They are attached
    // here at parse time (not popped from a shared connection FIFO at dispatch
    // time) so they stay correctly paired with their event even when dispatch is
    // deferred to a non-default queue. Ownership of a returned fd transfers to
    // the caller of NextFd; any fd left unconsumed is closed by CloseUnusedFds.
    Fds: array of cint;
    FdPos: Integer;
    procedure SetHandled;
    // Returns the next unconsumed fd (in signature order), or -1 if none remain.
    // The caller owns the returned fd and must close it.
    function NextFd: cint;
    // Closes any fds an event handler did not consume, so a partially- or
    // un-handled event cannot leak descriptors. Idempotent.
    procedure CloseUnusedFds;
  end;

  TWaylandMessage = object
    Target: Integer;
    Direction: TWaylandDirection;
    Message: TWaylandEventMessage;
  end;



implementation

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

procedure TWaylandEventMessage.CloseUnusedFds;
begin
  while FdPos <= High(Fds) do
  begin
    if Fds[FdPos] >= 0 then
      FpClose(Fds[FdPos]);
    Inc(FdPos);
  end;
end;

end.

