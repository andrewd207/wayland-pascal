unit ext_workspace_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TExtWorkspaceHandleV1Class = class of TExtWorkspaceHandleV1;
  { TExtWorkspaceHandleV1 }
  TExtWorkspaceHandleV1 = class;

  TExtWorkspaceGroupHandleV1Class = class of TExtWorkspaceGroupHandleV1;
  { TExtWorkspaceGroupHandleV1 }
  TExtWorkspaceGroupHandleV1 = class;

  TExtWorkspaceManagerV1Class = class of TExtWorkspaceManagerV1;
  { TExtWorkspaceManagerV1 }
  TExtWorkspaceManagerV1 = class;

  IExtWorkspaceManagerV1Listener = interface;

  [TWLIntfAttribute('commit(),stop()', 'workspace_group(n),workspace(n),done(),finished()')]
  { TExtWorkspaceManagerV1 }
  TExtWorkspaceManagerV1 = class(TWaylandBase)
  public type
    TWorkspaceGroupEvent = procedure(Sender: TExtWorkspaceManagerV1; aWorkspaceGroup: TExtWorkspaceGroupHandleV1) of object;
    TWorkspaceEvent = procedure(Sender: TExtWorkspaceManagerV1; aWorkspace: TExtWorkspaceHandleV1) of object;
    TDoneEvent = procedure(Sender: TExtWorkspaceManagerV1) of object;
    TFinishedEvent = procedure(Sender: TExtWorkspaceManagerV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_COMMIT = 0, _STOP = 1);
    TEvents = (EV_WORKSPACE_GROUP = 0, EV_WORKSPACE = 1, EV_DONE = 2, EV_FINISHED = 3);
  private
    FOnWorkspaceGroupPriv: TWorkspaceGroupEvent;
    FOnWorkspacePriv: TWorkspaceEvent;
    FOnDonePriv: TDoneEvent;
    FOnFinishedPriv: TFinishedEvent;
  protected
    procedure HandleWorkspaceGroup(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_WORKSPACE_GROUP); virtual;
    procedure HandleWorkspace(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_WORKSPACE); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleFinished(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FINISHED); virtual;
  published
    property OnWorkspaceGroup: TWorkspaceGroupEvent read FOnWorkspaceGroupPriv write FOnWorkspaceGroupPriv;
    property OnWorkspace: TWorkspaceEvent read FOnWorkspacePriv write FOnWorkspacePriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnFinished: TFinishedEvent read FOnFinishedPriv write FOnFinishedPriv;
  public
    procedure Commit;
    procedure Stop;
  private
    FListeners: array of IExtWorkspaceManagerV1Listener;
  public
    function AddListener(AIntf: IExtWorkspaceManagerV1Listener): LongInt;
  end;

  IExtWorkspaceManagerV1Listener = interface
  ['IExtWorkspaceManagerV1Listener']
    procedure ext_workspace_manager_v1_workspace_group(AExtWorkspaceManagerV1: TExtWorkspaceManagerV1; aWorkspaceGroup: TExtWorkspaceGroupHandleV1);
    procedure ext_workspace_manager_v1_workspace(AExtWorkspaceManagerV1: TExtWorkspaceManagerV1; aWorkspace: TExtWorkspaceHandleV1);
    procedure ext_workspace_manager_v1_done(AExtWorkspaceManagerV1: TExtWorkspaceManagerV1);
    procedure ext_workspace_manager_v1_finished(AExtWorkspaceManagerV1: TExtWorkspaceManagerV1);
  end;

  IExtWorkspaceGroupHandleV1Listener = interface;

  [TWLIntfAttribute('create_workspace(s),destroy()', 'capabilities(u),output_enter(o),output_leave(o),workspace_enter(o),workspace_leave(o),removed()')]
  { TExtWorkspaceGroupHandleV1 }
  TExtWorkspaceGroupHandleV1 = class(TWaylandBase)
  public type
    { TExtWorkspaceGroupHandleV1.TGroupCapabilities }
    TGroupCapabilities = object(TBitfield)
    public
      property CreateWorkspace: Boolean  index 1 read GetValue write SetValue;
    end;

    TCapabilitiesEvent = procedure(Sender: TExtWorkspaceGroupHandleV1; aCapabilities: TGroupCapabilities) of object;
    TOutputEnterEvent = procedure(Sender: TExtWorkspaceGroupHandleV1; aOutput: TWlOutput) of object;
    TOutputLeaveEvent = procedure(Sender: TExtWorkspaceGroupHandleV1; aOutput: TWlOutput) of object;
    TWorkspaceEnterEvent = procedure(Sender: TExtWorkspaceGroupHandleV1; aWorkspace: TExtWorkspaceHandleV1) of object;
    TWorkspaceLeaveEvent = procedure(Sender: TExtWorkspaceGroupHandleV1; aWorkspace: TExtWorkspaceHandleV1) of object;
    TRemovedEvent = procedure(Sender: TExtWorkspaceGroupHandleV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE_WORKSPACE = 0, _DESTROY = 1);
    TEvents = (EV_CAPABILITIES = 0, EV_OUTPUT_ENTER = 1, EV_OUTPUT_LEAVE = 2, EV_WORKSPACE_ENTER = 3, EV_WORKSPACE_LEAVE = 4, EV_REMOVED = 5);
  private
    FOnCapabilitiesPriv: TCapabilitiesEvent;
    FOnOutputEnterPriv: TOutputEnterEvent;
    FOnOutputLeavePriv: TOutputLeaveEvent;
    FOnWorkspaceEnterPriv: TWorkspaceEnterEvent;
    FOnWorkspaceLeavePriv: TWorkspaceLeaveEvent;
    FOnRemovedPriv: TRemovedEvent;
  protected
    procedure HandleCapabilities(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CAPABILITIES); virtual;
    procedure HandleOutputEnter(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_OUTPUT_ENTER); virtual;
    procedure HandleOutputLeave(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_OUTPUT_LEAVE); virtual;
    procedure HandleWorkspaceEnter(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_WORKSPACE_ENTER); virtual;
    procedure HandleWorkspaceLeave(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_WORKSPACE_LEAVE); virtual;
    procedure HandleRemoved(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_REMOVED); virtual;
  published
    property OnCapabilities: TCapabilitiesEvent read FOnCapabilitiesPriv write FOnCapabilitiesPriv;
    property OnOutputEnter: TOutputEnterEvent read FOnOutputEnterPriv write FOnOutputEnterPriv;
    property OnOutputLeave: TOutputLeaveEvent read FOnOutputLeavePriv write FOnOutputLeavePriv;
    property OnWorkspaceEnter: TWorkspaceEnterEvent read FOnWorkspaceEnterPriv write FOnWorkspaceEnterPriv;
    property OnWorkspaceLeave: TWorkspaceLeaveEvent read FOnWorkspaceLeavePriv write FOnWorkspaceLeavePriv;
    property OnRemoved: TRemovedEvent read FOnRemovedPriv write FOnRemovedPriv;
  public
    procedure CreateWorkspace(aWorkspace: String);
    destructor Destroy; override;
  private
    FListeners: array of IExtWorkspaceGroupHandleV1Listener;
  public
    function AddListener(AIntf: IExtWorkspaceGroupHandleV1Listener): LongInt;
  end;

  IExtWorkspaceGroupHandleV1Listener = interface
  ['IExtWorkspaceGroupHandleV1Listener']
    procedure ext_workspace_group_handle_v1_capabilities(AExtWorkspaceGroupHandleV1: TExtWorkspaceGroupHandleV1; aCapabilities: TExtWorkspaceGroupHandleV1.TGroupCapabilities);
    procedure ext_workspace_group_handle_v1_output_enter(AExtWorkspaceGroupHandleV1: TExtWorkspaceGroupHandleV1; aOutput: TWlOutput);
    procedure ext_workspace_group_handle_v1_output_leave(AExtWorkspaceGroupHandleV1: TExtWorkspaceGroupHandleV1; aOutput: TWlOutput);
    procedure ext_workspace_group_handle_v1_workspace_enter(AExtWorkspaceGroupHandleV1: TExtWorkspaceGroupHandleV1; aWorkspace: TExtWorkspaceHandleV1);
    procedure ext_workspace_group_handle_v1_workspace_leave(AExtWorkspaceGroupHandleV1: TExtWorkspaceGroupHandleV1; aWorkspace: TExtWorkspaceHandleV1);
    procedure ext_workspace_group_handle_v1_removed(AExtWorkspaceGroupHandleV1: TExtWorkspaceGroupHandleV1);
  end;

  IExtWorkspaceHandleV1Listener = interface;

  [TWLIntfAttribute('destroy(),activate(),deactivate(),assign(o),remove()', 'id(s),name(s),coordinates(a),state(u),capabilities(u),removed()')]
  { TExtWorkspaceHandleV1 }
  TExtWorkspaceHandleV1 = class(TWaylandBase)
  public type
    { TExtWorkspaceHandleV1.TState }
    TState = object(TBitfield)
    public
      property Active: Boolean  index 1 read GetValue write SetValue;
      property Urgent: Boolean  index 2 read GetValue write SetValue;
      property Hidden: Boolean  index 4 read GetValue write SetValue;
    end;

    { TExtWorkspaceHandleV1.TWorkspaceCapabilities }
    TWorkspaceCapabilities = object(TBitfield)
    public
      property Activate: Boolean  index 1 read GetValue write SetValue;
      property Deactivate: Boolean  index 2 read GetValue write SetValue;
      property Remove: Boolean  index 4 read GetValue write SetValue;
      property Assign: Boolean  index 8 read GetValue write SetValue;
    end;

    TIdEvent = procedure(Sender: TExtWorkspaceHandleV1; aId: String) of object;
    TNameEvent = procedure(Sender: TExtWorkspaceHandleV1; aName: String) of object;
    TCoordinatesEvent = procedure(Sender: TExtWorkspaceHandleV1; aCoordinates: TBytes) of object;
    TStateEvent = procedure(Sender: TExtWorkspaceHandleV1; aState: TState) of object;
    TCapabilitiesEvent = procedure(Sender: TExtWorkspaceHandleV1; aCapabilities: TWorkspaceCapabilities) of object;
    TRemovedEvent = procedure(Sender: TExtWorkspaceHandleV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _ACTIVATE = 1, _DEACTIVATE = 2, _ASSIGN = 3, _REMOVE = 4);
    TEvents = (EV_ID = 0, EV_NAME = 1, EV_COORDINATES = 2, EV_STATE = 3, EV_CAPABILITIES = 4, EV_REMOVED = 5);
  private
    FOnIdPriv: TIdEvent;
    FOnNamePriv: TNameEvent;
    FOnCoordinatesPriv: TCoordinatesEvent;
    FOnStatePriv: TStateEvent;
    FOnCapabilitiesPriv: TCapabilitiesEvent;
    FOnRemovedPriv: TRemovedEvent;
  protected
    procedure HandleId(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ID); virtual;
    procedure HandleName(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_NAME); virtual;
    procedure HandleCoordinates(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_COORDINATES); virtual;
    procedure HandleState(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_STATE); virtual;
    procedure HandleCapabilities(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CAPABILITIES); virtual;
    procedure HandleRemoved(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_REMOVED); virtual;
  published
    property OnId: TIdEvent read FOnIdPriv write FOnIdPriv;
    property OnName: TNameEvent read FOnNamePriv write FOnNamePriv;
    property OnCoordinates: TCoordinatesEvent read FOnCoordinatesPriv write FOnCoordinatesPriv;
    property OnState: TStateEvent read FOnStatePriv write FOnStatePriv;
    property OnCapabilities: TCapabilitiesEvent read FOnCapabilitiesPriv write FOnCapabilitiesPriv;
    property OnRemoved: TRemovedEvent read FOnRemovedPriv write FOnRemovedPriv;
  public
    destructor Destroy; override;
    procedure Activate;
    procedure Deactivate;
    procedure Assign(aWorkspaceGroup: TExtWorkspaceGroupHandleV1);
    procedure Remove;
  private
    FListeners: array of IExtWorkspaceHandleV1Listener;
  public
    function AddListener(AIntf: IExtWorkspaceHandleV1Listener): LongInt;
  end;

  IExtWorkspaceHandleV1Listener = interface
  ['IExtWorkspaceHandleV1Listener']
    procedure ext_workspace_handle_v1_id(AExtWorkspaceHandleV1: TExtWorkspaceHandleV1; aId: String);
    procedure ext_workspace_handle_v1_name(AExtWorkspaceHandleV1: TExtWorkspaceHandleV1; aName: String);
    procedure ext_workspace_handle_v1_coordinates(AExtWorkspaceHandleV1: TExtWorkspaceHandleV1; aCoordinates: TBytes);
    procedure ext_workspace_handle_v1_state(AExtWorkspaceHandleV1: TExtWorkspaceHandleV1; aState: TExtWorkspaceHandleV1.TState);
    procedure ext_workspace_handle_v1_capabilities(AExtWorkspaceHandleV1: TExtWorkspaceHandleV1; aCapabilities: TExtWorkspaceHandleV1.TWorkspaceCapabilities);
    procedure ext_workspace_handle_v1_removed(AExtWorkspaceHandleV1: TExtWorkspaceHandleV1);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TExtWorkspaceManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtWorkspaceManagerV1.GetInterfaceName: String;
begin
  Result := 'ext_workspace_manager_v1';
end;

procedure TExtWorkspaceManagerV1.HandleWorkspaceGroup(var AMsg: TWaylandEventMessage);
var
  lWorkspaceGroup: TExtWorkspaceGroupHandleV1;
  lListenerIdx: Integer;
begin
  lWorkspaceGroup := TExtWorkspaceGroupHandleV1.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnWorkspaceGroup) then OnWorkspaceGroup(Self,lWorkspaceGroup);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_manager_v1_workspace_group(Self,lWorkspaceGroup);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceManagerV1.HandleWorkspace(var AMsg: TWaylandEventMessage);
var
  lWorkspace: TExtWorkspaceHandleV1;
  lListenerIdx: Integer;
begin
  lWorkspace := TExtWorkspaceHandleV1.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnWorkspace) then OnWorkspace(Self,lWorkspace);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_manager_v1_workspace(Self,lWorkspace);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceManagerV1.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_manager_v1_done(Self);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceManagerV1.HandleFinished(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnFinished) then OnFinished(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_manager_v1_finished(Self);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceManagerV1.Commit;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._COMMIT), []);
end;

procedure TExtWorkspaceManagerV1.Stop;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._STOP), []);
end;

function TExtWorkspaceManagerV1.AddListener(AIntf: IExtWorkspaceManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TExtWorkspaceGroupHandleV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtWorkspaceGroupHandleV1.GetInterfaceName: String;
begin
  Result := 'ext_workspace_group_handle_v1';
end;

procedure TExtWorkspaceGroupHandleV1.HandleCapabilities(var AMsg: TWaylandEventMessage);
var
  lCapabilities: TGroupCapabilities;
  lListenerIdx: Integer;
begin
  lCapabilities := TGroupCapabilities(AMsg.Args.ReadDWord);
  if Assigned(OnCapabilities) then OnCapabilities(Self,lCapabilities);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_group_handle_v1_capabilities(Self,lCapabilities);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceGroupHandleV1.HandleOutputEnter(var AMsg: TWaylandEventMessage);
var
  lOutput: TWlOutput;
  lListenerIdx: Integer;
begin
  lOutput := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlOutput);
  if Assigned(OnOutputEnter) then OnOutputEnter(Self,lOutput);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_group_handle_v1_output_enter(Self,lOutput);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceGroupHandleV1.HandleOutputLeave(var AMsg: TWaylandEventMessage);
var
  lOutput: TWlOutput;
  lListenerIdx: Integer;
begin
  lOutput := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlOutput);
  if Assigned(OnOutputLeave) then OnOutputLeave(Self,lOutput);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_group_handle_v1_output_leave(Self,lOutput);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceGroupHandleV1.HandleWorkspaceEnter(var AMsg: TWaylandEventMessage);
var
  lWorkspace: TExtWorkspaceHandleV1;
  lListenerIdx: Integer;
begin
  lWorkspace := (Connection.GetObject(AMsg.Args.ReadDWord) as TExtWorkspaceHandleV1);
  if Assigned(OnWorkspaceEnter) then OnWorkspaceEnter(Self,lWorkspace);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_group_handle_v1_workspace_enter(Self,lWorkspace);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceGroupHandleV1.HandleWorkspaceLeave(var AMsg: TWaylandEventMessage);
var
  lWorkspace: TExtWorkspaceHandleV1;
  lListenerIdx: Integer;
begin
  lWorkspace := (Connection.GetObject(AMsg.Args.ReadDWord) as TExtWorkspaceHandleV1);
  if Assigned(OnWorkspaceLeave) then OnWorkspaceLeave(Self,lWorkspace);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_group_handle_v1_workspace_leave(Self,lWorkspace);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceGroupHandleV1.HandleRemoved(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnRemoved) then OnRemoved(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_group_handle_v1_removed(Self);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceGroupHandleV1.CreateWorkspace(aWorkspace: String);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_WORKSPACE), [aWorkspace]);
end;

destructor TExtWorkspaceGroupHandleV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TExtWorkspaceGroupHandleV1.AddListener(AIntf: IExtWorkspaceGroupHandleV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TExtWorkspaceHandleV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtWorkspaceHandleV1.GetInterfaceName: String;
begin
  Result := 'ext_workspace_handle_v1';
end;

procedure TExtWorkspaceHandleV1.HandleId(var AMsg: TWaylandEventMessage);
var
  lId: String;
  lListenerIdx: Integer;
begin
  lId := AMsg.Args.ReadString;
  if Assigned(OnId) then OnId(Self,lId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_handle_v1_id(Self,lId);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceHandleV1.HandleName(var AMsg: TWaylandEventMessage);
var
  lName: String;
  lListenerIdx: Integer;
begin
  lName := AMsg.Args.ReadString;
  if Assigned(OnName) then OnName(Self,lName);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_handle_v1_name(Self,lName);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceHandleV1.HandleCoordinates(var AMsg: TWaylandEventMessage);
var
  lCoordinates: TBytes;
  lListenerIdx: Integer;
begin
  lCoordinates := AMsg.Args.ReadBlob;
  if Assigned(OnCoordinates) then OnCoordinates(Self,lCoordinates);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_handle_v1_coordinates(Self,lCoordinates);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceHandleV1.HandleState(var AMsg: TWaylandEventMessage);
var
  lState: TState;
  lListenerIdx: Integer;
begin
  lState := TState(AMsg.Args.ReadDWord);
  if Assigned(OnState) then OnState(Self,lState);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_handle_v1_state(Self,lState);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceHandleV1.HandleCapabilities(var AMsg: TWaylandEventMessage);
var
  lCapabilities: TWorkspaceCapabilities;
  lListenerIdx: Integer;
begin
  lCapabilities := TWorkspaceCapabilities(AMsg.Args.ReadDWord);
  if Assigned(OnCapabilities) then OnCapabilities(Self,lCapabilities);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_handle_v1_capabilities(Self,lCapabilities);
  AMsg.SetHandled;
end;

procedure TExtWorkspaceHandleV1.HandleRemoved(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnRemoved) then OnRemoved(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_workspace_handle_v1_removed(Self);
  AMsg.SetHandled;
end;

destructor TExtWorkspaceHandleV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TExtWorkspaceHandleV1.Activate;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._ACTIVATE), []);
end;

procedure TExtWorkspaceHandleV1.Deactivate;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DEACTIVATE), []);
end;

procedure TExtWorkspaceHandleV1.Assign(aWorkspaceGroup: TExtWorkspaceGroupHandleV1);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._ASSIGN), [aWorkspaceGroup.GetObjectId]);
end;

procedure TExtWorkspaceHandleV1.Remove;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._REMOVE), []);
end;

function TExtWorkspaceHandleV1.AddListener(AIntf: IExtWorkspaceHandleV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.