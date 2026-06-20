program smoke_client;
// End-to-end smoke test (client side). Connects via the isolated XDG_RUNTIME_DIR,
// calls get_registry, and waits for the server's wl_registry.global event.
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Wayland_Core, wayland;

type
  TApp = class
    GotGlobal: Boolean;
    procedure OnGlobal(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord);
  end;

procedure TApp.OnGlobal(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord);
begin
  WriteLn('[client] GLOBAL name=', aName, ' interface=', aInterface, ' version=', aVersion);
  GotGlobal := (aName = 1) and (aInterface = 'wl_compositor') and (aVersion = 4);
end;

var
  disp: TWlDisplay;
  reg: TWlRegistry;
  app: TApp;
  i: Integer;
begin
  app := TApp.Create;
  if not TWlDisplay.TryCreateConnection(disp) then
  begin
    WriteLn('[client] connect failed'); Halt(2);
  end;
  reg := disp.GetRegistry;
  reg.OnGlobal := @app.OnGlobal;
  for i := 1 to 50 do
  begin
    disp.WaitMessage(100);
    if app.GotGlobal then Break;
  end;
  if app.GotGlobal then
  begin
    WriteLn('[client] OK: round-trip verified'); Halt(0);
  end
  else
  begin
    WriteLn('[client] FAILED: no matching global'); Halt(1);
  end;
end.
