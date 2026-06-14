unit wayland;

{$mode ObjFPC}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$modeswitch prefixedattributes}
{$interfaces corba}

interface
uses
  Classes, Sysutils, Wayland_Core, wayland_queue, wayland_internal_interfaces;

type
  TWlSubsurfaceClass = class of TWlSubsurface;
  { TWlSubsurface }
  TWlSubsurface = class;

  TWlSubcompositorClass = class of TWlSubcompositor;
  { TWlSubcompositor }
  TWlSubcompositor = class;

  TWlTouchClass = class of TWlTouch;
  { TWlTouch }
  TWlTouch = class;

  TWlKeyboardClass = class of TWlKeyboard;
  { TWlKeyboard }
  TWlKeyboard = class;

  TWlPointerClass = class of TWlPointer;
  { TWlPointer }
  TWlPointer = class;

  TWlOutputClass = class of TWlOutput;
  { TWlOutput }
  TWlOutput = class;

  TWlShellSurfaceClass = class of TWlShellSurface;
  { TWlShellSurface }
  TWlShellSurface = class;

  TWlShellClass = class of TWlShell;
  { TWlShell }
  TWlShell = class;

  TWlSeatClass = class of TWlSeat;
  { TWlSeat }
  TWlSeat = class;

  TWlDataDeviceClass = class of TWlDataDevice;
  { TWlDataDevice }
  TWlDataDevice = class;

  TWlDataSourceClass = class of TWlDataSource;
  { TWlDataSource }
  TWlDataSource = class;

  TWlDataDeviceManagerClass = class of TWlDataDeviceManager;
  { TWlDataDeviceManager }
  TWlDataDeviceManager = class;

  TWlDataOfferClass = class of TWlDataOffer;
  { TWlDataOffer }
  TWlDataOffer = class;

  TWlShmClass = class of TWlShm;
  { TWlShm }
  TWlShm = class;

  TWlBufferClass = class of TWlBuffer;
  { TWlBuffer }
  TWlBuffer = class;

  TWlShmPoolClass = class of TWlShmPool;
  { TWlShmPool }
  TWlShmPool = class;

  TWlRegionClass = class of TWlRegion;
  { TWlRegion }
  TWlRegion = class;

  TWlSurfaceClass = class of TWlSurface;
  { TWlSurface }
  TWlSurface = class;

  TWlCompositorClass = class of TWlCompositor;
  { TWlCompositor }
  TWlCompositor = class;

  TWlRegistryClass = class of TWlRegistry;
  { TWlRegistry }
  TWlRegistry = class;

  TWlCallbackClass = class of TWlCallback;
  { TWlCallback }
  TWlCallback = class;

  TWlDisplayClass = class of TWlDisplay;
  { TWlDisplay }
  TWlDisplay = class;

  IWlDisplayListener = interface;

  [TWLIntfAttribute('sync(n),get_registry(n)', 'error(ous),delete_id(u)')]
  { TWlDisplay }
  TWlDisplay = class(TWaylandDisplayBase)
  public type
    TError = (erInvalidobject = 0, erInvalidmethod = 1, erNomemory = 2, erImplementation = 3);
    TErrorEvent = procedure(Sender: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String) of object;
    TDeleteIdEvent = procedure(Sender: TWlDisplay; aId: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_SYNC = 0, _GET_REGISTRY = 1);
    TEvents = (EV_ERROR = 0, EV_DELETE_ID = 1);
  private
    FOnErrorPriv: TErrorEvent;
    FOnDeleteIdPriv: TDeleteIdEvent;
  protected
    procedure HandleError(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ERROR); virtual;
    procedure HandleDeleteId(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DELETE_ID); virtual;
  published
    property OnError: TErrorEvent read FOnErrorPriv write FOnErrorPriv;
    property OnDeleteId: TDeleteIdEvent read FOnDeleteIdPriv write FOnDeleteIdPriv;
  public
    function Sync(aClassType: TWlCallbackClass = nil): TWlCallback;
    function GetRegistry(aClassType: TWlRegistryClass = nil): TWlRegistry;
  private
    FListeners: array of IWlDisplayListener;
  public
    function AddListener(AIntf: IWlDisplayListener): LongInt;
  end;

  IWlDisplayListener = interface
  ['IWlDisplayListener']
    procedure wl_display_error(AWlDisplay: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String);
    procedure wl_display_delete_id(AWlDisplay: TWlDisplay; aId: DWord);
  end;

  IWlRegistryListener = interface;

  [TWLIntfAttribute('bind(un)', 'global(usu),global_remove(u)')]
  { TWlRegistry }
  TWlRegistry = class(TWaylandBase)
  public type
    TGlobalEvent = procedure(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord) of object;
    TGlobalRemoveEvent = procedure(Sender: TWlRegistry; aName: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_BIND = 0);
    TEvents = (EV_GLOBAL = 0, EV_GLOBAL_REMOVE = 1);
  private
    FOnGlobalPriv: TGlobalEvent;
    FOnGlobalRemovePriv: TGlobalRemoveEvent;
  protected
    procedure HandleGlobal(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_GLOBAL); virtual;
    procedure HandleGlobalRemove(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_GLOBAL_REMOVE); virtual;
  published
    property OnGlobal: TGlobalEvent read FOnGlobalPriv write FOnGlobalPriv;
    property OnGlobalRemove: TGlobalRemoveEvent read FOnGlobalRemovePriv write FOnGlobalRemovePriv;
  public
    procedure Bind(aInterfaceIndex: DWord; aInterfaceName: String; aInterfaceVersion: Integer; aClassType: TWaylandBaseClass; var aOutObject{aClassType});
  private
    FListeners: array of IWlRegistryListener;
  public
    function AddListener(AIntf: IWlRegistryListener): LongInt;
  end;

  IWlRegistryListener = interface
  ['IWlRegistryListener']
    procedure wl_registry_global(AWlRegistry: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord);
    procedure wl_registry_global_remove(AWlRegistry: TWlRegistry; aName: DWord);
  end;

  IWlCallbackListener = interface;

  [TWLIntfAttribute('', 'done(u)')]
  { TWlCallback }
  TWlCallback = class(TWaylandBase)
  public type
    TDoneEvent = procedure(Sender: TWlCallback; aCallbackData: DWord) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TEvents = (EV_DONE = 0);
  private
    FOnDonePriv: TDoneEvent;
    FIsDonePriv: Boolean;
  protected
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
  published
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
  private
    FListeners: array of IWlCallbackListener;
  public
    function AddListener(AIntf: IWlCallbackListener): LongInt;
    property IsDone: Boolean read FIsDonePriv;
  end;

  IWlCallbackListener = interface
  ['IWlCallbackListener']
    procedure wl_callback_done(AWlCallback: TWlCallback; aCallbackData: DWord);
  end;

  IWlCompositorListener = interface;

  [TWLIntfAttribute('create_surface(n),create_region(n)', '')]
  { TWlCompositor }
  TWlCompositor = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE_SURFACE = 0, _CREATE_REGION = 1);
  public
    function CreateSurface(aClassType: TWlSurfaceClass = nil): TWlSurface;
    function CreateRegion(aClassType: TWlRegionClass = nil): TWlRegion;
  private
    FListeners: array of IWlCompositorListener;
  public
    function AddListener(AIntf: IWlCompositorListener): LongInt;
  end;

  IWlCompositorListener = interface
  ['IWlCompositorListener']
  end;

  IWlShmPoolListener = interface;

  IWlShmListener = interface;

  [TWLIntfAttribute('create_pool(nhi)', 'format(u)')]
  { TWlShm }
  TWlShm = class(TWaylandBase)
  public type
    TError = (erInvalidformat = 0, erInvalidstride = 1, erInvalidfd = 2);
    TFormat = (foArgb8888 = 0, foXrgb8888 = 1, foC8 = 538982467, foRgb332 = 943867730, foBgr233 = 944916290, foXrgb4444 = 842093144, foXbgr4444 = 842089048, foRgbx4444 = 842094674, foBgrx4444 = 842094658, foArgb4444 = 842093121, foAbgr4444 = 842089025, foRgba4444 = 842088786, foBgra4444 = 842088770, foXrgb1555 = 892424792, foXbgr1555 = 892420696, foRgbx5551 = 892426322, foBgrx5551 = 892426306, foArgb1555 = 892424769, foAbgr1555 = 892420673, foRgba5551 = 892420434, foBgra5551 = 892420418, foRgb565 = 909199186, foBgr565 = 909199170, foRgb888 = 875710290, foBgr888 = 875710274, foXbgr8888 = 875709016, foRgbx8888 = 875714642, foBgrx8888 = 875714626, foAbgr8888 = 875708993, foRgba8888 = 875708754, foBgra8888 = 875708738, foXrgb2101010 = 808669784, foXbgr2101010 = 808665688, foRgbx1010102 = 808671314, foBgrx1010102 = 808671298, foArgb2101010 = 808669761, foAbgr2101010 = 808665665, foRgba1010102 = 808665426, foBgra1010102 = 808665410, foYuyv = 1448695129, foYvyu = 1431918169, foUyvy = 1498831189, foVyuy = 1498765654, foAyuv = 1448433985, foNv12 = 842094158, foNv21 = 825382478, foNv16 = 909203022, foNv61 = 825644622, foYuv410 = 961959257, foYvu410 = 961893977, foYuv411 = 825316697, foYvu411 = 825316953, foYuv420 = 842093913, foYvu420 = 842094169, foYuv422 = 909202777, foYvu422 = 909203033, foYuv444 = 875713881, foYvu444 = 875714137, foR8 = 538982482, foR16 = 540422482, foRg88 = 943212370, foGr88 = 943215175, foRg1616 = 842221394, foGr1616 = 842224199, foXrgb16161616f = 1211388504, foXbgr16161616f = 1211384408, foArgb16161616f = 1211388481, foAbgr16161616f = 1211384385, foXyuv8888 = 1448434008, foVuy888 = 875713878, foVuy101010 = 808670550, foY210 = 808530521, foY212 = 842084953, foY216 = 909193817, foY410 = 808531033, foY412 = 842085465, foY416 = 909194329, foXvyu2101010 = 808670808, foXvyu1216161616 = 909334104, foXvyu16161616 = 942954072, foY0l0 = 810299481, foX0l0 = 810299480, foY0l2 = 843853913, foX0l2 = 843853912, foYuv4208bit = 942691673, foYuv42010bit = 808539481, foXrgb8888a8 = 943805016, foXbgr8888a8 = 943800920, foRgbx8888a8 = 943806546, foBgrx8888a8 = 943806530, foRgb888a8 = 943798354, foBgr888a8 = 943798338, foRgb565a8 = 943797586, foBgr565a8 = 943797570, foNv24 = 875714126, foNv42 = 842290766, foP210 = 808530512, foP010 = 808530000, foP012 = 842084432, foP016 = 909193296, foAxbxgxrx106106106106 = 808534593, foNv15 = 892425806, foQ410 = 808531025, foQ401 = 825242705, foXrgb16161616 = 942953048, foXbgr16161616 = 942948952, foArgb16161616 = 942953025, foAbgr16161616 = 942948929);
    TFormatEvent = procedure(Sender: TWlShm; aFormat: TFormat) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE_POOL = 0);
    TEvents = (EV_FORMAT = 0);
  private
    FOnFormatPriv: TFormatEvent;
  protected
    procedure HandleFormat(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FORMAT); virtual;
  published
    property OnFormat: TFormatEvent read FOnFormatPriv write FOnFormatPriv;
  public
    function CreatePool(aFd: Integer; aSize: Integer; aClassType: TWlShmPoolClass = nil): TWlShmPool;
  private
    FListeners: array of IWlShmListener;
  public
    function AddListener(AIntf: IWlShmListener): LongInt;
    function AllocateShmBuffer(aWidth: Integer; aHeight: Integer; aFormat: TWlShm.TFormat; out aData: Pointer; out fd: Integer): TWlBuffer;
    function AllocateShmPool(aSize: Integer; aOutData: PPointer; aOutFd: PInteger): TWlShmPool;
  end;

  IWlShmListener = interface
  ['IWlShmListener']
    procedure wl_shm_format(AWlShm: TWlShm; aFormat: TWlShm.TFormat);
  end;

  [TWLIntfAttribute('create_buffer(niiiiu),destroy(),resize(i)', '')]
  { TWlShmPool }
  TWlShmPool = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE_BUFFER = 0, _DESTROY = 1, _RESIZE = 2);
  public
    function CreateBuffer(aOffset: Integer; aWidth: Integer; aHeight: Integer; aStride: Integer; aFormat: TWlShm.TFormat; aClassType: TWlBufferClass = nil): TWlBuffer;
    destructor Destroy; override;
    procedure Resize(aSize: Integer);
  private
    FListeners: array of IWlShmPoolListener;
  public
    function AddListener(AIntf: IWlShmPoolListener): LongInt;
  end;

  IWlShmPoolListener = interface
  ['IWlShmPoolListener']
  end;

  IWlBufferListener = interface;

  [TWLIntfAttribute('destroy()', 'release()')]
  { TWlBuffer }
  TWlBuffer = class(TWaylandBase)
  public type
    TReleaseEvent = procedure(Sender: TWlBuffer) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0);
    TEvents = (EV_RELEASE = 0);
  private
    FOnReleasePriv: TReleaseEvent;
  protected
    procedure HandleRelease(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_RELEASE); virtual;
  published
    property OnRelease: TReleaseEvent read FOnReleasePriv write FOnReleasePriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWlBufferListener;
  public
    function AddListener(AIntf: IWlBufferListener): LongInt;
  end;

  IWlBufferListener = interface
  ['IWlBufferListener']
    procedure wl_buffer_release(AWlBuffer: TWlBuffer);
  end;

  IWlDataOfferListener = interface;

  IWlDataDeviceManagerListener = interface;

  [TWLIntfAttribute('create_data_source(n),get_data_device(no)', '')]
  { TWlDataDeviceManager }
  TWlDataDeviceManager = class(TWaylandBase)
  public type
    { TWlDataDeviceManager.TDndAction }
    TDndAction = object(TBitfield)
    public
      property None: Boolean  index 0 read GetValue write SetValue;
      property Copy: Boolean  index 1 read GetValue write SetValue;
      property Move: Boolean  index 2 read GetValue write SetValue;
      property Ask: Boolean  index 4 read GetValue write SetValue;
    end;

  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_CREATE_DATA_SOURCE = 0, _GET_DATA_DEVICE = 1);
  public
    function CreateDataSource(aClassType: TWlDataSourceClass = nil): TWlDataSource;
    function GetDataDevice(aSeat: TWlSeat; aClassType: TWlDataDeviceClass = nil): TWlDataDevice;
  private
    FListeners: array of IWlDataDeviceManagerListener;
  public
    function AddListener(AIntf: IWlDataDeviceManagerListener): LongInt;
  end;

  IWlDataDeviceManagerListener = interface
  ['IWlDataDeviceManagerListener']
  end;

  [TWLIntfAttribute('accept(u?s),receive(sh),destroy(),finish(),set_actions(uu)', 'offer(s),source_actions(u),action(u)')]
  { TWlDataOffer }
  TWlDataOffer = class(TWaylandBase)
  public type
    TError = (erInvalidfinish = 0, erInvalidactionmask = 1, erInvalidaction = 2, erInvalidoffer = 3);
    TOfferEvent = procedure(Sender: TWlDataOffer; aMimeType: String) of object;
    TSourceActionsEvent = procedure(Sender: TWlDataOffer; aSourceActions: TWlDataDeviceManager.TDndAction) of object;
    TActionEvent = procedure(Sender: TWlDataOffer; aDndAction: TWlDataDeviceManager.TDndAction) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_ACCEPT = 0, _RECEIVE = 1, _DESTROY = 2, _FINISH = 3, _SET_ACTIONS = 4);
    TEvents = (EV_OFFER = 0, EV_SOURCE_ACTIONS = 1, EV_ACTION = 2);
  private
    FOnOfferPriv: TOfferEvent;
    FOnSourceActionsPriv: TSourceActionsEvent;
    FOnActionPriv: TActionEvent;
  protected
    procedure HandleOffer(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_OFFER); virtual;
    procedure HandleSourceActions(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SOURCE_ACTIONS); virtual;
    procedure HandleAction(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ACTION); virtual;
  published
    property OnOffer: TOfferEvent read FOnOfferPriv write FOnOfferPriv;
    property OnSourceActions: TSourceActionsEvent read FOnSourceActionsPriv write FOnSourceActionsPriv;
    property OnAction: TActionEvent read FOnActionPriv write FOnActionPriv;
  public
    procedure Accept(aSerial: DWord; aMimeType: String);
    procedure Receive(aMimeType: String; aFd: Integer);
    destructor Destroy; override;
    procedure Finish;
    procedure SetActions(aDndActions: TWlDataDeviceManager.TDndAction; aPreferredAction: TWlDataDeviceManager.TDndAction);
  private
    FListeners: array of IWlDataOfferListener;
  public
    function AddListener(AIntf: IWlDataOfferListener): LongInt;
  end;

  IWlDataOfferListener = interface
  ['IWlDataOfferListener']
    procedure wl_data_offer_offer(AWlDataOffer: TWlDataOffer; aMimeType: String);
    procedure wl_data_offer_source_actions(AWlDataOffer: TWlDataOffer; aSourceActions: TWlDataDeviceManager.TDndAction);
    procedure wl_data_offer_action(AWlDataOffer: TWlDataOffer; aDndAction: TWlDataDeviceManager.TDndAction);
  end;

  IWlDataSourceListener = interface;

  [TWLIntfAttribute('offer(s),destroy(),set_actions(u)', 'target(?s),send(sh),cancelled(),dnd_drop_performed(),dnd_finished(),action(u)')]
  { TWlDataSource }
  TWlDataSource = class(TWaylandBase)
  public type
    TError = (erInvalidactionmask = 0, erInvalidsource = 1);
    TTargetEvent = procedure(Sender: TWlDataSource; aMimeType: String) of object;
    TSendEvent = procedure(Sender: TWlDataSource; aMimeType: String; aFd: Integer) of object;
    TCancelledEvent = procedure(Sender: TWlDataSource) of object;
    TDndDropPerformedEvent = procedure(Sender: TWlDataSource) of object;
    TDndFinishedEvent = procedure(Sender: TWlDataSource) of object;
    TActionEvent = procedure(Sender: TWlDataSource; aDndAction: TWlDataDeviceManager.TDndAction) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_OFFER = 0, _DESTROY = 1, _SET_ACTIONS = 2);
    TEvents = (EV_TARGET = 0, EV_SEND = 1, EV_CANCELLED = 2, EV_DND_DROP_PERFORMED = 3, EV_DND_FINISHED = 4, EV_ACTION = 5);
  private
    FOnTargetPriv: TTargetEvent;
    FOnSendPriv: TSendEvent;
    FOnCancelledPriv: TCancelledEvent;
    FOnDndDropPerformedPriv: TDndDropPerformedEvent;
    FOnDndFinishedPriv: TDndFinishedEvent;
    FOnActionPriv: TActionEvent;
  protected
    procedure HandleTarget(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_TARGET); virtual;
    procedure HandleSend(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SEND); virtual;
    procedure HandleCancelled(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CANCELLED); virtual;
    procedure HandleDndDropPerformed(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DND_DROP_PERFORMED); virtual;
    procedure HandleDndFinished(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DND_FINISHED); virtual;
    procedure HandleAction(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ACTION); virtual;
  published
    property OnTarget: TTargetEvent read FOnTargetPriv write FOnTargetPriv;
    property OnSend: TSendEvent read FOnSendPriv write FOnSendPriv;
    property OnCancelled: TCancelledEvent read FOnCancelledPriv write FOnCancelledPriv;
    property OnDndDropPerformed: TDndDropPerformedEvent read FOnDndDropPerformedPriv write FOnDndDropPerformedPriv;
    property OnDndFinished: TDndFinishedEvent read FOnDndFinishedPriv write FOnDndFinishedPriv;
    property OnAction: TActionEvent read FOnActionPriv write FOnActionPriv;
  public
    procedure Offer(aMimeType: String);
    destructor Destroy; override;
    procedure SetActions(aDndActions: TWlDataDeviceManager.TDndAction);
  private
    FListeners: array of IWlDataSourceListener;
  public
    function AddListener(AIntf: IWlDataSourceListener): LongInt;
  end;

  IWlDataSourceListener = interface
  ['IWlDataSourceListener']
    procedure wl_data_source_target(AWlDataSource: TWlDataSource; aMimeType: String);
    procedure wl_data_source_send(AWlDataSource: TWlDataSource; aMimeType: String; aFd: Integer);
    procedure wl_data_source_cancelled(AWlDataSource: TWlDataSource);
    procedure wl_data_source_dnd_drop_performed(AWlDataSource: TWlDataSource);
    procedure wl_data_source_dnd_finished(AWlDataSource: TWlDataSource);
    procedure wl_data_source_action(AWlDataSource: TWlDataSource; aDndAction: TWlDataDeviceManager.TDndAction);
  end;

  IWlDataDeviceListener = interface;

  [TWLIntfAttribute('start_drag(?oo?ou),set_selection(?ou),release()', 'data_offer(n),enter(uoff?o),leave(),motion(uff),drop(),selection(?o)')]
  { TWlDataDevice }
  TWlDataDevice = class(TWaylandBase)
  public type
    TError = (erRole = 0);
    TDataOfferEvent = procedure(Sender: TWlDataDevice; aId: TWlDataOffer) of object;
    TEnterEvent = procedure(Sender: TWlDataDevice; aSerial: DWord; aSurface: TWlSurface; aX: TWaylandFixed; aY: TWaylandFixed; aId: TWlDataOffer) of object;
    TLeaveEvent = procedure(Sender: TWlDataDevice) of object;
    TMotionEvent = procedure(Sender: TWlDataDevice; aTime: DWord; aX: TWaylandFixed; aY: TWaylandFixed) of object;
    TDropEvent = procedure(Sender: TWlDataDevice) of object;
    TSelectionEvent = procedure(Sender: TWlDataDevice; aId: TWlDataOffer) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_START_DRAG = 0, _SET_SELECTION = 1, _RELEASE = 2);
    TEvents = (EV_DATA_OFFER = 0, EV_ENTER = 1, EV_LEAVE = 2, EV_MOTION = 3, EV_DROP = 4, EV_SELECTION = 5);
  private
    FOnDataOfferPriv: TDataOfferEvent;
    FOnEnterPriv: TEnterEvent;
    FOnLeavePriv: TLeaveEvent;
    FOnMotionPriv: TMotionEvent;
    FOnDropPriv: TDropEvent;
    FOnSelectionPriv: TSelectionEvent;
  protected
    procedure HandleDataOffer(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DATA_OFFER); virtual;
    procedure HandleEnter(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ENTER); virtual;
    procedure HandleLeave(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LEAVE); virtual;
    procedure HandleMotion(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_MOTION); virtual;
    procedure HandleDrop(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DROP); virtual;
    procedure HandleSelection(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SELECTION); virtual;
  published
    property OnDataOffer: TDataOfferEvent read FOnDataOfferPriv write FOnDataOfferPriv;
    property OnEnter: TEnterEvent read FOnEnterPriv write FOnEnterPriv;
    property OnLeave: TLeaveEvent read FOnLeavePriv write FOnLeavePriv;
    property OnMotion: TMotionEvent read FOnMotionPriv write FOnMotionPriv;
    property OnDrop: TDropEvent read FOnDropPriv write FOnDropPriv;
    property OnSelection: TSelectionEvent read FOnSelectionPriv write FOnSelectionPriv;
  public
    procedure StartDrag(aSource: TWlDataSource; aOrigin: TWlSurface; aIcon: TWlSurface; aSerial: DWord);
    procedure SetSelection(aSource: TWlDataSource; aSerial: DWord);
    destructor Destroy; override;
  private
    FListeners: array of IWlDataDeviceListener;
  public
    function AddListener(AIntf: IWlDataDeviceListener): LongInt;
  end;

  IWlDataDeviceListener = interface
  ['IWlDataDeviceListener']
    procedure wl_data_device_data_offer(AWlDataDevice: TWlDataDevice; aId: TWlDataOffer);
    procedure wl_data_device_enter(AWlDataDevice: TWlDataDevice; aSerial: DWord; aSurface: TWlSurface; aX: TWaylandFixed; aY: TWaylandFixed; aId: TWlDataOffer);
    procedure wl_data_device_leave(AWlDataDevice: TWlDataDevice);
    procedure wl_data_device_motion(AWlDataDevice: TWlDataDevice; aTime: DWord; aX: TWaylandFixed; aY: TWaylandFixed);
    procedure wl_data_device_drop(AWlDataDevice: TWlDataDevice);
    procedure wl_data_device_selection(AWlDataDevice: TWlDataDevice; aId: TWlDataOffer);
  end;

  IWlShellListener = interface;

  [TWLIntfAttribute('get_shell_surface(no)', '')]
  { TWlShell }
  TWlShell = class(TWaylandBase)
  public type
    TError = (erRole = 0);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_GET_SHELL_SURFACE = 0);
  public
    function GetShellSurface(aSurface: TWlSurface; aClassType: TWlShellSurfaceClass = nil): TWlShellSurface;
  private
    FListeners: array of IWlShellListener;
  public
    function AddListener(AIntf: IWlShellListener): LongInt;
  end;

  IWlShellListener = interface
  ['IWlShellListener']
  end;

  IWlShellSurfaceListener = interface;

  [TWLIntfAttribute('pong(u),move(ou),resize(ouu),set_toplevel(),set_transient(oiiu),set_fullscreen(uu?o),set_popup(ouoiiu),set_maximized(?o),set_title(s),set_class(s)', 'ping(u),configure(uii),popup_done()')]
  { TWlShellSurface }
  TWlShellSurface = class(TWaylandBase)
  public type
    { TWlShellSurface.TResize }
    TResize = object(TBitfield)
    public
      property None: Boolean  index 0 read GetValue write SetValue;
      property Top: Boolean  index 1 read GetValue write SetValue;
      property Bottom: Boolean  index 2 read GetValue write SetValue;
      property Left: Boolean  index 4 read GetValue write SetValue;
      property TopLeft: Boolean  index 5 read GetValue write SetValue;
      property BottomLeft: Boolean  index 6 read GetValue write SetValue;
      property Right: Boolean  index 8 read GetValue write SetValue;
      property TopRight: Boolean  index 9 read GetValue write SetValue;
      property BottomRight: Boolean  index 10 read GetValue write SetValue;
    end;

    { TWlShellSurface.TTransient }
    TTransient = object(TBitfield)
    public
      property Inactive: Boolean  index 1 read GetValue write SetValue;
    end;

    TFullscreenMethod = (fuDefault = 0, fuScale = 1, fuDriver = 2, fuFill = 3);
    TPingEvent = procedure(Sender: TWlShellSurface; aSerial: DWord) of object;
    TConfigureEvent = procedure(Sender: TWlShellSurface; aEdges: TResize; aWidth: Integer; aHeight: Integer) of object;
    TPopupDoneEvent = procedure(Sender: TWlShellSurface) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_PONG = 0, _MOVE = 1, _RESIZE = 2, _SET_TOPLEVEL = 3, _SET_TRANSIENT = 4, _SET_FULLSCREEN = 5, _SET_POPUP = 6, _SET_MAXIMIZED = 7, _SET_TITLE = 8, _SET_CLASS = 9);
    TEvents = (EV_PING = 0, EV_CONFIGURE = 1, EV_POPUP_DONE = 2);
  private
    FOnPingPriv: TPingEvent;
    FOnConfigurePriv: TConfigureEvent;
    FOnPopupDonePriv: TPopupDoneEvent;
  protected
    procedure HandlePing(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PING); virtual;
    procedure HandleConfigure(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CONFIGURE); virtual;
    procedure HandlePopupDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_POPUP_DONE); virtual;
  published
    property OnPing: TPingEvent read FOnPingPriv write FOnPingPriv;
    property OnConfigure: TConfigureEvent read FOnConfigurePriv write FOnConfigurePriv;
    property OnPopupDone: TPopupDoneEvent read FOnPopupDonePriv write FOnPopupDonePriv;
  public
    procedure Pong(aSerial: DWord);
    procedure Move(aSeat: TWlSeat; aSerial: DWord);
    procedure Resize(aSeat: TWlSeat; aSerial: DWord; aEdges: TResize);
    procedure SetToplevel;
    procedure SetTransient(aParent: TWlSurface; aX: Integer; aY: Integer; aFlags: TTransient);
    procedure SetFullscreen(aMethod: TFullscreenMethod; aFramerate: DWord; aOutput: TWlOutput);
    procedure SetPopup(aSeat: TWlSeat; aSerial: DWord; aParent: TWlSurface; aX: Integer; aY: Integer; aFlags: TTransient);
    procedure SetMaximized(aOutput: TWlOutput);
    procedure SetTitle(aTitle: String);
    procedure SetClass(aClass: String);
  private
    FListeners: array of IWlShellSurfaceListener;
  public
    function AddListener(AIntf: IWlShellSurfaceListener): LongInt;
  end;

  IWlShellSurfaceListener = interface
  ['IWlShellSurfaceListener']
    procedure wl_shell_surface_ping(AWlShellSurface: TWlShellSurface; aSerial: DWord);
    procedure wl_shell_surface_configure(AWlShellSurface: TWlShellSurface; aEdges: TWlShellSurface.TResize; aWidth: Integer; aHeight: Integer);
    procedure wl_shell_surface_popup_done(AWlShellSurface: TWlShellSurface);
  end;

  IWlSurfaceListener = interface;

  IWlOutputListener = interface;

  [TWLIntfAttribute('release()', 'geometry(iiiiissi),mode(uiii),done(),scale(i),name(s),description(s)')]
  { TWlOutput }
  TWlOutput = class(TWaylandBase)
  public type
    TSubpixel = (suUnknown = 0, suNone = 1, suHorizontalrgb = 2, suHorizontalbgr = 3, suVerticalrgb = 4, suVerticalbgr = 5);
    TTransform = (trNormal = 0, tr90 = 1, tr180 = 2, tr270 = 3, trFlipped = 4, trFlipped90 = 5, trFlipped180 = 6, trFlipped270 = 7);
    { TWlOutput.TMode }
    TMode = object(TBitfield)
    public
      property Current: Boolean  index 1 read GetValue write SetValue;
      property Preferred: Boolean  index 2 read GetValue write SetValue;
    end;

    TGeometryEvent = procedure(Sender: TWlOutput; aX: Integer; aY: Integer; aPhysicalWidth: Integer; aPhysicalHeight: Integer; aSubpixel: TSubpixel; aMake: String; aModel: String; aTransform: TTransform) of object;
    TModeEvent = procedure(Sender: TWlOutput; aFlags: TMode; aWidth: Integer; aHeight: Integer; aRefresh: Integer) of object;
    TDoneEvent = procedure(Sender: TWlOutput) of object;
    TScaleEvent = procedure(Sender: TWlOutput; aFactor: Integer) of object;
    TNameEvent = procedure(Sender: TWlOutput; aName: String) of object;
    TDescriptionEvent = procedure(Sender: TWlOutput; aDescription: String) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_RELEASE = 0);
    TEvents = (EV_GEOMETRY = 0, EV_MODE = 1, EV_DONE = 2, EV_SCALE = 3, EV_NAME = 4, EV_DESCRIPTION = 5);
  private
    FOnGeometryPriv: TGeometryEvent;
    FOnModePriv: TModeEvent;
    FOnDonePriv: TDoneEvent;
    FOnScalePriv: TScaleEvent;
    FOnNamePriv: TNameEvent;
    FOnDescriptionPriv: TDescriptionEvent;
  protected
    procedure HandleGeometry(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_GEOMETRY); virtual;
    procedure HandleMode(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_MODE); virtual;
    procedure HandleDone(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DONE); virtual;
    procedure HandleScale(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SCALE); virtual;
    procedure HandleName(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_NAME); virtual;
    procedure HandleDescription(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DESCRIPTION); virtual;
  published
    property OnGeometry: TGeometryEvent read FOnGeometryPriv write FOnGeometryPriv;
    property OnMode: TModeEvent read FOnModePriv write FOnModePriv;
    property OnDone: TDoneEvent read FOnDonePriv write FOnDonePriv;
    property OnScale: TScaleEvent read FOnScalePriv write FOnScalePriv;
    property OnName: TNameEvent read FOnNamePriv write FOnNamePriv;
    property OnDescription: TDescriptionEvent read FOnDescriptionPriv write FOnDescriptionPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWlOutputListener;
  public
    function AddListener(AIntf: IWlOutputListener): LongInt;
  end;

  IWlOutputListener = interface
  ['IWlOutputListener']
    procedure wl_output_geometry(AWlOutput: TWlOutput; aX: Integer; aY: Integer; aPhysicalWidth: Integer; aPhysicalHeight: Integer; aSubpixel: TWlOutput.TSubpixel; aMake: String; aModel: String; aTransform: TWlOutput.TTransform);
    procedure wl_output_mode(AWlOutput: TWlOutput; aFlags: TWlOutput.TMode; aWidth: Integer; aHeight: Integer; aRefresh: Integer);
    procedure wl_output_done(AWlOutput: TWlOutput);
    procedure wl_output_scale(AWlOutput: TWlOutput; aFactor: Integer);
    procedure wl_output_name(AWlOutput: TWlOutput; aName: String);
    procedure wl_output_description(AWlOutput: TWlOutput; aDescription: String);
  end;

  [TWLIntfAttribute('destroy(),attach(?oii),damage(iiii),frame(n),set_opaque_region(?o),set_input_region(?o),commit(),set_buffer_transform(i),set_buffer_scale(i),damage_buffer(iiii),offset(ii)', 'enter(o),leave(o),preferred_buffer_scale(i),preferred_buffer_transform(u)')]
  { TWlSurface }
  TWlSurface = class(TWaylandBase)
  public type
    TError = (erInvalidscale = 0, erInvalidtransform = 1, erInvalidsize = 2, erInvalidoffset = 3, erDefunctroleobject = 4);
    TEnterEvent = procedure(Sender: TWlSurface; aOutput: TWlOutput) of object;
    TLeaveEvent = procedure(Sender: TWlSurface; aOutput: TWlOutput) of object;
    TPreferredBufferScaleEvent = procedure(Sender: TWlSurface; aFactor: Integer) of object;
    TPreferredBufferTransformEvent = procedure(Sender: TWlSurface; aTransform: TWlOutput.TTransform) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _ATTACH = 1, _DAMAGE = 2, _FRAME = 3, _SET_OPAQUE_REGION = 4, _SET_INPUT_REGION = 5, _COMMIT = 6, _SET_BUFFER_TRANSFORM = 7, _SET_BUFFER_SCALE = 8, _DAMAGE_BUFFER = 9, _OFFSET = 10);
    TEvents = (EV_ENTER = 0, EV_LEAVE = 1, EV_PREFERRED_BUFFER_SCALE = 2, EV_PREFERRED_BUFFER_TRANSFORM = 3);
  private
    FOnEnterPriv: TEnterEvent;
    FOnLeavePriv: TLeaveEvent;
    FOnPreferredBufferScalePriv: TPreferredBufferScaleEvent;
    FOnPreferredBufferTransformPriv: TPreferredBufferTransformEvent;
  protected
    procedure HandleEnter(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ENTER); virtual;
    procedure HandleLeave(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LEAVE); virtual;
    procedure HandlePreferredBufferScale(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PREFERRED_BUFFER_SCALE); virtual;
    procedure HandlePreferredBufferTransform(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_PREFERRED_BUFFER_TRANSFORM); virtual;
  published
    property OnEnter: TEnterEvent read FOnEnterPriv write FOnEnterPriv;
    property OnLeave: TLeaveEvent read FOnLeavePriv write FOnLeavePriv;
    property OnPreferredBufferScale: TPreferredBufferScaleEvent read FOnPreferredBufferScalePriv write FOnPreferredBufferScalePriv;
    property OnPreferredBufferTransform: TPreferredBufferTransformEvent read FOnPreferredBufferTransformPriv write FOnPreferredBufferTransformPriv;
  public
    destructor Destroy; override;
    procedure Attach(aBuffer: TWlBuffer; aX: Integer; aY: Integer);
    procedure Damage(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
    function Frame(aClassType: TWlCallbackClass = nil): TWlCallback;
    procedure SetOpaqueRegion(aRegion: TWlRegion);
    procedure SetInputRegion(aRegion: TWlRegion);
    procedure Commit;
    procedure SetBufferTransform(aTransform: TWlOutput.TTransform);
    procedure SetBufferScale(aScale: Integer);
    procedure DamageBuffer(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
    procedure Offset(aX: Integer; aY: Integer);
  private
    FListeners: array of IWlSurfaceListener;
  public
    function AddListener(AIntf: IWlSurfaceListener): LongInt;
  end;

  IWlSurfaceListener = interface
  ['IWlSurfaceListener']
    procedure wl_surface_enter(AWlSurface: TWlSurface; aOutput: TWlOutput);
    procedure wl_surface_leave(AWlSurface: TWlSurface; aOutput: TWlOutput);
    procedure wl_surface_preferred_buffer_scale(AWlSurface: TWlSurface; aFactor: Integer);
    procedure wl_surface_preferred_buffer_transform(AWlSurface: TWlSurface; aTransform: TWlOutput.TTransform);
  end;

  IWlSeatListener = interface;

  [TWLIntfAttribute('get_pointer(n),get_keyboard(n),get_touch(n),release()', 'capabilities(u),name(s)')]
  { TWlSeat }
  TWlSeat = class(TWaylandBase)
  public type
    { TWlSeat.TCapability }
    TCapability = object(TBitfield)
    public
      property Pointer: Boolean  index 1 read GetValue write SetValue;
      property Keyboard: Boolean  index 2 read GetValue write SetValue;
      property Touch: Boolean  index 4 read GetValue write SetValue;
    end;

    TError = (erMissingcapability = 0);
    TCapabilitiesEvent = procedure(Sender: TWlSeat; aCapabilities: TCapability) of object;
    TNameEvent = procedure(Sender: TWlSeat; aName: String) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_GET_POINTER = 0, _GET_KEYBOARD = 1, _GET_TOUCH = 2, _RELEASE = 3);
    TEvents = (EV_CAPABILITIES = 0, EV_NAME = 1);
  private
    FOnCapabilitiesPriv: TCapabilitiesEvent;
    FOnNamePriv: TNameEvent;
  protected
    procedure HandleCapabilities(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CAPABILITIES); virtual;
    procedure HandleName(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_NAME); virtual;
  published
    property OnCapabilities: TCapabilitiesEvent read FOnCapabilitiesPriv write FOnCapabilitiesPriv;
    property OnName: TNameEvent read FOnNamePriv write FOnNamePriv;
  public
    function GetPointer(aClassType: TWlPointerClass = nil): TWlPointer;
    function GetKeyboard(aClassType: TWlKeyboardClass = nil): TWlKeyboard;
    function GetTouch(aClassType: TWlTouchClass = nil): TWlTouch;
    destructor Destroy; override;
  private
    FListeners: array of IWlSeatListener;
  public
    function AddListener(AIntf: IWlSeatListener): LongInt;
  end;

  IWlSeatListener = interface
  ['IWlSeatListener']
    procedure wl_seat_capabilities(AWlSeat: TWlSeat; aCapabilities: TWlSeat.TCapability);
    procedure wl_seat_name(AWlSeat: TWlSeat; aName: String);
  end;

  IWlPointerListener = interface;

  [TWLIntfAttribute('set_cursor(u?oii),release()', 'enter(uoff),leave(uo),motion(uff),button(uuuu),axis(uuf),frame(),axis_source(u),axis_stop(uu),axis_discrete(ui),axis_value120(ui),axis_relative_direction(uu)')]
  { TWlPointer }
  TWlPointer = class(TWaylandBase)
  public type
    TError = (erRole = 0);
    TButtonState = (buReleased = 0, buPressed = 1);
    TAxis = (axVerticalscroll = 0, axHorizontalscroll = 1);
    TAxisSource = (axWheel = 0, axFinger = 1, axContinuous = 2, axWheeltilt = 3);
    TAxisRelativeDirection = (axIdentical = 0, axInverted = 1);
    TEnterEvent = procedure(Sender: TWlPointer; aSerial: DWord; aSurface: TWlSurface; aSurfaceX: TWaylandFixed; aSurfaceY: TWaylandFixed) of object;
    TLeaveEvent = procedure(Sender: TWlPointer; aSerial: DWord; aSurface: TWlSurface) of object;
    TMotionEvent = procedure(Sender: TWlPointer; aTime: DWord; aSurfaceX: TWaylandFixed; aSurfaceY: TWaylandFixed) of object;
    TButtonEvent = procedure(Sender: TWlPointer; aSerial: DWord; aTime: DWord; aButton: DWord; aState: TButtonState) of object;
    TAxisEvent = procedure(Sender: TWlPointer; aTime: DWord; aAxis: TAxis; aValue: TWaylandFixed) of object;
    TFrameEvent = procedure(Sender: TWlPointer) of object;
    TAxisSourceEvent = procedure(Sender: TWlPointer; aAxisSource: TAxisSource) of object;
    TAxisStopEvent = procedure(Sender: TWlPointer; aTime: DWord; aAxis: TAxis) of object;
    TAxisDiscreteEvent = procedure(Sender: TWlPointer; aAxis: TAxis; aDiscrete: Integer) of object;
    TAxisValue120Event = procedure(Sender: TWlPointer; aAxis: TAxis; aValue120: Integer) of object;
    TAxisRelativeDirectionEvent = procedure(Sender: TWlPointer; aAxis: TAxis; aDirection: TAxisRelativeDirection) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_SET_CURSOR = 0, _RELEASE = 1);
    TEvents = (EV_ENTER = 0, EV_LEAVE = 1, EV_MOTION = 2, EV_BUTTON = 3, EV_AXIS = 4, EV_FRAME = 5, EV_AXIS_SOURCE = 6, EV_AXIS_STOP = 7, EV_AXIS_DISCRETE = 8, EV_AXIS_VALUE120 = 9, EV_AXIS_RELATIVE_DIRECTION = 10);
  private
    FOnEnterPriv: TEnterEvent;
    FOnLeavePriv: TLeaveEvent;
    FOnMotionPriv: TMotionEvent;
    FOnButtonPriv: TButtonEvent;
    FOnAxisPriv: TAxisEvent;
    FOnFramePriv: TFrameEvent;
    FOnAxisSourcePriv: TAxisSourceEvent;
    FOnAxisStopPriv: TAxisStopEvent;
    FOnAxisDiscretePriv: TAxisDiscreteEvent;
    FOnAxisValue120Priv: TAxisValue120Event;
    FOnAxisRelativeDirectionPriv: TAxisRelativeDirectionEvent;
  protected
    procedure HandleEnter(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ENTER); virtual;
    procedure HandleLeave(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LEAVE); virtual;
    procedure HandleMotion(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_MOTION); virtual;
    procedure HandleButton(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_BUTTON); virtual;
    procedure HandleAxis(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_AXIS); virtual;
    procedure HandleFrame(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FRAME); virtual;
    procedure HandleAxisSource(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_AXIS_SOURCE); virtual;
    procedure HandleAxisStop(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_AXIS_STOP); virtual;
    procedure HandleAxisDiscrete(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_AXIS_DISCRETE); virtual;
    procedure HandleAxisValue120(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_AXIS_VALUE120); virtual;
    procedure HandleAxisRelativeDirection(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_AXIS_RELATIVE_DIRECTION); virtual;
  published
    property OnEnter: TEnterEvent read FOnEnterPriv write FOnEnterPriv;
    property OnLeave: TLeaveEvent read FOnLeavePriv write FOnLeavePriv;
    property OnMotion: TMotionEvent read FOnMotionPriv write FOnMotionPriv;
    property OnButton: TButtonEvent read FOnButtonPriv write FOnButtonPriv;
    property OnAxis: TAxisEvent read FOnAxisPriv write FOnAxisPriv;
    property OnFrame: TFrameEvent read FOnFramePriv write FOnFramePriv;
    property OnAxisSource: TAxisSourceEvent read FOnAxisSourcePriv write FOnAxisSourcePriv;
    property OnAxisStop: TAxisStopEvent read FOnAxisStopPriv write FOnAxisStopPriv;
    property OnAxisDiscrete: TAxisDiscreteEvent read FOnAxisDiscretePriv write FOnAxisDiscretePriv;
    property OnAxisValue120: TAxisValue120Event read FOnAxisValue120Priv write FOnAxisValue120Priv;
    property OnAxisRelativeDirection: TAxisRelativeDirectionEvent read FOnAxisRelativeDirectionPriv write FOnAxisRelativeDirectionPriv;
  public
    procedure SetCursor(aSerial: DWord; aSurface: TWlSurface; aHotspotX: Integer; aHotspotY: Integer);
    destructor Destroy; override;
  private
    FListeners: array of IWlPointerListener;
  public
    function AddListener(AIntf: IWlPointerListener): LongInt;
  end;

  IWlPointerListener = interface
  ['IWlPointerListener']
    procedure wl_pointer_enter(AWlPointer: TWlPointer; aSerial: DWord; aSurface: TWlSurface; aSurfaceX: TWaylandFixed; aSurfaceY: TWaylandFixed);
    procedure wl_pointer_leave(AWlPointer: TWlPointer; aSerial: DWord; aSurface: TWlSurface);
    procedure wl_pointer_motion(AWlPointer: TWlPointer; aTime: DWord; aSurfaceX: TWaylandFixed; aSurfaceY: TWaylandFixed);
    procedure wl_pointer_button(AWlPointer: TWlPointer; aSerial: DWord; aTime: DWord; aButton: DWord; aState: TWlPointer.TButtonState);
    procedure wl_pointer_axis(AWlPointer: TWlPointer; aTime: DWord; aAxis: TWlPointer.TAxis; aValue: TWaylandFixed);
    procedure wl_pointer_frame(AWlPointer: TWlPointer);
    procedure wl_pointer_axis_source(AWlPointer: TWlPointer; aAxisSource: TWlPointer.TAxisSource);
    procedure wl_pointer_axis_stop(AWlPointer: TWlPointer; aTime: DWord; aAxis: TWlPointer.TAxis);
    procedure wl_pointer_axis_discrete(AWlPointer: TWlPointer; aAxis: TWlPointer.TAxis; aDiscrete: Integer);
    procedure wl_pointer_axis_value120(AWlPointer: TWlPointer; aAxis: TWlPointer.TAxis; aValue120: Integer);
    procedure wl_pointer_axis_relative_direction(AWlPointer: TWlPointer; aAxis: TWlPointer.TAxis; aDirection: TWlPointer.TAxisRelativeDirection);
  end;

  IWlKeyboardListener = interface;

  [TWLIntfAttribute('release()', 'keymap(uhu),enter(uoa),leave(uo),key(uuuu),modifiers(uuuuu),repeat_info(ii)')]
  { TWlKeyboard }
  TWlKeyboard = class(TWaylandBase)
  public type
    TKeymapFormat = (keNokeymap = 0, keXkbv1 = 1);
    TKeyState = (keReleased = 0, kePressed = 1);
    TKeymapEvent = procedure(Sender: TWlKeyboard; aFormat: TKeymapFormat; aFd: Integer; aSize: DWord) of object;
    TEnterEvent = procedure(Sender: TWlKeyboard; aSerial: DWord; aSurface: TWlSurface; aKeys: TBytes) of object;
    TLeaveEvent = procedure(Sender: TWlKeyboard; aSerial: DWord; aSurface: TWlSurface) of object;
    TKeyEvent = procedure(Sender: TWlKeyboard; aSerial: DWord; aTime: DWord; aKey: DWord; aState: TKeyState) of object;
    TModifiersEvent = procedure(Sender: TWlKeyboard; aSerial: DWord; aModsDepressed: DWord; aModsLatched: DWord; aModsLocked: DWord; aGroup: DWord) of object;
    TRepeatInfoEvent = procedure(Sender: TWlKeyboard; aRate: Integer; aDelay: Integer) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_RELEASE = 0);
    TEvents = (EV_KEYMAP = 0, EV_ENTER = 1, EV_LEAVE = 2, EV_KEY = 3, EV_MODIFIERS = 4, EV_REPEAT_INFO = 5);
  private
    FOnKeymapPriv: TKeymapEvent;
    FOnEnterPriv: TEnterEvent;
    FOnLeavePriv: TLeaveEvent;
    FOnKeyPriv: TKeyEvent;
    FOnModifiersPriv: TModifiersEvent;
    FOnRepeatInfoPriv: TRepeatInfoEvent;
  protected
    procedure HandleKeymap(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_KEYMAP); virtual;
    procedure HandleEnter(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ENTER); virtual;
    procedure HandleLeave(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_LEAVE); virtual;
    procedure HandleKey(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_KEY); virtual;
    procedure HandleModifiers(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_MODIFIERS); virtual;
    procedure HandleRepeatInfo(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_REPEAT_INFO); virtual;
  published
    property OnKeymap: TKeymapEvent read FOnKeymapPriv write FOnKeymapPriv;
    property OnEnter: TEnterEvent read FOnEnterPriv write FOnEnterPriv;
    property OnLeave: TLeaveEvent read FOnLeavePriv write FOnLeavePriv;
    property OnKey: TKeyEvent read FOnKeyPriv write FOnKeyPriv;
    property OnModifiers: TModifiersEvent read FOnModifiersPriv write FOnModifiersPriv;
    property OnRepeatInfo: TRepeatInfoEvent read FOnRepeatInfoPriv write FOnRepeatInfoPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWlKeyboardListener;
  public
    function AddListener(AIntf: IWlKeyboardListener): LongInt;
  end;

  IWlKeyboardListener = interface
  ['IWlKeyboardListener']
    procedure wl_keyboard_keymap(AWlKeyboard: TWlKeyboard; aFormat: TWlKeyboard.TKeymapFormat; aFd: Integer; aSize: DWord);
    procedure wl_keyboard_enter(AWlKeyboard: TWlKeyboard; aSerial: DWord; aSurface: TWlSurface; aKeys: TBytes);
    procedure wl_keyboard_leave(AWlKeyboard: TWlKeyboard; aSerial: DWord; aSurface: TWlSurface);
    procedure wl_keyboard_key(AWlKeyboard: TWlKeyboard; aSerial: DWord; aTime: DWord; aKey: DWord; aState: TWlKeyboard.TKeyState);
    procedure wl_keyboard_modifiers(AWlKeyboard: TWlKeyboard; aSerial: DWord; aModsDepressed: DWord; aModsLatched: DWord; aModsLocked: DWord; aGroup: DWord);
    procedure wl_keyboard_repeat_info(AWlKeyboard: TWlKeyboard; aRate: Integer; aDelay: Integer);
  end;

  IWlTouchListener = interface;

  [TWLIntfAttribute('release()', 'down(uuoiff),up(uui),motion(uiff),frame(),cancel(),shape(iff),orientation(if)')]
  { TWlTouch }
  TWlTouch = class(TWaylandBase)
  public type
    TDownEvent = procedure(Sender: TWlTouch; aSerial: DWord; aTime: DWord; aSurface: TWlSurface; aId: Integer; aX: TWaylandFixed; aY: TWaylandFixed) of object;
    TUpEvent = procedure(Sender: TWlTouch; aSerial: DWord; aTime: DWord; aId: Integer) of object;
    TMotionEvent = procedure(Sender: TWlTouch; aTime: DWord; aId: Integer; aX: TWaylandFixed; aY: TWaylandFixed) of object;
    TFrameEvent = procedure(Sender: TWlTouch) of object;
    TCancelEvent = procedure(Sender: TWlTouch) of object;
    TShapeEvent = procedure(Sender: TWlTouch; aId: Integer; aMajor: TWaylandFixed; aMinor: TWaylandFixed) of object;
    TOrientationEvent = procedure(Sender: TWlTouch; aId: Integer; aOrientation: TWaylandFixed) of object;
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_RELEASE = 0);
    TEvents = (EV_DOWN = 0, EV_UP = 1, EV_MOTION = 2, EV_FRAME = 3, EV_CANCEL = 4, EV_SHAPE = 5, EV_ORIENTATION = 6);
  private
    FOnDownPriv: TDownEvent;
    FOnUpPriv: TUpEvent;
    FOnMotionPriv: TMotionEvent;
    FOnFramePriv: TFrameEvent;
    FOnCancelPriv: TCancelEvent;
    FOnShapePriv: TShapeEvent;
    FOnOrientationPriv: TOrientationEvent;
  protected
    procedure HandleDown(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_DOWN); virtual;
    procedure HandleUp(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_UP); virtual;
    procedure HandleMotion(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_MOTION); virtual;
    procedure HandleFrame(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_FRAME); virtual;
    procedure HandleCancel(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_CANCEL); virtual;
    procedure HandleShape(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_SHAPE); virtual;
    procedure HandleOrientation(var AMsg: TWaylandEventMessage); message Ord(TEvents.EV_ORIENTATION); virtual;
  published
    property OnDown: TDownEvent read FOnDownPriv write FOnDownPriv;
    property OnUp: TUpEvent read FOnUpPriv write FOnUpPriv;
    property OnMotion: TMotionEvent read FOnMotionPriv write FOnMotionPriv;
    property OnFrame: TFrameEvent read FOnFramePriv write FOnFramePriv;
    property OnCancel: TCancelEvent read FOnCancelPriv write FOnCancelPriv;
    property OnShape: TShapeEvent read FOnShapePriv write FOnShapePriv;
    property OnOrientation: TOrientationEvent read FOnOrientationPriv write FOnOrientationPriv;
  public
    destructor Destroy; override;
  private
    FListeners: array of IWlTouchListener;
  public
    function AddListener(AIntf: IWlTouchListener): LongInt;
  end;

  IWlTouchListener = interface
  ['IWlTouchListener']
    procedure wl_touch_down(AWlTouch: TWlTouch; aSerial: DWord; aTime: DWord; aSurface: TWlSurface; aId: Integer; aX: TWaylandFixed; aY: TWaylandFixed);
    procedure wl_touch_up(AWlTouch: TWlTouch; aSerial: DWord; aTime: DWord; aId: Integer);
    procedure wl_touch_motion(AWlTouch: TWlTouch; aTime: DWord; aId: Integer; aX: TWaylandFixed; aY: TWaylandFixed);
    procedure wl_touch_frame(AWlTouch: TWlTouch);
    procedure wl_touch_cancel(AWlTouch: TWlTouch);
    procedure wl_touch_shape(AWlTouch: TWlTouch; aId: Integer; aMajor: TWaylandFixed; aMinor: TWaylandFixed);
    procedure wl_touch_orientation(AWlTouch: TWlTouch; aId: Integer; aOrientation: TWaylandFixed);
  end;

  IWlRegionListener = interface;

  [TWLIntfAttribute('destroy(),add(iiii),subtract(iiii)', '')]
  { TWlRegion }
  TWlRegion = class(TWaylandBase)
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _ADD = 1, _SUBTRACT = 2);
  public
    destructor Destroy; override;
    procedure Add(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
    procedure Subtract(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
  private
    FListeners: array of IWlRegionListener;
  public
    function AddListener(AIntf: IWlRegionListener): LongInt;
  end;

  IWlRegionListener = interface
  ['IWlRegionListener']
  end;

  IWlSubcompositorListener = interface;

  [TWLIntfAttribute('destroy(),get_subsurface(noo)', '')]
  { TWlSubcompositor }
  TWlSubcompositor = class(TWaylandBase)
  public type
    TError = (erBadsurface = 0, erBadparent = 1);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _GET_SUBSURFACE = 1);
  public
    destructor Destroy; override;
    function GetSubsurface(aSurface: TWlSurface; aParent: TWlSurface; aClassType: TWlSubsurfaceClass = nil): TWlSubsurface;
  private
    FListeners: array of IWlSubcompositorListener;
  public
    function AddListener(AIntf: IWlSubcompositorListener): LongInt;
  end;

  IWlSubcompositorListener = interface
  ['IWlSubcompositorListener']
  end;

  IWlSubsurfaceListener = interface;

  [TWLIntfAttribute('destroy(),set_position(ii),place_above(o),place_below(o),set_sync(),set_desync()', '')]
  { TWlSubsurface }
  TWlSubsurface = class(TWaylandBase)
  public type
    TError = (erBadsurface = 0);
  protected
    class function GetInterfaceVersion: Integer; override;
    class function GetInterfaceName: String; override;
  protected type
    TRequests = (_DESTROY = 0, _SET_POSITION = 1, _PLACE_ABOVE = 2, _PLACE_BELOW = 3, _SET_SYNC = 4, _SET_DESYNC = 5);
  public
    destructor Destroy; override;
    procedure SetPosition(aX: Integer; aY: Integer);
    procedure PlaceAbove(aSibling: TWlSurface);
    procedure PlaceBelow(aSibling: TWlSurface);
    procedure SetSync;
    procedure SetDesync;
  private
    FListeners: array of IWlSubsurfaceListener;
  public
    function AddListener(AIntf: IWlSubsurfaceListener): LongInt;
  end;

  IWlSubsurfaceListener = interface
  ['IWlSubsurfaceListener']
  end;

implementation
uses
  wayland_shm_impl, wayland_stream, wayland_interfaces;

class function TWlDisplay.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlDisplay.GetInterfaceName: String;
begin
  Result := 'wl_display';
end;

procedure TWlDisplay.HandleError(var AMsg: TWaylandEventMessage);
var
  lObjectId: Cardinal;
  lCode: DWord;
  lMessage: String;
  lListenerIdx: Integer;
begin
  lObjectId := AMsg.Args.ReadDWord;
  lCode := AMsg.Args.ReadDWord;
  lMessage := AMsg.Args.ReadString;
  if Assigned(OnError) then OnError(Self,lObjectId,lCode,lMessage);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_display_error(Self,lObjectId,lCode,lMessage);
  AMsg.SetHandled;
end;

procedure TWlDisplay.HandleDeleteId(var AMsg: TWaylandEventMessage);
var
  lId: DWord;
  lListenerIdx: Integer;
begin
  lId := AMsg.Args.ReadDWord;
  if Assigned(OnDeleteId) then OnDeleteId(Self,lId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_display_delete_id(Self,lId);
  AMsg.SetHandled;
end;

function TWlDisplay.Sync(aClassType: TWlCallbackClass = nil): TWlCallback;
begin
  if aClassType = nil then aClassType := TWlCallback;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._SYNC), [Result.GetObjectId]);
end;

function TWlDisplay.GetRegistry(aClassType: TWlRegistryClass = nil): TWlRegistry;
begin
  if aClassType = nil then aClassType := TWlRegistry;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_REGISTRY), [Result.GetObjectId]);
end;

function TWlDisplay.AddListener(AIntf: IWlDisplayListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlRegistry.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlRegistry.GetInterfaceName: String;
begin
  Result := 'wl_registry';
end;

procedure TWlRegistry.HandleGlobal(var AMsg: TWaylandEventMessage);
var
  lName: DWord;
  lInterface: String;
  lVersion: DWord;
  lListenerIdx: Integer;
begin
  lName := AMsg.Args.ReadDWord;
  lInterface := AMsg.Args.ReadString;
  lVersion := AMsg.Args.ReadDWord;
  if Assigned(OnGlobal) then OnGlobal(Self,lName,lInterface,lVersion);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_registry_global(Self,lName,lInterface,lVersion);
  AMsg.SetHandled;
end;

procedure TWlRegistry.HandleGlobalRemove(var AMsg: TWaylandEventMessage);
var
  lName: DWord;
  lListenerIdx: Integer;
begin
  lName := AMsg.Args.ReadDWord;
  if Assigned(OnGlobalRemove) then OnGlobalRemove(Self,lName);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_registry_global_remove(Self,lName);
  AMsg.SetHandled;
end;

procedure TWlRegistry.Bind(aInterfaceIndex: DWord; aInterfaceName: String; aInterfaceVersion: Integer; aClassType: TWaylandBaseClass; var aOutObject{aClassType});
var
  lVersion: Integer;
begin
  lVersion := aClassType.GetInterfaceVersion;
  if lVersion > aInterfaceVersion then
    lVersion := aInterfaceVersion;
  if aInterfaceName <> AClassType.GetInterfaceName then
    raise Exception.CreateFmt('interface names must match: %s != %s', [TWaylandBase(aOutObject).GetInterfaceName, aInterfaceName]);
  TWaylandBase(aOutObject) := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._BIND), [aInterfaceIndex, TWaylandBase(aOutObject).GetInterfaceName, lVersion,TWaylandBase(aOutObject).GetObjectId]);
  TWaylandBase(aOutObject).SetProtocolVersion(lVersion);
end;

function TWlRegistry.AddListener(AIntf: IWlRegistryListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlCallback.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlCallback.GetInterfaceName: String;
begin
  Result := 'wl_callback';
end;

procedure TWlCallback.HandleDone(var AMsg: TWaylandEventMessage);
var
  lCallbackData: DWord;
  lListenerIdx: Integer;
begin
  lCallbackData := AMsg.Args.ReadDWord;
  if Assigned(OnDone) then OnDone(Self,lCallbackData);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_callback_done(Self,lCallbackData);
  AMsg.SetHandled;
  FIsDonePriv := True;
end;

function TWlCallback.AddListener(AIntf: IWlCallbackListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlCompositor.GetInterfaceVersion: Integer;
begin
  Result := 6;
end;

class function TWlCompositor.GetInterfaceName: String;
begin
  Result := 'wl_compositor';
end;

function TWlCompositor.CreateSurface(aClassType: TWlSurfaceClass = nil): TWlSurface;
begin
  if aClassType = nil then aClassType := TWlSurface;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_SURFACE), [Result.GetObjectId]);
end;

function TWlCompositor.CreateRegion(aClassType: TWlRegionClass = nil): TWlRegion;
begin
  if aClassType = nil then aClassType := TWlRegion;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_REGION), [Result.GetObjectId]);
end;

function TWlCompositor.AddListener(AIntf: IWlCompositorListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlShmPool.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlShmPool.GetInterfaceName: String;
begin
  Result := 'wl_shm_pool';
end;

class function TWlShm.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlShm.GetInterfaceName: String;
begin
  Result := 'wl_shm';
end;

procedure TWlShm.HandleFormat(var AMsg: TWaylandEventMessage);
var
  lFormat: TFormat;
  lListenerIdx: Integer;
begin
  lFormat := TFormat(AMsg.Args.ReadDWord);
  if Assigned(OnFormat) then OnFormat(Self,lFormat);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_shm_format(Self,lFormat);
  AMsg.SetHandled;
end;

function TWlShm.CreatePool(aFd: Integer; aSize: Integer; aClassType: TWlShmPoolClass = nil): TWlShmPool;
begin
  if aClassType = nil then aClassType := TWlShmPool;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_POOL), [Result.GetObjectId,aFd,aSize], 1);
end;

function TWlShm.AddListener(AIntf: IWlShmListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

function TWlShm.AllocateShmBuffer(aWidth: Integer; aHeight: Integer; aFormat: TWlShm.TFormat; out aData: Pointer; out fd: Integer): TWlBuffer;
begin
  Result := Create_shm_buffer(Self, aWidth, aHeight, aFormat, aData, fd);
end;

function TWlShm.AllocateShmPool(aSize: Integer; aOutData: PPointer; aOutFd: PInteger): TWlShmPool;
begin
  Result := Create_shm_pool(Self, aSize, aOutData, aOutFd);
end;

function TWlShmPool.CreateBuffer(aOffset: Integer; aWidth: Integer; aHeight: Integer; aStride: Integer; aFormat: TWlShm.TFormat; aClassType: TWlBufferClass = nil): TWlBuffer;
begin
  if aClassType = nil then aClassType := TWlBuffer;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_BUFFER), [Result.GetObjectId,aOffset,aWidth,aHeight,aStride,DWord(aFormat)]);
end;

destructor TWlShmPool.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWlShmPool.Resize(aSize: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RESIZE), [aSize]);
end;

function TWlShmPool.AddListener(AIntf: IWlShmPoolListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlBuffer.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlBuffer.GetInterfaceName: String;
begin
  Result := 'wl_buffer';
end;

procedure TWlBuffer.HandleRelease(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnRelease) then OnRelease(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_buffer_release(Self);
  AMsg.SetHandled;
end;

destructor TWlBuffer.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWlBuffer.AddListener(AIntf: IWlBufferListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlDataOffer.GetInterfaceVersion: Integer;
begin
  Result := 3;
end;

class function TWlDataOffer.GetInterfaceName: String;
begin
  Result := 'wl_data_offer';
end;

procedure TWlDataOffer.HandleOffer(var AMsg: TWaylandEventMessage);
var
  lMimeType: String;
  lListenerIdx: Integer;
begin
  lMimeType := AMsg.Args.ReadString;
  if Assigned(OnOffer) then OnOffer(Self,lMimeType);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_offer_offer(Self,lMimeType);
  AMsg.SetHandled;
end;

class function TWlDataDeviceManager.GetInterfaceVersion: Integer;
begin
  Result := 3;
end;

class function TWlDataDeviceManager.GetInterfaceName: String;
begin
  Result := 'wl_data_device_manager';
end;

function TWlDataDeviceManager.CreateDataSource(aClassType: TWlDataSourceClass = nil): TWlDataSource;
begin
  if aClassType = nil then aClassType := TWlDataSource;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._CREATE_DATA_SOURCE), [Result.GetObjectId]);
end;

function TWlDataDeviceManager.GetDataDevice(aSeat: TWlSeat; aClassType: TWlDataDeviceClass = nil): TWlDataDevice;
begin
  if aClassType = nil then aClassType := TWlDataDevice;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_DATA_DEVICE), [Result.GetObjectId,aSeat.GetObjectId]);
end;

function TWlDataDeviceManager.AddListener(AIntf: IWlDataDeviceManagerListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

procedure TWlDataOffer.HandleSourceActions(var AMsg: TWaylandEventMessage);
var
  lSourceActions: TWlDataDeviceManager.TDndAction;
  lListenerIdx: Integer;
begin
  lSourceActions := TWlDataDeviceManager.TDndAction(AMsg.Args.ReadDWord);
  if Assigned(OnSourceActions) then OnSourceActions(Self,lSourceActions);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_offer_source_actions(Self,lSourceActions);
  AMsg.SetHandled;
end;

procedure TWlDataOffer.HandleAction(var AMsg: TWaylandEventMessage);
var
  lDndAction: TWlDataDeviceManager.TDndAction;
  lListenerIdx: Integer;
begin
  lDndAction := TWlDataDeviceManager.TDndAction(AMsg.Args.ReadDWord);
  if Assigned(OnAction) then OnAction(Self,lDndAction);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_offer_action(Self,lDndAction);
  AMsg.SetHandled;
end;

procedure TWlDataOffer.Accept(aSerial: DWord; aMimeType: String);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._ACCEPT), [aSerial,aMimeType]);
end;

procedure TWlDataOffer.Receive(aMimeType: String; aFd: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RECEIVE), [aMimeType,aFd], 1);
end;

destructor TWlDataOffer.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWlDataOffer.Finish;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._FINISH), []);
end;

procedure TWlDataOffer.SetActions(aDndActions: TWlDataDeviceManager.TDndAction; aPreferredAction: TWlDataDeviceManager.TDndAction);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_ACTIONS), [DWord(aDndActions),DWord(aPreferredAction)]);
end;

function TWlDataOffer.AddListener(AIntf: IWlDataOfferListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlDataSource.GetInterfaceVersion: Integer;
begin
  Result := 3;
end;

class function TWlDataSource.GetInterfaceName: String;
begin
  Result := 'wl_data_source';
end;

procedure TWlDataSource.HandleTarget(var AMsg: TWaylandEventMessage);
var
  lMimeType: String;
  lListenerIdx: Integer;
begin
  lMimeType := AMsg.Args.ReadString;
  if Assigned(OnTarget) then OnTarget(Self,lMimeType);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_source_target(Self,lMimeType);
  AMsg.SetHandled;
end;

procedure TWlDataSource.HandleSend(var AMsg: TWaylandEventMessage);
var
  lMimeType: String;
  lFd: Integer;
  lListenerIdx: Integer;
begin
  lMimeType := AMsg.Args.ReadString;
  lFd := AMsg.Args.ReadInteger;
  if Assigned(OnSend) then OnSend(Self,lMimeType,lFd);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_source_send(Self,lMimeType,lFd);
  AMsg.SetHandled;
end;

procedure TWlDataSource.HandleCancelled(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnCancelled) then OnCancelled(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_source_cancelled(Self);
  AMsg.SetHandled;
end;

procedure TWlDataSource.HandleDndDropPerformed(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDndDropPerformed) then OnDndDropPerformed(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_source_dnd_drop_performed(Self);
  AMsg.SetHandled;
end;

procedure TWlDataSource.HandleDndFinished(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDndFinished) then OnDndFinished(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_source_dnd_finished(Self);
  AMsg.SetHandled;
end;

procedure TWlDataSource.HandleAction(var AMsg: TWaylandEventMessage);
var
  lDndAction: TWlDataDeviceManager.TDndAction;
  lListenerIdx: Integer;
begin
  lDndAction := TWlDataDeviceManager.TDndAction(AMsg.Args.ReadDWord);
  if Assigned(OnAction) then OnAction(Self,lDndAction);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_source_action(Self,lDndAction);
  AMsg.SetHandled;
end;

procedure TWlDataSource.Offer(aMimeType: String);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._OFFER), [aMimeType]);
end;

destructor TWlDataSource.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWlDataSource.SetActions(aDndActions: TWlDataDeviceManager.TDndAction);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_ACTIONS), [DWord(aDndActions)]);
end;

function TWlDataSource.AddListener(AIntf: IWlDataSourceListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlDataDevice.GetInterfaceVersion: Integer;
begin
  Result := 3;
end;

class function TWlDataDevice.GetInterfaceName: String;
begin
  Result := 'wl_data_device';
end;

procedure TWlDataDevice.HandleDataOffer(var AMsg: TWaylandEventMessage);
var
  lId: TWlDataOffer;
  lListenerIdx: Integer;
begin
  lId := TWlDataOffer.Create(Connection, nil, AMsg.Args.ReadDWord);
  if Assigned(OnDataOffer) then OnDataOffer(Self,lId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_device_data_offer(Self,lId);
  AMsg.SetHandled;
end;

procedure TWlDataDevice.HandleEnter(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lSurface: TWlSurface;
  lX: TWaylandFixed;
  lY: TWaylandFixed;
  lId: TWlDataOffer;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lSurface := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlSurface);
  lX := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lY := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lId := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlDataOffer);
  if Assigned(OnEnter) then OnEnter(Self,lSerial,lSurface,lX,lY,lId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_device_enter(Self,lSerial,lSurface,lX,lY,lId);
  AMsg.SetHandled;
end;

procedure TWlDataDevice.HandleLeave(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnLeave) then OnLeave(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_device_leave(Self);
  AMsg.SetHandled;
end;

procedure TWlDataDevice.HandleMotion(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lX: TWaylandFixed;
  lY: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  lX := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lY := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnMotion) then OnMotion(Self,lTime,lX,lY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_device_motion(Self,lTime,lX,lY);
  AMsg.SetHandled;
end;

procedure TWlDataDevice.HandleDrop(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDrop) then OnDrop(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_device_drop(Self);
  AMsg.SetHandled;
end;

procedure TWlDataDevice.HandleSelection(var AMsg: TWaylandEventMessage);
var
  lId: TWlDataOffer;
  lListenerIdx: Integer;
begin
  lId := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlDataOffer);
  if Assigned(OnSelection) then OnSelection(Self,lId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_data_device_selection(Self,lId);
  AMsg.SetHandled;
end;

procedure TWlDataDevice.StartDrag(aSource: TWlDataSource; aOrigin: TWlSurface; aIcon: TWlSurface; aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._START_DRAG), [WlObjectId(aSource),aOrigin.GetObjectId,WlObjectId(aIcon),aSerial]);
end;

procedure TWlDataDevice.SetSelection(aSource: TWlDataSource; aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_SELECTION), [WlObjectId(aSource),aSerial]);
end;

destructor TWlDataDevice.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RELEASE), []);
  inherited Destroy;
end;

function TWlDataDevice.AddListener(AIntf: IWlDataDeviceListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlShell.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlShell.GetInterfaceName: String;
begin
  Result := 'wl_shell';
end;

function TWlShell.GetShellSurface(aSurface: TWlSurface; aClassType: TWlShellSurfaceClass = nil): TWlShellSurface;
begin
  if aClassType = nil then aClassType := TWlShellSurface;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_SHELL_SURFACE), [Result.GetObjectId,aSurface.GetObjectId]);
end;

function TWlShell.AddListener(AIntf: IWlShellListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlShellSurface.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlShellSurface.GetInterfaceName: String;
begin
  Result := 'wl_shell_surface';
end;

procedure TWlShellSurface.HandlePing(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  if Assigned(OnPing) then OnPing(Self,lSerial);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_shell_surface_ping(Self,lSerial);
  AMsg.SetHandled;
end;

procedure TWlShellSurface.HandleConfigure(var AMsg: TWaylandEventMessage);
var
  lEdges: TResize;
  lWidth: Integer;
  lHeight: Integer;
  lListenerIdx: Integer;
begin
  lEdges := TResize(AMsg.Args.ReadDWord);
  lWidth := AMsg.Args.ReadInteger;
  lHeight := AMsg.Args.ReadInteger;
  if Assigned(OnConfigure) then OnConfigure(Self,lEdges,lWidth,lHeight);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_shell_surface_configure(Self,lEdges,lWidth,lHeight);
  AMsg.SetHandled;
end;

procedure TWlShellSurface.HandlePopupDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnPopupDone) then OnPopupDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_shell_surface_popup_done(Self);
  AMsg.SetHandled;
end;

procedure TWlShellSurface.Pong(aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._PONG), [aSerial]);
end;

procedure TWlShellSurface.Move(aSeat: TWlSeat; aSerial: DWord);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._MOVE), [aSeat.GetObjectId,aSerial]);
end;

procedure TWlShellSurface.Resize(aSeat: TWlSeat; aSerial: DWord; aEdges: TResize);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RESIZE), [aSeat.GetObjectId,aSerial,DWord(aEdges)]);
end;

procedure TWlShellSurface.SetToplevel;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_TOPLEVEL), []);
end;

procedure TWlShellSurface.SetTransient(aParent: TWlSurface; aX: Integer; aY: Integer; aFlags: TTransient);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_TRANSIENT), [aParent.GetObjectId,aX,aY,DWord(aFlags)]);
end;

procedure TWlShellSurface.SetFullscreen(aMethod: TFullscreenMethod; aFramerate: DWord; aOutput: TWlOutput);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_FULLSCREEN), [DWord(aMethod),aFramerate,WlObjectId(aOutput)]);
end;

procedure TWlShellSurface.SetPopup(aSeat: TWlSeat; aSerial: DWord; aParent: TWlSurface; aX: Integer; aY: Integer; aFlags: TTransient);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_POPUP), [aSeat.GetObjectId,aSerial,aParent.GetObjectId,aX,aY,DWord(aFlags)]);
end;

procedure TWlShellSurface.SetMaximized(aOutput: TWlOutput);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_MAXIMIZED), [WlObjectId(aOutput)]);
end;

procedure TWlShellSurface.SetTitle(aTitle: String);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_TITLE), [aTitle]);
end;

procedure TWlShellSurface.SetClass(aClass: String);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_CLASS), [aClass]);
end;

function TWlShellSurface.AddListener(AIntf: IWlShellSurfaceListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlSurface.GetInterfaceVersion: Integer;
begin
  Result := 6;
end;

class function TWlSurface.GetInterfaceName: String;
begin
  Result := 'wl_surface';
end;

procedure TWlSurface.HandleEnter(var AMsg: TWaylandEventMessage);
var
  lOutput: TWlOutput;
  lListenerIdx: Integer;
begin
  lOutput := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlOutput);
  if Assigned(OnEnter) then OnEnter(Self,lOutput);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_surface_enter(Self,lOutput);
  AMsg.SetHandled;
end;

procedure TWlSurface.HandleLeave(var AMsg: TWaylandEventMessage);
var
  lOutput: TWlOutput;
  lListenerIdx: Integer;
begin
  lOutput := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlOutput);
  if Assigned(OnLeave) then OnLeave(Self,lOutput);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_surface_leave(Self,lOutput);
  AMsg.SetHandled;
end;

procedure TWlSurface.HandlePreferredBufferScale(var AMsg: TWaylandEventMessage);
var
  lFactor: Integer;
  lListenerIdx: Integer;
begin
  lFactor := AMsg.Args.ReadInteger;
  if Assigned(OnPreferredBufferScale) then OnPreferredBufferScale(Self,lFactor);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_surface_preferred_buffer_scale(Self,lFactor);
  AMsg.SetHandled;
end;

class function TWlOutput.GetInterfaceVersion: Integer;
begin
  Result := 4;
end;

class function TWlOutput.GetInterfaceName: String;
begin
  Result := 'wl_output';
end;

procedure TWlOutput.HandleGeometry(var AMsg: TWaylandEventMessage);
var
  lX: Integer;
  lY: Integer;
  lPhysicalWidth: Integer;
  lPhysicalHeight: Integer;
  lSubpixel: TSubpixel;
  lMake: String;
  lModel: String;
  lTransform: TTransform;
  lListenerIdx: Integer;
begin
  lX := AMsg.Args.ReadInteger;
  lY := AMsg.Args.ReadInteger;
  lPhysicalWidth := AMsg.Args.ReadInteger;
  lPhysicalHeight := AMsg.Args.ReadInteger;
  lSubpixel := TSubpixel(AMsg.Args.ReadInteger);
  lMake := AMsg.Args.ReadString;
  lModel := AMsg.Args.ReadString;
  lTransform := TTransform(AMsg.Args.ReadInteger);
  if Assigned(OnGeometry) then OnGeometry(Self,lX,lY,lPhysicalWidth,lPhysicalHeight,lSubpixel,lMake,lModel,lTransform);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_output_geometry(Self,lX,lY,lPhysicalWidth,lPhysicalHeight,lSubpixel,lMake,lModel,lTransform);
  AMsg.SetHandled;
end;

procedure TWlOutput.HandleMode(var AMsg: TWaylandEventMessage);
var
  lFlags: TMode;
  lWidth: Integer;
  lHeight: Integer;
  lRefresh: Integer;
  lListenerIdx: Integer;
begin
  lFlags := TMode(AMsg.Args.ReadDWord);
  lWidth := AMsg.Args.ReadInteger;
  lHeight := AMsg.Args.ReadInteger;
  lRefresh := AMsg.Args.ReadInteger;
  if Assigned(OnMode) then OnMode(Self,lFlags,lWidth,lHeight,lRefresh);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_output_mode(Self,lFlags,lWidth,lHeight,lRefresh);
  AMsg.SetHandled;
end;

procedure TWlOutput.HandleDone(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnDone) then OnDone(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_output_done(Self);
  AMsg.SetHandled;
end;

procedure TWlOutput.HandleScale(var AMsg: TWaylandEventMessage);
var
  lFactor: Integer;
  lListenerIdx: Integer;
begin
  lFactor := AMsg.Args.ReadInteger;
  if Assigned(OnScale) then OnScale(Self,lFactor);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_output_scale(Self,lFactor);
  AMsg.SetHandled;
end;

procedure TWlOutput.HandleName(var AMsg: TWaylandEventMessage);
var
  lName: String;
  lListenerIdx: Integer;
begin
  lName := AMsg.Args.ReadString;
  if Assigned(OnName) then OnName(Self,lName);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_output_name(Self,lName);
  AMsg.SetHandled;
end;

procedure TWlOutput.HandleDescription(var AMsg: TWaylandEventMessage);
var
  lDescription: String;
  lListenerIdx: Integer;
begin
  lDescription := AMsg.Args.ReadString;
  if Assigned(OnDescription) then OnDescription(Self,lDescription);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_output_description(Self,lDescription);
  AMsg.SetHandled;
end;

destructor TWlOutput.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RELEASE), []);
  inherited Destroy;
end;

function TWlOutput.AddListener(AIntf: IWlOutputListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

procedure TWlSurface.HandlePreferredBufferTransform(var AMsg: TWaylandEventMessage);
var
  lTransform: TWlOutput.TTransform;
  lListenerIdx: Integer;
begin
  lTransform := TWlOutput.TTransform(AMsg.Args.ReadDWord);
  if Assigned(OnPreferredBufferTransform) then OnPreferredBufferTransform(Self,lTransform);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_surface_preferred_buffer_transform(Self,lTransform);
  AMsg.SetHandled;
end;

destructor TWlSurface.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWlSurface.Attach(aBuffer: TWlBuffer; aX: Integer; aY: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._ATTACH), [WlObjectId(aBuffer),aX,aY]);
end;

procedure TWlSurface.Damage(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DAMAGE), [aX,aY,aWidth,aHeight]);
end;

function TWlSurface.Frame(aClassType: TWlCallbackClass = nil): TWlCallback;
begin
  if aClassType = nil then aClassType := TWlCallback;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._FRAME), [Result.GetObjectId]);
end;

procedure TWlSurface.SetOpaqueRegion(aRegion: TWlRegion);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_OPAQUE_REGION), [WlObjectId(aRegion)]);
end;

procedure TWlSurface.SetInputRegion(aRegion: TWlRegion);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_INPUT_REGION), [WlObjectId(aRegion)]);
end;

procedure TWlSurface.Commit;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._COMMIT), []);
end;

procedure TWlSurface.SetBufferTransform(aTransform: TWlOutput.TTransform);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_BUFFER_TRANSFORM), [DWord(aTransform)]);
end;

procedure TWlSurface.SetBufferScale(aScale: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_BUFFER_SCALE), [aScale]);
end;

procedure TWlSurface.DamageBuffer(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DAMAGE_BUFFER), [aX,aY,aWidth,aHeight]);
end;

procedure TWlSurface.Offset(aX: Integer; aY: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._OFFSET), [aX,aY]);
end;

function TWlSurface.AddListener(AIntf: IWlSurfaceListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlSeat.GetInterfaceVersion: Integer;
begin
  Result := 9;
end;

class function TWlSeat.GetInterfaceName: String;
begin
  Result := 'wl_seat';
end;

procedure TWlSeat.HandleCapabilities(var AMsg: TWaylandEventMessage);
var
  lCapabilities: TCapability;
  lListenerIdx: Integer;
begin
  lCapabilities := TCapability(AMsg.Args.ReadDWord);
  if Assigned(OnCapabilities) then OnCapabilities(Self,lCapabilities);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_seat_capabilities(Self,lCapabilities);
  AMsg.SetHandled;
end;

procedure TWlSeat.HandleName(var AMsg: TWaylandEventMessage);
var
  lName: String;
  lListenerIdx: Integer;
begin
  lName := AMsg.Args.ReadString;
  if Assigned(OnName) then OnName(Self,lName);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_seat_name(Self,lName);
  AMsg.SetHandled;
end;

function TWlSeat.GetPointer(aClassType: TWlPointerClass = nil): TWlPointer;
begin
  if aClassType = nil then aClassType := TWlPointer;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_POINTER), [Result.GetObjectId]);
end;

function TWlSeat.GetKeyboard(aClassType: TWlKeyboardClass = nil): TWlKeyboard;
begin
  if aClassType = nil then aClassType := TWlKeyboard;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_KEYBOARD), [Result.GetObjectId]);
end;

function TWlSeat.GetTouch(aClassType: TWlTouchClass = nil): TWlTouch;
begin
  if aClassType = nil then aClassType := TWlTouch;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_TOUCH), [Result.GetObjectId]);
end;

destructor TWlSeat.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RELEASE), []);
  inherited Destroy;
end;

function TWlSeat.AddListener(AIntf: IWlSeatListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlPointer.GetInterfaceVersion: Integer;
begin
  Result := 9;
end;

class function TWlPointer.GetInterfaceName: String;
begin
  Result := 'wl_pointer';
end;

procedure TWlPointer.HandleEnter(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lSurface: TWlSurface;
  lSurfaceX: TWaylandFixed;
  lSurfaceY: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lSurface := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlSurface);
  lSurfaceX := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lSurfaceY := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnEnter) then OnEnter(Self,lSerial,lSurface,lSurfaceX,lSurfaceY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_enter(Self,lSerial,lSurface,lSurfaceX,lSurfaceY);
  AMsg.SetHandled;
end;

procedure TWlPointer.HandleLeave(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lSurface: TWlSurface;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lSurface := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlSurface);
  if Assigned(OnLeave) then OnLeave(Self,lSerial,lSurface);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_leave(Self,lSerial,lSurface);
  AMsg.SetHandled;
end;

procedure TWlPointer.HandleMotion(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lSurfaceX: TWaylandFixed;
  lSurfaceY: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  lSurfaceX := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lSurfaceY := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnMotion) then OnMotion(Self,lTime,lSurfaceX,lSurfaceY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_motion(Self,lTime,lSurfaceX,lSurfaceY);
  AMsg.SetHandled;
end;

procedure TWlPointer.HandleButton(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lTime: DWord;
  lButton: DWord;
  lState: TButtonState;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lTime := AMsg.Args.ReadDWord;
  lButton := AMsg.Args.ReadDWord;
  lState := TButtonState(AMsg.Args.ReadDWord);
  if Assigned(OnButton) then OnButton(Self,lSerial,lTime,lButton,lState);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_button(Self,lSerial,lTime,lButton,lState);
  AMsg.SetHandled;
end;

procedure TWlPointer.HandleAxis(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lAxis: TAxis;
  lValue: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  lAxis := TAxis(AMsg.Args.ReadDWord);
  lValue := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnAxis) then OnAxis(Self,lTime,lAxis,lValue);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_axis(Self,lTime,lAxis,lValue);
  AMsg.SetHandled;
end;

procedure TWlPointer.HandleFrame(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnFrame) then OnFrame(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_frame(Self);
  AMsg.SetHandled;
end;

procedure TWlPointer.HandleAxisSource(var AMsg: TWaylandEventMessage);
var
  lAxisSource: TAxisSource;
  lListenerIdx: Integer;
begin
  lAxisSource := TAxisSource(AMsg.Args.ReadDWord);
  if Assigned(OnAxisSource) then OnAxisSource(Self,lAxisSource);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_axis_source(Self,lAxisSource);
  AMsg.SetHandled;
end;

procedure TWlPointer.HandleAxisStop(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lAxis: TAxis;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  lAxis := TAxis(AMsg.Args.ReadDWord);
  if Assigned(OnAxisStop) then OnAxisStop(Self,lTime,lAxis);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_axis_stop(Self,lTime,lAxis);
  AMsg.SetHandled;
end;

procedure TWlPointer.HandleAxisDiscrete(var AMsg: TWaylandEventMessage);
var
  lAxis: TAxis;
  lDiscrete: Integer;
  lListenerIdx: Integer;
begin
  lAxis := TAxis(AMsg.Args.ReadDWord);
  lDiscrete := AMsg.Args.ReadInteger;
  if Assigned(OnAxisDiscrete) then OnAxisDiscrete(Self,lAxis,lDiscrete);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_axis_discrete(Self,lAxis,lDiscrete);
  AMsg.SetHandled;
end;

procedure TWlPointer.HandleAxisValue120(var AMsg: TWaylandEventMessage);
var
  lAxis: TAxis;
  lValue120: Integer;
  lListenerIdx: Integer;
begin
  lAxis := TAxis(AMsg.Args.ReadDWord);
  lValue120 := AMsg.Args.ReadInteger;
  if Assigned(OnAxisValue120) then OnAxisValue120(Self,lAxis,lValue120);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_axis_value120(Self,lAxis,lValue120);
  AMsg.SetHandled;
end;

procedure TWlPointer.HandleAxisRelativeDirection(var AMsg: TWaylandEventMessage);
var
  lAxis: TAxis;
  lDirection: TAxisRelativeDirection;
  lListenerIdx: Integer;
begin
  lAxis := TAxis(AMsg.Args.ReadDWord);
  lDirection := TAxisRelativeDirection(AMsg.Args.ReadDWord);
  if Assigned(OnAxisRelativeDirection) then OnAxisRelativeDirection(Self,lAxis,lDirection);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_pointer_axis_relative_direction(Self,lAxis,lDirection);
  AMsg.SetHandled;
end;

procedure TWlPointer.SetCursor(aSerial: DWord; aSurface: TWlSurface; aHotspotX: Integer; aHotspotY: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_CURSOR), [aSerial,WlObjectId(aSurface),aHotspotX,aHotspotY]);
end;

destructor TWlPointer.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RELEASE), []);
  inherited Destroy;
end;

function TWlPointer.AddListener(AIntf: IWlPointerListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlKeyboard.GetInterfaceVersion: Integer;
begin
  Result := 9;
end;

class function TWlKeyboard.GetInterfaceName: String;
begin
  Result := 'wl_keyboard';
end;

procedure TWlKeyboard.HandleKeymap(var AMsg: TWaylandEventMessage);
var
  lFormat: TKeymapFormat;
  lFd: Integer;
  lSize: DWord;
  lListenerIdx: Integer;
begin
  lFormat := TKeymapFormat(AMsg.Args.ReadDWord);
  lFd := AMsg.Args.ReadInteger;
  lSize := AMsg.Args.ReadDWord;
  if Assigned(OnKeymap) then OnKeymap(Self,lFormat,lFd,lSize);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_keyboard_keymap(Self,lFormat,lFd,lSize);
  AMsg.SetHandled;
end;

procedure TWlKeyboard.HandleEnter(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lSurface: TWlSurface;
  lKeys: TBytes;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lSurface := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlSurface);
  lKeys := AMsg.Args.ReadBlob;
  if Assigned(OnEnter) then OnEnter(Self,lSerial,lSurface,lKeys);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_keyboard_enter(Self,lSerial,lSurface,lKeys);
  AMsg.SetHandled;
end;

procedure TWlKeyboard.HandleLeave(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lSurface: TWlSurface;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lSurface := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlSurface);
  if Assigned(OnLeave) then OnLeave(Self,lSerial,lSurface);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_keyboard_leave(Self,lSerial,lSurface);
  AMsg.SetHandled;
end;

procedure TWlKeyboard.HandleKey(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lTime: DWord;
  lKey: DWord;
  lState: TKeyState;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lTime := AMsg.Args.ReadDWord;
  lKey := AMsg.Args.ReadDWord;
  lState := TKeyState(AMsg.Args.ReadDWord);
  if Assigned(OnKey) then OnKey(Self,lSerial,lTime,lKey,lState);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_keyboard_key(Self,lSerial,lTime,lKey,lState);
  AMsg.SetHandled;
end;

procedure TWlKeyboard.HandleModifiers(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lModsDepressed: DWord;
  lModsLatched: DWord;
  lModsLocked: DWord;
  lGroup: DWord;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lModsDepressed := AMsg.Args.ReadDWord;
  lModsLatched := AMsg.Args.ReadDWord;
  lModsLocked := AMsg.Args.ReadDWord;
  lGroup := AMsg.Args.ReadDWord;
  if Assigned(OnModifiers) then OnModifiers(Self,lSerial,lModsDepressed,lModsLatched,lModsLocked,lGroup);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_keyboard_modifiers(Self,lSerial,lModsDepressed,lModsLatched,lModsLocked,lGroup);
  AMsg.SetHandled;
end;

procedure TWlKeyboard.HandleRepeatInfo(var AMsg: TWaylandEventMessage);
var
  lRate: Integer;
  lDelay: Integer;
  lListenerIdx: Integer;
begin
  lRate := AMsg.Args.ReadInteger;
  lDelay := AMsg.Args.ReadInteger;
  if Assigned(OnRepeatInfo) then OnRepeatInfo(Self,lRate,lDelay);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_keyboard_repeat_info(Self,lRate,lDelay);
  AMsg.SetHandled;
end;

destructor TWlKeyboard.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RELEASE), []);
  inherited Destroy;
end;

function TWlKeyboard.AddListener(AIntf: IWlKeyboardListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlTouch.GetInterfaceVersion: Integer;
begin
  Result := 9;
end;

class function TWlTouch.GetInterfaceName: String;
begin
  Result := 'wl_touch';
end;

procedure TWlTouch.HandleDown(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lTime: DWord;
  lSurface: TWlSurface;
  lId: Integer;
  lX: TWaylandFixed;
  lY: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lTime := AMsg.Args.ReadDWord;
  lSurface := (Connection.GetObject(AMsg.Args.ReadDWord) as TWlSurface);
  lId := AMsg.Args.ReadInteger;
  lX := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lY := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnDown) then OnDown(Self,lSerial,lTime,lSurface,lId,lX,lY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_touch_down(Self,lSerial,lTime,lSurface,lId,lX,lY);
  AMsg.SetHandled;
end;

procedure TWlTouch.HandleUp(var AMsg: TWaylandEventMessage);
var
  lSerial: DWord;
  lTime: DWord;
  lId: Integer;
  lListenerIdx: Integer;
begin
  lSerial := AMsg.Args.ReadDWord;
  lTime := AMsg.Args.ReadDWord;
  lId := AMsg.Args.ReadInteger;
  if Assigned(OnUp) then OnUp(Self,lSerial,lTime,lId);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_touch_up(Self,lSerial,lTime,lId);
  AMsg.SetHandled;
end;

procedure TWlTouch.HandleMotion(var AMsg: TWaylandEventMessage);
var
  lTime: DWord;
  lId: Integer;
  lX: TWaylandFixed;
  lY: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lTime := AMsg.Args.ReadDWord;
  lId := AMsg.Args.ReadInteger;
  lX := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lY := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnMotion) then OnMotion(Self,lTime,lId,lX,lY);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_touch_motion(Self,lTime,lId,lX,lY);
  AMsg.SetHandled;
end;

procedure TWlTouch.HandleFrame(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnFrame) then OnFrame(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_touch_frame(Self);
  AMsg.SetHandled;
end;

procedure TWlTouch.HandleCancel(var AMsg: TWaylandEventMessage);
var
  lListenerIdx: Integer;
begin
  if Assigned(OnCancel) then OnCancel(Self);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_touch_cancel(Self);
  AMsg.SetHandled;
end;

procedure TWlTouch.HandleShape(var AMsg: TWaylandEventMessage);
var
  lId: Integer;
  lMajor: TWaylandFixed;
  lMinor: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lId := AMsg.Args.ReadInteger;
  lMajor := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  lMinor := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnShape) then OnShape(Self,lId,lMajor,lMinor);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_touch_shape(Self,lId,lMajor,lMinor);
  AMsg.SetHandled;
end;

procedure TWlTouch.HandleOrientation(var AMsg: TWaylandEventMessage);
var
  lId: Integer;
  lOrientation: TWaylandFixed;
  lListenerIdx: Integer;
begin
  lId := AMsg.Args.ReadInteger;
  lOrientation := TWaylandFixed.FromFixed(AMsg.Args.ReadDWord);
  if Assigned(OnOrientation) then OnOrientation(Self,lId,lOrientation);
  for lListenerIdx := 0 to High(FListeners) do FListeners[lListenerIdx].wl_touch_orientation(Self,lId,lOrientation);
  AMsg.SetHandled;
end;

destructor TWlTouch.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._RELEASE), []);
  inherited Destroy;
end;

function TWlTouch.AddListener(AIntf: IWlTouchListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlRegion.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlRegion.GetInterfaceName: String;
begin
  Result := 'wl_region';
end;

destructor TWlRegion.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWlRegion.Add(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._ADD), [aX,aY,aWidth,aHeight]);
end;

procedure TWlRegion.Subtract(aX: Integer; aY: Integer; aWidth: Integer; aHeight: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SUBTRACT), [aX,aY,aWidth,aHeight]);
end;

function TWlRegion.AddListener(AIntf: IWlRegionListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlSubcompositor.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlSubcompositor.GetInterfaceName: String;
begin
  Result := 'wl_subcompositor';
end;

destructor TWlSubcompositor.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

function TWlSubcompositor.GetSubsurface(aSurface: TWlSurface; aParent: TWlSurface; aClassType: TWlSubsurfaceClass = nil): TWlSubsurface;
begin
  if aClassType = nil then aClassType := TWlSubsurface;
  Result := aClassType.Create(Connection);
  Connection.SendRequest(GetObjectId, Ord(TRequests._GET_SUBSURFACE), [Result.GetObjectId,aSurface.GetObjectId,aParent.GetObjectId]);
end;

function TWlSubcompositor.AddListener(AIntf: IWlSubcompositorListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;

class function TWlSubsurface.GetInterfaceVersion: Integer;
begin
  Result := 1;
end;

class function TWlSubsurface.GetInterfaceName: String;
begin
  Result := 'wl_subsurface';
end;

destructor TWlSubsurface.Destroy;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._DESTROY), []);
  inherited Destroy;
end;

procedure TWlSubsurface.SetPosition(aX: Integer; aY: Integer);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_POSITION), [aX,aY]);
end;

procedure TWlSubsurface.PlaceAbove(aSibling: TWlSurface);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._PLACE_ABOVE), [aSibling.GetObjectId]);
end;

procedure TWlSubsurface.PlaceBelow(aSibling: TWlSurface);
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._PLACE_BELOW), [aSibling.GetObjectId]);
end;

procedure TWlSubsurface.SetSync;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_SYNC), []);
end;

procedure TWlSubsurface.SetDesync;
begin
  Connection.SendRequest(GetObjectId, Ord(TRequests._SET_DESYNC), []);
end;

function TWlSubsurface.AddListener(AIntf: IWlSubsurfaceListener): LongInt;
begin
  SetLength(FListeners, Length(FListeners)+1);
  FListeners[High(FListeners)] := AIntf;
  Result := 0;
end;


end.