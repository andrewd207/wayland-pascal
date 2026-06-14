unit relative_pointer_unstable_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpRelativePointerV1Class = class of TWpRelativePointerV1;
  { TWpRelativePointerV1 }
  TWpRelativePointerV1 = class;

  TWpRelativePointerManagerV1Class = class of TWpRelativePointerManagerV1;
  { TWpRelativePointerManagerV1 }
  TWpRelativePointerManagerV1 = class;

  IWpRelativePointerManagerV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_relative_pointer(no)', '')]
  { TWpRelativePointerManagerV1 }
  TWpRelativePointerManagerV1 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_RELATIVE_POINTER = 1);
  public
    destructor Destroy; override;
    function GetRelativePointer(aPointer: TWlPointer; aClassType: TWpRelativePointerV1Class = nil): TWpRelativePointerV1;
  private
    FListeners: array of IWpRelativePointerManagerV1Listener;
  public
    function AddListener(AIntf: IWpRelativePointerManagerV1Listener): LongInt;
  end;

  IWpRelativePointerManagerV1Listener = interface
  ['IWpRelativePointerManagerV1Listener']
  end;

  IWpRelativePointerV1Listener = interface;

  [TWLIntfAttribute('destroy()', 'relative_motion(uuffff)')]
  { TWpRelativePointerV1 }
  TWpRelativePointerV1 = class(TWaylandBase)
  public type
    TRelativeMotionEvent = procedure(Sender: TWpRelativePointerV1; aUtimeHi: DWord; aUtimeLo: DWord; aDx: TWaylandFixed; aDy: TWaylandFixed; aDxUnaccel: TWaylandFixed; aDyUnaccel: TWaylandFixed) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_RELATIVE_MOTION = 0);
  private
    FOnRelativeMotionPriv: TRelativeMotionEvent;
  protected
    procedure HandleRelativeMotion(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_RELATIVE_MOTION); virtual;
  published
    property OnRelativeMotion: TRelativeMotionEvent read FOnRelativeMotionPriv write FOnRelativeMotionPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWpRelativePointerV1Listener;
  public
    function AddListener(AIntf: IWpRelativePointerV1Listener): LongInt;
  end;

  IWpRelativePointerV1Listener = interface
  ['IWpRelativePointerV1Listener']
    procedure wp_relative_pointer_v1_relative_motion(AWpRelativePointerV1: TWpRelativePointerV1; aUtimeHi: DWord; aUtimeLo: DWord; aDx: TWaylandFixed; aDy: TWaylandFixed; aDxUnaccel: TWaylandFixed; aDyUnaccel: TWaylandFixed);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpRelativePointerManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpRelativePointerManagerV1.GetInterfaceName: String;
begin
  Result := 'zwp_relative_pointer_manager_v1';
end;

destructor TWpRelativePointerManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpRelativePointerManagerV1.GetRelativePointer(aPointer: TWlPointer; aClassType: TWpRelativePointerV1Class = nil): TWpRelativePointerV1;
begin
  if aClassType = nil then aClassType := TWpRelativePointerV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_RELATIVE_POINTER), [Result.GetObjectId,aPointer.GetObjectId]);
end;

function TWpRelativePointerManagerV1.AddListener(AIntf: IWpRelativePointerManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpRelativePointerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWpRelativePointerV1.GetInterfaceName: String;
begin
  Result := 'zwp_relative_pointer_v1';
end;

procedure TWpRelativePointerV1.HandleRelativeMotion(var AMsg: TWaylandEventMessage);
var
  lUtimeHi: DWord;
  lUtimeLo: DWord;
  lDx: TWaylandFixed;
  lDy: TWaylandFixed;
  lDxUnaccel: TWaylandFixed;
  lDyUnaccel: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lUtimeHi := AMsg.Args.ReadDWord;
  lUtimeLo := AMsg.Args.ReadDWord;
  lDx := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lDy := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lDxUnaccel := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lDyUnaccel := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnRelativeMotion) then OnRelativeMotion(Self,lUtimeHi,lUtimeLo,lDx,lDy,lDxUnaccel,lDyUnaccel);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_relative_pointer_v1_relative_motion(Self,lUtimeHi,lUtimeLo,lDx,lDy,lDxUnaccel,lDyUnaccel);
  AMsg.SetHandled;
end;

destructor TWpRelativePointerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpRelativePointerV1.AddListener(AIntf: IWpRelativePointerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.