// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

unit wayland_server_classes;

{ Server protocol-ergonomics layer — the server-side counterpart of the client's
  wayland-classes. It hides the boilerplate every Wayland server repeats:

    * wl_display bound at id 1 on each client (via the runtime's DisplayClass),
    * wl_display.get_registry -> a wl_registry that announces your globals,
    * wl_registry.bind -> instantiate the right resource, version-CLAMPED to
      min(advertised, client-requested), then a callback to wire its handlers,
    * wl_display.sync -> wl_callback.done + teardown,
    * a monotonic serial source for input/configure events.

  You declare globals with AddGlobal and run the loop. Resource destruction and
  the wl_display.delete_id acknowledgement are handled in the runtime.

  What this layer deliberately does NOT do: compositing, buffer access, scanout,
  window placement/stacking, input devices, cursors. Those are a backend you
  supply — the layer stops at "here is a resource (and, after commit, its
  wl_buffer)". It is glue, not a compositor. }

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fgl, wayland_server_core, wayland_server;

type
  { Fired when a client binds one of your globals. AResource is the freshly
    created resource (already at the clamped version); wire its request handlers
    here, e.g. (AResource as TWlCompositor).OnCreateSurface := ... }
  TGlobalBindEvent = procedure(AClient: TWaylandServerClient; AResource: TWaylandServerResource) of object;

  { TWaylandServerGlobal }

  TWaylandServerGlobal = class
  public
    Name: DWord;                          // server-assigned registry name (>=1)
    InterfaceName: String;
    Version: Integer;                     // advertised (max) version
    ResClass: TWaylandServerResourceClass;
    OnBind: TGlobalBindEvent;
  end;

  TWaylandServerGlobalList = specialize TFPGObjectList<TWaylandServerGlobal>;

  { TWaylandServer }

  TWaylandServer = class
  private
    FDisplay: TWaylandServerDisplay;
    FGlobals: TWaylandServerGlobalList;
    FNextGlobalName: DWord;
    FSerial: DWord;
    procedure DoConnect(AClient: TWaylandServerClient);
    procedure DoGetRegistry(Sender: TWlDisplay; aRegistry: TWlRegistry);
    procedure DoSync(Sender: TWlDisplay; aCallback: TWlCallback);
    procedure DoBind(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord; aId: DWord);
  public
    constructor Create;
    destructor Destroy; override;

    // Advertise a global. AClass is the generated server resource class (e.g.
    // TWlCompositor); its interface name and, by default, its max version are
    // taken from the class. AOnBind (optional) fires when a client binds it.
    function AddGlobal(AClass: TWaylandServerResourceClass; AOnBind: TGlobalBindEvent = nil): TWaylandServerGlobal; overload;
    function AddGlobal(AClass: TWaylandServerResourceClass; AVersion: Integer; AOnBind: TGlobalBindEvent = nil): TWaylandServerGlobal; overload;

    // Bind the listening socket ('' => first free wayland-N). Returns its name.
    function AddSocket(const AName: String = ''): String;
    procedure Run;                        // accept + dispatch until Quit
    procedure Iterate(ATimeoutMs: Integer);
    procedure Quit;

    // Monotonic, ever-increasing serial for events that need one (button/key/
    // motion, configure, ...). Wraps the compositor-wide event clock.
    function NextSerial: DWord;

    property Display: TWaylandServerDisplay read FDisplay; // escape hatch
    property Globals: TWaylandServerGlobalList read FGlobals;
  end;

implementation

constructor TWaylandServer.Create;
begin
  inherited Create;
  FGlobals := TWaylandServerGlobalList.Create(True);
  FNextGlobalName := 1;
  FDisplay := TWaylandServerDisplay.Create;
  FDisplay.DisplayClass := TWlDisplay;     // auto-bind wl_display at id 1 per client
  FDisplay.OnConnect := @DoConnect;
end;

destructor TWaylandServer.Destroy;
begin
  FDisplay.Free;
  FGlobals.Free;
  inherited Destroy;
end;

function TWaylandServer.AddGlobal(AClass: TWaylandServerResourceClass;
  AOnBind: TGlobalBindEvent): TWaylandServerGlobal;
begin
  Result := AddGlobal(AClass, AClass.GetInterfaceVersion, AOnBind);
end;

function TWaylandServer.AddGlobal(AClass: TWaylandServerResourceClass;
  AVersion: Integer; AOnBind: TGlobalBindEvent): TWaylandServerGlobal;
begin
  Result := TWaylandServerGlobal.Create;
  Result.Name := FNextGlobalName;
  Inc(FNextGlobalName);
  Result.InterfaceName := AClass.GetInterfaceName;
  Result.Version := AVersion;
  Result.ResClass := AClass;
  Result.OnBind := AOnBind;
  FGlobals.Add(Result);
end;

function TWaylandServer.AddSocket(const AName: String): String;
begin
  if AName = '' then
    Result := FDisplay.AddSocketAuto
  else
    Result := FDisplay.AddSocket(AName);
end;

procedure TWaylandServer.Run;
begin
  FDisplay.Run;
end;

procedure TWaylandServer.Iterate(ATimeoutMs: Integer);
begin
  FDisplay.Iterate(ATimeoutMs);
end;

procedure TWaylandServer.Quit;
begin
  FDisplay.Quit;
end;

function TWaylandServer.NextSerial: DWord;
begin
  Inc(FSerial);
  Result := FSerial;
end;

procedure TWaylandServer.DoConnect(AClient: TWaylandServerClient);
var
  lDisplay: TWlDisplay;
begin
  // wl_display was auto-bound at id 1; wire its two requests.
  lDisplay := AClient.GetObject(WL_DISPLAY_OBJECT_ID) as TWlDisplay;
  lDisplay.OnGetRegistry := @DoGetRegistry;
  lDisplay.OnSync := @DoSync;
end;

procedure TWaylandServer.DoGetRegistry(Sender: TWlDisplay; aRegistry: TWlRegistry);
var
  i: Integer;
begin
  // Announce every advertised global to this registry, then handle its binds.
  for i := 0 to FGlobals.Count - 1 do
    aRegistry.Global(FGlobals[i].Name, FGlobals[i].InterfaceName, FGlobals[i].Version);
  aRegistry.OnBind := @DoBind;
end;

procedure TWaylandServer.DoBind(Sender: TWlRegistry; aName: DWord;
  aInterface: String; aVersion: DWord; aId: DWord);
var
  i, lVer: Integer;
  lGlobal: TWaylandServerGlobal;
  lResource: TWaylandServerResource;
begin
  lGlobal := nil;
  for i := 0 to FGlobals.Count - 1 do
    if FGlobals[i].Name = aName then begin lGlobal := FGlobals[i]; Break; end;
  if lGlobal = nil then
    Exit; // unknown global name — a misbehaving client; ignore.

  // Clamp to the version the server actually advertised.
  lVer := Integer(aVersion);
  if lVer > lGlobal.Version then lVer := lGlobal.Version;

  lResource := lGlobal.ResClass.Create(Sender.Client, aId, lVer);
  if Assigned(lGlobal.OnBind) then
    lGlobal.OnBind(Sender.Client, lResource);
end;

procedure TWaylandServer.DoSync(Sender: TWlDisplay; aCallback: TWlCallback);
begin
  // One-shot: answer with done, then destroy the callback (the runtime sends the
  // wl_display.delete_id for it).
  aCallback.Done(NextSerial);
  aCallback.Free;
end;

end.
