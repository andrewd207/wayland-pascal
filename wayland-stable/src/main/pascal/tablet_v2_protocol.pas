unit tablet_v2_protocol;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces, wayland;

type
  TWpTabletPadDialV2Class = class of TWpTabletPadDialV2;
  { TWpTabletPadDialV2 }
  TWpTabletPadDialV2 = class;

  TWpTabletPadGroupV2Class = class of TWpTabletPadGroupV2;
  { TWpTabletPadGroupV2 }
  TWpTabletPadGroupV2 = class;

  TWpTabletPadStripV2Class = class of TWpTabletPadStripV2;
  { TWpTabletPadStripV2 }
  TWpTabletPadStripV2 = class;

  TWpTabletPadRingV2Class = class of TWpTabletPadRingV2;
  { TWpTabletPadRingV2 }
  TWpTabletPadRingV2 = class;

  TWpTabletPadV2Class = class of TWpTabletPadV2;
  { TWpTabletPadV2 }
  TWpTabletPadV2 = class;

  TWpTabletToolV2Class = class of TWpTabletToolV2;
  { TWpTabletToolV2 }
  TWpTabletToolV2 = class;

  TWpTabletV2Class = class of TWpTabletV2;
  { TWpTabletV2 }
  TWpTabletV2 = class;

  TWpTabletSeatV2Class = class of TWpTabletSeatV2;
  { TWpTabletSeatV2 }
  TWpTabletSeatV2 = class;

  TWpTabletManagerV2Class = class of TWpTabletManagerV2;
  { TWpTabletManagerV2 }
  TWpTabletManagerV2 = class;

  IWpTabletManagerV2Listener = interface;

  [TWLIntfAttribute('get_tablet_seat(no),destroy()', '')]
  { TWpTabletManagerV2 }
  TWpTabletManagerV2 = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_GET_TABLET_SEAT = 0, _DESTROY = 1);
  public
    function GetTabletSeat(aSeat: TWlSeat; aClassType: TWpTabletSeatV2Class = nil): TWpTabletSeatV2;
    destructor Destroy; override;
  private
    FListeners: array of IWpTabletManagerV2Listener;
  public
    function AddListener(AIntf: IWpTabletManagerV2Listener): LongInt;
  end;

  IWpTabletManagerV2Listener = interface
  ['IWpTabletManagerV2Listener']
  end;

  IWpTabletSeatV2Listener = interface;

  [TWLIntfAttribute('destroy()', 'tablet_added(n),tool_added(n),pad_added(n)')]
  { TWpTabletSeatV2 }
  TWpTabletSeatV2 = class(TWaylandBase)
  public type
    TTabletAddedEvent = procedure(Sender: TWpTabletSeatV2; aId: TWpTabletV2) of object;
    TToolAddedEvent = procedure(Sender: TWpTabletSeatV2; aId: TWpTabletToolV2) of object;
    TPadAddedEvent = procedure(Sender: TWpTabletSeatV2; aId: TWpTabletPadV2) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_TABLET_ADDED = 0, EV_TOOL_ADDED = 1, EV_PAD_ADDED = 2);
  private
    FOnTabletAddedPriv: TTabletAddedEvent;
    FOnToolAddedPriv: TToolAddedEvent;
    FOnPadAddedPriv: TPadAddedEvent;
  protected
    procedure HandleTabletAdded(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TABLET_ADDED); virtual;
    procedure HandleToolAdded(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TOOL_ADDED); virtual;
    procedure HandlePadAdded(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PAD_ADDED); virtual;
  published
    property OnTabletAdded: TTabletAddedEvent read FOnTabletAddedPriv write FOnTabletAddedPriv;
    property OnToolAdded: TToolAddedEvent read FOnToolAddedPriv write FOnToolAddedPriv;
    property OnPadAdded: TPadAddedEvent read FOnPadAddedPriv write FOnPadAddedPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWpTabletSeatV2Listener;
  public
    function AddListener(AIntf: IWpTabletSeatV2Listener): LongInt;
  end;

  IWpTabletSeatV2Listener = interface
  ['IWpTabletSeatV2Listener']
    procedure wp_tablet_seat_v2_tablet_added(AWpTabletSeatV2: TWpTabletSeatV2; aId: TWpTabletV2);
    procedure wp_tablet_seat_v2_tool_added(AWpTabletSeatV2: TWpTabletSeatV2; aId: TWpTabletToolV2);
    procedure wp_tablet_seat_v2_pad_added(AWpTabletSeatV2: TWpTabletSeatV2; aId: TWpTabletPadV2);
  end;

  IWpTabletToolV2Listener = interface;

  [TWLIntfAttribute('set_cursor(u?oii),destroy()', 'type(u),hardware_serial(uu),hardware_id_wacom(uu),capability(u),done(),removed(),proximity_in(uoo),proximity_out(),down(u),up(),motion(ff),pressure(u),distance(u),tilt(ff),rotation(f),slider(i),wheel(fi),button(uuu),frame(u)')]
  { TWpTabletToolV2 }
  TWpTabletToolV2 = class(TWaylandBase)
  public type
    TType = (tyPen = 320, tyEraser = 321, tyBrush = 322, tyPencil = 323, tyAirbrush = 324, tyFinger = 325, tyMouse = 326, tyLens = 327);
    TCapability = (caTilt = 1, caPressure = 2, caDistance = 3, caRotation = 4, caSlider = 5, caWheel = 6);
    TButtonState = (buReleased = 0, buPressed = 1);
    TError = (erRole = 0);
    TTypeEvent = procedure(Sender: TWpTabletToolV2; aToolType: TType) of object;
    THardwareSerialEvent = procedure(Sender: TWpTabletToolV2; aHardwareSerialHi: DWord; aHardwareSerialLo: DWord) of object;
    THardwareIdWacomEvent = procedure(Sender: TWpTabletToolV2; aHardwareIdHi: DWord; aHardwareIdLo: DWord) of object;
    TCapabilityEvent = procedure(Sender: TWpTabletToolV2; aCapability: TCapability) of object;
    TDoneEvent = procedure(Sender: TWpTabletToolV2) of object;
    TRemovedEvent = procedure(Sender: TWpTabletToolV2) of object;
    TProximityInEvent = procedure(Sender: TWpTabletToolV2; aSerial: DWord; aTablet: TWpTabletV2; aSurface: TWlSurface) of object;
    TProximityOutEvent = procedure(Sender: TWpTabletToolV2) of object;
    TDownEvent = procedure(Sender: TWpTabletToolV2; aSerial: DWord) of object;
    TUpEvent = procedure(Sender: TWpTabletToolV2) of object;
    TMotionEvent = procedure(Sender: TWpTabletToolV2; aX: TWaylandFixed; aY: TWaylandFixed) of object;
    TPressureEvent = procedure(Sender: TWpTabletToolV2; aPressure: DWord) of object;
    TDistanceEvent = procedure(Sender: TWpTabletToolV2; aDistance: DWord) of object;
    TTiltEvent = procedure(Sender: TWpTabletToolV2; aTiltX: TWaylandFixed; aTiltY: TWaylandFixed) of object;
    TRotationEvent = procedure(Sender: TWpTabletToolV2; aDegrees: TWaylandFixed) of object;
    TSliderEvent = procedure(Sender: TWpTabletToolV2; aPosition: Integer) of object;
    TWheelEvent = procedure(Sender: TWpTabletToolV2; aDegrees: TWaylandFixed; aClicks: Integer) of object;
    TButtonEvent = procedure(Sender: TWpTabletToolV2; aSerial: DWord; aButton: DWord; aState: TButtonState) of object;
    TFrameEvent = procedure(Sender: TWpTabletToolV2; aTime: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_SET_CURSOR = 0, _DESTROY = 1);
    TEvents = (EV_TYPE = 0, EV_HARDWARE_SERIAL = 1, EV_HARDWARE_ID_WACOM = 2, EV_CAPABILITY = 3, EV_DONE = 4, EV_REMOVED = 5, EV_PROXIMITY_IN = 6, EV_PROXIMITY_OUT = 7, EV_DOWN = 8, EV_UP = 9, EV_MOTION = 10, EV_PRESSURE = 11, EV_DISTANCE = 12, EV_TILT = 13, EV_ROTATION = 14, EV_SLIDER = 15, EV_WHEEL = 16, EV_BUTTON = 17, EV_FRAME = 18);
  private
    FOnTypePriv: TTypeEvent;
    FOnHardwareSerialPriv: THardwareSerialEvent;
    FOnHardwareIdWacomPriv: THardwareIdWacomEvent;
    FOnCapabilityPriv: TCapabilityEvent;
    FOnDonePriv: TDoneEvent;
    FOnRemovedPriv: TRemovedEvent;
    FOnProximityInPriv: TProximityInEvent;
    FOnProximityOutPriv: TProximityOutEvent;
    FOnDownPriv: TDownEvent;
    FOnUpPriv: TUpEvent;
    FOnMotionPriv: TMotionEvent;
    FOnPressurePriv: TPressureEvent;
    FOnDistancePriv: TDistanceEvent;
    FOnTiltPriv: TTiltEvent;
    FOnRotationPriv: TRotationEvent;
    FOnSliderPriv: TSliderEvent;
    FOnWheelPriv: TWheelEvent;
    FOnButtonPriv: TButtonEvent;
    FOnFramePriv: TFrameEvent;
  protected
    procedure HandleType(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TYPE); virtual;
    procedure HandleHardwareSerial(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_HARDWARE_SERIAL); virtual;
    procedure HandleHardwareIdWacom(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_HARDWARE_ID_WACOM); virtual;
    procedure HandleCapability(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CAPABILITY); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleRemoved(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_REMOVED); virtual;
    procedure HandleProximityIn(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PROXIMITY_IN); virtual;
    procedure HandleProximityOut(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PROXIMITY_OUT); virtual;
    procedure HandleDown(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DOWN); virtual;
    procedure HandleUp(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_UP); virtual;
    procedure HandleMotion(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_MOTION); virtual;
    procedure HandlePressure(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PRESSURE); virtual;
    procedure HandleDistance(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DISTANCE); virtual;
    procedure HandleTilt(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TILT); virtual;
    procedure HandleRotation(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ROTATION); virtual;
    procedure HandleSlider(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SLIDER); virtual;
    procedure HandleWheel(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_WHEEL); virtual;
    procedure HandleButton(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_BUTTON); virtual;
    procedure HandleFrame(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FRAME); virtual;
  published
    property OnType: TTypeEvent read FOnTypePriv write FOnTypePriv;
    property OnHardwareSerial: THardwareSerialEvent read FOnHardwareSerialPriv write FOnHardwareSerialPriv;
    property OnHardwareIdWacom: THardwareIdWacomEvent read FOnHardwareIdWacomPriv write FOnHardwareIdWacomPriv;
    property OnCapability: TCapabilityEvent read FOnCapabilityPriv write FOnCapabilityPriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnRemoved: TRemovedEvent read FOnRemovedPriv write FOnRemovedPriv;
    property OnProximityIn: TProximityInEvent read FOnProximityInPriv write FOnProximityInPriv;
    property OnProximityOut: TProximityOutEvent read FOnProximityOutPriv write FOnProximityOutPriv;
    property OnDown: TDownEvent read FOnDownPriv write FOnDownPriv;
    property OnUp: TUpEvent read FOnUpPriv write FOnUpPriv;
    property OnMotion: TMotionEvent read FOnMotionPriv write FOnMotionPriv;
    property OnPressure: TPressureEvent read FOnPressurePriv write FOnPressurePriv;
    property OnDistance: TDistanceEvent read FOnDistancePriv write FOnDistancePriv;
    property OnTilt: TTiltEvent read FOnTiltPriv write FOnTiltPriv;
    property OnRotation: TRotationEvent read FOnRotationPriv write FOnRotationPriv;
    property OnSlider: TSliderEvent read FOnSliderPriv write FOnSliderPriv;
    property OnWheel: TWheelEvent read FOnWheelPriv write FOnWheelPriv;
    property OnButton: TButtonEvent read FOnButtonPriv write FOnButtonPriv;
    property OnFrame: TFrameEvent read FOnFramePriv write FOnFramePriv;
  public
    procedure SetCursor(aSerial: DWord; aSurface: TWlSurface; aHotspotX: Integer; aHotspotY: Integer);
    destructor Destroy; override;
  private
    FListeners: array of IWpTabletToolV2Listener;
  public
    function AddListener(AIntf: IWpTabletToolV2Listener): LongInt;
  end;

  IWpTabletToolV2Listener = interface
  ['IWpTabletToolV2Listener']
    procedure wp_tablet_tool_v2_type(AWpTabletToolV2: TWpTabletToolV2; aToolType: TWpTabletToolV2.TType);
    procedure wp_tablet_tool_v2_hardware_serial(AWpTabletToolV2: TWpTabletToolV2; aHardwareSerialHi: DWord; aHardwareSerialLo: DWord);
    procedure wp_tablet_tool_v2_hardware_id_wacom(AWpTabletToolV2: TWpTabletToolV2; aHardwareIdHi: DWord; aHardwareIdLo: DWord);
    procedure wp_tablet_tool_v2_capability(AWpTabletToolV2: TWpTabletToolV2; aCapability: TWpTabletToolV2.TCapability);
    procedure wp_tablet_tool_v2_done(AWpTabletToolV2: TWpTabletToolV2);
    procedure wp_tablet_tool_v2_removed(AWpTabletToolV2: TWpTabletToolV2);
    procedure wp_tablet_tool_v2_proximity_in(AWpTabletToolV2: TWpTabletToolV2; aSerial: DWord; aTablet: TWpTabletV2; aSurface: TWlSurface);
    procedure wp_tablet_tool_v2_proximity_out(AWpTabletToolV2: TWpTabletToolV2);
    procedure wp_tablet_tool_v2_down(AWpTabletToolV2: TWpTabletToolV2; aSerial: DWord);
    procedure wp_tablet_tool_v2_up(AWpTabletToolV2: TWpTabletToolV2);
    procedure wp_tablet_tool_v2_motion(AWpTabletToolV2: TWpTabletToolV2; aX: TWaylandFixed; aY: TWaylandFixed);
    procedure wp_tablet_tool_v2_pressure(AWpTabletToolV2: TWpTabletToolV2; aPressure: DWord);
    procedure wp_tablet_tool_v2_distance(AWpTabletToolV2: TWpTabletToolV2; aDistance: DWord);
    procedure wp_tablet_tool_v2_tilt(AWpTabletToolV2: TWpTabletToolV2; aTiltX: TWaylandFixed; aTiltY: TWaylandFixed);
    procedure wp_tablet_tool_v2_rotation(AWpTabletToolV2: TWpTabletToolV2; aDegrees: TWaylandFixed);
    procedure wp_tablet_tool_v2_slider(AWpTabletToolV2: TWpTabletToolV2; aPosition: Integer);
    procedure wp_tablet_tool_v2_wheel(AWpTabletToolV2: TWpTabletToolV2; aDegrees: TWaylandFixed; aClicks: Integer);
    procedure wp_tablet_tool_v2_button(AWpTabletToolV2: TWpTabletToolV2; aSerial: DWord; aButton: DWord; aState: TWpTabletToolV2.TButtonState);
    procedure wp_tablet_tool_v2_frame(AWpTabletToolV2: TWpTabletToolV2; aTime: DWord);
  end;

  IWpTabletV2Listener = interface;

  [TWLIntfAttribute('destroy()', 'name(s),id(uu),path(s),done(),removed(),bustype(u)')]
  { TWpTabletV2 }
  TWpTabletV2 = class(TWaylandBase)
  public type
    TBustype = (buUsb = 3, buBluetooth = 5, buVirtual = 6, buSerial = 17, buI2c = 24);
    TNameEvent = procedure(Sender: TWpTabletV2; aName: String) of object;
    TIdEvent = procedure(Sender: TWpTabletV2; aVid: DWord; aPid: DWord) of object;
    TPathEvent = procedure(Sender: TWpTabletV2; aPath: String) of object;
    TDoneEvent = procedure(Sender: TWpTabletV2) of object;
    TRemovedEvent = procedure(Sender: TWpTabletV2) of object;
    TBustypeEvent = procedure(Sender: TWpTabletV2; aBustype: TBustype) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_NAME = 0, EV_ID = 1, EV_PATH = 2, EV_DONE = 3, EV_REMOVED = 4, EV_BUSTYPE = 5);
  private
    FOnNamePriv: TNameEvent;
    FOnIdPriv: TIdEvent;
    FOnPathPriv: TPathEvent;
    FOnDonePriv: TDoneEvent;
    FOnRemovedPriv: TRemovedEvent;
    FOnBustypePriv: TBustypeEvent;
  protected
    procedure HandleName(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_NAME); virtual;
    procedure HandleId(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ID); virtual;
    procedure HandlePath(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PATH); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleRemoved(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_REMOVED); virtual;
    procedure HandleBustype(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_BUSTYPE); virtual;
  published
    property OnName: TNameEvent read FOnNamePriv write FOnNamePriv;
    property OnId: TIdEvent read FOnIdPriv write FOnIdPriv;
    property OnPath: TPathEvent read FOnPathPriv write FOnPathPriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnRemoved: TRemovedEvent read FOnRemovedPriv write FOnRemovedPriv;
    property OnBustype: TBustypeEvent read FOnBustypePriv write FOnBustypePriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWpTabletV2Listener;
  public
    function AddListener(AIntf: IWpTabletV2Listener): LongInt;
  end;

  IWpTabletV2Listener = interface
  ['IWpTabletV2Listener']
    procedure wp_tablet_v2_name(AWpTabletV2: TWpTabletV2; aName: String);
    procedure wp_tablet_v2_id(AWpTabletV2: TWpTabletV2; aVid: DWord; aPid: DWord);
    procedure wp_tablet_v2_path(AWpTabletV2: TWpTabletV2; aPath: String);
    procedure wp_tablet_v2_done(AWpTabletV2: TWpTabletV2);
    procedure wp_tablet_v2_removed(AWpTabletV2: TWpTabletV2);
    procedure wp_tablet_v2_bustype(AWpTabletV2: TWpTabletV2; aBustype: TWpTabletV2.TBustype);
  end;

  IWpTabletPadRingV2Listener = interface;

  [TWLIntfAttribute('set_feedback(su),destroy()', 'source(u),angle(f),stop(),frame(u)')]
  { TWpTabletPadRingV2 }
  TWpTabletPadRingV2 = class(TWaylandBase)
  public type
    TSource = (soFinger = 1);
    TSourceEvent = procedure(Sender: TWpTabletPadRingV2; aSource: TSource) of object;
    TAngleEvent = procedure(Sender: TWpTabletPadRingV2; aDegrees: TWaylandFixed) of object;
    TStopEvent = procedure(Sender: TWpTabletPadRingV2) of object;
    TFrameEvent = procedure(Sender: TWpTabletPadRingV2; aTime: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_SET_FEEDBACK = 0, _DESTROY = 1);
    TEvents = (EV_SOURCE = 0, EV_ANGLE = 1, EV_STOP = 2, EV_FRAME = 3);
  private
    FOnSourcePriv: TSourceEvent;
    FOnAnglePriv: TAngleEvent;
    FOnStopPriv: TStopEvent;
    FOnFramePriv: TFrameEvent;
  protected
    procedure HandleSource(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SOURCE); virtual;
    procedure HandleAngle(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ANGLE); virtual;
    procedure HandleStop(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_STOP); virtual;
    procedure HandleFrame(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FRAME); virtual;
  published
    property OnSource: TSourceEvent read FOnSourcePriv write FOnSourcePriv;
    property OnAngle: TAngleEvent read FOnAnglePriv write FOnAnglePriv;
    property OnStop: TStopEvent read FOnStopPriv write FOnStopPriv;
    property OnFrame: TFrameEvent read FOnFramePriv write FOnFramePriv;
  public
    procedure SetFeedback(aDescription: String; aSerial: DWord);
    destructor Destroy; override;
  private
    FListeners: array of IWpTabletPadRingV2Listener;
  public
    function AddListener(AIntf: IWpTabletPadRingV2Listener): LongInt;
  end;

  IWpTabletPadRingV2Listener = interface
  ['IWpTabletPadRingV2Listener']
    procedure wp_tablet_pad_ring_v2_source(AWpTabletPadRingV2: TWpTabletPadRingV2; aSource: TWpTabletPadRingV2.TSource);
    procedure wp_tablet_pad_ring_v2_angle(AWpTabletPadRingV2: TWpTabletPadRingV2; aDegrees: TWaylandFixed);
    procedure wp_tablet_pad_ring_v2_stop(AWpTabletPadRingV2: TWpTabletPadRingV2);
    procedure wp_tablet_pad_ring_v2_frame(AWpTabletPadRingV2: TWpTabletPadRingV2; aTime: DWord);
  end;

  IWpTabletPadStripV2Listener = interface;

  [TWLIntfAttribute('set_feedback(su),destroy()', 'source(u),position(u),stop(),frame(u)')]
  { TWpTabletPadStripV2 }
  TWpTabletPadStripV2 = class(TWaylandBase)
  public type
    TSource = (soFinger = 1);
    TSourceEvent = procedure(Sender: TWpTabletPadStripV2; aSource: TSource) of object;
    TPositionEvent = procedure(Sender: TWpTabletPadStripV2; aPosition: DWord) of object;
    TStopEvent = procedure(Sender: TWpTabletPadStripV2) of object;
    TFrameEvent = procedure(Sender: TWpTabletPadStripV2; aTime: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_SET_FEEDBACK = 0, _DESTROY = 1);
    TEvents = (EV_SOURCE = 0, EV_POSITION = 1, EV_STOP = 2, EV_FRAME = 3);
  private
    FOnSourcePriv: TSourceEvent;
    FOnPositionPriv: TPositionEvent;
    FOnStopPriv: TStopEvent;
    FOnFramePriv: TFrameEvent;
  protected
    procedure HandleSource(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SOURCE); virtual;
    procedure HandlePosition(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_POSITION); virtual;
    procedure HandleStop(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_STOP); virtual;
    procedure HandleFrame(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FRAME); virtual;
  published
    property OnSource: TSourceEvent read FOnSourcePriv write FOnSourcePriv;
    property OnPosition: TPositionEvent read FOnPositionPriv write FOnPositionPriv;
    property OnStop: TStopEvent read FOnStopPriv write FOnStopPriv;
    property OnFrame: TFrameEvent read FOnFramePriv write FOnFramePriv;
  public
    procedure SetFeedback(aDescription: String; aSerial: DWord);
    destructor Destroy; override;
  private
    FListeners: array of IWpTabletPadStripV2Listener;
  public
    function AddListener(AIntf: IWpTabletPadStripV2Listener): LongInt;
  end;

  IWpTabletPadStripV2Listener = interface
  ['IWpTabletPadStripV2Listener']
    procedure wp_tablet_pad_strip_v2_source(AWpTabletPadStripV2: TWpTabletPadStripV2; aSource: TWpTabletPadStripV2.TSource);
    procedure wp_tablet_pad_strip_v2_position(AWpTabletPadStripV2: TWpTabletPadStripV2; aPosition: DWord);
    procedure wp_tablet_pad_strip_v2_stop(AWpTabletPadStripV2: TWpTabletPadStripV2);
    procedure wp_tablet_pad_strip_v2_frame(AWpTabletPadStripV2: TWpTabletPadStripV2; aTime: DWord);
  end;

  IWpTabletPadGroupV2Listener = interface;

  [TWLIntfAttribute('destroy()', 'buttons(a),ring(n),strip(n),modes(u),done(),mode_switch(uuu),dial(n)')]
  { TWpTabletPadGroupV2 }
  TWpTabletPadGroupV2 = class(TWaylandBase)
  public type
    TButtonsEvent = procedure(Sender: TWpTabletPadGroupV2; aButtons: TBytes) of object;
    TRingEvent = procedure(Sender: TWpTabletPadGroupV2; aRing: TWpTabletPadRingV2) of object;
    TStripEvent = procedure(Sender: TWpTabletPadGroupV2; aStrip: TWpTabletPadStripV2) of object;
    TModesEvent = procedure(Sender: TWpTabletPadGroupV2; aModes: DWord) of object;
    TDoneEvent = procedure(Sender: TWpTabletPadGroupV2) of object;
    TModeSwitchEvent = procedure(Sender: TWpTabletPadGroupV2; aTime: DWord; aSerial: DWord; aMode: DWord) of object;
    TDialEvent = procedure(Sender: TWpTabletPadGroupV2; aDial: TWpTabletPadDialV2) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_BUTTONS = 0, EV_RING = 1, EV_STRIP = 2, EV_MODES = 3, EV_DONE = 4, EV_MODE_SWITCH = 5, EV_DIAL = 6);
  private
    FOnButtonsPriv: TButtonsEvent;
    FOnRingPriv: TRingEvent;
    FOnStripPriv: TStripEvent;
    FOnModesPriv: TModesEvent;
    FOnDonePriv: TDoneEvent;
    FOnModeSwitchPriv: TModeSwitchEvent;
    FOnDialPriv: TDialEvent;
  protected
    procedure HandleButtons(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_BUTTONS); virtual;
    procedure HandleRing(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_RING); virtual;
    procedure HandleStrip(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_STRIP); virtual;
    procedure HandleModes(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_MODES); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleModeSwitch(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_MODE_SWITCH); virtual;
    procedure HandleDial(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DIAL); virtual;
  published
    property OnButtons: TButtonsEvent read FOnButtonsPriv write FOnButtonsPriv;
    property OnRing: TRingEvent read FOnRingPriv write FOnRingPriv;
    property OnStrip: TStripEvent read FOnStripPriv write FOnStripPriv;
    property OnModes: TModesEvent read FOnModesPriv write FOnModesPriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnModeSwitch: TModeSwitchEvent read FOnModeSwitchPriv write FOnModeSwitchPriv;
    property OnDial: TDialEvent read FOnDialPriv write FOnDialPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWpTabletPadGroupV2Listener;
  public
    function AddListener(AIntf: IWpTabletPadGroupV2Listener): LongInt;
  end;

  IWpTabletPadGroupV2Listener = interface
  ['IWpTabletPadGroupV2Listener']
    procedure wp_tablet_pad_group_v2_buttons(AWpTabletPadGroupV2: TWpTabletPadGroupV2; aButtons: TBytes);
    procedure wp_tablet_pad_group_v2_ring(AWpTabletPadGroupV2: TWpTabletPadGroupV2; aRing: TWpTabletPadRingV2);
    procedure wp_tablet_pad_group_v2_strip(AWpTabletPadGroupV2: TWpTabletPadGroupV2; aStrip: TWpTabletPadStripV2);
    procedure wp_tablet_pad_group_v2_modes(AWpTabletPadGroupV2: TWpTabletPadGroupV2; aModes: DWord);
    procedure wp_tablet_pad_group_v2_done(AWpTabletPadGroupV2: TWpTabletPadGroupV2);
    procedure wp_tablet_pad_group_v2_mode_switch(AWpTabletPadGroupV2: TWpTabletPadGroupV2; aTime: DWord; aSerial: DWord; aMode: DWord);
    procedure wp_tablet_pad_group_v2_dial(AWpTabletPadGroupV2: TWpTabletPadGroupV2; aDial: TWpTabletPadDialV2);
  end;

  IWpTabletPadV2Listener = interface;

  [TWLIntfAttribute('set_feedback(usu),destroy()', 'group(n),path(s),buttons(u),done(),button(uuu),enter(uoo),leave(uo),removed()')]
  { TWpTabletPadV2 }
  TWpTabletPadV2 = class(TWaylandBase)
  public type
    TButtonState = (buReleased = 0, buPressed = 1);
    TGroupEvent = procedure(Sender: TWpTabletPadV2; aPadGroup: TWpTabletPadGroupV2) of object;
    TPathEvent = procedure(Sender: TWpTabletPadV2; aPath: String) of object;
    TButtonsEvent = procedure(Sender: TWpTabletPadV2; aButtons: DWord) of object;
    TDoneEvent = procedure(Sender: TWpTabletPadV2) of object;
    TButtonEvent = procedure(Sender: TWpTabletPadV2; aTime: DWord; aButton: DWord; aState: TButtonState) of object;
    TEnterEvent = procedure(Sender: TWpTabletPadV2; aSerial: DWord; aTablet: TWpTabletV2; aSurface: TWlSurface) of object;
    TLeaveEvent = procedure(Sender: TWpTabletPadV2; aSerial: DWord; aSurface: TWlSurface) of object;
    TRemovedEvent = procedure(Sender: TWpTabletPadV2) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_SET_FEEDBACK = 0, _DESTROY = 1);
    TEvents = (EV_GROUP = 0, EV_PATH = 1, EV_BUTTONS = 2, EV_DONE = 3, EV_BUTTON = 4, EV_ENTER = 5, EV_LEAVE = 6, EV_REMOVED = 7);
  private
    FOnGroupPriv: TGroupEvent;
    FOnPathPriv: TPathEvent;
    FOnButtonsPriv: TButtonsEvent;
    FOnDonePriv: TDoneEvent;
    FOnButtonPriv: TButtonEvent;
    FOnEnterPriv: TEnterEvent;
    FOnLeavePriv: TLeaveEvent;
    FOnRemovedPriv: TRemovedEvent;
  protected
    procedure HandleGroup(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_GROUP); virtual;
    procedure HandlePath(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PATH); virtual;
    procedure HandleButtons(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_BUTTONS); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleButton(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_BUTTON); virtual;
    procedure HandleEnter(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ENTER); virtual;
    procedure HandleLeave(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LEAVE); virtual;
    procedure HandleRemoved(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_REMOVED); virtual;
  published
    property OnGroup: TGroupEvent read FOnGroupPriv write FOnGroupPriv;
    property OnPath: TPathEvent read FOnPathPriv write FOnPathPriv;
    property OnButtons: TButtonsEvent read FOnButtonsPriv write FOnButtonsPriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnButton: TButtonEvent read FOnButtonPriv write FOnButtonPriv;
    property OnEnter: TEnterEvent read FOnEnterPriv write FOnEnterPriv;
    property OnLeave: TLeaveEvent read FOnLeavePriv write FOnLeavePriv;
    property OnRemoved: TRemovedEvent read FOnRemovedPriv write FOnRemovedPriv;
  public
    procedure SetFeedback(aButton: DWord; aDescription: String; aSerial: DWord);
    destructor Destroy; override;
  private
    FListeners: array of IWpTabletPadV2Listener;
  public
    function AddListener(AIntf: IWpTabletPadV2Listener): LongInt;
  end;

  IWpTabletPadV2Listener = interface
  ['IWpTabletPadV2Listener']
    procedure wp_tablet_pad_v2_group(AWpTabletPadV2: TWpTabletPadV2; aPadGroup: TWpTabletPadGroupV2);
    procedure wp_tablet_pad_v2_path(AWpTabletPadV2: TWpTabletPadV2; aPath: String);
    procedure wp_tablet_pad_v2_buttons(AWpTabletPadV2: TWpTabletPadV2; aButtons: DWord);
    procedure wp_tablet_pad_v2_done(AWpTabletPadV2: TWpTabletPadV2);
    procedure wp_tablet_pad_v2_button(AWpTabletPadV2: TWpTabletPadV2; aTime: DWord; aButton: DWord; aState: TWpTabletPadV2.TButtonState);
    procedure wp_tablet_pad_v2_enter(AWpTabletPadV2: TWpTabletPadV2; aSerial: DWord; aTablet: TWpTabletV2; aSurface: TWlSurface);
    procedure wp_tablet_pad_v2_leave(AWpTabletPadV2: TWpTabletPadV2; aSerial: DWord; aSurface: TWlSurface);
    procedure wp_tablet_pad_v2_removed(AWpTabletPadV2: TWpTabletPadV2);
  end;

  IWpTabletPadDialV2Listener = interface;

  [TWLIntfAttribute('set_feedback(su),destroy()', 'delta(i),frame(u)')]
  { TWpTabletPadDialV2 }
  TWpTabletPadDialV2 = class(TWaylandBase)
  public type
    TDeltaEvent = procedure(Sender: TWpTabletPadDialV2; aValue120: Integer) of object;
    TFrameEvent = procedure(Sender: TWpTabletPadDialV2; aTime: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_SET_FEEDBACK = 0, _DESTROY = 1);
    TEvents = (EV_DELTA = 0, EV_FRAME = 1);
  private
    FOnDeltaPriv: TDeltaEvent;
    FOnFramePriv: TFrameEvent;
  protected
    procedure HandleDelta(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DELTA); virtual;
    procedure HandleFrame(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FRAME); virtual;
  published
    property OnDelta: TDeltaEvent read FOnDeltaPriv write FOnDeltaPriv;
    property OnFrame: TFrameEvent read FOnFramePriv write FOnFramePriv;
  public
    procedure SetFeedback(aDescription: String; aSerial: DWord);
    destructor Destroy; override;
  private
    FListeners: array of IWpTabletPadDialV2Listener;
  public
    function AddListener(AIntf: IWpTabletPadDialV2Listener): LongInt;
  end;

  IWpTabletPadDialV2Listener = interface
  ['IWpTabletPadDialV2Listener']
    procedure wp_tablet_pad_dial_v2_delta(AWpTabletPadDialV2: TWpTabletPadDialV2; aValue120: Integer);
    procedure wp_tablet_pad_dial_v2_frame(AWpTabletPadDialV2: TWpTabletPadDialV2; aTime: DWord);
  end;

implementation
uses
  wayland_stream, wayland_interfaces;

class function TWpTabletManagerV2.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpTabletManagerV2.GetInterfaceName: String;
begin
  Result := 'zwp_tablet_manager_v2';
end;

function TWpTabletManagerV2.GetTabletSeat(aSeat: TWlSeat; aClassType: TWpTabletSeatV2Class = nil): TWpTabletSeatV2;
begin
  if aClassType = nil then aClassType := TWpTabletSeatV2;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_TABLET_SEAT), [Result.GetObjectId,aSeat.GetObjectId]);
end;

destructor TWpTabletManagerV2.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTabletManagerV2.AddListener(AIntf: IWpTabletManagerV2Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpTabletSeatV2.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpTabletSeatV2.GetInterfaceName: String;
begin
  Result := 'zwp_tablet_seat_v2';
end;

procedure TWpTabletSeatV2.HandleTabletAdded(var AMsg: TWaylandEventMessage);
var
  lId: TWpTabletV2;
  lListenerIdx: Integer;
begin
  lId := TWpTabletV2.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnTabletAdded) then OnTabletAdded(Self,lId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_seat_v2_tablet_added(Self,lId);
  AMsg.SetHandled;
end;

procedure TWpTabletSeatV2.HandleToolAdded(var AMsg: TWaylandEventMessage);
var
  lId: TWpTabletToolV2;
  lListenerIdx: Integer;
begin
  lId := TWpTabletToolV2.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnToolAdded) then OnToolAdded(Self,lId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_seat_v2_tool_added(Self,lId);
  AMsg.SetHandled;
end;

procedure TWpTabletSeatV2.HandlePadAdded(var AMsg: TWaylandEventMessage);
var
  lId: TWpTabletPadV2;
  lListenerIdx: Integer;
begin
  lId := TWpTabletPadV2.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnPadAdded) then OnPadAdded(Self,lId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_seat_v2_pad_added(Self,lId);
  AMsg.SetHandled;
end;

destructor TWpTabletSeatV2.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTabletSeatV2.AddListener(AIntf: IWpTabletSeatV2Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpTabletToolV2.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpTabletToolV2.GetInterfaceName: String;
begin
  Result := 'zwp_tablet_tool_v2';
end;

procedure TWpTabletToolV2.HandleType(var AMsg: TWaylandEventMessage);
var
  lToolType: TType;
  lListenerIdx: Integer;
begin
  lToolType := TType(AMsg.Args.ReadDWord);
  if Assigned(OnType) then OnType(Self,lToolType);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_type(Self,lToolType);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleHardwareSerial(var AMsg: TWaylandEventMessage);
var
  lHardwareSerialHi: DWord;
  lHardwareSerialLo: DWord;
  lListenerIdx: Integer;
begin
  lHardwareSerialHi := AMsg.Args.ReadDWord;
  lHardwareSerialLo := AMsg.Args.ReadDWord;
  if Assigned(OnHardwareSerial) then OnHardwareSerial(Self,lHardwareSerialHi,lHardwareSerialLo);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_hardware_serial(Self,lHardwareSerialHi,lHardwareSerialLo);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleHardwareIdWacom(var AMsg: TWaylandEventMessage);
var
  lHardwareIdHi: DWord;
  lHardwareIdLo: DWord;
  lListenerIdx: Integer;
begin
  lHardwareIdHi := AMsg.Args.ReadDWord;
  lHardwareIdLo := AMsg.Args.ReadDWord;
  if Assigned(OnHardwareIdWacom) then OnHardwareIdWacom(Self,lHardwareIdHi,lHardwareIdLo);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_hardware_id_wacom(Self,lHardwareIdHi,lHardwareIdLo);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleCapability(var AMsg: TWaylandEventMessage);
var
  lCapability: TCapability;
  lListenerIdx: Integer;
begin
  lCapability := TCapability(AMsg.Args.ReadDWord);
  if Assigned(OnCapability) then OnCapability(Self,lCapability);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_capability(Self,lCapability);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_done(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleRemoved(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnRemoved) then OnRemoved(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_removed(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleProximityIn(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lTablet: TWpTabletV2;
  lSurface: TWlSurface;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lTablet := (Connection.GetObject(AMsg.Args.ReadDWord) as TWpTabletV2);
  lSurface := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlSurface);
  if Assigned(OnProximityIn) then OnProximityIn(Self,lSerial,lTablet,lSurface);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_proximity_in(Self,lSerial,lTablet,lSurface);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleProximityOut(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnProximityOut) then OnProximityOut(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_proximity_out(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleDown(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  if Assigned(OnDown) then OnDown(Self,lSerial);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_down(Self,lSerial);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleUp(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnUp) then OnUp(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_up(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleMotion(var AMsg: TWaylandEventMessage);
var
  lX: TWaylandFixed;
  lY: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lX := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lY := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnMotion) then OnMotion(Self,lX,lY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_motion(Self,lX,lY);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandlePressure(var AMsg: TWaylandEventMessage);
var
  lPressure: DWord;
  lListenerIdx: Integer;
begin
  lPressure := AMsg.Args.ReadDWord;
  if Assigned(OnPressure) then OnPressure(Self,lPressure);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_pressure(Self,lPressure);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleDistance(var AMsg: TWaylandEventMessage);
var
  lDistance: DWord;
  lListenerIdx: Integer;
begin
  lDistance := AMsg.Args.ReadDWord;
  if Assigned(OnDistance) then OnDistance(Self,lDistance);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_distance(Self,lDistance);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleTilt(var AMsg: TWaylandEventMessage);
var
  lTiltX: TWaylandFixed;
  lTiltY: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lTiltX := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lTiltY := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnTilt) then OnTilt(Self,lTiltX,lTiltY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_tilt(Self,lTiltX,lTiltY);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleRotation(var AMsg: TWaylandEventMessage);
var
  lDegrees: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lDegrees := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnRotation) then OnRotation(Self,lDegrees);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_rotation(Self,lDegrees);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleSlider(var AMsg: TWaylandEventMessage);
var
  lPosition: Integer;
  lListenerIdx: Integer;
begin
  lPosition := AMsg.Args.ReadInteger;
  if Assigned(OnSlider) then OnSlider(Self,lPosition);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_slider(Self,lPosition);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleWheel(var AMsg: TWaylandEventMessage);
var
  lDegrees: TWaylandFixed;
  lClicks: Integer;
  lListenerIdx: Integer;
begin
  lDegrees := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lClicks := AMsg.Args.ReadInteger;
  if Assigned(OnWheel) then OnWheel(Self,lDegrees,lClicks);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_wheel(Self,lDegrees,lClicks);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleButton(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lButton: DWord;
  lState: TButtonState;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lButton := AMsg.Args.ReadDWord;
  lState := TButtonState(AMsg.Args.ReadDWord);
  if Assigned(OnButton) then OnButton(Self,lSerial,lButton,lState);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_button(Self,lSerial,lButton,lState);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.HandleFrame(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  if Assigned(OnFrame) then OnFrame(Self,lTime);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_tool_v2_frame(Self,lTime);
  AMsg.SetHandled;
end;

procedure TWpTabletToolV2.SetCursor(aSerial: DWord; aSurface: TWlSurface; aHotspotX: Integer; aHotspotY: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_CURSOR), [aSerial,WlObjectId(aSurface),aHotspotX,aHotspotY]);
end;

destructor TWpTabletToolV2.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTabletToolV2.AddListener(AIntf: IWpTabletToolV2Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpTabletV2.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpTabletV2.GetInterfaceName: String;
begin
  Result := 'zwp_tablet_v2';
end;

procedure TWpTabletV2.HandleName(var AMsg: TWaylandEventMessage);
var
  lName: String;
  lListenerIdx: Integer;
begin
  lName := AMsg.Args.ReadString;
  if Assigned(OnName) then OnName(Self,lName);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_v2_name(Self,lName);
  AMsg.SetHandled;
end;

procedure TWpTabletV2.HandleId(var AMsg: TWaylandEventMessage);
var
  lVid: DWord;
  lPid: DWord;
  lListenerIdx: Integer;
begin
  lVid := AMsg.Args.ReadDWord;
  lPid := AMsg.Args.ReadDWord;
  if Assigned(OnId) then OnId(Self,lVid,lPid);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_v2_id(Self,lVid,lPid);
  AMsg.SetHandled;
end;

procedure TWpTabletV2.HandlePath(var AMsg: TWaylandEventMessage);
var
  lPath: String;
  lListenerIdx: Integer;
begin
  lPath := AMsg.Args.ReadString;
  if Assigned(OnPath) then OnPath(Self,lPath);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_v2_path(Self,lPath);
  AMsg.SetHandled;
end;

procedure TWpTabletV2.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_v2_done(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletV2.HandleRemoved(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnRemoved) then OnRemoved(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_v2_removed(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletV2.HandleBustype(var AMsg: TWaylandEventMessage);
var
  lBustype: TBustype;
  lListenerIdx: Integer;
begin
  lBustype := TBustype(AMsg.Args.ReadDWord);
  if Assigned(OnBustype) then OnBustype(Self,lBustype);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_v2_bustype(Self,lBustype);
  AMsg.SetHandled;
end;

destructor TWpTabletV2.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTabletV2.AddListener(AIntf: IWpTabletV2Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpTabletPadRingV2.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpTabletPadRingV2.GetInterfaceName: String;
begin
  Result := 'zwp_tablet_pad_ring_v2';
end;

procedure TWpTabletPadRingV2.HandleSource(var AMsg: TWaylandEventMessage);
var
  lSource: TSource;
  lListenerIdx: Integer;
begin
  lSource := TSource(AMsg.Args.ReadDWord);
  if Assigned(OnSource) then OnSource(Self,lSource);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_ring_v2_source(Self,lSource);
  AMsg.SetHandled;
end;

procedure TWpTabletPadRingV2.HandleAngle(var AMsg: TWaylandEventMessage);
var
  lDegrees: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lDegrees := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnAngle) then OnAngle(Self,lDegrees);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_ring_v2_angle(Self,lDegrees);
  AMsg.SetHandled;
end;

procedure TWpTabletPadRingV2.HandleStop(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnStop) then OnStop(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_ring_v2_stop(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletPadRingV2.HandleFrame(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  if Assigned(OnFrame) then OnFrame(Self,lTime);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_ring_v2_frame(Self,lTime);
  AMsg.SetHandled;
end;

procedure TWpTabletPadRingV2.SetFeedback(aDescription: String; aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_FEEDBACK), [aDescription,aSerial]);
end;

destructor TWpTabletPadRingV2.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTabletPadRingV2.AddListener(AIntf: IWpTabletPadRingV2Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpTabletPadStripV2.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpTabletPadStripV2.GetInterfaceName: String;
begin
  Result := 'zwp_tablet_pad_strip_v2';
end;

procedure TWpTabletPadStripV2.HandleSource(var AMsg: TWaylandEventMessage);
var
  lSource: TSource;
  lListenerIdx: Integer;
begin
  lSource := TSource(AMsg.Args.ReadDWord);
  if Assigned(OnSource) then OnSource(Self,lSource);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_strip_v2_source(Self,lSource);
  AMsg.SetHandled;
end;

procedure TWpTabletPadStripV2.HandlePosition(var AMsg: TWaylandEventMessage);
var
  lPosition: DWord;
  lListenerIdx: Integer;
begin
  lPosition := AMsg.Args.ReadDWord;
  if Assigned(OnPosition) then OnPosition(Self,lPosition);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_strip_v2_position(Self,lPosition);
  AMsg.SetHandled;
end;

procedure TWpTabletPadStripV2.HandleStop(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnStop) then OnStop(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_strip_v2_stop(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletPadStripV2.HandleFrame(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  if Assigned(OnFrame) then OnFrame(Self,lTime);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_strip_v2_frame(Self,lTime);
  AMsg.SetHandled;
end;

procedure TWpTabletPadStripV2.SetFeedback(aDescription: String; aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_FEEDBACK), [aDescription,aSerial]);
end;

destructor TWpTabletPadStripV2.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTabletPadStripV2.AddListener(AIntf: IWpTabletPadStripV2Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpTabletPadGroupV2.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpTabletPadGroupV2.GetInterfaceName: String;
begin
  Result := 'zwp_tablet_pad_group_v2';
end;

procedure TWpTabletPadGroupV2.HandleButtons(var AMsg: TWaylandEventMessage);
var
  lButtons: TBytes;
  lListenerIdx: Integer;
begin
  lButtons := AMsg.Args.ReadBlob;
  if Assigned(OnButtons) then OnButtons(Self,lButtons);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_group_v2_buttons(Self,lButtons);
  AMsg.SetHandled;
end;

procedure TWpTabletPadGroupV2.HandleRing(var AMsg: TWaylandEventMessage);
var
  lRing: TWpTabletPadRingV2;
  lListenerIdx: Integer;
begin
  lRing := TWpTabletPadRingV2.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnRing) then OnRing(Self,lRing);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_group_v2_ring(Self,lRing);
  AMsg.SetHandled;
end;

procedure TWpTabletPadGroupV2.HandleStrip(var AMsg: TWaylandEventMessage);
var
  lStrip: TWpTabletPadStripV2;
  lListenerIdx: Integer;
begin
  lStrip := TWpTabletPadStripV2.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnStrip) then OnStrip(Self,lStrip);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_group_v2_strip(Self,lStrip);
  AMsg.SetHandled;
end;

procedure TWpTabletPadGroupV2.HandleModes(var AMsg: TWaylandEventMessage);
var
  lModes: DWord;
  lListenerIdx: Integer;
begin
  lModes := AMsg.Args.ReadDWord;
  if Assigned(OnModes) then OnModes(Self,lModes);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_group_v2_modes(Self,lModes);
  AMsg.SetHandled;
end;

procedure TWpTabletPadGroupV2.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_group_v2_done(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletPadGroupV2.HandleModeSwitch(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lSerial: DWord;
  lMode: DWord;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  lSerial := AMsg.Args.ReadDWord;
  lMode := AMsg.Args.ReadDWord;
  if Assigned(OnModeSwitch) then OnModeSwitch(Self,lTime,lSerial,lMode);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_group_v2_mode_switch(Self,lTime,lSerial,lMode);
  AMsg.SetHandled;
end;

procedure TWpTabletPadGroupV2.HandleDial(var AMsg: TWaylandEventMessage);
var
  lDial: TWpTabletPadDialV2;
  lListenerIdx: Integer;
begin
  lDial := TWpTabletPadDialV2.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnDial) then OnDial(Self,lDial);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_group_v2_dial(Self,lDial);
  AMsg.SetHandled;
end;

destructor TWpTabletPadGroupV2.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTabletPadGroupV2.AddListener(AIntf: IWpTabletPadGroupV2Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpTabletPadV2.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpTabletPadV2.GetInterfaceName: String;
begin
  Result := 'zwp_tablet_pad_v2';
end;

procedure TWpTabletPadV2.HandleGroup(var AMsg: TWaylandEventMessage);
var
  lPadGroup: TWpTabletPadGroupV2;
  lListenerIdx: Integer;
begin
  lPadGroup := TWpTabletPadGroupV2.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnGroup) then OnGroup(Self,lPadGroup);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_v2_group(Self,lPadGroup);
  AMsg.SetHandled;
end;

procedure TWpTabletPadV2.HandlePath(var AMsg: TWaylandEventMessage);
var
  lPath: String;
  lListenerIdx: Integer;
begin
  lPath := AMsg.Args.ReadString;
  if Assigned(OnPath) then OnPath(Self,lPath);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_v2_path(Self,lPath);
  AMsg.SetHandled;
end;

procedure TWpTabletPadV2.HandleButtons(var AMsg: TWaylandEventMessage);
var
  lButtons: DWord;
  lListenerIdx: Integer;
begin
  lButtons := AMsg.Args.ReadDWord;
  if Assigned(OnButtons) then OnButtons(Self,lButtons);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_v2_buttons(Self,lButtons);
  AMsg.SetHandled;
end;

procedure TWpTabletPadV2.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_v2_done(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletPadV2.HandleButton(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lButton: DWord;
  lState: TButtonState;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  lButton := AMsg.Args.ReadDWord;
  lState := TButtonState(AMsg.Args.ReadDWord);
  if Assigned(OnButton) then OnButton(Self,lTime,lButton,lState);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_v2_button(Self,lTime,lButton,lState);
  AMsg.SetHandled;
end;

procedure TWpTabletPadV2.HandleEnter(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lTablet: TWpTabletV2;
  lSurface: TWlSurface;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lTablet := (Connection.GetObject(AMsg.Args.ReadDWord) as TWpTabletV2);
  lSurface := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlSurface);
  if Assigned(OnEnter) then OnEnter(Self,lSerial,lTablet,lSurface);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_v2_enter(Self,lSerial,lTablet,lSurface);
  AMsg.SetHandled;
end;

procedure TWpTabletPadV2.HandleLeave(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lSurface: TWlSurface;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lSurface := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlSurface);
  if Assigned(OnLeave) then OnLeave(Self,lSerial,lSurface);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_v2_leave(Self,lSerial,lSurface);
  AMsg.SetHandled;
end;

procedure TWpTabletPadV2.HandleRemoved(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnRemoved) then OnRemoved(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_v2_removed(Self);
  AMsg.SetHandled;
end;

procedure TWpTabletPadV2.SetFeedback(aButton: DWord; aDescription: String; aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_FEEDBACK), [aButton,aDescription,aSerial]);
end;

destructor TWpTabletPadV2.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTabletPadV2.AddListener(AIntf: IWpTabletPadV2Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWpTabletPadDialV2.GetInterfaceVersion: Integer;
begin
  Result := 2;
end;

class function TWpTabletPadDialV2.GetInterfaceName: String;
begin
  Result := 'zwp_tablet_pad_dial_v2';
end;

procedure TWpTabletPadDialV2.HandleDelta(var AMsg: TWaylandEventMessage);
var
  lValue120: Integer;
  lListenerIdx: Integer;
begin
  lValue120 := AMsg.Args.ReadInteger;
  if Assigned(OnDelta) then OnDelta(Self,lValue120);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_dial_v2_delta(Self,lValue120);
  AMsg.SetHandled;
end;

procedure TWpTabletPadDialV2.HandleFrame(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  if Assigned(OnFrame) then OnFrame(Self,lTime);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wp_tablet_pad_dial_v2_frame(Self,lTime);
  AMsg.SetHandled;
end;

procedure TWpTabletPadDialV2.SetFeedback(aDescription: String; aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_FEEDBACK), [aDescription,aSerial]);
end;

destructor TWpTabletPadDialV2.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWpTabletPadDialV2.AddListener(AIntf: IWpTabletPadDialV2Listener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.