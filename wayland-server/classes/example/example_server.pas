program example_server;
// Minimal server built on the wayland-server-classes ergonomics layer. It
// advertises a few globals and lets clients bind them — the registry / bind /
// version-clamp / sync plumbing is all handled by TWaylandServer. (It has no
// rendering backend, so it doesn't show windows; it's a protocol-side demo.)
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, wayland_server_core, wayland_server, wayland_server_classes;

type
  TApp = class
    procedure OnCompositorBound(AClient: TWaylandServerClient; AResource: TWaylandServerResource);
    procedure OnCreateSurface(Sender: TWlCompositor; aId: TWlSurface);
  end;

procedure TApp.OnCompositorBound(AClient: TWaylandServerClient; AResource: TWaylandServerResource);
begin
  WriteLn('[server] wl_compositor bound at id ', AResource.GetObjectId,
          ' (version ', AResource.Version, ')');
  Flush(Output);
  (AResource as TWlCompositor).OnCreateSurface := @OnCreateSurface;
end;

procedure TApp.OnCreateSurface(Sender: TWlCompositor; aId: TWlSurface);
begin
  WriteLn('[server] create_surface -> wl_surface id ', aId.GetObjectId);
  Flush(Output);
end;

var
  App: TApp;
  Server: TWaylandServer;
begin
  App := TApp.Create;
  Server := TWaylandServer.Create;
  // Declare globals. Version defaults to the class's max; here we cap
  // wl_compositor at 4 to show version negotiation (clients get min(4, theirs)).
  Server.AddGlobal(TWlCompositor, 4, @App.OnCompositorBound);
  Server.AddGlobal(TWlShm, 1);
  Server.AddGlobal(TWlSeat, 5);
  WriteLn('[server] listening on ', Server.AddSocket('wayland-0'));
  WriteLn('[server] point a client at it: export WAYLAND_DISPLAY=wayland-0');
  Flush(Output);
  Server.Run; // until killed
end.
