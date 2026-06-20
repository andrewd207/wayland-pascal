program bind_client;
// Test client for the classes-layer example_server: connect, read the registry,
// bind wl_compositor, create a surface, and sync. Exercises the server's
// bind (+version clamp), request dispatch, sync->done, and delete_id paths.
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Wayland_Core, wayland;

type
  TApp = class
    CompName: DWord;
    HasComp: Boolean;
    procedure OnGlobal(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord);
  end;

procedure TApp.OnGlobal(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord);
begin
  WriteLn('[client] registry global ', aName, ' = ', aInterface, ' v', aVersion);
  if aInterface = 'wl_compositor' then
  begin
    CompName := aName;
    HasComp := True;
  end;
end;

var
  disp: TWlDisplay;
  reg: TWlRegistry;
  comp: TWlCompositor;
  surf: TWlSurface;
  app: TApp;
  i: Integer;
begin
  app := TApp.Create;
  if not TWlDisplay.TryCreateConnection(disp) then begin WriteLn('connect failed'); Halt(2); end;
  reg := disp.GetRegistry;
  reg.OnGlobal := @app.OnGlobal;
  for i := 1 to 30 do begin disp.WaitMessage(100); if app.HasComp then Break; end;
  if not app.HasComp then begin WriteLn('[client] no wl_compositor'); Halt(1); end;

  comp := nil;
  reg.Bind(app.CompName, 'wl_compositor', 4, TWlCompositor, comp);
  surf := comp.CreateSurface;
  WriteLn('[client] bound wl_compositor, created wl_surface id ', surf.GetObjectId);
  disp.SyncAndWait; // round-trips through the server (sync -> done)
  WriteLn('[client] sync OK');
  Halt(0);
end.
