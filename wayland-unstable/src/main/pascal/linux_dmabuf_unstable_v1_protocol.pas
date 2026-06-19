unit linux_dmabuf_unstable_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpLinuxDmabufFeedbackV1Class = class of TWpLinuxDmabufFeedbackV1;
  { TWpLinuxDmabufFeedbackV1 }
  TWpLinuxDmabufFeedbackV1 = class;

  TWpLinuxBufferParamsV1Class = class of TWpLinuxBufferParamsV1;
  { TWpLinuxBufferParamsV1 }
  TWpLinuxBufferParamsV1 = class;

  TWpLinuxDmabufV1Class = class of TWpLinuxDmabufV1;
  { TWpLinuxDmabufV1 }
  TWpLinuxDmabufV1 = class;

  IWpLinuxDmabufV1Listener = interface;

  [TWLIntfAttribute('destroy(),create_params(n),get_default_feedback(n),get_surface_feedback(no)', 'format(u),modifier(uuu)')]
  { TWpLinuxDmabufV1 }
  TWpLinuxDmabufV1 = class(TWaylandBase)
  public type
    TFormatEvent = procedure(Sender: TWpLinuxDmabufV1; aFormat: DWord) of object;
    TModifierEvent = procedure(Sender: TWpLinuxDmabufV1; aFormat: DWord; aModifierHi: DWord; aModifierLo: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _CREATE_PARAMS = 1, _GET_DEFAULT_FEEDBACK = 2, _GET_SURFACE_FEEDBACK = 3);
    TEvents = (EV_FORMAT = 0, EV_MODIFIER = 1);
  private
    FOnFormatPriv: TFormatEvent;
    FOnModifierPriv: TModifierEvent;
  protected
    procedure HandleFormat(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FORMAT); virtual;
    procedure HandleModifier(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_MODIFIER); virtual;
  published
    property OnFormat: TFormatEvent read FOnFormatPriv write FOnFormatPriv;
    property OnModifier: TModifierEvent read FOnModifierPriv write FOnModifierPriv;
  public
    destructor Destroy; override;
    function CreateParams(aClassType: TWpLinuxBufferParamsV1Class = nil): TWpLinuxBufferParamsV1;
    function GetDefaultFeedback(aClassType: TWpLinuxDmabufFeedbackV1Class = nil): TWpLinuxDmabufFeedbackV1;
    function GetSurfaceFeedback(aSurface: TWlSurface; aClassType: TWpLinuxDmabufFeedbackV1Class = nil): TWpLinuxDmabufFeedbackV1;
  private
    FListeners: array of IWpLinuxDmabufV1Listener;
  public
    function AddListener(AIntf: IWpLinuxDmabufV1Listener): LongInt;
  end;

  IWpLinuxDmabufV1Listener = interface
  ['IWpLinuxDmabufV1Listener']
    procedure wp_linux_dmabuf_v1_format(AWpLinuxDmabufV1: TWpLinuxDmabufV1; aFormat: DWord);
    procedure wp_linux_dmabuf_v1_modifier(AWpLinuxDmabufV1: TWpLinuxDmabufV1; aFormat: DWord; aModifierHi: DWord; aModifierLo: DWord);
  end;

  IWpLinuxBufferParamsV1Listener = interface;

  [TWLIntfAttribute('destroy(),add(huuuuu),create(iiuu),create_immed(niiuu)', 'created(n),failed()')]
  { TWpLinuxBufferParamsV1 }
  TWpLinuxBufferParamsV1 = class(TWaylandBase)
  public type
    TError = (erAlreadyused = 0, erPlaneidx = 1, erPlaneset = 2, erIncomplete = 3, erInvalidformat = 4, erInvaliddimensions = 5, erOutofbounds = 6, erInvalidwlbuffer = 7);
    { TWpLinuxBufferParamsV1.TFlags }
    TFlags = object(TBitfield)
    public
      property YInvert: Boolean  index 1 read GetValue write SetValue;
      property Interlaced: Boolean  index 2 read GetValue write SetValue;
      property BottomFirst: Boolean  index 4 read GetValue write SetValue;
    end;

    TCreatedEvent = procedure(Sender: TWpLinuxBufferParamsV1; aBuffer: TWlBuffer) of object;
    TFailedEvent = procedure(Sender: TWpLinuxBufferParamsV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _ADD = 1, _CREATE = 2, _CREATE_IMMED = 3);
    TEvents = (EV_CREATED = 0, EV_FAILED = 1);
  private
    FOnCreatedPriv: TCreatedEvent;
    FOnFailedPriv: TFailedEvent;
  protected
    procedure HandleCreated(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CREATED); virtual;
    procedure HandleFailed(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FAILED); virtual;
  published
    property OnCreated: TCreatedEvent read FOnCreatedPriv write FOnCreatedPriv;
    property OnFailed: TFailedEvent read FOnFailedPriv write FOnFailedPriv;
  public
    destructor Destroy; override;
    procedure Add(aFd: Integer; aPlaneIdx: DWord; aOffset: DWord; aStride: DWord; aModifierHi: DWord; aModifierLo: DWord);
    procedure Create_(aWidth: Integer; aHeight: Integer; aFormat: DWord; aFlags: TFlags);
    function CreateImmed(aWidth: Integer; aHeight: Integer; aFormat: DWord; aFlags: TFlags; aClassType: TWlBufferClass = nil): TWlBuffer;
  private
    FListeners: array of IWpLinuxBufferParamsV1Listener;
  public
    function AddListener(AIntf: IWpLinuxBufferParamsV1Listener): LongInt;
  end;

  IWpLinuxBufferParamsV1Listener = interface
  ['IWpLinuxBufferParamsV1Listener']
    procedure wp_linux_buffer_params_v1_created(AWpLinuxBufferParamsV1: TWpLinuxBufferParamsV1; aBuffer: TWlBuffer);
    procedure wp_linux_buffer_params_v1_failed(AWpLinuxBufferParamsV1: TWpLinuxBufferParamsV1);
  end;

  IWpLinuxDmabufFeedbackV1Listener = interface;

  [TWLIntfAttribute('destroy()', 'done(),format_table(hu),main_device(a),tranche_done(),tranche_target_device(a),tranche_formats(a),tranche_flags(u)')]
  { TWpLinuxDmabufFeedbackV1 }
  TWpLinuxDmabufFeedbackV1 = class(TWaylandBase)
  public type
    { TWpLinuxDmabufFeedbackV1.TTrancheFlags }
    TTrancheFlags = object(TBitfield)
    public
      property Scanout: Boolean  index 1 read GetValue write SetValue;
    end;

    TDoneEvent = procedure(Sender: TWpLinuxDmabufFeedbackV1) of object;
    TFormatTableEvent = procedure(Sender: TWpLinuxDmabufFeedbackV1; aFd: TWaylandFdStream; aSize: DWord) of object;
    TMainDeviceEvent = procedure(Sender: TWpLinuxDmabufFeedbackV1; aDevice: TBytes) of object;
    TTrancheDoneEvent = procedure(Sender: TWpLinuxDmabufFeedbackV1) of object;
    TTrancheTargetDeviceEvent = procedure(Sender: TWpLinuxDmabufFeedbackV1; aDevice: TBytes) of object;
    TTrancheFormatsEvent = procedure(Sender: TWpLinuxDmabufFeedbackV1; aIndices: TBytes) of object;
    TTrancheFlagsEvent = procedure(Sender: TWpLinuxDmabufFeedbackV1; aFlags: TTrancheFlags) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_DONE = 0, EV_FORMAT_TABLE = 1, EV_MAIN_DEVICE = 2, EV_TRANCHE_DONE = 3, EV_TRANCHE_TARGET_DEVICE = 4, EV_TRANCHE_FORMATS = 5, EV_TRANCHE_FLAGS = 6);
  private
    FOnDonePriv: TDoneEvent;
    FOnFormatTablePriv: TFormatTableEvent;
    FOnMainDevicePriv: TMainDeviceEvent;
    FOnTrancheDonePriv: TTrancheDoneEvent;
    FOnTrancheTargetDevicePriv: TTrancheTargetDeviceEvent;
    FOnTrancheFormatsPriv: TTrancheFormatsEvent;
    FOnTrancheFlagsPriv: TTrancheFlagsEvent;
  protected
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleFormatTable(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FORMAT_TABLE); virtual;
    procedure HandleMainDevice(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_MAIN_DEVICE); virtual;
    procedure HandleTrancheDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TRANCHE_DONE); virtual;
    procedure HandleTrancheTargetDevice(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TRANCHE_TARGET_DEVICE); virtual;
    procedure HandleTrancheFormats(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TRANCHE_FORMATS); virtual;
    procedure HandleTrancheFlags(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TRANCHE_FLAGS); virtual;
  published
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnFormatTable: TFormatTableEvent read FOnFormatTablePriv write FOnFormatTablePriv;
    property OnMainDevice: TMainDeviceEvent read FOnMainDevicePriv write FOnMainDevicePriv;
    property OnTrancheDone: TTrancheDoneEvent read FOnTrancheDonePriv write FOnTrancheDonePriv;
    property OnTrancheTargetDevice: TTrancheTargetDeviceEvent read FOnTrancheTargetDevicePriv write FOnTrancheTargetDevicePriv;
    property OnTrancheFormats: TTrancheFormatsEvent read FOnTrancheFormatsPriv write FOnTrancheFormatsPriv;
    property OnTrancheFlags: TTrancheFlagsEvent read FOnTrancheFlagsPriv write FOnTrancheFlagsPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWpLinuxDmabufFeedbackV1Listener;
  public
    function AddListener(AIntf: IWpLinuxDmabufFeedbackV1Listener): LongInt;
  end;

  IWpLinuxDmabufFeedbackV1Listener = interface
  ['IWpLinuxDmabufFeedbackV1Listener']
    procedure wp_linux_dmabuf_feedback_v1_done(AWpLinuxDmabufFeedbackV1: TWpLinuxDmabufFeedbackV1);
    procedure wp_linux_dmabuf_feedback_v1_format_table(AWpLinuxDmabufFeedbackV1: TWpLinuxDmabufFeedbackV1; aFd: TWaylandFdStream; aSize: DWord);
    procedure wp_linux_dmabuf_feedback_v1_main_device(AWpLinuxDmabufFeedbackV1: TWpLinuxDmabufFeedbackV1; aDevice: TBytes);
    procedure wp_linux_dmabuf_feedback_v1_tranche_done(AWpLinuxDmabufFeedbackV1: TWpLinuxDmabufFeedbackV1);
    procedure wp_linux_dmabuf_feedback_v1_tranche_target_device(AWpLinuxDmabufFeedbackV1: TWpLinuxDmabufFeedbackV1; aDevice: TBytes);
    procedure wp_linux_dmabuf_feedback_v1_tranche_formats(AWpLinuxDmabufFeedbackV1: TWpLinuxDmabufFeedbackV1; aIndices: TBytes);
    procedure wp_linux_dmabuf_feedback_v1_tranche_flags(AWpLinuxDmabufFeedbackV1: TWpLinuxDmabufFeedbackV1; aFlags: TWpLinuxDmabufFeedbackV1.TTrancheFlags);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpLinuxDmabufV1.GetInterfaceVersion: Integer;
begin
  Result := 5;
end;

class function TWpLinuxDmabufV1.GetInterfaceName: String;
begin
  Result := 'zwp_linux_dmabuf_v1';
end;

procedure TWpLinuxDmabufV1.HandleFormat(var AMsg: TWaylandEventMessage);
var
  lFormat: DWord;
  lListenerIdx: Integer;
begin
  lFormat := AMsg.Args.ReadDWord;
  if Assigned(OnFormat) then OnFormat(Self,lFormat);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_dmabuf_v1_format(Self,lFormat);
  AMsg.SetHandled;
end;

procedure TWpLinuxDmabufV1.HandleModifier(var AMsg: TWaylandEventMessage);
var
  lFormat: DWord;
  lModifierHi: DWord;
  lModifierLo: DWord;
  lListenerIdx: Integer;
begin
  lFormat := AMsg.Args.ReadDWord;
  lModifierHi := AMsg.Args.ReadDWord;
  lModifierLo := AMsg.Args.ReadDWord;
  if Assigned(OnModifier) then OnModifier(Self,lFormat,lModifierHi,lModifierLo);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_dmabuf_v1_modifier(Self,lFormat,lModifierHi,lModifierLo);
  AMsg.SetHandled;
end;

destructor TWpLinuxDmabufV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpLinuxDmabufV1.CreateParams(aClassType: TWpLinuxBufferParamsV1Class = nil): TWpLinuxBufferParamsV1;
begin
  if aClassType = nil then aClassType := TWpLinuxBufferParamsV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_PARAMS), [Result.GetObjectId]);
end;

function TWpLinuxDmabufV1.GetDefaultFeedback(aClassType: TWpLinuxDmabufFeedbackV1Class = nil): TWpLinuxDmabufFeedbackV1;
begin
  if aClassType = nil then aClassType := TWpLinuxDmabufFeedbackV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_DEFAULT_FEEDBACK), [Result.GetObjectId]);
end;

function TWpLinuxDmabufV1.GetSurfaceFeedback(aSurface: TWlSurface; aClassType: TWpLinuxDmabufFeedbackV1Class = nil): TWpLinuxDmabufFeedbackV1;
begin
  if aClassType = nil then aClassType := TWpLinuxDmabufFeedbackV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_SURFACE_FEEDBACK), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TWpLinuxDmabufV1.AddListener(AIntf: IWpLinuxDmabufV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpLinuxBufferParamsV1.GetInterfaceVersion: Integer;
begin
  Result := 5;
end;

class function TWpLinuxBufferParamsV1.GetInterfaceName: String;
begin
  Result := 'zwp_linux_buffer_params_v1';
end;

procedure TWpLinuxBufferParamsV1.HandleCreated(var AMsg: TWaylandEventMessage);
var
  lBuffer: TWlBuffer;
  lListenerIdx: Integer;
begin
  lBuffer := TWlBuffer.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnCreated) then OnCreated(Self,lBuffer);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_buffer_params_v1_created(Self,lBuffer);
  AMsg.SetHandled;
end;

procedure TWpLinuxBufferParamsV1.HandleFailed(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnFailed) then OnFailed(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_buffer_params_v1_failed(Self);
  AMsg.SetHandled;
end;

destructor TWpLinuxBufferParamsV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWpLinuxBufferParamsV1.Add(aFd: Integer; aPlaneIdx: DWord; aOffset: DWord; aStride: DWord; aModifierHi: DWord; aModifierLo: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._ADD), [aFd,aPlaneIdx,aOffset,aStride,aModifierHi,aModifierLo], 0);
end;

procedure TWpLinuxBufferParamsV1.Create_(aWidth: Integer; aHeight: Integer; aFormat: DWord; aFlags: TFlags);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE), [aWidth,aHeight,aFormat,DWord(aFlags)]);
end;

function TWpLinuxBufferParamsV1.CreateImmed(aWidth: Integer; aHeight: Integer; aFormat: DWord; aFlags: TFlags; aClassType: TWlBufferClass = nil): TWlBuffer;
begin
  if aClassType = nil then aClassType := TWlBuffer;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_IMMED), [Result.GetObjectId,aWidth,aHeight,aFormat,DWord(aFlags)]);
end;

function TWpLinuxBufferParamsV1.AddListener(AIntf: IWpLinuxBufferParamsV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpLinuxDmabufFeedbackV1.GetInterfaceVersion: Integer;
begin
  Result := 5;
end;

class function TWpLinuxDmabufFeedbackV1.GetInterfaceName: String;
begin
  Result := 'zwp_linux_dmabuf_feedback_v1';
end;

procedure TWpLinuxDmabufFeedbackV1.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_dmabuf_feedback_v1_done(Self);
  AMsg.SetHandled;
end;

procedure TWpLinuxDmabufFeedbackV1.HandleFormatTable(var AMsg: TWaylandEventMessage);
var
  lFd: TWaylandFdStream;
  lSize: DWord;
  lListenerIdx: Integer;
begin
  lFd := AMsg.NextFdStream;
  lSize := AMsg.Args.ReadDWord;
  if Assigned(OnFormatTable) then OnFormatTable(Self,lFd,lSize);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_dmabuf_feedback_v1_format_table(Self,lFd,lSize);
  AMsg.SetHandled;
end;

procedure TWpLinuxDmabufFeedbackV1.HandleMainDevice(var AMsg: TWaylandEventMessage);
var
  lDevice: TBytes;
  lListenerIdx: Integer;
begin
  lDevice := AMsg.Args.ReadBlob;
  if Assigned(OnMainDevice) then OnMainDevice(Self,lDevice);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_dmabuf_feedback_v1_main_device(Self,lDevice);
  AMsg.SetHandled;
end;

procedure TWpLinuxDmabufFeedbackV1.HandleTrancheDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnTrancheDone) then OnTrancheDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_dmabuf_feedback_v1_tranche_done(Self);
  AMsg.SetHandled;
end;

procedure TWpLinuxDmabufFeedbackV1.HandleTrancheTargetDevice(var AMsg: TWaylandEventMessage);
var
  lDevice: TBytes;
  lListenerIdx: Integer;
begin
  lDevice := AMsg.Args.ReadBlob;
  if Assigned(OnTrancheTargetDevice) then OnTrancheTargetDevice(Self,lDevice);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_dmabuf_feedback_v1_tranche_target_device(Self,lDevice);
  AMsg.SetHandled;
end;

procedure TWpLinuxDmabufFeedbackV1.HandleTrancheFormats(var AMsg: TWaylandEventMessage);
var
  lIndices: TBytes;
  lListenerIdx: Integer;
begin
  lIndices := AMsg.Args.ReadBlob;
  if Assigned(OnTrancheFormats) then OnTrancheFormats(Self,lIndices);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_dmabuf_feedback_v1_tranche_formats(Self,lIndices);
  AMsg.SetHandled;
end;

procedure TWpLinuxDmabufFeedbackV1.HandleTrancheFlags(var AMsg: TWaylandEventMessage);
var
  lFlags: TTrancheFlags;
  lListenerIdx: Integer;
begin
  lFlags := TTrancheFlags(AMsg.Args.ReadDWord);
  if Assigned(OnTrancheFlags) then OnTrancheFlags(Self,lFlags);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_linux_dmabuf_feedback_v1_tranche_flags(Self,lFlags);
  AMsg.SetHandled;
end;

destructor TWpLinuxDmabufFeedbackV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpLinuxDmabufFeedbackV1.AddListener(AIntf: IWpLinuxDmabufFeedbackV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.