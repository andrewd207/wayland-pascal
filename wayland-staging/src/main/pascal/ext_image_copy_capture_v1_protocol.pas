unit ext_image_copy_capture_v1_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland, ext_image_capture_source_v1_protocol;

type
  TExtImageCopyCaptureFrameV1Class = class of TExtImageCopyCaptureFrameV1;
  { TExtImageCopyCaptureFrameV1 }
  TExtImageCopyCaptureFrameV1 = class;

  TExtImageCopyCaptureCursorSessionV1Class = class of TExtImageCopyCaptureCursorSessionV1;
  { TExtImageCopyCaptureCursorSessionV1 }
  TExtImageCopyCaptureCursorSessionV1 = class;

  TExtImageCopyCaptureSessionV1Class = class of TExtImageCopyCaptureSessionV1;
  { TExtImageCopyCaptureSessionV1 }
  TExtImageCopyCaptureSessionV1 = class;

  TExtImageCopyCaptureManagerV1Class = class of TExtImageCopyCaptureManagerV1;
  { TExtImageCopyCaptureManagerV1 }
  TExtImageCopyCaptureManagerV1 = class;

  IExtImageCopyCaptureManagerV1Listener = interface;

  [TWLIntfAttribute('create_session(nou),create_pointer_cursor_session(noo),destroy()', '')]
  { TExtImageCopyCaptureManagerV1 }
  TExtImageCopyCaptureManagerV1 = class(TWaylandBase)
  public type
    TError = (erInvalidoption = 1);
    { TExtImageCopyCaptureManagerV1.TOptions }
    TOptions = object(TBitfield)
    public
      property PaintCursors: Boolean  index 1 read GetValue write SetValue;
    end;

  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE_SESSION = 0, _CREATE_POINTER_CURSOR_SESSION = 1, _DESTROY = 2);
  public
    function CreateSession(aSource: TExtImageCaptureSourceV1; aOptions: TOptions; aClassType: TExtImageCopyCaptureSessionV1Class = nil): TExtImageCopyCaptureSessionV1;
    function CreatePointerCursorSession(aSource: TExtImageCaptureSourceV1; aPointer: TWlPointer; aClassType: TExtImageCopyCaptureCursorSessionV1Class = nil): TExtImageCopyCaptureCursorSessionV1;
    destructor Destroy; override;
  private
    FListeners: array of IExtImageCopyCaptureManagerV1Listener;
  public
    function AddListener(AIntf: IExtImageCopyCaptureManagerV1Listener): LongInt;
  end;

  IExtImageCopyCaptureManagerV1Listener = interface
  ['IExtImageCopyCaptureManagerV1Listener']
  end;

  IExtImageCopyCaptureSessionV1Listener = interface;

  [TWLIntfAttribute('create_frame(n),destroy()', 'buffer_size(uu),shm_format(u),dmabuf_device(a),dmabuf_format(ua),done(),stopped()')]
  { TExtImageCopyCaptureSessionV1 }
  TExtImageCopyCaptureSessionV1 = class(TWaylandBase)
  public type
    TError = (erDuplicateframe = 1);
    TBufferSizeEvent = procedure(Sender: TExtImageCopyCaptureSessionV1; aWidth: DWord; aHeight: DWord) of object;
    TShmFormatEvent = procedure(Sender: TExtImageCopyCaptureSessionV1; aFormat: TWlShm.TFormat) of object;
    TDmabufDeviceEvent = procedure(Sender: TExtImageCopyCaptureSessionV1; aDevice: TBytes) of object;
    TDmabufFormatEvent = procedure(Sender: TExtImageCopyCaptureSessionV1; aFormat: DWord; aModifiers: TBytes) of object;
    TDoneEvent = procedure(Sender: TExtImageCopyCaptureSessionV1) of object;
    TStoppedEvent = procedure(Sender: TExtImageCopyCaptureSessionV1) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE_FRAME = 0, _DESTROY = 1);
    TEvents = (EV_BUFFER_SIZE = 0, EV_SHM_FORMAT = 1, EV_DMABUF_DEVICE = 2, EV_DMABUF_FORMAT = 3, EV_DONE = 4, EV_STOPPED = 5);
  private
    FOnBufferSizePriv: TBufferSizeEvent;
    FOnShmFormatPriv: TShmFormatEvent;
    FOnDmabufDevicePriv: TDmabufDeviceEvent;
    FOnDmabufFormatPriv: TDmabufFormatEvent;
    FOnDonePriv: TDoneEvent;
    FOnStoppedPriv: TStoppedEvent;
  protected
    procedure HandleBufferSize(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_BUFFER_SIZE); virtual;
    procedure HandleShmFormat(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SHM_FORMAT); virtual;
    procedure HandleDmabufDevice(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DMABUF_DEVICE); virtual;
    procedure HandleDmabufFormat(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DMABUF_FORMAT); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleStopped(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_STOPPED); virtual;
  published
    property OnBufferSize: TBufferSizeEvent read FOnBufferSizePriv write FOnBufferSizePriv;
    property OnShmFormat: TShmFormatEvent read FOnShmFormatPriv write FOnShmFormatPriv;
    property OnDmabufDevice: TDmabufDeviceEvent read FOnDmabufDevicePriv write FOnDmabufDevicePriv;
    property OnDmabufFormat: TDmabufFormatEvent read FOnDmabufFormatPriv write FOnDmabufFormatPriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnStopped: TStoppedEvent read FOnStoppedPriv write FOnStoppedPriv;
  public
    function CreateFrame(aClassType: TExtImageCopyCaptureFrameV1Class = nil): TExtImageCopyCaptureFrameV1;
    destructor Destroy; override;
  private
    FListeners: array of IExtImageCopyCaptureSessionV1Listener;
  public
    function AddListener(AIntf: IExtImageCopyCaptureSessionV1Listener): LongInt;
  end;

  IExtImageCopyCaptureSessionV1Listener = interface
  ['IExtImageCopyCaptureSessionV1Listener']
    procedure ext_image_copy_capture_session_v1_buffer_size(AExtImageCopyCaptureSessionV1: TExtImageCopyCaptureSessionV1; aWidth: DWord; aHeight: DWord);
    procedure ext_image_copy_capture_session_v1_shm_format(AExtImageCopyCaptureSessionV1: TExtImageCopyCaptureSessionV1; aFormat: TWlShm.TFormat);
    procedure ext_image_copy_capture_session_v1_dmabuf_device(AExtImageCopyCaptureSessionV1: TExtImageCopyCaptureSessionV1; aDevice: TBytes);
    procedure ext_image_copy_capture_session_v1_dmabuf_format(AExtImageCopyCaptureSessionV1: TExtImageCopyCaptureSessionV1; aFormat: DWord; aModifiers: TBytes);
    procedure ext_image_copy_capture_session_v1_done(AExtImageCopyCaptureSessionV1: TExtImageCopyCaptureSessionV1);
    procedure ext_image_copy_capture_session_v1_stopped(AExtImageCopyCaptureSessionV1: TExtImageCopyCaptureSessionV1);
  end;

  IExtImageCopyCaptureFrameV1Listener = interface;

  [TWLIntfAttribute('destroy(),attach_buffer(o),damage_buffer(iiii),capture()', 'transform(u),damage(iiii),presentation_time(uuu),ready(),failed(u)')]
  { TExtImageCopyCaptureFrameV1 }
  TExtImageCopyCaptureFrameV1 = class(TWaylandBase)
  public type
    TError = (erNobuffer = 1, erInvalidbufferdamage = 2, erAlreadycaptured = 3);
    TFailureReason = (faUnknown = 0, faBufferconstraints = 1, faStopped = 2);
    TTransformEvent = procedure(Sender: TExtImageCopyCaptureFrameV1; aTransform: TWlOutput.TTransform) of object;
    TDamageEvent = procedure(Sender: TExtImageCopyCaptureFrameV1; aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer) of object;
    TPresentationTimeEvent = procedure(Sender: TExtImageCopyCaptureFrameV1; aTvSecHi: DWord; aTvSecLo: DWord; aTvNsec: DWord) of object;
    TReadyEvent = procedure(Sender: TExtImageCopyCaptureFrameV1) of object;
    TFailedEvent = procedure(Sender: TExtImageCopyCaptureFrameV1; aReason: TFailureReason) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _ATTACH_BUFFER = 1, _DAMAGE_BUFFER = 2, _CAPTURE = 3);
    TEvents = (EV_TRANSFORM = 0, EV_DAMAGE = 1, EV_PRESENTATION_TIME = 2, EV_READY = 3, EV_FAILED = 4);
  private
    FOnTransformPriv: TTransformEvent;
    FOnDamagePriv: TDamageEvent;
    FOnPresentationTimePriv: TPresentationTimeEvent;
    FOnReadyPriv: TReadyEvent;
    FOnFailedPriv: TFailedEvent;
  protected
    procedure HandleTransform(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TRANSFORM); virtual;
    procedure HandleDamage(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DAMAGE); virtual;
    procedure HandlePresentationTime(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PRESENTATION_TIME); virtual;
    procedure HandleReady(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_READY); virtual;
    procedure HandleFailed(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FAILED); virtual;
  published
    property OnTransform: TTransformEvent read FOnTransformPriv write FOnTransformPriv;
    property OnDamage: TDamageEvent read FOnDamagePriv write FOnDamagePriv;
    property OnPresentationTime: TPresentationTimeEvent read FOnPresentationTimePriv write FOnPresentationTimePriv;
    property OnReady: TReadyEvent read FOnReadyPriv write FOnReadyPriv;
    property OnFailed: TFailedEvent read FOnFailedPriv write FOnFailedPriv;
  public
    destructor Destroy; override;
    procedure AttachBuffer(aBuffer: TWlBuffer);
    procedure DamageBuffer(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
    procedure Capture;
  private
    FListeners: array of IExtImageCopyCaptureFrameV1Listener;
  public
    function AddListener(AIntf: IExtImageCopyCaptureFrameV1Listener): LongInt;
  end;

  IExtImageCopyCaptureFrameV1Listener = interface
  ['IExtImageCopyCaptureFrameV1Listener']
    procedure ext_image_copy_capture_frame_v1_transform(AExtImageCopyCaptureFrameV1: TExtImageCopyCaptureFrameV1; aTransform: TWlOutput.TTransform);
    procedure ext_image_copy_capture_frame_v1_damage(AExtImageCopyCaptureFrameV1: TExtImageCopyCaptureFrameV1; aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
    procedure ext_image_copy_capture_frame_v1_presentation_time(AExtImageCopyCaptureFrameV1: TExtImageCopyCaptureFrameV1; aTvSecHi: DWord; aTvSecLo: DWord; aTvNsec: DWord);
    procedure ext_image_copy_capture_frame_v1_ready(AExtImageCopyCaptureFrameV1: TExtImageCopyCaptureFrameV1);
    procedure ext_image_copy_capture_frame_v1_failed(AExtImageCopyCaptureFrameV1: TExtImageCopyCaptureFrameV1; aReason: TExtImageCopyCaptureFrameV1.TFailureReason);
  end;

  IExtImageCopyCaptureCursorSessionV1Listener = interface;

  [TWLIntfAttribute('destroy(),get_capture_session(n)', 'enter(),leave(),position(ii),hotspot(ii)')]
  { TExtImageCopyCaptureCursorSessionV1 }
  TExtImageCopyCaptureCursorSessionV1 = class(TWaylandBase)
  public type
    TError = (erDuplicatesession = 1);
    TEnterEvent = procedure(Sender: TExtImageCopyCaptureCursorSessionV1) of object;
    TLeaveEvent = procedure(Sender: TExtImageCopyCaptureCursorSessionV1) of object;
    TPositionEvent = procedure(Sender: TExtImageCopyCaptureCursorSessionV1; aX: Integer; aY: Integer) of object;
    THotspotEvent = procedure(Sender: TExtImageCopyCaptureCursorSessionV1; aX: Integer; aY: Integer) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_CAPTURE_SESSION = 1);
    TEvents = (EV_ENTER = 0, EV_LEAVE = 1, EV_POSITION = 2, EV_HOTSPOT = 3);
  private
    FOnEnterPriv: TEnterEvent;
    FOnLeavePriv: TLeaveEvent;
    FOnPositionPriv: TPositionEvent;
    FOnHotspotPriv: THotspotEvent;
  protected
    procedure HandleEnter(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ENTER); virtual;
    procedure HandleLeave(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LEAVE); virtual;
    procedure HandlePosition(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_POSITION); virtual;
    procedure HandleHotspot(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_HOTSPOT); virtual;
  published
    property OnEnter: TEnterEvent read FOnEnterPriv write FOnEnterPriv;
    property OnLeave: TLeaveEvent read FOnLeavePriv write FOnLeavePriv;
    property OnPosition: TPositionEvent read FOnPositionPriv write FOnPositionPriv;
    property OnHotspot: THotspotEvent read FOnHotspotPriv write FOnHotspotPriv;
  public
    destructor Destroy; override;
    function GetCaptureSession(aClassType: TExtImageCopyCaptureSessionV1Class = nil): TExtImageCopyCaptureSessionV1;
  private
    FListeners: array of IExtImageCopyCaptureCursorSessionV1Listener;
  public
    function AddListener(AIntf: IExtImageCopyCaptureCursorSessionV1Listener): LongInt;
  end;

  IExtImageCopyCaptureCursorSessionV1Listener = interface
  ['IExtImageCopyCaptureCursorSessionV1Listener']
    procedure ext_image_copy_capture_cursor_session_v1_enter(AExtImageCopyCaptureCursorSessionV1: TExtImageCopyCaptureCursorSessionV1);
    procedure ext_image_copy_capture_cursor_session_v1_leave(AExtImageCopyCaptureCursorSessionV1: TExtImageCopyCaptureCursorSessionV1);
    procedure ext_image_copy_capture_cursor_session_v1_position(AExtImageCopyCaptureCursorSessionV1: TExtImageCopyCaptureCursorSessionV1; aX: Integer; aY: Integer);
    procedure ext_image_copy_capture_cursor_session_v1_hotspot(AExtImageCopyCaptureCursorSessionV1: TExtImageCopyCaptureCursorSessionV1; aX: Integer; aY: Integer);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TExtImageCopyCaptureManagerV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtImageCopyCaptureManagerV1.GetInterfaceName: String;
begin
  Result := 'ext_image_copy_capture_manager_v1';
end;

function TExtImageCopyCaptureManagerV1.CreateSession(aSource: TExtImageCaptureSourceV1; aOptions: TOptions; aClassType: TExtImageCopyCaptureSessionV1Class = nil): TExtImageCopyCaptureSessionV1;
begin
  if aClassType = nil then aClassType := TExtImageCopyCaptureSessionV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_SESSION), [Result.GetObjectId,aSource.GetObjectId,DWord(aOptions)]);
end;

function TExtImageCopyCaptureManagerV1.CreatePointerCursorSession(aSource: TExtImageCaptureSourceV1; aPointer: TWlPointer; aClassType: TExtImageCopyCaptureCursorSessionV1Class = nil): TExtImageCopyCaptureCursorSessionV1;
begin
  if aClassType = nil then aClassType := TExtImageCopyCaptureCursorSessionV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_POINTER_CURSOR_SESSION), [Result.GetObjectId,aSource.GetObjectId,aPointer.GetObjectId]);
end;

destructor TExtImageCopyCaptureManagerV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TExtImageCopyCaptureManagerV1.AddListener(AIntf: IExtImageCopyCaptureManagerV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TExtImageCopyCaptureSessionV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtImageCopyCaptureSessionV1.GetInterfaceName: String;
begin
  Result := 'ext_image_copy_capture_session_v1';
end;

procedure TExtImageCopyCaptureSessionV1.HandleBufferSize(var AMsg: TWaylandEventMessage);
var
  lWidth: DWord;
  lHeight: DWord;
  lListenerIdx: Integer;
begin
  lWidth := AMsg.Args.ReadDWord;
  lHeight := AMsg.Args.ReadDWord;
  if Assigned(OnBufferSize) then OnBufferSize(Self,lWidth,lHeight);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_session_v1_buffer_size(Self,lWidth,lHeight);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureSessionV1.HandleShmFormat(var AMsg: TWaylandEventMessage);
var
  lFormat: TWlShm.TFormat;
  lListenerIdx: Integer;
begin
  lFormat := TWlShm.TFormat(AMsg.Args.ReadDWord);
  if Assigned(OnShmFormat) then OnShmFormat(Self,lFormat);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_session_v1_shm_format(Self,lFormat);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureSessionV1.HandleDmabufDevice(var AMsg: TWaylandEventMessage);
var
  lDevice: TBytes;
  lListenerIdx: Integer;
begin
  lDevice := AMsg.Args.ReadBlob;
  if Assigned(OnDmabufDevice) then OnDmabufDevice(Self,lDevice);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_session_v1_dmabuf_device(Self,lDevice);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureSessionV1.HandleDmabufFormat(var AMsg: TWaylandEventMessage);
var
  lFormat: DWord;
  lModifiers: TBytes;
  lListenerIdx: Integer;
begin
  lFormat := AMsg.Args.ReadDWord;
  lModifiers := AMsg.Args.ReadBlob;
  if Assigned(OnDmabufFormat) then OnDmabufFormat(Self,lFormat,lModifiers);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_session_v1_dmabuf_format(Self,lFormat,lModifiers);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureSessionV1.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_session_v1_done(Self);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureSessionV1.HandleStopped(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnStopped) then OnStopped(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_session_v1_stopped(Self);
  AMsg.SetHandled;
end;

function TExtImageCopyCaptureSessionV1.CreateFrame(aClassType: TExtImageCopyCaptureFrameV1Class = nil): TExtImageCopyCaptureFrameV1;
begin
  if aClassType = nil then aClassType := TExtImageCopyCaptureFrameV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_FRAME), [Result.GetObjectId]);
end;

destructor TExtImageCopyCaptureSessionV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TExtImageCopyCaptureSessionV1.AddListener(AIntf: IExtImageCopyCaptureSessionV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TExtImageCopyCaptureFrameV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtImageCopyCaptureFrameV1.GetInterfaceName: String;
begin
  Result := 'ext_image_copy_capture_frame_v1';
end;

procedure TExtImageCopyCaptureFrameV1.HandleTransform(var AMsg: TWaylandEventMessage);
var
  lTransform: TWlOutput.TTransform;
  lListenerIdx: Integer;
begin
  lTransform := TWlOutput.TTransform(AMsg.Args.ReadDWord);
  if Assigned(OnTransform) then OnTransform(Self,lTransform);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_frame_v1_transform(Self,lTransform);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureFrameV1.HandleDamage(var AMsg: TWaylandEventMessage);
var
  lX: Integer;
  lY: Integer;
  lWidth: Integer;
  lHeight: Integer;
  lListenerIdx: Integer;
begin
  lX := AMsg.Args.ReadInteger;
  lY := AMsg.Args.ReadInteger;
  lWidth := AMsg.Args.ReadInteger;
  lHeight := AMsg.Args.ReadInteger;
  if Assigned(OnDamage) then OnDamage(Self,lX,lY,lWidth,lHeight);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_frame_v1_damage(Self,lX,lY,lWidth,lHeight);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureFrameV1.HandlePresentationTime(var AMsg: TWaylandEventMessage);
var
  lTvSecHi: DWord;
  lTvSecLo: DWord;
  lTvNsec: DWord;
  lListenerIdx: Integer;
begin
  lTvSecHi := AMsg.Args.ReadDWord;
  lTvSecLo := AMsg.Args.ReadDWord;
  lTvNsec := AMsg.Args.ReadDWord;
  if Assigned(OnPresentationTime) then OnPresentationTime(Self,lTvSecHi,lTvSecLo,lTvNsec);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_frame_v1_presentation_time(Self,lTvSecHi,lTvSecLo,lTvNsec);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureFrameV1.HandleReady(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnReady) then OnReady(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_frame_v1_ready(Self);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureFrameV1.HandleFailed(var AMsg: TWaylandEventMessage);
var
  lReason: TFailureReason;
  lListenerIdx: Integer;
begin
  lReason := TFailureReason(AMsg.Args.ReadDWord);
  if Assigned(OnFailed) then OnFailed(Self,lReason);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_frame_v1_failed(Self,lReason);
  AMsg.SetHandled;
end;

destructor TExtImageCopyCaptureFrameV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TExtImageCopyCaptureFrameV1.AttachBuffer(aBuffer: TWlBuffer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._ATTACH_BUFFER), [aBuffer.GetObjectId]);
end;

procedure TExtImageCopyCaptureFrameV1.DamageBuffer(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DAMAGE_BUFFER), [aX,aY,aWidth,aHeight]);
end;

procedure TExtImageCopyCaptureFrameV1.Capture;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._CAPTURE), []);
end;

function TExtImageCopyCaptureFrameV1.AddListener(AIntf: IExtImageCopyCaptureFrameV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TExtImageCopyCaptureCursorSessionV1.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TExtImageCopyCaptureCursorSessionV1.GetInterfaceName: String;
begin
  Result := 'ext_image_copy_capture_cursor_session_v1';
end;

procedure TExtImageCopyCaptureCursorSessionV1.HandleEnter(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnEnter) then OnEnter(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_cursor_session_v1_enter(Self);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureCursorSessionV1.HandleLeave(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnLeave) then OnLeave(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_cursor_session_v1_leave(Self);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureCursorSessionV1.HandlePosition(var AMsg: TWaylandEventMessage);
var
  lX: Integer;
  lY: Integer;
  lListenerIdx: Integer;
begin
  lX := AMsg.Args.ReadInteger;
  lY := AMsg.Args.ReadInteger;
  if Assigned(OnPosition) then OnPosition(Self,lX,lY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_cursor_session_v1_position(Self,lX,lY);
  AMsg.SetHandled;
end;

procedure TExtImageCopyCaptureCursorSessionV1.HandleHotspot(var AMsg: TWaylandEventMessage);
var
  lX: Integer;
  lY: Integer;
  lListenerIdx: Integer;
begin
  lX := AMsg.Args.ReadInteger;
  lY := AMsg.Args.ReadInteger;
  if Assigned(OnHotspot) then OnHotspot(Self,lX,lY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].ext_image_copy_capture_cursor_session_v1_hotspot(Self,lX,lY);
  AMsg.SetHandled;
end;

destructor TExtImageCopyCaptureCursorSessionV1.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TExtImageCopyCaptureCursorSessionV1.GetCaptureSession(aClassType: TExtImageCopyCaptureSessionV1Class = nil): TExtImageCopyCaptureSessionV1;
begin
  if aClassType = nil then aClassType := TExtImageCopyCaptureSessionV1;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_CAPTURE_SESSION), [Result.GetObjectId]);
end;

function TExtImageCopyCaptureCursorSessionV1.AddListener(AIntf: IExtImageCopyCaptureCursorSessionV1Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.