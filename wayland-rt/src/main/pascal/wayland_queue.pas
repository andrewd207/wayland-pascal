unit wayland_queue;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, syncobjs, wayland_stream, BaseUnix, ssockets;

type
  TWaylandDirection = (wdIncoming, wdOutgoing);

  { TWaylandEventMessage }

  TWaylandEventMessage = object
    OpCode: Integer;
    Args: TWaylandStream;
    Handled: Boolean;
    procedure SetHandled;
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

end.

