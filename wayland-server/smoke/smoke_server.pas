program smoke_server;
// End-to-end smoke test (server side). Binds a socket inside an ISOLATED
// XDG_RUNTIME_DIR (set by the runner), accepts one client, answers get_registry
// by creating the registry resource and sending one wl_registry.global event.
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, wayland_server_core, wayland_queue, wayland_server;

type
  TApp = class
    Done: Boolean;
    procedure OnGetRegistry(Sender: TWlDisplay; aRegistry: TWlRegistry);
    procedure OnConnect(AClient: TWaylandServerClient);
  end;

procedure TApp.OnGetRegistry(Sender: TWlDisplay; aRegistry: TWlRegistry);
begin
  WriteLn('[server] get_registry (registry id=', aRegistry.GetObjectId, ') -> send global');
  aRegistry.Global(1, 'wl_compositor', 4);
  Done := True;
end;

procedure TApp.OnConnect(AClient: TWaylandServerClient);
var
  lDisplay: TWlDisplay;
begin
  WriteLn('[server] client connected; binding wl_display at id 1');
  lDisplay := TWlDisplay.Create(AClient, 1, 1); // owned by the client's object map
  lDisplay.OnGetRegistry := @OnGetRegistry;
end;

var
  d: TWaylandServerDisplay;
  app: TApp;
  i: Integer;
begin
  app := TApp.Create;
  d := TWaylandServerDisplay.Create;
  d.OnConnect := @app.OnConnect;
  WriteLn('[server] listening on ', d.AddSocket('wayland-0'));
  Flush(Output);
  for i := 1 to 100 do
  begin
    d.Iterate(100);
    if app.Done then Break;
  end;
  d.Iterate(100); // grace flush
  WriteLn('[server] handled get_registry = ', app.Done);
  d.Free;
  app.Free;
  if not app.Done then Halt(1);
end.
