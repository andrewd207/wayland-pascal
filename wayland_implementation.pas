unit wayland_implementation;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, wayland_interfaces, fgl, wayland_stream{, wayland_wire},
  Wayland_Core, wayland_queue, wayland_internal_interfaces;

type


{







}


  //TWaylandProxy = class;

  //TWaylandProxyList = specialize TFPGInterfacedObjectList<TWaylandProxy>;

  { TWaylandProxy }

{  TWaylandProxy = class(TWaylandBase, IWaylandProxy)
  private
    UserData: TObject;
    FObject: IWaylandBase;
    FConstructor: TWaylandConstructor;
  public
    function  GetConstructor: TWaylandConstructor;
    function  GetObject: IWaylandBase;
    procedure SetObject(AValue: IWaylandBase);

    property  Obj: IWaylandBase read GetObject write SetObject;

    constructor Create(AConnection: IWaylandDisplayCore; AConstructor: TWaylandConstructor; AId: Integer; AObject: IWaylandBase);
  end;}

   { TWaylandDisplay }
  //TWRegistry

  { TWaylandCompositor }

  TWaylandCompositor = class(TWaylandBase, IWaylandBase)
    constructor Create(ADisplay: IWaylandDisplay; AQueue: IWaylandEventQueue = nil); override;

  end;

  TWaylandDisplay = class(TWaylandDisplayBase, IWaylandDisplay)
  public
  const
    EV_ERROR = 0;
    EV_DELETE_ID = 1;
  private
    FRegistry: IWaylandRegistry;
    procedure HandleError(var Msg: TWaylandEventMessage); message EV_ERROR;
    procedure HandleDeleteId(var Msg: TWaylandEventMessage); message EV_DELETE_ID;
  public
    procedure Sync;
    function GetRegistry: IWaylandRegistry;
  end;

  { TWRegistry }

  { TWaylandRegistry }

  TWaylandRegistry = class(TWaylandBase, IWaylandRegistry)
  private
  const
    R_BIND = 0;
  public
  const
    EV_GLOBAL = 0;
    EV_GLOBAL_REMOVE = 1;
  public
    procedure HandleGlobal(var Msg: TWaylandEventMessage); message EV_GLOBAL;
    procedure Bind(ANameIndex: Integer; AInterfaceName: String; AVersion: Integer; AObjectID: Integer);
    constructor Create(ADisplay: IWaylandDisplay; AQueue: IWaylandEventQueue); override;

  end;

  { TWaylandCallback }

  TWaylandCallback = class(TWaylandBase, IWaylandCallBack)
  private
    FDone: Boolean;
  public
  const
    EV_DONE = 0;

    procedure HandleDone(var Msg: TWaylandEventMessage); message EV_DONE;
    property Done: Boolean read FDone;
  end;

implementation

{ TWaylandCompositor }

constructor TWaylandCompositor.Create(ADisplay: IWaylandDisplay;
  AQueue: IWaylandEventQueue);
begin
  inherited Create(ADisplay, AQueue, -1);
  ADisplay.GetRegistry.Bind(1, 'wl_compositor', 5, GetObjectId);
end;

{ TWaylandCallback }

procedure TWaylandCallback.HandleDone(var Msg: TWaylandEventMessage);
begin
  WriteLn('!!!Done!!!!');
  FDone:= True;
  Msg.SetHandled;
end;


{ TWaylandProxy }

{function TWaylandProxy.GetConstructor: TWaylandConstructor;
begin
  Result := FConstructor;
end;

function TWaylandProxy.GetObject: IWaylandBase;
begin
   Result := FObject;
end;

procedure TWaylandProxy.SetObject(AValue: IWaylandBase);
begin
  FObject := Avalue
end;

constructor TWaylandProxy.Create(AConnection: IWaylandDisplayCore;
  AConstructor: TWaylandConstructor; AId: Integer; AObject: IWaylandBase);
begin
  inherited Create(AConnection, True);
  FObjectId:=AId;
  FConstructor:=AConstructor;
  FObject:=AObject;
end;}

{ TWRegistry }

procedure TWaylandRegistry.HandleGlobal(var Msg: TWaylandEventMessage);
var
  lName: String;
begin
  WriteLn('GLOBAL called!');
  WriteLn('NameID = ', Msg.Args.ReadDWord);
  lName := Msg.Args.ReadString;
  WriteLn('Name = ', lName);
  WriteLn('Version = ', Msg.Args.ReadDWord);
  Msg.SetHandled;
end;

procedure TWaylandRegistry.Bind(ANameIndex: Integer; AInterfaceName: String; AVersion: Integer; AObjectID: Integer);
begin
  Connection.SendRequest(GetObjectId, R_BIND, [ANameIndex, AInterfaceName, AVersion, AObjectID]);
end;

constructor TWaylandRegistry.Create(ADisplay: IWaylandDisplay;
  AQueue: IWaylandEventQueue);
begin
  inherited Create(ADisplay, AQueue, -1);
end;

procedure TWaylandDisplay.HandleError(var Msg: TWaylandEventMessage);
begin
  with Msg.Args do
  begin
    WriteLn('objectid: ', ReadDWord);
    WriteLn('code: ', ReadDWord);
    WriteLn('message: ', ReadString);
  end;
  Msg.SetHandled;
end;

procedure TWaylandDisplay.HandleDeleteId(var Msg: TWaylandEventMessage);
var
  lDeleting: Cardinal;
begin
  with Msg.Args do
  begin
    lDeleting := ReadDWord;
    Connection.ObjectDestroying(lDeleting);
    WriteLn('Deleted ID:  ', lDeleting);
  end;
  Msg.SetHandled;

end;

procedure TWaylandDisplay.Sync; // this is supposed to return a new callback
var
  lCallback: IWaylandCallback;
begin
  lCallback := TWaylandCallback.Create(Self, GetQueue);
  Connection.SendRequest(GetObjectId, 0, [lCallback]);

  // this code should no be here.
  while not (lCallback as TWaylandCallback).Done do
   Connection.WaitMessage(0);

  lCallback._Release;
end;

function TWaylandDisplay.GetRegistry: IWaylandRegistry;
begin
  if not Assigned(FRegistry) then
  begin
    FRegistry := TWaylandRegistry.Create(Self, GetQueue);
    Connection.SendRequest(GetObjectId, 1, [FRegistry.GetObjectId]);
  end;
  Result := FRegistry;
end;

end.

