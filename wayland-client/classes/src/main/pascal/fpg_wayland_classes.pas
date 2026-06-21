// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

unit fpg_wayland_classes;

{$mode objfpc}{$H+}
{$ScopedEnums on}
{$modeswitch advancedrecords}
{$interfaces corba}

interface

uses
  Classes, SysUtils, ctypes, Contnrs, AVL_Tree, fgl,
  // pure-Pascal wayl binding (was: wayland_client_core / wayland_protocol /
  // wayland_util / wayland_cursor). Cursor support is Phase 6 (no direct
  // equivalent to wayland_cursor yet).
  wayland_strings, wayland_stream, Wayland_Core,
  wayland_errors, wayland_queue, wayland_internal_interfaces,
  wayland, wayland_shm_impl, unix_fd_socket, wayland_dmabuf,
  xcursor,
  xdg_shell_protocol
  ,xdg_decoration_unstable_v1_protocol
  ,viewporter_protocol
  ,linux_dmabuf_v1_protocol
  ;

type
  TfpgwDisplay = class;
  TfpgwWindow = class;
  TfpgwCursor = class;
  TfpgwShellSurfaceCommon = class;
  TfpgwShellSurfaceClass = class of TfpgwShellSurfaceCommon;
  TfpgwBufferPool = class;
  TfpgwBufferPoolClass = class of TfpgwBufferPool;
  TfpgwDataOffer = class;
  TfpgwDataSource = class;

  { Drag-and-drop notifications from the data device (surface coords are pixels,
    already converted from wl_fixed). The offer exposes the available mime types
    and lets the consumer read the payload. }
  TfpgwDndEnterEvent  = procedure(Sender: TObject; AWindow: TfpgwWindow; AX, AY: Integer; AOffer: TfpgwDataOffer) of object;
  TfpgwDndMotionEvent = procedure(Sender: TObject; ATime: LongWord; AX, AY: Integer) of object;
  TfpgwDndLeaveEvent  = procedure(Sender: TObject) of object;
  TfpgwDndDropEvent   = procedure(Sender: TObject; AOffer: TfpgwDataOffer) of object;

  { TfpgwCallbackHelper }

  TfpgwCallbackHelper = class(IWlCallbackListener)
  private
    FCallback: TWlCallback;
    FNotify: TNotifyEvent;
    procedure wl_callback_done(AWlCallback: TWlCallback; ACallbackData: DWord);
  public
    property Notify: TNotifyEvent read FNotify;
    property Callback: TWlCallback read FCallback;
    constructor Create(ADisplay: TfpgwDisplay; ANotify: TNotifyEvent);
  end;

  TfpgwMouseEnterEvent = procedure(Sender: TObject; AX, AY: Integer) of object;
  TfpgwMouseLeaveEvent = procedure(Sender: TObject) of object;
  TfpgwMouseMotionEvent = procedure(Sender: TObject; ATime: LongWord; AX, AY: Integer) of object;
  TfpgwMouseAxisEvent = procedure(Sender: TObject; ATime: LongWord; AAxis: TWlPointer.TAxis; AValue: LongInt) of object;
  TfpgwMouseButtonEvent = procedure(Sender: TObject; ATime: LongWord; AButton: LongWord; AState: TWlPointer.TButtonState) of object;

  TfpgwKeyboardKeymap = procedure(Sender: TObject; AFormat: TWlKeyboard.TKeymapFormat; AFileDesc: LongInt; ASize: LongInt) of object;
  TfpgwKeyboardEnter = procedure(Sender: TObject; AKeys: TBytes)of object;
  TfpgwKeyboardLeave = procedure(Sender: TObject) of object;
  TfpgwKeyboardKey = procedure(Sender: TObject; ATime: LongWord; AKey: LongWord; AState: TWlKeyboard.TKeyState) of object;
  TfpgwKeyboardModifiers = procedure(Sender: TObject; AModsDepressed, AModsLatched, AmodsLocked, AGroup: LongWord) of object;
  TfpgwKeyboardRepeatInfo = procedure(Sender: TObject; ARate, ADelay: LongInt) of object;

  { TfpgwRegistryEntry }

  TfpgwRegistryEntry = class
  private
    FInterface: String;
    FName: DWord;
    FVersion: DWord;
  public
    constructor Create(AName: DWord; AInterface: String; AVersion: DWord);
  published
    property Name: DWord read FName write FName;
    property Interface_: String read FInterface write FInterface;
    property Version: DWord read FVersion write FVersion;
  end;

  TfpgwRegistryList = specialize TFPGObjectList<TfpgwRegistryEntry>;

  { TfpgwDisplay }

  TfpgwDisplay = class(IWlRegistryListener,
                       IWlShmListener,
                       IWlSeatListener,
                       IWlPointerListener,
                       IWlKeyboardListener,
                       IWlDataDeviceListener,
                       IXdgWmBaseListener)
  private
    FSurfaceClass: TfpgwShellSurfaceClass;
    FBufferPoolClass: TfpgwBufferPoolClass;  { shm by default; dma-buf when available }
    FCapabilities: LongWord;
    FDisplay: TWlDisplay;
    FQueue: TWaylandMessageQueue;
    FRegistry: TWlRegistry;
    FCompositor: TWlCompositor;
    FSubcompositor: TWlSubcompositor;
    FViewporter: TWpViewporter;
    FFormats: LongWord;
    FSeat: TWlSeat;
    FShell: TWlShell;
    FShm: TWlShm;
    FDmabuf: TWpLinuxDmabufV1;
    FXDGShell: TXdgWmBase;
    FMouse: TWlPointer;
    FKeyboard: TWlKeyboard;
    FDecorationManager: TXdgDecorationManagerV1;
    FRegList: TfpgwRegistryList;
    { Data device (drag-and-drop + clipboard). }
    FDataDeviceManager: TWlDataDeviceManager;
    FDataDevice: TWlDataDevice;
    FPendingOffer: TfpgwDataOffer;    { last introduced offer, not yet claimed }
    FSelectionOffer: TfpgwDataOffer;  { current clipboard selection (incoming) }
    FDndOffer: TfpgwDataOffer;        { offer for an in-progress drag over us }
    FDndEnterSerial: DWord;           { serial of the current drag-enter (for Accept) }
    FClipboardSource: TfpgwDataSource;{ our outgoing clipboard, kept until cancelled }
    FOwnClipboardText: String;        { our clipboard text, for same-process paste }
    FOnDndEnter: TfpgwDndEnterEvent;
    FOnDndMotion: TfpgwDndMotionEvent;
    FOnDndLeave: TfpgwDndLeaveEvent;
    FOnDndDrop: TfpgwDndDropEvent;
    procedure SetupDataDevice;        { create the data device once seat+mgr exist }
    function  ClaimPendingOffer(AId: TWlDataOffer): TfpgwDataOffer;
    function GetConnected: Boolean;
    // interface implementations
    // registry
    procedure wl_registry_global(AWlRegistry: TWlRegistry; AName: DWord; AInterface: String; AVersion: DWord);
    procedure wl_registry_global_remove(AWlRegistry: TWlRegistry; AName: DWord);
    // shm
    procedure wl_shm_format(AWlShm: TWlShm; AFormat: TWlShm.TFormat);
    // seat
    procedure wl_seat_capabilities(AWlSeat: TWlSeat; ACapabilities: TWlSeat.TCapability);
    procedure wl_seat_name(AWlSeat: TWlSeat; AName: String);
    // pointer
    procedure wl_pointer_enter(AWlPointer: TWlPointer; ASerial: DWord; ASurface: TWlSurface; ASurfaceX: TWaylandFixed; ASurfaceY: TWaylandFixed);
    procedure wl_pointer_leave(AWlPointer: TWlPointer; ASerial: DWord; ASurface: TWlSurface);
    procedure wl_pointer_motion(AWlPointer: TWlPointer; ATime: DWord; ASurfaceX: TWaylandFixed; ASurfaceY: TWaylandFixed);
    procedure wl_pointer_button(AWlPointer: TWlPointer; ASerial: DWord; ATime: DWord; AButton: DWord; AState: TWlPointer.TButtonState);
    procedure wl_pointer_axis(AWlPointer: TWlPointer; ATime: DWord; AAxis: TWlPointer.TAxis; AValue: TWaylandFixed);
    procedure wl_pointer_frame(AWlPointer: TWlPointer);
    procedure wl_pointer_axis_source(AWlPointer: TWlPointer; AAxisSource: TWlPointer.TAxisSource);
    procedure wl_pointer_axis_stop(AWlPointer: TWlPointer; ATime: DWord; AAxis: TWlPointer.TAxis);
    procedure wl_pointer_axis_discrete(AWlPointer: TWlPointer; AAxis: TWlPointer.TAxis; ADiscrete: LongInt);
    procedure wl_pointer_axis_value120(AWlPointer: TWlPointer; AAxis: TWlPointer.TAxis; AValue120: LongInt);
    procedure wl_pointer_axis_relative_direction(AWlPointer: TWlPointer; AAxis: TWlPointer.TAxis; ADirection: TWlPointer.TAxisRelativeDirection);
    // keyboard
    procedure wl_keyboard_keymap(AWlKeyboard: TWlKeyboard; AFormat: TWlKeyboard.TKeymapFormat; AFd: TWaylandFdStream; ASize: DWord);
    procedure wl_keyboard_enter(AWlKeyboard: TWlKeyboard; ASerial: DWord; ASurface: TWlSurface; AKeys: TBytes);
    procedure wl_keyboard_leave(AWlKeyboard: TWlKeyboard; ASerial: DWord; ASurface: TWlSurface);
    procedure wl_keyboard_key(AWlKeyboard: TWlKeyboard; ASerial: DWord; ATime: DWord; AKey: DWord; AState: TWlKeyboard.TKeyState);
    procedure wl_keyboard_modifiers(AWlKeyboard: TWlKeyboard; ASerial: DWord; AModsDepressed: DWord; AModsLatched: DWord; AModsLocked: DWord; AGroup: DWord);
    procedure wl_keyboard_repeat_info(AWlKeyboard: TWlKeyboard; ARate: LongInt; ADelay: LongInt);
    //xdg-shell
    procedure xdg_wm_base_ping(AXdgWmBase: TXdgWmBase; ASerial: DWord);
    // data device (drag-and-drop + clipboard selection)
    procedure wl_data_device_data_offer(AWlDataDevice: TWlDataDevice; AId: TWlDataOffer);
    procedure wl_data_device_enter(AWlDataDevice: TWlDataDevice; ASerial: DWord; ASurface: TWlSurface; AX: TWaylandFixed; AY: TWaylandFixed; AId: TWlDataOffer);
    procedure wl_data_device_leave(AWlDataDevice: TWlDataDevice);
    procedure wl_data_device_motion(AWlDataDevice: TWlDataDevice; ATime: DWord; AX: TWaylandFixed; AY: TWaylandFixed);
    procedure wl_data_device_drop(AWlDataDevice: TWlDataDevice);
    procedure wl_data_device_selection(AWlDataDevice: TWlDataDevice; AId: TWlDataOffer);
  private
    FCursor: TfpgwCursor;
    FCursorThemeName: String;  { desired cursor theme; applied when wl_shm binds }
    FCursorSize: Integer;
    FEventSerial: LongWord;
    FButtonPressSerial: LongWord;  { serial of the last pointer-button PRESS }
    FOnKeyboardEnter: TfpgwKeyboardEnter;
    FOnKeyboardKey: TfpgwKeyboardKey;
    FOnKeyboardKeymap: TfpgwKeyboardKeymap;
    FOnKeyboardLeave: TfpgwKeyboardLeave;
    FOnKeyboardModifiers: TfpgwKeyboardModifiers;
    FOnKeyBoardRepeatInfo: TfpgwKeyboardRepeatInfo;
    FOnMouseAxis: TfpgwMouseAxisEvent;
    FOnMouseButton: TfpgwMouseButtonEvent;
    FOnMouseEnter: TfpgwMouseEnterEvent;
    FOnMouseLeave: TfpgwMouseLeaveEvent;
    FOnMouseMotion: TfpgwMouseMotionEvent;
    FActiveMouseWin: TfpgwWindow;
    FActiveKeyboardWin: TfpgwWindow;
    FOwner: TObject;
    FSupportsServerSideDecorations: Boolean;
    FUserDataList: TAVLTree;
    FPopupStack: TfpList;
    FSerial: DWord;
  protected
    function NextSerial: DWord;
  public
    // wayland objects
    property Display: TWlDisplay read FDisplay;
    property Registry: TWlRegistry read FRegistry;
    property Compositor: TWlCompositor read FCompositor;
    property SubCompositor: TWlSubcompositor read FSubcompositor;
    property Viewporter: TWpViewporter read FViewporter;
    property Shell: TWlShell read FShell;
    property Shm: TWlShm read FShm;
    property Dmabuf: TWpLinuxDmabufV1 read FDmabuf;
    property Seat: TWlSeat read FSeat;
    property Formats: LongWord read FFormats;
    property Mouse: TWlPointer read FMouse;
    property Keyboard: TWlKeyboard read FKeyboard;
    property Queue: TWaylandMessageQueue read FQueue;
    property Capabilities: LongWord read FCapabilities;  // keyboard, pointer, touch
    property Cursor: TfpgwCursor read FCursor;

    property OnMouseEnter: TfpgwMouseEnterEvent read FOnMouseEnter write FOnMouseEnter;
    property OnMouseLeave: TfpgwMouseLeaveEvent read FOnMouseLeave write FOnMouseLeave;
    property OnMouseButton: TfpgwMouseButtonEvent read FOnMouseButton write FOnMouseButton;
    property OnMouseMotion: TfpgwMouseMotionEvent read FOnMouseMotion write FOnMouseMotion;
    property OnMouseAxis: TfpgwMouseAxisEvent read FOnMouseAxis write FOnMouseAxis;
    property OnKeyboardKeymap: TfpgwKeyboardKeymap read FOnKeyboardKeymap write FOnKeyboardKeymap;
    property OnKeyboardEnter: TfpgwKeyboardEnter read FOnKeyboardEnter write FOnKeyboardEnter;
    property OnKeyboardLeave: TfpgwKeyboardLeave read FOnKeyboardLeave write FOnKeyboardLeave;
    property OnKeyboardKey: TfpgwKeyboardKey read FOnKeyboardKey write FOnKeyboardKey;
    property OnKeyboardModifiers: TfpgwKeyboardModifiers read FOnKeyboardModifiers write FOnKeyboardModifiers;
    property OnKeyBoardRepeatInfo: TfpgwKeyboardRepeatInfo read FOnKeyBoardRepeatInfo write FOnKeyBoardRepeatInfo;


    property Connected: Boolean read GetConnected;
    property EventSerial: LongWord read FEventSerial; // the last serial sent from the server
    { Serial of the most recent pointer-button PRESS. Unlike EventSerial this is
      not overwritten by pointer enter/leave/motion, so it stays valid as the
      "triggering event" serial for an xdg_popup grab even when a menu is opened
      on the matching button release. }
    property ButtonPressSerial: LongWord read FButtonPressSerial;

    class function TryCreate(AOwner: TObject; AName: String = ''): TfpgwDisplay;
    constructor Create(AOwner: TObject; AName: String = '');
    procedure   AfterCreate; // call this after the events are set to complete create
    destructor  Destroy; override;


    procedure Flush;
    procedure Roundtrip;
    procedure AddUserData(ALookup: Pointer; AData: TObject);
    function  GetUserData(ALookup: Pointer): Pointer;
    procedure RemoveUserData(Alookup: Pointer);
    function  HasEvent(ATimeout: Integer=0; AWillRead: Boolean=False): Boolean;
    procedure WaitEvent(ATimeOut: Integer);
    { Thread-safe: wake a WaitEvent that is blocked (or about to block) in another
      thread so the event loop iterates promptly — e.g. after posting work to the
      consumer's queue or requesting a redraw from a worker thread. }
    procedure Wakeup;
    procedure SetCursor(ACursors: array of String);
    { Replace the cursor theme/size. AName='' uses the libwayland default.
      ASize<=0 defaults to 24. The consumer (toolkit) resolves the desktop's
      configured theme and passes it here. }
    procedure SetCursorTheme(const AName: String; ASize: Integer);

    { Clipboard (wl_data_device selection). SetClipboard publishes a single
      mime-typed payload as the selection; SetClipboardText is the common case.
      ClipboardOffer is the current incoming selection (nil if none) — read it
      with TfpgwDataOffer.ReceiveText / Receive. }
    procedure SetClipboard(const AMimeType, AData: String);
    procedure SetClipboardText(const AText: String);
    function  ClipboardText: String;
    property  ClipboardOffer: TfpgwDataOffer read FSelectionOffer;

    { Start an outgoing drag. ASource carries the payload/mime types; the drag
      ends when the source is dropped/cancelled. }
    procedure StartDrag(ASource: TfpgwDataSource; AOrigin: TfpgwWindow; AIcon: TWlSurface = nil);
    function  CreateDataSource: TfpgwDataSource;

    property OnDndEnter: TfpgwDndEnterEvent read FOnDndEnter write FOnDndEnter;
    property OnDndMotion: TfpgwDndMotionEvent read FOnDndMotion write FOnDndMotion;
    property OnDndLeave: TfpgwDndLeaveEvent read FOnDndLeave write FOnDndLeave;
    property OnDndDrop: TfpgwDndDropEvent read FOnDndDrop write FOnDndDrop;

    property Owner: TObject read FOwner;
    property ActiveMouseWin: TfpgwWindow read FActiveMouseWin;
    property SupportsServerSideDecorations: Boolean read FSupportsServerSideDecorations;
  end;

  { TfpgwDataOffer — an incoming offer (clipboard selection or a drag over us).
    Collects the advertised mime types and reads the payload over a pipe. }

  TfpgwDataOffer = class(IWlDataOfferListener)
  private
    FDisplay: TfpgwDisplay;
    FOffer: TWlDataOffer;
    FMimeTypes: TStringList;
    FSourceActions: TWlDataDeviceManager.TDndAction;
    FAction: TWlDataDeviceManager.TDndAction;
    procedure wl_data_offer_offer(AWlDataOffer: TWlDataOffer; AMimeType: String);
    procedure wl_data_offer_source_actions(AWlDataOffer: TWlDataOffer; ASourceActions: TWlDataDeviceManager.TDndAction);
    procedure wl_data_offer_action(AWlDataOffer: TWlDataOffer; ADndAction: TWlDataDeviceManager.TDndAction);
  public
    constructor Create(ADisplay: TfpgwDisplay; AOffer: TWlDataOffer);
    destructor  Destroy; override;
    function  HasMimeType(const AMimeType: String): Boolean;
    { First advertised text mime ('text/plain;charset=utf-8' preferred), or ''. }
    function  PreferredTextMimeType: String;
    { Read the payload for AMimeType (blocks, pumping the event loop so a
      same-process source can answer). Returns raw bytes. }
    function  Receive(const AMimeType: String): TBytes;
    function  ReceiveText: String;
    procedure Accept(ASerial: DWord; const AMimeType: String);
    procedure SetActions(ADndActions, APreferredAction: TWlDataDeviceManager.TDndAction);
    procedure Finish;
    property  Offer: TWlDataOffer read FOffer;
    property  MimeTypes: TStringList read FMimeTypes;
    property  SourceActions: TWlDataDeviceManager.TDndAction read FSourceActions;
    property  Action: TWlDataDeviceManager.TDndAction read FAction;
  end;

  { TfpgwDataSource — an outgoing payload for the clipboard or a drag. Holds the
    data per mime type and writes it to the requesting fd on demand. }

  TfpgwDataSource = class(IWlDataSourceListener)
  private
    FDisplay: TfpgwDisplay;
    FSource: TWlDataSource;
    FMimes: TStringList;     { offered mime types }
    FPayloads: TStringList;  { payload per mime (parallel to FMimes; may be multi-line) }
    FOnCancelled: TNotifyEvent;
    FDndFinished: Boolean;
    FDndAction: TWlDataDeviceManager.TDndAction;
    procedure wl_data_source_target(AWlDataSource: TWlDataSource; AMimeType: String);
    procedure wl_data_source_send(AWlDataSource: TWlDataSource; AMimeType: String; AFd: TWaylandFdStream);
    procedure wl_data_source_cancelled(AWlDataSource: TWlDataSource);
    procedure wl_data_source_dnd_drop_performed(AWlDataSource: TWlDataSource);
    procedure wl_data_source_dnd_finished(AWlDataSource: TWlDataSource);
    procedure wl_data_source_action(AWlDataSource: TWlDataSource; ADndAction: TWlDataDeviceManager.TDndAction);
  public
    constructor Create(ADisplay: TfpgwDisplay);
    destructor  Destroy; override;
    procedure SetData(const AMimeType, AData: String);  { also offers the type }
    procedure SetDndActions(AActions: TWlDataDeviceManager.TDndAction);
    property  Source: TWlDataSource read FSource;
    property  DndFinished: Boolean read FDndFinished;
    property  DndAction: TWlDataDeviceManager.TDndAction read FDndAction;
    property  OnCancelled: TNotifyEvent read FOnCancelled write FOnCancelled;
  end;

  { TfpgwBufferPool — abstraction over how a window buffer's pixels are backed.
    Mirrors the shell abstraction (TfpgwShellSurfaceCommon with concrete
    wl_shell/xdg-shell subclasses): a common base with concrete wl_shm and
    dma-buf backends, chosen per display by TfpgwDisplay.FBufferPoolClass.
    Each TfpgwBuffer owns one pool instance. }
  TfpgwBufferPool = class
  protected
    FDisplay: TfpgwDisplay;
    FStride: Integer;          { bytes per row of the most recent GetBuffer }
  public
    constructor Create(ADisplay: TfpgwDisplay); virtual;
    { Allocate (or reallocate) a buffer of these dimensions; returns the
      wl_buffer and a CPU-writable pointer to its pixels. }
    function GetBuffer(AWidth, AHeight: Integer; AFormat: TWlShm.TFormat; out AData: Pointer): TWlBuffer; virtual; abstract;
    { Cache-coherency bracketing around CPU writes (no-op for shm; the dma-buf
      backend issues DMA_BUF_IOCTL_SYNC). }
    procedure BeginAccess; virtual;
    procedure EndAccess; virtual;
    property Stride: Integer read FStride;
  end;

  { TfpgwShmPool — wl_shm backend: a growable anonymous shared-memory pool.
    (Formerly TfpgwSharedPool.) }
  TfpgwShmPool = class(TfpgwBufferPool)
  private
    FPool: TWlShmPool;
    FData: Pointer;
    FFd: LongWord;
    FAllocated: LongWord;
    procedure GrowPool(ANewSize: LongWord);
  public
    destructor  Destroy; override;
    function GetBuffer(AWidth, AHeight: Integer; AFormat: TWlShm.TFormat; out AData: Pointer): TWlBuffer; override;
  end;

  { TfpgwDmabufPool — zwp_linux_dmabuf_v1 backend over a CPU-mapped udmabuf.
    Faster than shm: the compositor can import/scan out the dma-buf directly.
    Presented LINEAR + DRM ARGB8888/XRGB8888, with a 256-aligned stride. }
  TfpgwDmabufPool = class(TfpgwBufferPool)
  private
    FBuf: TWaylandUdmabuf;
    FWidth, FHeight: Integer;
  public
    constructor Create(ADisplay: TfpgwDisplay); override;
    destructor  Destroy; override;
    function GetBuffer(AWidth, AHeight: Integer; AFormat: TWlShm.TFormat; out AData: Pointer): TWlBuffer; override;
    procedure BeginAccess; override;
    procedure EndAccess; override;
  end;

  { TfpgwBuffer }

  TfpgwBuffer = class(IWlBufferListener)
  private
    FDisplay: TfpgwDisplay;
    FBuffer: TWlBuffer;
    FData: Pointer; {shm}
    FBusy: Boolean;
    FHeight: Integer;
    FNext: TfpgwBuffer;
    FWidth: Integer;
    FRect: TRect;
    FPool: TfpgwBufferPool;
    procedure FreeBuffer;
    function GetAllocated(AWidth, AHeight: Integer): Boolean;
    function GetStride: Integer;
    procedure wl_buffer_release(AWlBuffer: TWlBuffer);
  public
    constructor Create(ADisplay: TfpgwDisplay);
    destructor Destroy; override;
    procedure SetPaintRect(AX, AY, AWidth, Aheight: Integer);
    procedure Allocate(AWidth, AHeight: Integer; AFormat: TWlShm.TFormat{=foArgb8888});
    { Bracket CPU writes to Data. No-op for the wl_shm backend; the dma-buf
      backend issues DMA_BUF_IOCTL_SYNC (BeginCpuAccess/EndCpuAccess) so the
      compositor/GPU sees a coherent buffer. Always pair Begin/EndAccess around
      a frame's pixel writes. }
    procedure BeginAccess;
    procedure EndAccess;
    property Allocated[AWidth, AHeight: Integer]: Boolean read GetAllocated;
    property Busy: Boolean read FBusy write FBusy;
    property Data: Pointer read FData;
    property Buffer: TWlBuffer read FBuffer;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Stride: Integer read GetStride;
    property Next: TfpgwBuffer read FNext write FNext;
    property PaintArea: TRect read FRect;
  end;

  { TfpgwShellSurfaceCommon }

  TfpgwShellSurfaceCommon = class(IWlSurfaceListener)
  private
    FDisplay: TfpgwDisplay;
    FWin: TfpgwWindow;
    FSurface: TWlSurface;
    FSubSurface: TWlSubsurface;
    procedure wl_surface_enter(AWlSurface: TWlSurface; AOutput: TWlOutput);
    procedure wl_surface_leave(AWlSurface: TWlSurface; AOutput: TWlOutput);
    procedure wl_surface_preferred_buffer_scale(AWlSurface: TWlSurface; AFactor: LongInt);
    procedure wl_surface_preferred_buffer_transform(AWlSurface: TWlSurface; ATransform: TWlOutput.TTransform);
  protected
    FOutput: TWlOutput;
  public
    constructor Create(ADisplay: TfpgwDisplay; AWin: TfpgwWindow); virtual;
    destructor  Destroy; override;
    procedure Commit;
    procedure SetOpaqueRegion(ARegion: TRect);
    procedure SetTitle(AValue: String); virtual; abstract;
    procedure SetFullscreen(AValue: Boolean); virtual; abstract;
    procedure SetMaximized(AValue: Boolean); virtual; abstract;
    function IsMaximized: Boolean; virtual; abstract;
    { True when the compositor reports this surface as focused/activated. Default
      True (e.g. wl_shell, which has no such notion, so it always looks focused);
      xdg-shell overrides with the real ACTIVATED state. }
    function IsActive: Boolean; virtual;
    procedure SetMinimized; virtual; abstract;
    procedure Move(Serial: LongWord); virtual; abstract;
    procedure Resize(ASerial: DWord; AEdges: DWord); virtual; abstract;
    { Ask the compositor to pop up its native window menu (minimize/maximize/
      move/resize/close) at AX,AY relative to the window's top-left. ASerial must
      come from a recent input event. No-op for shells that don't support it. }
    procedure ShowWindowMenu(ASerial: DWord; AX, AY: Integer); virtual; abstract;


    // roles. only one is valid
    procedure SetToplevel; virtual; abstract;
    procedure SetPopup(AParent: TfpgwWindow; AX, AY: Integer; AGrab: Boolean = False; AGrabSerial: DWord = 0); virtual; abstract;
    procedure SetSubSurface(AParent: TfpgwShellSurfaceCommon); virtual;
    { Request compositor (server-side) decorations. Returns True if the
      compositor supports the xdg-decoration protocol and the request was
      made; False means the client must draw its own decorations. }
    function  SetServerSideDecorations: Boolean; virtual;
    { Tell the compositor we will draw our own decorations, so it must not add
      server-side ones (prevents a double frame on compositors that default to
      server-side). Safe no-op when the decoration protocol is unavailable. }
    procedure SetClientSideDecorations; virtual;
    { Tell the compositor the geometry of the "real" window within the surface
      (excludes client-side decoration shadow/margins). No-op for wl_shell. }
    procedure SetWindowGeometry(AX, AY, AWidth, AHeight: Integer); virtual;
    { Constrain interactive (compositor) resizing. A zero dimension means
      unconstrained on that axis. No-op for wl_shell. }
    procedure SetMinSize(AWidth, AHeight: Integer); virtual;
    procedure SetMaxSize(AWidth, AHeight: Integer); virtual;
    property Surface: TWlSurface read FSurface;
    property SubSurface: TWlSubsurface read FSubSurface;
  end;

  { TfpgwWLShellSurface }

  TfpgwWLShellSurface = class(TfpgwShellSurfaceCommon, IWlShellSurfaceListener)
  private
    FShellSurface: TWlShellSurface;
    procedure wl_shell_surface_ping(AWlShellSurface: TWlShellSurface; ASerial: DWord);
    procedure wl_shell_surface_configure(AWlShellSurface: TWlShellSurface; AEdges: TWlShellSurface.TResize; AWidth: LongInt; AHeight: LongInt);
    procedure wl_shell_surface_popup_done(AWlShellSurface: TWlShellSurface);
  public
    constructor Create(ADisplay: TfpgwDisplay; AWin: TfpgwWindow); override;
    destructor  Destroy; override;
    procedure SetToplevel; override;
    procedure SetPopup(AParent: TfpgwWindow; AX, AY: Integer; AGrab: Boolean = False; AGrabSerial: DWord = 0); override;
    procedure SetTitle(AValue: String);  override;
    procedure SetFullscreen(AValue: Boolean); override;
    procedure SetMaximized(AValue: Boolean); override;
    procedure SetMinimized; override;
    procedure Move(Serial: LongWord); override;
    procedure Resize(ASerial: DWord; AEdges: DWord); override;
    procedure ShowWindowMenu(ASerial: DWord; AX, AY: Integer); override;
    property ShellSurface: TWlShellSurface read FShellSurface;

  end;

  { TfpgwXDGShellSurface }

  TfpgwXDGShellSurface = class(TfpgwShellSurfaceCommon,
                               IXdgSurfaceListener,
                               IXdgToplevelListener,
                               IXdgPopupListener,
                               IXdgToplevelDecorationV1Listener)
  private
    FDecoration: TXdgToplevelDecorationV1;
    FDecorationMode: DWord;  { 0 = unknown; else XDG_TOPLEVEL_DECORATION_V1_MODE_* }
    FXdgSurface: TXdgSurface;
    procedure xdg_surface_configure(AXdgSurface: TXdgSurface; ASerial: DWord);
    procedure xdg_toplevel_decoration_v1_configure(AXdgToplevelDecorationV1: TXdgToplevelDecorationV1; AMode: TXdgToplevelDecorationV1.TMode);
  private
    FToplevel: TXdgToplevel;
    FState: set of TXdgToplevel.TState;
    FHasWindowMenu: Boolean;
    procedure xdg_toplevel_configure(AXdgToplevel: TXdgToplevel; AWidth: LongInt; AHeight: LongInt; AStates: TBytes);
    procedure xdg_toplevel_close(AXdgToplevel: TXdgToplevel);
    procedure xdg_toplevel_configure_bounds(AXdgToplevel: TXdgToplevel; AWidth: LongInt; AHeight: LongInt);
    procedure xdg_toplevel_wm_capabilities(AXdgToplevel: TXdgToplevel; ACapabilities: TBytes);
  private
    FPopup: TXdgPopup;
    procedure xdg_popup_configure(AXdgPopup: TXdgPopup; AX: LongInt; AY: LongInt; AWidth: LongInt; AHeight: LongInt);
    procedure xdg_popup_popup_done(AXdgPopup: TXdgPopup);
    procedure xdg_popup_repositioned(AXdgPopup: TXdgPopup; AToken: DWord);
  public
    constructor Create(ADisplay: TfpgwDisplay; AWin: TfpgwWindow); override;
    destructor  Destroy; override;
    procedure SetTitle(AValue: String); override;
    function  IsMaximized: Boolean; override;
    procedure SetMaximized(AValue: Boolean); override;
    procedure SetMinimized; override;
    procedure SetPopup(AParent: TfpgwWindow; AX, AY: Integer; AGrab: Boolean = False; AGrabSerial: DWord = 0); override;
    procedure SetToplevel; override;
    procedure Move(Serial: LongWord); override;
    procedure Resize(ASerial: DWord; AEdges: DWord); override;
    procedure ShowWindowMenu(ASerial: DWord; AX, AY: Integer); override;
    function  IsActive: Boolean; override;
    function  SetServerSideDecorations: Boolean; override;
    procedure SetClientSideDecorations; override;
    procedure SetWindowGeometry(AX, AY, AWidth, AHeight: Integer); override;
    procedure SetMinSize(AWidth, AHeight: Integer); override;
    procedure SetMaxSize(AWidth, AHeight: Integer); override;
    property Toplevel: TXdgToplevel read FToplevel;
    property Popup: TXdgPopup read FPopup;
    property Surface: TXdgSurface read FXdgSurface;
    { True if the compositor advertised the window-menu capability (xdg-shell v5+
      wm_capabilities). Older compositors send no capabilities event; we default
      to True there since show_window_menu has existed since the protocol's start. }
    property HasWindowMenu: Boolean read FHasWindowMenu;
    { Mode the compositor chose after a SetServerSideDecorations request
      (XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE / _CLIENT_SIDE; 0 if never
      negotiated). }
    property DecorationMode: DWord read FDecorationMode;
  end;

  TfpgwShellConfigureEvent = procedure(Sender: TObject; AEdges: LongWord; AWidth, AHeight: LongInt) of object;

  TfpgwWindowDecorator = class;

  { TfpgwWindow }

  TfpgwWindow = class(IWlCallbackListener)
  private
    FDisplay: TfpgwDisplay;
    FBuffers: Array[0..1] of TfpgwBuffer;
    FReadyBuffer: TfpgwBuffer;
    FServerReadyToPaint: Boolean;
    FEntered: Boolean; // only useful if decoration assigned.
    //interfaces
    // frame draw
    procedure wl_callback_done(AWlCallback: TWlCallback; ACallbackData: DWord); // redraw
  private
    FClientHeight: Integer;
    FClientWidth: Integer;
    FOnClose: TNotifyEvent;
    FOnConfigure: TfpgwShellConfigureEvent;
    FOnPaint: TNotifyEvent;
    FOwner: TObject;
    FSurfaceShell: TfpgwShellSurfaceCommon;
    //FTopLevel: TfpgwWindow;
    FWindowState: DWord;
    FClientArea: TRect; // if toplevel then the decorations might resize the window.
    FDecorations: TfpgwWindowDecorator;
    FViewport: TWpViewport;
    { Offset (in surface pixels) of this window's content origin from its surface
      top-left. Non-zero when the consumer draws its own frame inside the surface
      (e.g. a client-side titlebar). Used to place child popups relative to the
      content rather than the frame. Consumer sets it after creation. }
    FContentOffsetX, FContentOffsetY: Integer;
    FConfigured: Boolean;  { first xdg configure received + acked }
    FButtonPressSerial: DWord;  { serial of the last pointer PRESS over this window }
    { Observers (e.g. a buffer manager that caches this handle) registered to be
      told the instant this window is torn down, so they can drop their cached
      reference before the surface/viewport proxies are freed. }
    FFreeNotifies: array of TNotifyEvent;
  public
    constructor Create(AOwner: TObject; ADisplay: TfpgwDisplay; AParent:TfpgwWindow; ALeft, ATop, AWidth, AHeight: Integer; APopupFor: TfpgwWindow; APopupGrab: Boolean = False; AGrabSerial: DWord = 0);
    destructor  Destroy; override;
    { Crop/scale the surface to exactly AWidth x AHeight from the buffer's
      top-left, hiding any over-allocated buffer slack (needs wp_viewporter). }
    procedure SetSurfaceSize(AWidth, AHeight: Integer);
    procedure Redraw;
    procedure Paint(Buffer: TfpgwBuffer);
    function  NextBuffer: TfpgwBuffer;
    function  IsMaximized: Boolean;
    function  IsMinimized: Boolean;
    { True when the compositor reports this window as focused/activated. }
    function  IsActive: Boolean;
    procedure SetClientSize(AWidth: Integer; AHeight: Integer);
    property  Display: TfpgwDisplay read FDisplay;
    property  SurfaceShell: TfpgwShellSurfaceCommon read FSurfaceShell;
    property  ClientWidth: Integer read FClientWidth;
    property  ClientHeight: Integer read FClientHeight;
    function  GetHeight: Integer;
    function  GetWidth: Integer;
    property  OnPaint: TNotifyEvent read FOnPaint write FOnPaint;
    property  OnConfigure: TfpgwShellConfigureEvent read FOnConfigure write FOnConfigure;
    property  OnClose: TNotifyEvent read FOnClose write FOnClose;
    { Free-notification: an observer that caches this handle (e.g. a buffer
      manager) registers here to be called with Sender=Self the moment Destroy
      runs — before the surface/viewport proxies are freed — so it can drop its
      cached reference. Idempotent add (no duplicate registrations). }
    procedure AddFreeNotification(ANotify: TNotifyEvent);
    procedure RemoveFreeNotification(ANotify: TNotifyEvent);
    property  Owner: TObject read FOwner;
    property  WindowState: DWord read FWindowState;
    property  ContentOffsetX: Integer read FContentOffsetX write FContentOffsetX;
    property  ContentOffsetY: Integer read FContentOffsetY write FContentOffsetY;
    { True once the surface has received and acked its initial xdg configure.
      A buffer must not be attached before this (xdg-shell requirement), or the
      compositor will not map the surface. }
    property  Configured: Boolean read FConfigured write FConfigured;
    { Serial of the most recent pointer-button PRESS delivered while this window
      held the pointer. Cached here so interactive requests that need a recent
      serial (SurfaceShell.Move/Resize/ShowWindowMenu) can read it straight off
      the window without reaching back to the display. }
    property  ButtonPressSerial: DWord read FButtonPressSerial;
  end;

  { TfpgwWindowDecorator }

  TfpgwWindowDecorator = class//(TfpgwWindow)
  private
    FBorderBottom: Integer;
    FBorderLeft: Integer;
    FBorderRight: Integer;
    FBorderTop: Integer;
    FHost: TfpgwWindow;
    //FChildHeight: Integer;
    //FChildWidth: Integer;
    FMousePos: TPoint;
    procedure SetHost(AValue: TfpgwWindow);
    function MouseInDecoratorArea(AX, AY: Integer): Boolean;
  protected
    function  MouseEnter(AX, AY: Integer): Boolean;
    function  MouseLeave: Boolean;
    function  MouseMove(AX, AY: Integer): Boolean;
    function  MouseButton(ASerial: Longword; ATime: Longword; AButton: LongWord; AState: LongWord): Boolean;
  public
    constructor Create(AOwner: TObject; ADisplay: TfpgwDisplay; L, R, T, B: Integer
      );
    property Host: TfpgwWindow read FHost write SetHost;
    property BorderLeft: Integer read FBorderLeft write FBorderLeft;
    property BorderRight: Integer read FBorderRight write FBorderRight;
    property BorderTop: Integer read FBorderTop write FBorderTop;
    property BorderBottom: Integer read FBorderBottom write FBorderBottom;
    //property ChildWidth: Integer read FChildWidth write FChildWidth;
    //property ChildHeight: Integer read FChildHeight write FChildHeight;
  end;

  { TfpgwCursor }

  TfpgwCursor = class
  private
    FSurface: TWlSurface;
    FTheme: TXCursorTheme;    { pure-Pascal XCursor theme loader (was libwayland-cursor) }
    FDisplay: TfpgwDisplay;
    FCursors: TFPHashList;    { name -> TfpgwCursorEntry cache (owns the shm buffers) }
    FCurrent: TObject;        { the active TfpgwCursorEntry (for animation) }
    FFrame: Integer;          { current animation frame index }
    FFrameStartMs: QWord;     { tick (ms) at which the current frame was shown }
    procedure CheckSurface;
    procedure ShowFrame(AIndex: Integer);  { attach + commit one frame to FSurface }
  public
    constructor Create(ADisplay: TfpgwDisplay; AThemeName: String; ADesiredSize: Integer);
    destructor  Destroy; override;
    procedure SetCursor(ANames: array of String);
    { Advance the active cursor's animation if its current frame's delay has
      elapsed. Cheap no-op for static cursors; called from the event loop. }
    procedure Tick;
    property    Surface: TWlSurface read FSurface;
  end;

const
  // from input-event-codes.h in the kernel
  BTN_LEFT  = $110;
  BTN_RIGHT = $111;
  BTN_MIDDLE = $112;
  BTN_SIDE = $113;
  BTN_EXTRA = $114;
  BTN_FORWARD = $115;
  BTN_BACK = $116;
  BTN_TASK = $117;

implementation
uses
  BaseUnix, Math;

type
  { One animation frame: a ready-to-attach shm buffer + how long to show it. }
  TfpgwCursorFrame = record
    Buffer: TWlBuffer;
    Delay: Integer;       { ms to display this frame (0 for a static cursor) }
  end;

  { Cached, ready-to-attach cursor: one shm buffer per frame plus the shared
    hotspot/size. Owned by TfpgwCursor.FCursors. }
  TfpgwCursorEntry = class
    Frames: array of TfpgwCursorFrame;
    Width, Height: Integer;
    XHot, YHot: Integer;
    function Animated: Boolean;
    destructor Destroy; override;
  end;

function TfpgwCursorEntry.Animated: Boolean;
begin
  Result := Length(Frames) > 1;
end;

destructor TfpgwCursorEntry.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(Frames) do
    Frames[i].Buffer.Free;
  inherited Destroy;
end;

type
  TWaylandAvlNode = class(TAVLTreeNode)
    UserData: Pointer;
  end;

{ TfpgwRegistryEntry }

constructor TfpgwRegistryEntry.Create(AName: DWord; AInterface: String;
  AVersion: DWord);
begin
  FName:=AName;
  FInterface:=AInterface;
  FVersion:=AVersion;
end;

{ TfpgwWindowDecorator }

procedure TfpgwWindowDecorator.SetHost(AValue: TfpgwWindow);
begin
  if FHost=AValue then Exit;
  FHost:=AValue;

  if not Assigned(AValue) then
    Exit;

  FHost.FDecorations := Self;

  //FHost.FTopLevel := Self;

  {AValue.SurfaceShell.SubSurface.SetPosition(BorderLeft, BorderTop);
  AValue.SurfaceShell.SubSurface.SetDesync;}
end;

function TfpgwWindowDecorator.MouseInDecoratorArea(AX, AY: Integer): Boolean;
begin
  Result := (AX < BorderLeft) or (AY < BorderTop)
    or (AY > FHost.GetHeight - BorderBottom)
    or (AX > FHost.GetWidth - BorderRight)
end;

function TfpgwWindowDecorator.MouseEnter(AX, AY: Integer): Boolean;
begin
  Result := MouseInDecoratorArea(AX, AY);
  FMousePos := Point(AX, AY);
 // FDisplay.Cursor.SetCursor('arrow');
end;

function TfpgwWindowDecorator.MouseLeave: Boolean;
begin
  Result := False;//MouseInDecoratorArea(AX, AY);
end;

function TfpgwWindowDecorator.MouseMove(AX, AY: Integer): Boolean;
begin
  Result := MouseInDecoratorArea(AX, AY);
  FMousePos := Point(AX, AY);
  if FMousePos.Y > BorderTop then
  begin
    if FMousePos.Y >= FHost.GetHeight - BorderBottom then
    begin
      FHost.FDisplay.SetCursor(['sb_down_arrow', 'bottom_side']);
    end
    else
    if FMousePos.X <= BorderLeft then
    begin
      FHost.FDisplay.SetCursor(['sb_left_arrow', 'left_side']);
    end
    else
    if FMousePos.X > FHost.GetWidth - BorderRight then
    begin
      FHost.FDisplay.SetCursor(['sb_right_arrow', 'right_side']);
    end;
  end
  else
  begin
    if FMousePos.Y < BorderBottom then
      FHost.FDisplay.SetCursor(['sb_up_arrow', 'top_side'])
    else
      FHost.FDisplay.SetCursor(['left_ptr']);
  end;
end;

function TfpgwWindowDecorator.MouseButton(ASerial: Longword; ATime: Longword;
  AButton: LongWord; AState: LongWord): Boolean;
begin
  Result := MouseInDecoratorArea(FMousePos.X, FMousePos.Y) and (AState = Ord(TWlPointer.TButtonState.buPressed));
  if not Result then
    Exit;
  case AButton of
    BTN_RIGHT:
      { Pop up the compositor's native window menu, but only from the titlebar
        (top border) — matches the GNOME titlebar right-click, not the resize
        edges. Outside the titlebar a right-press does nothing here. }
      if FMousePos.Y < BorderTop then
        FHost.SurfaceShell.ShowWindowMenu(ASerial, FMousePos.X, FMousePos.Y)
      else
        Result := False;
    else
      FHost.SurfaceShell.Move(ASerial);
  end;
end;

constructor TfpgwWindowDecorator.Create(AOwner: TObject;
  ADisplay: TfpgwDisplay; L, R, T, B: Integer);
begin
  BorderLeft:=L;
  BorderRight:=R;
  BorderTop:=T;
  BorderBottom:=B;
  //inherited Create(AOwner, ADisplay, nil, 0,0, AChildWidth+L+R, AChildHeight+T+B, nil);
end;

{ TfpgwBufferPool }

constructor TfpgwBufferPool.Create(ADisplay: TfpgwDisplay);
begin
  FDisplay := ADisplay;
end;

procedure TfpgwBufferPool.BeginAccess;
begin
  // no-op; the dma-buf backend overrides this
end;

procedure TfpgwBufferPool.EndAccess;
begin
  // no-op; the dma-buf backend overrides this
end;

{ TfpgwShmPool }

procedure TfpgwShmPool.GrowPool(ANewSize: LongWord);
var
  lFd: Integer;
begin
  { The pure-Pascal binding's AllocateShmPool creates the anonymous fd, mmaps it
    and hands back the data pointer; TWlShmPool exposes no Data()/Reallocate. To
    grow we drop the old pool and allocate a fresh, larger one. Buffers already
    handed out stay valid: wl_shm_pool.destroy only releases the protocol object
    (TWlShmPool.Destroy does not munmap), so the old mapping lives on for them. }
  if Assigned(FPool) then
    FreeAndNil(FPool);
  FPool := FDisplay.Shm.AllocateShmPool(ANewSize, @FData, @lFd);
  FFd := lFd;
  FAllocated:=ANewSize;
end;

destructor TfpgwShmPool.Destroy;
begin
  if Assigned(FPool) then
  begin
    FPool.Free;
  end;
  inherited Destroy;
end;

function TfpgwShmPool.GetBuffer(AWidth, AHeight: Integer; AFormat: TWlShm.TFormat;
  out AData: Pointer): TWlBuffer;
var
  lNeededBytes: Integer;
begin
  FStride := AWidth * 4;
  lNeededBytes:=AWidth*AHeight*4;

  if FAllocated < lNeededBytes then
     GrowPool(lNeededBytes+((AWidth+50)*50*4));

  Result := FPool.CreateBuffer(0, AWidth, AHeight, FStride, AFormat);
  AData:=FData;
end;

{ TfpgwDmabufPool }

constructor TfpgwDmabufPool.Create(ADisplay: TfpgwDisplay);
begin
  inherited Create(ADisplay);
  FBuf := TWaylandUdmabuf.Create;
end;

destructor TfpgwDmabufPool.Destroy;
begin
  FBuf.Free;   { munmaps and closes the memfd/dma-buf fds }
  inherited Destroy;
end;

function TfpgwDmabufPool.GetBuffer(AWidth, AHeight: Integer; AFormat: TWlShm.TFormat;
  out AData: Pointer): TWlBuffer;
var
  lParams: TWpLinuxBufferParamsV1;
  lFlags: TWpLinuxBufferParamsV1.TFlags;
  lDrmFormat: DWord;
begin
  { GPU import wants a 256-byte-aligned LINEAR stride; size the udmabuf to the
    padded stride. The reported Stride is the padded one so the caller's drawing
    (and TfpgwBuffer.Stride) lands on the right row boundaries. }
  FStride := TWaylandUdmabuf.RoundStride(AWidth * 4);
  FWidth := AWidth;
  FHeight := AHeight;
  if not FBuf.Alloc(csize_t(FStride) * AHeight) then
    raise Exception.Create('TfpgwDmabufPool: failed to allocate udmabuf');
  AData := FBuf.Data;

  { wl_shm's ARGB8888/XRGB8888 are sentinel values (0/1), not DRM fourccs; map
    them. Any other format already carries its fourcc as the enum value. }
  case AFormat of
    TWlShm.TFormat.foArgb8888: lDrmFormat := DRM_FORMAT_ARGB8888;
    TWlShm.TFormat.foXrgb8888: lDrmFormat := DRM_FORMAT_XRGB8888;
  else
    lDrmFormat := DWord(Ord(AFormat));
  end;

  lParams := FDisplay.FDmabuf.CreateParams;
  lParams.Add(FBuf.DmabufFd, 0, 0, FStride, 0, 0); { plane 0, offset 0, LINEAR (mod 0) }
  lFlags.Value := 0;
  Result := lParams.CreateImmed(AWidth, AHeight, lDrmFormat, lFlags);
  lParams.Free;
end;

procedure TfpgwDmabufPool.BeginAccess;
begin
  FBuf.BeginCpuAccess;
end;

procedure TfpgwDmabufPool.EndAccess;
begin
  FBuf.EndCpuAccess;
end;


{ TfpgwWLShellSurface }

procedure TfpgwWLShellSurface.wl_shell_surface_ping(
  AWlShellSurface: TWlShellSurface; ASerial: DWord);
begin
  AWlShellSurface.Pong(ASerial);
  //writeln('ping');
end;

procedure TfpgwWLShellSurface.wl_shell_surface_configure(
  AWlShellSurface: TWlShellSurface; AEdges: TWlShellSurface.TResize; AWidth: LongInt;
  AHeight: LongInt);
begin
  FWin.Configured := True;
  if Assigned(FWin.FOnConfigure) then
    FWin.FOnConfigure(FWin, AEdges.Value, AWidth, AHeight);
  //WriteLn('Configure ', FWin.ClassNAme);

end;

procedure TfpgwWLShellSurface.wl_shell_surface_popup_done(
  AWlShellSurface: TWlShellSurface);
begin

end;

constructor TfpgwWLShellSurface.Create(ADisplay: TfpgwDisplay; AWin: TfpgwWindow);
begin
  inherited Create(ADisplay, AWin);
end;

destructor TfpgwWLShellSurface.Destroy;
begin
  // subsurface windows don't have a shell surface
  if Assigned(FShellSurface) then
    FShellSurface.Free;
  inherited Destroy;
end;

procedure TfpgwWLShellSurface.SetToplevel;
begin
  FShellSurface:= FDisplay.Shell.GetShellSurface(FSurface);
  FShellSurface.AddListener(Self);
  FShellSurface.SetToplevel;
end;

procedure TfpgwWLShellSurface.SetPopup(AParent: TfpgwWindow; AX, AY: Integer; AGrab: Boolean = False; AGrabSerial: DWord = 0);
var
  lNoFlags: TWlShellSurface.TTransient;  { no transient flags; bitfield zero }
begin
  //WriteLn('Setting Popup');
  { wl_shell popups are inherently grabbing; AGrab/AGrabSerial are not used here. }
  lNoFlags.Value := 0;
  FShellSurface:= FDisplay.Shell.GetShellSurface(FSurface);
  FShellSurface.AddListener(Self);
  FShellSurface.SetPopup(FDisplay.Seat, FDisplay.NextSerial, AParent.SurfaceShell.Surface, AX + AParent.ContentOffsetX, AY + AParent.ContentOffsetY, lNoFlags);
end;

procedure TfpgwWLShellSurface.SetTitle(AValue: String);
begin
  FShellSurface.SetTitle(AValue);
end;

procedure TfpgwWLShellSurface.SetFullscreen(AValue: Boolean);
begin

  if AValue then
  FShellSurface.SetFullscreen(TWlShellSurface.TFullscreenMethod.fuDefault, 30, FOutput)
  else
    //wl_shell_surface_set_maximized();
end;

procedure TfpgwWLShellSurface.SetMaximized(AValue: Boolean);
begin
  if AValue then
    FShellSurface.SetMaximized(FOutput);
end;

procedure TfpgwWLShellSurface.SetMinimized;
begin
  // not supported
end;

procedure TfpgwWLShellSurface.Move(Serial: LongWord);
begin
  if Assigned(FShellSurface) then
    FShellSurface.Move(FDisplay.Seat, Serial);
end;

procedure TfpgwWLShellSurface.Resize(ASerial: DWord; AEdges: DWord);
var
  lEdges: TWlShellSurface.TResize;  { wl_shell resize edges are a bitfield }
begin
  if Assigned(FShellSurface) then
  begin
    lEdges.Value := AEdges;
    FShellSurface.Resize(FDisplay.Seat, ASerial, lEdges);
  end;
end;

procedure TfpgwWLShellSurface.ShowWindowMenu(ASerial: DWord; AX, AY: Integer);
begin
  { wl_shell has no window-menu request; nothing to do. }
end;

{ TfpgwXDGShellSurface }

procedure TfpgwXDGShellSurface.xdg_surface_configure(AXdgSurface: TXdgSurface;
  ASerial: DWord);
begin
  //zxdg_surface_v6_set_window_geometry(FXdgSurface, 0,0,FWin.Width,FWin.Height);
  AXdgSurface.AckConfigure(ASerial);
  { Now safe to attach a buffer (xdg-shell: not before the first ack'd configure). }
  FWin.Configured := True;
end;

procedure TfpgwXDGShellSurface.xdg_toplevel_configure(
  AXdgToplevel: TXdgToplevel; AWidth: LongInt; AHeight: LongInt;
  AStates: TBytes);
var
  lIndex: Integer;
  lValue: DWord;
begin
  { States arrive as a packed array of little-endian uint32 enum values (the new
    binding hands them over as raw TBytes instead of a wl_array). Collect them
    into a typed set. }
  FState := [];
  lIndex := 0;
  while lIndex + SizeOf(DWord) <= Length(AStates) do
  begin
    lValue := PDWord(@AStates[lIndex])^;
    Include(FState, TXdgToplevel.TState(lValue));
    Inc(lIndex, SizeOf(DWord));
  end;
  if Assigned(FWin.OnConfigure) then
    FWin.OnConfigure(Self, 0, AWidth, AHeight);


end;

procedure TfpgwXDGShellSurface.xdg_toplevel_close(AXdgToplevel: TXdgToplevel);
begin
  if Assigned(FWin.OnClose) then
    FWin.OnClose(FWin);
  //WriteLn('Close Toplevel');
end;

procedure TfpgwXDGShellSurface.xdg_popup_configure(AXdgPopup: TXdgPopup;
  AX: LongInt; AY: LongInt; AWidth: LongInt; AHeight: LongInt);
begin
  { Trigger a repaint AFTER the popup is configured (xdg_surface_configure acks
    next). The buffer attached during Create's initial Redraw happens before the
    first configure/ack and is ignored by xdg, so without this the popup maps
    blank / not at all. Mirrors the toplevel configure path. }
  if Assigned(FWin.OnConfigure) then
    FWin.OnConfigure(FWin, 0, AWidth, AHeight);
end;

procedure TfpgwXDGShellSurface.xdg_popup_popup_done(AXdgPopup: TXdgPopup);
begin
  { The compositor dismissed the popup (click-outside, grab broken, etc.).
    Tell the consumer so it can tear the popup down and keep its state in sync. }
  if Assigned(FWin.OnClose) then
    FWin.OnClose(FWin);
end;

procedure TfpgwXDGShellSurface.xdg_toplevel_configure_bounds(
  AXdgToplevel: TXdgToplevel; AWidth: LongInt; AHeight: LongInt);
begin
  // recommended max bounds; no action needed for now
end;

procedure TfpgwXDGShellSurface.xdg_toplevel_wm_capabilities(
  AXdgToplevel: TXdgToplevel; ACapabilities: TBytes);
var
  lIndex: Integer;
  lValue: DWord;
begin
  { A v5+ compositor enumerates the menu/maximize/minimize/fullscreen actions it
    will honor. The event replaces (not augments) any prior set, so start clear.
    Capabilities arrive as packed little-endian uint32 values (raw TBytes). }
  FHasWindowMenu := False;
  lIndex := 0;
  while lIndex + SizeOf(DWord) <= Length(ACapabilities) do
  begin
    lValue := PDWord(@ACapabilities[lIndex])^;
    if lValue = Ord(TXdgToplevel.TWmCapabilities.wmWindowmenu) then
      FHasWindowMenu := True;
    Inc(lIndex, SizeOf(DWord));
  end;
end;

procedure TfpgwXDGShellSurface.xdg_popup_repositioned(AXdgPopup: TXdgPopup;
  AToken: DWord);
begin
  // reposition completed; no action needed for now
end;

constructor TfpgwXDGShellSurface.Create(ADisplay: TfpgwDisplay;
  AWin: TfpgwWindow);
begin
  inherited Create(ADisplay, AWin);
  FXdgSurface:= FDisplay.FXDGShell.GetXdgSurface(FSurface);
  FXdgSurface.AddListener(Self);
end;

destructor TfpgwXDGShellSurface.Destroy;
begin
  if Assigned(FToplevel) then
    FToplevel.Free;
  if Assigned(FPopup) then
    FPopup.Free;
  FDisplay.Roundtrip;
  FXdgSurface.Free;
  inherited Destroy;
end;

procedure TfpgwXDGShellSurface.SetTitle(AValue: String);
begin
  if Assigned(FToplevel) then
    FToplevel.SetTitle(AValue);
end;

function TfpgwXDGShellSurface.IsMaximized: Boolean;
begin
  Result := TXdgToplevel.TState.stMaximized in FState;
end;

function TfpgwXDGShellSurface.IsActive: Boolean;
begin
  Result := TXdgToplevel.TState.stActivated in FState;
end;

procedure TfpgwXDGShellSurface.SetMaximized(AValue: Boolean);
begin
  if not Assigned(FToplevel) then
    Exit;
  if AValue then
    FToplevel.SetMaximized
  else
    FToplevel.UnsetMaximized;
end;

procedure TfpgwXDGShellSurface.SetMinimized;
begin
  FToplevel.SetMinimized;
end;

procedure TfpgwXDGShellSurface.SetPopup(AParent: TfpgwWindow; AX, AY: Integer; AGrab: Boolean = False; AGrabSerial: DWord = 0);
var
  lPositioner: TXdgPositioner;
begin
  lPositioner :=  FDisplay.FXDGShell.CreatePositioner;
  with lPositioner do
  begin
    SetAnchorRect(AX, AY,1,1);
    SetSize(FWin.GetWidth,FWin.GetHeight);
    SetAnchor(TXdgPositioner.TAnchor.anTopleft);
    { The anchor coords are relative to the parent's content; the parent's
      window geometry origin is its surface top-left (which includes any
      client-side frame). Shift by the parent's content offset so the popup
      lands at the requested content position rather than over the frame. }
    SetOffset(AParent.ContentOffsetX, AParent.ContentOffsetY);
    SetGravity(TXdgPositioner.TGravity.grBottomright);
  end;
  FPopup:= FXdgSurface.GetPopup(TfpgwXDGShellSurface(AParent.SurfaceShell).FXdgSurface, lPositioner);
  FPopup.AddListener(Self);
  { An explicit grab gives the popup an implicit pointer/keyboard grab and
    click-outside dismissal (menus); tooltips pass AGrab=False. Must be issued
    before the popup surface's first commit. }
  if AGrab then
    FPopup.Grab(FDisplay.Seat, AGrabSerial);
  FSurface.Commit;
  { Do NOT Dispatch here: that consumes the popup's initial xdg configure before
    the consumer has wired its OnConfigure/OnPaint callbacks (which happens after
    this constructor returns), so the popup never gets its post-configure paint.
    Flush instead and let the configure arrive in the main event loop, exactly
    like the toplevel path. }
  FDisplay.Flush;
end;

procedure TfpgwXDGShellSurface.SetToplevel;
begin
  { Default True: compositors older than xdg_wm_base v5 never send a
    wm_capabilities event, but they still honor show_window_menu. v5+ will
    overwrite this from the event below. }
  FHasWindowMenu := True;
  FToplevel :=  FXdgSurface.GetToplevel;
  FToplevel.AddListener(Self);
  FSurface.Commit;
  { Only flush the commit; do NOT Dispatch here, as that would consume the
    initial configure event before the consumer wires its callbacks. The
    configure is handled in the main event loop. }
  FDisplay.Flush;
end;

function TfpgwXDGShellSurface.SetServerSideDecorations: Boolean;
begin
  Result := False;
  if not FDisplay.SupportsServerSideDecorations then
    Exit;
  if not Assigned(FToplevel) then
    Exit;
  if not Assigned(FDecoration) then
  begin
    FDecoration := FDisplay.FDecorationManager.GetToplevelDecoration(FToplevel);
    FDecoration.AddListener(Self);
  end;
  { Express the SSD preference, commit it, and roundtrip so the compositor's
    decoration.configure (the mode it will actually use) arrives before we
    return. Compositors that don't honour SSD (e.g. mutter) answer client-side
    or never advertised the manager at all, so the caller falls back to CSD.
    Safe to roundtrip here: the consumer wires OnConfigure/OnPaint before
    calling this, so the paired xdg_surface configure is handled normally. }
  FDecorationMode := 0;
  FDecoration.SetMode(TXdgToplevelDecorationV1.TMode.moServerside);
  FSurface.Commit;
  FDisplay.Roundtrip;
  Result := FDecorationMode = Ord(TXdgToplevelDecorationV1.TMode.moServerside);
end;

procedure TfpgwXDGShellSurface.xdg_toplevel_decoration_v1_configure(
  AXdgToplevelDecorationV1: TXdgToplevelDecorationV1; AMode: TXdgToplevelDecorationV1.TMode);
begin
  FDecorationMode := Ord(AMode);
end;

procedure TfpgwXDGShellSurface.SetClientSideDecorations;
begin
  if not FDisplay.SupportsServerSideDecorations then
    Exit;  { nothing to negotiate; client-side is the default }
  if not Assigned(FToplevel) then
    Exit;
  if not Assigned(FDecoration) then
    FDecoration := FDisplay.FDecorationManager.GetToplevelDecoration(FToplevel);
  FDecoration.SetMode(TXdgToplevelDecorationV1.TMode.moClientside);
end;

procedure TfpgwXDGShellSurface.SetWindowGeometry(AX, AY, AWidth, AHeight: Integer);
begin
  if Assigned(FXdgSurface) then
    FXdgSurface.SetWindowGeometry(AX, AY, AWidth, AHeight);
end;

procedure TfpgwXDGShellSurface.SetMinSize(AWidth, AHeight: Integer);
begin
  if Assigned(FToplevel) then
    FToplevel.SetMinSize(AWidth, AHeight);
end;

procedure TfpgwXDGShellSurface.SetMaxSize(AWidth, AHeight: Integer);
begin
  if Assigned(FToplevel) then
    FToplevel.SetMaxSize(AWidth, AHeight);
end;

procedure TfpgwXDGShellSurface.Move(Serial: LongWord);
begin
  if Assigned(FToplevel) then
    FToplevel.Move(FDisplay.Seat, Serial);
end;

procedure TfpgwXDGShellSurface.Resize(ASerial: DWord; AEdges: DWord);
begin
   if Assigned(FToplevel) then
    FToplevel.Resize(FDisplay.Seat, ASerial, TXdgToplevel.TResizeEdge(AEdges));
end;

procedure TfpgwXDGShellSurface.ShowWindowMenu(ASerial: DWord; AX, AY: Integer);
begin
  if Assigned(FToplevel) and FHasWindowMenu then
    FToplevel.ShowWindowMenu(FDisplay.Seat, ASerial, AX, AY);
end;

{ TfpgwShellSurfaceCommon }

procedure TfpgwShellSurfaceCommon.wl_surface_enter(AWlSurface: TWlSurface;
  AOutput: TWlOutput);
begin
  //WriteLn('surface enter');
  FOutput:=AOutput;
end;

procedure TfpgwShellSurfaceCommon.wl_surface_leave(AWlSurface: TWlSurface;
  AOutput: TWlOutput);
begin
  //WriteLn('surface leave');

end;

procedure TfpgwShellSurfaceCommon.wl_surface_preferred_buffer_scale(
  AWlSurface: TWlSurface; AFactor: LongInt);
begin
  // preferred integer buffer scale; HiDPI handling TODO
end;

procedure TfpgwShellSurfaceCommon.wl_surface_preferred_buffer_transform(
  AWlSurface: TWlSurface; ATransform: TWlOutput.TTransform);
begin
  // preferred buffer transform; ignored for now
end;

constructor TfpgwShellSurfaceCommon.Create(ADisplay: TfpgwDisplay;
  AWin: TfpgwWindow);
begin
  FDisplay := ADisplay;
  FWin := AWin;
  FSurface:= FDisplay.Compositor.CreateSurface;
  FSurface.UserData:=FWin;

  FDisplay.AddUserData(FSurface, FWin);

  //WriteLn('Created Win: 0x', HexStr(Pointer(FSurface)));

  FSurface.AddListener(Self);
end;

destructor TfpgwShellSurfaceCommon.Destroy;
begin
  //WriteLn('Removing Surface 0x: ', HexStr(pointer(self)));
  FDisplay.RemoveUserData(FSurface);
  if Assigned(FSubSurface) then
    FSubSurface.Free;

  FSurface.Free;
  inherited Destroy;
end;

procedure TfpgwShellSurfaceCommon.SetOpaqueRegion(ARegion: TRect);
var
  lRegion: TWlRegion;
begin
  lRegion := FDisplay.Compositor.CreateRegion;
  lRegion.Add(ARegion.Left, ARegion.Top, ARegion.Width, ARegion.Height);
  FSurface.SetOpaqueRegion(lRegion);
  Commit;
  lRegion.Free;
end;

procedure TfpgwShellSurfaceCommon.Commit;
begin
  FSurface.Commit;
end;

procedure TfpgwShellSurfaceCommon.SetSubSurface(AParent: TfpgwShellSurfaceCommon);
begin
  FSubSurface := FDisplay.SubCompositor.GetSubsurface(Surface, AParent.Surface);
end;

function TfpgwShellSurfaceCommon.IsActive: Boolean;
begin
  { Shells with no activation notion (wl_shell, sub-surfaces) always look focused. }
  Result := True;
end;

function TfpgwShellSurfaceCommon.SetServerSideDecorations: Boolean;
begin
  { wl_shell and sub-surfaces have no decoration protocol. }
  Result := False;
end;

procedure TfpgwShellSurfaceCommon.SetClientSideDecorations;
begin
  { no decoration protocol for wl_shell / sub-surfaces }
end;

procedure TfpgwShellSurfaceCommon.SetWindowGeometry(AX, AY, AWidth, AHeight: Integer);
begin
  { no-op for wl_shell }
end;

procedure TfpgwShellSurfaceCommon.SetMinSize(AWidth, AHeight: Integer);
begin
  { no-op for wl_shell }
end;

procedure TfpgwShellSurfaceCommon.SetMaxSize(AWidth, AHeight: Integer);
begin
  { no-op for wl_shell }
end;

{ TfpgwCursor }

procedure TfpgwCursor.CheckSurface;
begin
  if Assigned(FSurface) then
    Exit;

  FSurface := FDisplay.Compositor.CreateSurface;
end;

constructor TfpgwCursor.Create(ADisplay: TfpgwDisplay; AThemeName: String;
  ADesiredSize: Integer);
begin
  FDisplay := ADisplay;
  if ADesiredSize <= 0 then
    ADesiredSize := 24;
  { Pure-Pascal XCursor loader (replaces libwayland-cursor's wl_cursor_theme_load).
    AThemeName='' resolves to the 'default' theme inside the loader. }
  FTheme := TXCursorTheme.Create(AThemeName, ADesiredSize);
  FCursors := TFPHashList.Create;
end;

destructor TfpgwCursor.Destroy;
var
  i: Integer;
begin
  for i := 0 to FCursors.Count - 1 do
    TfpgwCursorEntry(FCursors[i]).Free;
  FCursors.Free;
  FTheme.Free;
  FSurface.Free;
  inherited Destroy;
end;

procedure TfpgwCursor.SetCursor(ANames: array of String);
var
  lEntry: TfpgwCursorEntry;
  S: String;
  lImages: TXCursorImages;
  lData: Pointer;
  lFd, i: Integer;
begin
  CheckSurface;

  { Find the first of ANames that resolves in the theme chain, caching the built
    shm buffers per name so re-setting the same cursor is cheap. }
  lEntry := nil;
  for S in ANames do
  begin
    lEntry := TfpgwCursorEntry(FCursors.Find(S));
    if Assigned(lEntry) then
      Break;

    lImages := FTheme.LoadCursor(S);
    if Length(lImages) = 0 then
      Continue;

    { Build one shm buffer per frame. Xcursor pixels are premultiplied ARGB
      little-endian, which is exactly wl_shm ARGB8888, so copy verbatim. The
      hotspot/size are shared across frames (Xcursor guarantees a uniform size
      per loaded cursor). }
    lEntry := TfpgwCursorEntry.Create;
    lEntry.Width  := lImages[0].Width;
    lEntry.Height := lImages[0].Height;
    lEntry.XHot   := lImages[0].XHot;
    lEntry.YHot   := lImages[0].YHot;
    SetLength(lEntry.Frames, Length(lImages));
    for i := 0 to High(lImages) do
    begin
      lEntry.Frames[i].Delay := lImages[i].Delay;
      lEntry.Frames[i].Buffer := FDisplay.FShm.AllocateShmBuffer(
        lEntry.Width, lEntry.Height, TWlShm.TFormat.foArgb8888, lData, lFd);
      Move(lImages[i].Pixels[0], lData^, Length(lImages[i].Pixels));
    end;
    FCursors.Add(S, lEntry);
    Break;
  end;

  if not Assigned(lEntry) then
  begin
    FCurrent := nil;
    Exit;  { unknown cursor: leave whatever the compositor currently shows }
  end;

  { Point the pointer at our cursor surface (hotspot in surface coords), then
    paint the first frame. Subsequent frames are re-attached by Tick without
    re-issuing set_cursor. }
  FCurrent := lEntry;
  FFrame := 0;
  FFrameStartMs := GetTickCount64;
  FDisplay.Mouse.SetCursor(FDisplay.NextSerial, FSurface, lEntry.XHot, lEntry.YHot);
  ShowFrame(0);
end;

procedure TfpgwCursor.ShowFrame(AIndex: Integer);
var
  lEntry: TfpgwCursorEntry;
begin
  lEntry := TfpgwCursorEntry(FCurrent);
  if (lEntry = nil) or (AIndex < 0) or (AIndex > High(lEntry.Frames)) then
    Exit;
  FFrame := AIndex;
  { The surface MUST be damaged so the compositor adopts the new image; without
    it a re-attached frame keeps the previous image. }
  FSurface.Attach(lEntry.Frames[AIndex].Buffer, 0, 0);
  FSurface.Damage(0, 0, lEntry.Width, lEntry.Height);
  FSurface.Commit;
end;

procedure TfpgwCursor.Tick;
var
  lEntry: TfpgwCursorEntry;
  lNow: QWord;
  lDelay: Integer;
begin
  lEntry := TfpgwCursorEntry(FCurrent);
  if (lEntry = nil) or not lEntry.Animated then
    Exit;
  lNow := GetTickCount64;
  { Advance as many frames as the elapsed time covers (handles slow event-loop
    ticks); each frame carries its own delay (clamp tiny/zero delays). }
  repeat
    lDelay := lEntry.Frames[FFrame].Delay;
    if lDelay <= 0 then
      lDelay := 60;
    if lNow - FFrameStartMs < QWord(lDelay) then
      Break;
    FFrameStartMs := FFrameStartMs + QWord(lDelay);
    ShowFrame((FFrame + 1) mod Length(lEntry.Frames));
  until False;
end;

{ TfpgwBuffer }

procedure TfpgwBuffer.wl_buffer_release(AWlBuffer: TWlBuffer);
begin
  FBusy:=False;
  FNext := nil;
end;

constructor TfpgwBuffer.Create(ADisplay: TfpgwDisplay);
begin
  FDisplay := ADisplay;
  { Backend chosen by the display (dma-buf when available, else wl_shm). }
  FPool := FDisplay.FBufferPoolClass.Create(FDisplay);
end;

procedure TfpgwBuffer.FreeBuffer;
begin
  if Assigned(FBuffer) then
  begin
    FreeAndNil(FBuffer);
  end;
end;

function TfpgwBuffer.GetAllocated(AWidth, AHeight: Integer): Boolean;
begin
  Result := FBuffer <> nil;
  if not Result then
    Exit;

  Result := (AWidth = FWidth) and (AHeight = FHeight);
end;

function TfpgwBuffer.GetStride: Integer;
begin
  { The pool decides the stride (wl_shm packs tightly at Width*4; the dma-buf
    backend pads rows to a 256-byte boundary). }
  Result := FPool.Stride;
end;

destructor TfpgwBuffer.Destroy;
begin
  { Free the wl_buffer FIRST: TWlBuffer.Destroy sends wl_buffer.destroy and
    unregisters the proxy from the display's object list, so a later
    wl_buffer.release event can no longer resolve to this (freed) object and
    dispatch HandleRelease into our dangling listener. Leaking it here caused a
    SIGSEGV in TWlBuffer.HandleRelease when a window (e.g. the About dialog) was
    closed while the compositor still held a buffer. }
  FreeBuffer;
  FPool.Free;
end;

procedure TfpgwBuffer.SetPaintRect(AX, AY, AWidth, Aheight: Integer);
begin
  FRect.Left:=AX;
  Frect.Top:=AY;
  FRect.Width:=AWidth;
  FRect.Height:=Aheight;
end;

procedure TfpgwBuffer.BeginAccess;
begin
  if Assigned(FPool) then
    FPool.BeginAccess;
end;

procedure TfpgwBuffer.EndAccess;
begin
  if Assigned(FPool) then
    FPool.EndAccess;
end;

procedure TfpgwBuffer.Allocate(AWidth, AHeight: Integer; AFormat: TWlShm.TFormat);
begin
  if (AWidth = FWidth) and (AHeight = FHeight) then
    Exit;
  FreeBuffer;

  FWidth:=AWidth;
  FHeight:=AHeight;
  // the pool gets some extra data so resizes are fast. It will grow as needed
  FBuffer := FPool.GetBuffer(FWidth, FHeight, AFormat, FData);
  FBuffer.AddListener(Self);

  // clear to opaque black (stride-aware: rows may be padded by the backend)
  FillDWord(FData^, (GetStride div 4) * FHeight, $FF000000);
end;

{ TfpgwWindow }

procedure TfpgwWindow.wl_callback_done(AWlCallback: TWlCallback;
  ACallbackData: DWord);
var
  buffer: TfpgwBuffer;
  lCallback: TWlCallback;
begin
  if Assigned(AWlCallback) then
    AWlCallback.Free;

  FServerReadyToPaint:=True;
  //WriteLn('server ready for paint');
  if FReadyBuffer <> nil then
  begin
    Paint(FReadyBuffer);

  end
  //else if Assigned(FOnPaint) then
  //  FOnPaint(Self)
  else
  begin
    exit;
    FServerReadyToPaint := False;
    // default paint...not very useful
    buffer := NextBuffer;
    buffer.FBusy:=True;
   // FillDWord(buffer.Data^, Width*20, $00FF0000);

    SurfaceShell.Surface.Attach(buffer.FBuffer, 0, 0);
    SurfaceShell.Surface.Damage(20, 20, GetWidth - 40, getHeight - 40);

    lCallback := SurfaceShell.Surface.Frame();
    lCallback.AddListener(Self);
    SurfaceShell.Surface.Commit;
  end;
end;

function TfpgwWindow.NextBuffer: TfpgwBuffer;
begin
  Result := nil;
  if not FBuffers[0].Busy then
    Result := FBuffers[0]
  else if not FBuffers[1].Busy then
    Result := FBuffers[1]
  else
    Exit;

  if not Result.Allocated[GetWidth, GetHeight] then
  begin
    //WriteLn(Format('Allocate buffer: %d:%d', [GetWidth,GetHeight]));
    Result.Allocate(GetWidth, GetHeight, TWlShm.TFormat.foArgb8888);
  end;

  { Open CPU access for this frame's drawing (no-op for shm; dma-buf sync). }
  Result.FPool.BeginAccess;

  // useful for debugging
  //FillDWord(Result.Data^, Width*Height, $0000ff00);
end;

function TfpgwWindow.IsMaximized: Boolean;
begin

end;

function TfpgwWindow.IsMinimized: Boolean;
begin
  Result := False;
  //Result := Result := WindowState and 1 shl ZXDG_TOPLEVEL_V6_STATE_MAXIMIZED ;
end;

function TfpgwWindow.IsActive: Boolean;
begin
  Result := (not Assigned(FSurfaceShell)) or FSurfaceShell.IsActive;
end;

procedure TfpgwWindow.SetClientSize(AWidth: Integer; AHeight: Integer);
begin
  FClientWidth:=AWidth;
  FClientHeight:=AHeight;
end;

function TfpgwWindow.GetHeight: Integer;
begin
  Result := FClientHeight;
  if Assigned(FDecorations) then
    Result += FDecorations.BorderTop + FDecorations.BorderBottom;
end;

function TfpgwWindow.GetWidth: Integer;
begin
  Result := FClientWidth;
  if Assigned(FDecorations) then
    Result += FDecorations.BorderLeft + FDecorations.BorderRight;
end;

constructor TfpgwWindow.Create(AOwner: TObject; ADisplay: TfpgwDisplay;
  AParent: TfpgwWindow; ALeft, ATop, AWidth, AHeight: Integer;
  APopupFor: TfpgwWindow; APopupGrab: Boolean = False; AGrabSerial: DWord = 0);
var
  lParentSurface: TfpgwShellSurfaceCommon = nil;
begin
  //FTopLevel := Self;
  FOwner := AOwner;
  FDisplay := ADisplay;
  FClientWidth:=AWidth;
  FClientHeight:=AHeight;

  if Assigned(AParent) then
    lParentSurface := AParent.SurfaceShell;

  if Assigned(lParentSurface) then
  begin
    // child surfaces are not xdg or ivi
    FSurfaceShell := TfpgwWLShellSurface.Create(FDisplay, Self);
    SurfaceShell.SetSubSurface(lParentSurface);
    { Sub-surfaces have no configure handshake; they may paint immediately. }
    FConfigured := True;
  end
  else
  begin
    // create the shell as the prefered parentless class
    FSurfaceShell := FDisplay.FSurfaceClass.Create(FDisplay, Self);

    if not Assigned(APopupFor) then
      SurfaceShell.SetToplevel
    else
      SurfaceShell.SetPopup(APopupFor, ALeft, ATop, APopupGrab, AGrabSerial);
  end;

  FBuffers[0] := TfpgwBuffer.Create(FDisplay);
  FBuffers[1] := TfpgwBuffer.Create(FDisplay);

  { Create a viewport so the surface can be cropped to the exact window size,
    independent of any over-allocated buffer. Optional — absent on the rare
    compositor without wp_viewporter. }
  if Assigned(FDisplay.Viewporter) then
    FViewport := FDisplay.Viewporter.GetViewport(SurfaceShell.Surface);

  SurfaceShell.Surface.Damage(0 ,0, AWidth, AHeight);
  FServerReadyToPaint:=True;
  { Do NOT roundtrip here: that would consume the initial xdg configure event
    before the consumer (fpGUI window) has wired its OnConfigure/OnPaint
    callbacks. Instead let the configure arrive in the main event loop, where
    it both wakes the poll and triggers the first paint (mirrors how the X11
    backend relies on the first Expose event). The pending surface commit is
    flushed by the event loop's WaitEvent. }
  ADisplay.Flush;
end;

procedure TfpgwWindow.SetSurfaceSize(AWidth, AHeight: Integer);
var
  lX, lY, lW, lH: TWaylandFixed;
begin
  if not Assigned(FViewport) then
    Exit;
  if (AWidth < 1) or (AHeight < 1) then
    Exit;
  { SetSource takes wl_fixed (24.8). TWaylandFixed is a Double here and is encoded
    to 24.8 on the wire by SendRequest, so assign the pixel values directly. Crop
    the buffer's top-left AWidth x AHeight at 1:1 and present it as the surface
    destination size. }
  lX := 0;
  lY := 0;
  lW := AWidth;
  lH := AHeight;
  FViewport.SetSource(lX, lY, lW, lH);
  FViewport.SetDestination(AWidth, AHeight);
end;

procedure TfpgwWindow.AddFreeNotification(ANotify: TNotifyEvent);
var
  i: Integer;
begin
  for i := 0 to High(FFreeNotifies) do
    if (TMethod(FFreeNotifies[i]).Code = TMethod(ANotify).Code)
    and (TMethod(FFreeNotifies[i]).Data = TMethod(ANotify).Data) then
      Exit;  { already registered }
  SetLength(FFreeNotifies, Length(FFreeNotifies) + 1);
  FFreeNotifies[High(FFreeNotifies)] := ANotify;
end;

procedure TfpgwWindow.RemoveFreeNotification(ANotify: TNotifyEvent);
var
  i, last: Integer;
begin
  last := High(FFreeNotifies);
  for i := 0 to last do
    if (TMethod(FFreeNotifies[i]).Code = TMethod(ANotify).Code)
    and (TMethod(FFreeNotifies[i]).Data = TMethod(ANotify).Data) then
    begin
      FFreeNotifies[i] := FFreeNotifies[last];  { swap-remove; order irrelevant }
      SetLength(FFreeNotifies, last);
      Exit;
    end;
end;

destructor TfpgwWindow.Destroy;
var
  i: Integer;
begin
  { Tell observers we're going away before any proxy is freed. A handler must
    not mutate the list (it just drops its own ref). }
  for i := 0 to High(FFreeNotifies) do
    FFreeNotifies[i](Self);
  FFreeNotifies := nil;

  FDisplay.RemoveUserData(FSurfaceShell.Surface);
  if Assigned(FViewport) then
    FViewport.Free;
  FSurfaceShell.Free;

  FBuffers[0].Free;
  FBuffers[1].Free;
end;

procedure TfpgwWindow.Redraw;
begin
  wl_callback_done(nil, 0);
  FOnPaint(Self);
end;

procedure TfpgwWindow.Paint(Buffer: TfpgwBuffer);
     procedure DrawPaintBorder;
     var
       i, j: Integer;
       c: LongWord;
     begin
       c := Random($00ffffff);
       with Buffer.PaintArea do
       for i :=  Left to Right-1 do begin
         for j := Top to Bottom-1 do
           if (i = Left) or ( i = Right-1) or (j = Top) or (j = Bottom-1) then
         PDword(Buffer.Data)[(j)*Buffer.Width+i] := c;
       end;
     end;

var
  lCallback: TWlCallback;
begin
  if Buffer = nil then
    Exit;
  if FServerReadyToPaint then
  begin
    //WriteLn(Format('Actually painting: %d, %d, %d, %d', [Buffer.PaintArea.Left,Buffer.PaintArea.Top, Buffer.PaintArea.Width, Buffer.PaintArea.Height]));
    //DrawPaintBorder;
    with buffer.PaintArea do
    begin

      SurfaceShell.Surface.Damage(Left, Top, Width, Height);
      //wl_surface_damage_buffer(FSurface, Left, Top, Width, Height);
    end;

    { Close CPU access before the compositor reads (no-op for shm; dma-buf sync). }
    Buffer.FPool.EndAccess;
    SurfaceShell.Surface.Attach(Buffer.FBuffer, 0, 0);
    buffer.FBusy:=True;
    FReadyBuffer := buffer.Next;
    buffer.Next := nil;

    lCallback := SurfaceShell.Surface.Frame();
    lCallback.AddListener(Self);
    SurfaceShell.Surface.Commit;
    FServerReadyToPaint := False;
    FDisplay.WaitEvent(0);
  end
  else
  begin
    if (FReadyBuffer <> nil) and (FReadyBuffer <> Buffer) then
      FReadyBuffer.Next := Buffer
    else
      FReadyBuffer := buffer;
    Buffer.Busy:=True;
  end;
end;

{ TfpgwCallbackHelper }

procedure TfpgwCallbackHelper.wl_callback_done(AWlCallback: TWlCallback;
  ACallbackData: DWord);
begin
  FCallback:=AWlCallback;
  if Assigned(FNotify) then
    FNotify(Self);
end;

constructor TfpgwCallbackHelper.Create(ADisplay: TfpgwDisplay; ANotify: TNotifyEvent);
begin
  FNotify:=ANotify;
end;

{ TfpgwDisplay }

function TfpgwDisplay.GetConnected: Boolean;
begin
  Result := FDisplay <> nil;
end;

procedure TfpgwDisplay.wl_registry_global(AWlRegistry: TWlRegistry;
  AName: DWord; AInterface: String; AVersion: DWord);
begin
  //WriteLn(AInterface, ' v ', AVersion);

  FRegList.Add(TfpgwRegistryEntry.Create(AName, AInterface, AVersion));

  case String(AInterface) of
    'wl_compositor': AWlRegistry.Bind(AName, AInterface, 1, TWlCompositor, FCompositor);
    'wl_subcompositor': AWlRegistry.Bind(AName, AInterface, 1, TWlSubcompositor, FSubcompositor);
    'wp_viewporter': AWlRegistry.Bind(AName, AInterface, 1, TWpViewporter, FViewporter);
    'wl_shell'     :
      begin
        AWlRegistry.Bind(AName, AInterface, 1, TWlShell, FShell);
        if not Assigned(FSurfaceClass) then
          FSurfaceClass:=TfpgwWLShellSurface;
      end;
    'wl_shm'       :
      begin
        AWlRegistry.Bind(AName, AInterface, 1, TWlShm, FShm);
        FShm.AddListener(Self);
        { Create the cursor using whatever theme the consumer requested before
          wl_shm became available (SetCursorTheme stores it as pending). }
        FCursor := TfpgwCursor.Create(Self, FCursorThemeName, FCursorSize);
      end;
    'wl_seat':
      begin
        AWlRegistry.Bind(AName, AInterface, 1, TWlSeat, FSeat);
        FSeat.AddListener(Self);
        FMouse := FSeat.GetPointer;
        if Assigned(FMouse) then
          FMouse.AddListener(Self);

        FKeyboard := FSeat.GetKeyboard;
        if Assigned(FKeyboard) then
          FKeyboard.AddListener(Self);
        SetupDataDevice;
      end;
    'zwp_linux_dmabuf_v1':
      begin
        { v3 is enough for the LINEAR + CreateImmed path we use. Prefer the
          dma-buf backend (faster) only if /dev/udmabuf is actually usable;
          otherwise stay on wl_shm. }
        AWlRegistry.Bind(AName, AInterface, Min(AVersion, 3), TWpLinuxDmabufV1, FDmabuf);
        if TWaylandUdmabuf.Available then
          FBufferPoolClass := TfpgwDmabufPool;
      end;
    'wl_data_device_manager':
      begin
        { v3 adds dnd actions + the source action events. }
        AWlRegistry.Bind(AName, AInterface, Min(AVersion, 3), TWlDataDeviceManager, FDataDeviceManager);
        SetupDataDevice;
      end;
    'xdg_wm_base':
      begin
        AWlRegistry.Bind(AName, AInterface, 1, TXdgWmBase, FXDGShell);
        FXDGShell.AddListener(Self);
        // we prefer xdg surfaces. perhaps ivi in the future...
        FSurfaceClass:=TfpgwXDGShellSurface;
      end;
    'zxdg_decoration_manager_v1':
      begin
        AWlRegistry.Bind(AName, AInterface, 1, TXdgDecorationManagerV1, FDecorationManager);
        FSupportsServerSideDecorations := True;
      end
    else
      ;//WriteLn(&interface, ' v ', version);
  end;
end;

procedure TfpgwDisplay.wl_registry_global_remove(AWlRegistry: TWlRegistry;
  AName: DWord);
begin

end;

procedure TfpgwDisplay.wl_shm_format(AWlShm: TWlShm; AFormat: TWlShm.TFormat);
begin
  // supported pixel formats WL_SHM_FORMAT_xxxxx;
  FFormats:=FFormats or (1 shl Ord(AFormat));
end;

procedure TfpgwDisplay.wl_seat_capabilities(AWlSeat: TWlSeat;
  ACapabilities: TWlSeat.TCapability);
begin
  //WL_SEAT_CAPABILITY_KEYBOARD;
  //WL_SEAT_CAPABILITY_POINTER;
  //WL_SEAT_CAPABILITY_TOUCH;
  FCapabilities:=ACapabilities.Value;
end;

procedure TfpgwDisplay.wl_seat_name(AWlSeat: TWlSeat; AName: String);
begin

end;

procedure TfpgwDisplay.wl_pointer_enter(AWlPointer: TWlPointer; ASerial: DWord;
  ASurface: TWlSurface; ASurfaceX: TWaylandFixed; ASurfaceY: TWaylandFixed);
var
  lWin: TfpgwWindow;
  lDecor: TfpgwWindowDecorator absolute lWin;
begin
  FEventSerial:=ASerial;
  lWin := TfpgwWindow(GetUserData(ASurface));

  if not Assigned(lWin) then
    lWin := TfpgwWindow(ASurface.UserData);
  if not Assigned(lWin) then
    Raise Exception.CreateFmt('pointer enter for unknown surface 0x%s', [HexStr(Pointer(ASurface))]);
  FActiveMouseWin := lWin;

  if Assigned(lWin.FDecorations)
  and not (lWin.FDecorations.MouseEnter(ASurfaceX.AsInteger, ASurfaceY.AsInteger))
  then
  begin
    if Assigned(FOnMouseEnter) then
      FOnMouseEnter(lWin.Owner, ASurfaceX.AsInteger, ASurfaceY.AsInteger);
    lWin.FEntered:= True;
  end;
end;

procedure TfpgwDisplay.wl_pointer_leave(AWlPointer: TWlPointer; ASerial: DWord;
  ASurface: TWlSurface);
var
  lWin: TfpgwWindow;
  lDecor: TfpgwWindowDecorator absolute lWin;
begin
  FEventSerial:=ASerial;
  lWin := TfpgwWindow(GetUserData(ASurface));

  if not Assigned(lWin) then
  begin
    FActiveMouseWin := nil;
    Exit;
  end;

  if Assigned(lWin.FDecorations) then
    lWin.FDecorations.MouseLeave;

  if Assigned(FOnMouseLeave) and Assigned(lWin) then
  begin
    lWin.FEntered:=False;
    FOnMouseLeave(lWin.Owner);
  end;

  FActiveMouseWin := nil;
end;

procedure TfpgwDisplay.wl_pointer_motion(AWlPointer: TWlPointer; ATime: DWord;
  ASurfaceX: TWaylandFixed; ASurfaceY: TWaylandFixed);
var
  lHandled: Boolean = False;
begin
  if Assigned(FActiveMouseWin) and Assigned(FActiveMouseWin.FDecorations) then
  begin
    lHandled:=FActiveMouseWin.FDecorations.MouseMove(ASurfaceX.AsInteger, ASurfaceY.AsInteger);
  end;

  { A motion can race a leave (which nils FActiveMouseWin); ignore if no surface. }
  if Assigned(FActiveMouseWin) and Assigned(FOnMouseMotion) then
  begin
    if not FActiveMouseWin.FEntered then
    begin
      FActiveMouseWin.FEntered := True;
      if Assigned(FOnMouseEnter) then
        FOnMouseEnter(FActiveMouseWin.Owner, ASurfaceX.AsInteger, ASurfaceY.AsInteger);
    end;


    FOnMouseMotion(FActiveMouseWin.Owner, ATime, ASurfaceX.AsInteger, ASurfaceY.AsInteger);
  end;
end;

procedure TfpgwDisplay.wl_pointer_button(AWlPointer: TWlPointer;
  ASerial: DWord; ATime: DWord; AButton: DWord; AState: TWlPointer.TButtonState);
var
  lHandled: Boolean = False;
begin
  FEventSerial:=ASerial;
  if AState = TWlPointer.TButtonState.buPressed then
  begin
    FButtonPressSerial := ASerial;
    { also cache on the window so it is available without the display detour }
    if Assigned(FActiveMouseWin) then
      FActiveMouseWin.FButtonPressSerial := ASerial;
  end;
  {if Assigned(FActiveMouseWin) and Assigned(FActiveMouseWin.FDecorations) then
  begin
    lHandled:=FActiveMouseWin.FDecorations.MouseButton(ASerial, ATime, AButton, AState);
  end;}
  { A button event can race a pointer leave (which nils FActiveMouseWin) — e.g.
    when a popup maps and the pointer churns between surfaces. Guard the deref. }
  if {not lHandled and} Assigned(FActiveMouseWin) and Assigned(FOnMouseButton) then
    FOnMouseButton(FActiveMouseWin.Owner, ATime, AButton, AState);
end;

procedure TfpgwDisplay.wl_pointer_axis(AWlPointer: TWlPointer; ATime: DWord;
  AAxis: TWlPointer.TAxis; AValue: TWaylandFixed);
begin
   if Assigned(FActiveMouseWin) and Assigned(FOnMouseAxis) then
    FOnMouseAxis(FActiveMouseWin.Owner, ATime, AAxis, AValue.AsFixed);
end;

procedure TfpgwDisplay.wl_pointer_frame(AWlPointer: TWlPointer);
begin

end;

procedure TfpgwDisplay.wl_pointer_axis_source(AWlPointer: TWlPointer;
  AAxisSource: TWlPointer.TAxisSource);
begin

end;

procedure TfpgwDisplay.wl_pointer_axis_stop(AWlPointer: TWlPointer;
  ATime: DWord; AAxis: TWlPointer.TAxis);
begin

end;

procedure TfpgwDisplay.wl_pointer_axis_discrete(AWlPointer: TWlPointer;
  AAxis: TWlPointer.TAxis; ADiscrete: LongInt);
begin

end;

procedure TfpgwDisplay.wl_pointer_axis_value120(AWlPointer: TWlPointer;
  AAxis: TWlPointer.TAxis; AValue120: LongInt);
begin
  // high-resolution scroll (replaces axis_discrete); TODO map to scroll events
end;

procedure TfpgwDisplay.wl_pointer_axis_relative_direction(AWlPointer: TWlPointer;
  AAxis: TWlPointer.TAxis; ADirection: TWlPointer.TAxisRelativeDirection);
begin
  // natural-scroll direction hint; ignored for now
end;

procedure TfpgwDisplay.wl_keyboard_keymap(AWlKeyboard: TWlKeyboard;
  AFormat: TWlKeyboard.TKeymapFormat; AFd: TWaylandFdStream; ASize: DWord);
begin
  //Writeln('keymap');
  { The fpGUI-facing event takes a raw fd to mmap then close, so hand ownership
    of the fd over (ReleaseHandle) — otherwise the message would also close it.
    If nobody is listening, the stream closes the fd itself after dispatch. }
  if Assigned(FOnKeyboardKeymap) then
    FOnKeyboardKeymap(Owner,AFormat,AFd.ReleaseHandle,ASize);
end;

procedure TfpgwDisplay.wl_keyboard_enter(AWlKeyboard: TWlKeyboard;
  ASerial: DWord; ASurface: TWlSurface; AKeys: TBytes);
begin
  FEventSerial:=ASerial;
  FActiveKeyboardWin := TfpgwWindow(GetUserData(ASurface));
  if Assigned(FOnKeyboardEnter) and Assigned(FActiveKeyboardWin) then
    FOnKeyboardEnter(FActiveKeyboardWin.Owner,AKeys);
end;

procedure TfpgwDisplay.wl_keyboard_leave(AWlKeyboard: TWlKeyboard;
  ASerial: DWord; ASurface: TWlSurface);
var
  lWin: TfpgwWindow;
begin
  FEventSerial:=ASerial;
  lWin := TfpgwWindow(GetUserData(ASurface));
  if Assigned(FOnKeyboardLeave) and Assigned(lWin) then
    FOnKeyboardLeave(lWin.Owner);
  FActiveKeyboardWin := nil;
end;

procedure TfpgwDisplay.wl_keyboard_key(AWlKeyboard: TWlKeyboard;
  ASerial: DWord; ATime: DWord; AKey: DWord; AState: TWlKeyboard.TKeyState);
begin
  FEventSerial:=ASerial;
  if Assigned(FOnKeyboardKey) and Assigned(FActiveKeyboardWin) then
    FOnKeyboardKey(FActiveKeyboardWin.Owner,ATime,AKey,AState);
end;

procedure TfpgwDisplay.wl_keyboard_modifiers(AWlKeyboard: TWlKeyboard;
  ASerial: DWord; AModsDepressed: DWord; AModsLatched: DWord;
  AModsLocked: DWord; AGroup: DWord);
begin
  FEventSerial:=ASerial;
  //Writeln('modifiers');
  if Assigned(FOnKeyboardModifiers) then
    FOnKeyboardModifiers(Owner,AModsDepressed,AModsLatched, AModsLocked, AGroup);
end;

procedure TfpgwDisplay.wl_keyboard_repeat_info(AWlKeyboard: TWlKeyboard;
  ARate: LongInt; ADelay: LongInt);
begin
  if Assigned(FOnKeyBoardRepeatInfo) then
    FOnKeyBoardRepeatInfo(Owner,ARate,ADelay);
end;

procedure TfpgwDisplay.xdg_wm_base_ping(AXdgWmBase: TXdgWmBase; ASerial: DWord);
begin
  FEventSerial:=ASerial;
  FXDGShell.Pong(ASerial);
end;

procedure TfpgwDisplay.SetupDataDevice;
begin
  if Assigned(FDataDevice) or not Assigned(FDataDeviceManager) or not Assigned(FSeat) then
    Exit;
  { The new binding decodes each event's new_id with per-event generated code, so
    the old libwayland interface-table workaround (manually registering
    wl_data_offer / wl_data_source before GetDataDevice to avoid the zeroed
    interface-struct crash in read_events) is no longer needed. }
  FDataDevice := FDataDeviceManager.GetDataDevice(FSeat);
  FDataDevice.AddListener(Self);
end;

procedure TfpgwDisplay.wl_data_device_data_offer(AWlDataDevice: TWlDataDevice;
  AId: TWlDataOffer);
begin
  { A new offer is introduced; the following enter/selection event claims it.
    Wrap it now so its mime-type events are collected. }
  FreeAndNil(FPendingOffer);
  FPendingOffer := TfpgwDataOffer.Create(Self, AId);
end;

function TfpgwDisplay.ClaimPendingOffer(AId: TWlDataOffer): TfpgwDataOffer;
begin
  { Hand over the pending wrapper if it matches AId, else wrap AId fresh. }
  if Assigned(FPendingOffer) and (FPendingOffer.Offer = AId) then
  begin
    Result := FPendingOffer;
    FPendingOffer := nil;
  end
  else if Assigned(AId) then
    Result := TfpgwDataOffer.Create(Self, AId)
  else
    Result := nil;
end;

procedure TfpgwDisplay.wl_data_device_selection(AWlDataDevice: TWlDataDevice;
  AId: TWlDataOffer);
begin
  { The clipboard selection changed (AId=nil clears it). }
  FreeAndNil(FSelectionOffer);
  FSelectionOffer := ClaimPendingOffer(AId);
end;

procedure TfpgwDisplay.wl_data_device_enter(AWlDataDevice: TWlDataDevice;
  ASerial: DWord; ASurface: TWlSurface; AX: TWaylandFixed; AY: TWaylandFixed; AId: TWlDataOffer);
var
  lWin: TfpgwWindow;
begin
  FEventSerial := ASerial;
  FreeAndNil(FDndOffer);
  FDndOffer := ClaimPendingOffer(AId);
  FDndEnterSerial := ASerial;
  if not Assigned(FDndOffer) then
    Exit;
  lWin := TfpgwWindow(GetUserData(ASurface));
  if Assigned(FOnDndEnter) then
    FOnDndEnter(Owner, lWin, AX.AsInteger, AY.AsInteger, FDndOffer);
end;

procedure TfpgwDisplay.wl_data_device_motion(AWlDataDevice: TWlDataDevice;
  ATime: DWord; AX: TWaylandFixed; AY: TWaylandFixed);
begin
  if Assigned(FOnDndMotion) then
    FOnDndMotion(Owner, ATime, AX.AsInteger, AY.AsInteger);
end;

procedure TfpgwDisplay.wl_data_device_leave(AWlDataDevice: TWlDataDevice);
begin
  if Assigned(FOnDndLeave) then
    FOnDndLeave(Owner);
  FreeAndNil(FDndOffer);
end;

procedure TfpgwDisplay.wl_data_device_drop(AWlDataDevice: TWlDataDevice);
begin
  if Assigned(FOnDndDrop) then
    FOnDndDrop(Owner, FDndOffer);
  { The consumer reads + finishes the offer during the callback; drop our ref. }
  FDndOffer := nil;
end;

function TfpgwDisplay.CreateDataSource: TfpgwDataSource;
begin
  Result := TfpgwDataSource.Create(Self);
end;

procedure TfpgwDisplay.SetClipboard(const AMimeType, AData: String);
var
  lSrc: TfpgwDataSource;
begin
  if not Assigned(FDataDevice) then
    Exit;
  lSrc := TfpgwDataSource.Create(Self);
  lSrc.SetData(AMimeType, AData);
  FOwnClipboardText := AData;
  { Keep our source alive until the compositor cancels it (replaced by another
    selection); free the previous one. }
  FreeAndNil(FClipboardSource);
  FClipboardSource := lSrc;
  FDataDevice.SetSelection(lSrc.Source, FEventSerial);
  Flush;
end;

procedure TfpgwDisplay.SetClipboardText(const AText: String);
var
  lSrc: TfpgwDataSource;
begin
  if not Assigned(FDataDevice) then
    Exit;
  lSrc := TfpgwDataSource.Create(Self);
  lSrc.SetData('text/plain;charset=utf-8', AText);
  lSrc.SetData('text/plain', AText);
  lSrc.SetData('UTF8_STRING', AText);
  lSrc.SetData('TEXT', AText);
  FOwnClipboardText := AText;
  FreeAndNil(FClipboardSource);
  FClipboardSource := lSrc;
  FDataDevice.SetSelection(lSrc.Source, FEventSerial);
  Flush;
end;

function TfpgwDisplay.ClipboardText: String;
begin
  { If we own the selection, return our own copy — avoids a same-process
    receive (our send handler can't run while we block reading the pipe). }
  if Assigned(FClipboardSource) then
    Result := FOwnClipboardText
  else if Assigned(FSelectionOffer) then
    Result := FSelectionOffer.ReceiveText
  else
    Result := '';
end;

procedure TfpgwDisplay.StartDrag(ASource: TfpgwDataSource; AOrigin: TfpgwWindow;
  AIcon: TWlSurface);
begin
  if not Assigned(FDataDevice) or not Assigned(ASource) or not Assigned(AOrigin) then
    Exit;
  FDataDevice.StartDrag(ASource.Source, AOrigin.SurfaceShell.Surface, AIcon,
    FButtonPressSerial);
  Flush;
end;

{ TfpgwDataOffer }

constructor TfpgwDataOffer.Create(ADisplay: TfpgwDisplay; AOffer: TWlDataOffer);
begin
  FDisplay := ADisplay;
  FOffer := AOffer;
  FMimeTypes := TStringList.Create;
  if Assigned(FOffer) then
    FOffer.AddListener(Self);
end;

destructor TfpgwDataOffer.Destroy;
begin
  if Assigned(FOffer) then
    FOffer.Free;   { wl_data_offer.destroy }
  FMimeTypes.Free;
  inherited Destroy;
end;

procedure TfpgwDataOffer.wl_data_offer_offer(AWlDataOffer: TWlDataOffer; AMimeType: String);
begin
  if FMimeTypes.IndexOf(AMimeType) < 0 then
    FMimeTypes.Add(AMimeType);
end;

procedure TfpgwDataOffer.wl_data_offer_source_actions(AWlDataOffer: TWlDataOffer; ASourceActions: TWlDataDeviceManager.TDndAction);
begin
  FSourceActions := ASourceActions;
end;

procedure TfpgwDataOffer.wl_data_offer_action(AWlDataOffer: TWlDataOffer; ADndAction: TWlDataDeviceManager.TDndAction);
begin
  FAction := ADndAction;
end;

function TfpgwDataOffer.HasMimeType(const AMimeType: String): Boolean;
begin
  Result := FMimeTypes.IndexOf(AMimeType) >= 0;
end;

function TfpgwDataOffer.PreferredTextMimeType: String;
const
  cPrefs: array[0..3] of String =
    ('text/plain;charset=utf-8', 'UTF8_STRING', 'text/plain', 'TEXT');
var
  i: Integer;
begin
  for i := Low(cPrefs) to High(cPrefs) do
    if HasMimeType(cPrefs[i]) then
      Exit(cPrefs[i]);
  Result := '';
end;

function TfpgwDataOffer.Receive(const AMimeType: String): TBytes;
var
  lRead, lWrite: TWaylandFdStream;
  ms: TMemoryStream;
  buf: array[0..4095] of Byte;
  n: LongInt;
  pfd: TPollFd;
  r: cint;
  done: Boolean;
begin
  SetLength(Result, 0);
  if not Assigned(FOffer) then
    Exit;
  if not TWaylandFdStream.CreatePipe(lRead, lWrite) then
    Exit;
  ms := TMemoryStream.Create;
  try
    FOffer.Receive(AMimeType, lWrite.Handle); { source writes into the write end }
    FDisplay.Flush;        { send the receive request (with the write fd) }
    FreeAndNil(lWrite);          { we only read; closing it gives the source EOF cue }

    { The source (another process) writes its payload to the pipe; we just read
      it. No wl_display dispatch here — doing so reentrantly deadlocks libwayland,
      and it isn't needed: the data arrives over the pipe, not the protocol. The
      same-process case is short-circuited in ClipboardText (we never reach here
      for our own selection). A poll timeout guards against a source that never
      answers — TStream has no timeout, so we poll the read end's Handle. }
    done := False;
    repeat
      pfd.fd := lRead.Handle; pfd.events := POLLIN; pfd.revents := 0;
      r := FpPoll(@pfd, 1, 2000);   { 2s safety timeout }
      if r <= 0 then
        Break;                       { timeout or error }
      if (pfd.revents and (POLLIN or POLLHUP)) <> 0 then
      begin
        n := lRead.Read(buf, SizeOf(buf));
        if n > 0 then
          ms.Write(buf, n)
        else
          done := True;              { EOF (0) or error (<0) }
      end;
    until done;
    SetLength(Result, ms.Size);
    if ms.Size > 0 then
      Move(ms.Memory^, Result[0], ms.Size);
  finally
    FreeAndNil(lWrite);  { nil-safe if already freed above }
    FreeAndNil(lRead);
    FreeAndNil(ms);
  end;
end;

function TfpgwDataOffer.ReceiveText: String;
var
  mt: String;
  b: TBytes;
begin
  Result := '';
  mt := PreferredTextMimeType;
  if mt = '' then
    Exit;
  b := Receive(mt);
  if Length(b) > 0 then
  begin
    SetLength(Result, Length(b));
    Move(b[0], Result[1], Length(b));
  end;
end;

procedure TfpgwDataOffer.Accept(ASerial: DWord; const AMimeType: String);
begin
  if Assigned(FOffer) then
    FOffer.Accept(ASerial, AMimeType);
end;

procedure TfpgwDataOffer.SetActions(ADndActions, APreferredAction: TWlDataDeviceManager.TDndAction);
begin
  if Assigned(FOffer) then
    FOffer.SetActions(ADndActions, APreferredAction);
end;

procedure TfpgwDataOffer.Finish;
begin
  if Assigned(FOffer) then
    FOffer.Finish;
end;

{ TfpgwDataSource }

constructor TfpgwDataSource.Create(ADisplay: TfpgwDisplay);
begin
  FDisplay := ADisplay;
  FMimes := TStringList.Create;
  FPayloads := TStringList.Create;
  FSource := FDisplay.FDataDeviceManager.CreateDataSource;
  FSource.AddListener(Self);
end;

destructor TfpgwDataSource.Destroy;
begin
  if Assigned(FSource) then
    FSource.Free;
  FMimes.Free;
  FPayloads.Free;
  inherited Destroy;
end;

procedure TfpgwDataSource.SetData(const AMimeType, AData: String);
begin
  FMimes.Add(AMimeType);
  FPayloads.Add(AData);
  if Assigned(FSource) then
    FSource.Offer(AMimeType);
end;

procedure TfpgwDataSource.SetDndActions(AActions: TWlDataDeviceManager.TDndAction);
begin
  if Assigned(FSource) then
    FSource.SetActions(AActions);
end;

procedure TfpgwDataSource.wl_data_source_target(AWlDataSource: TWlDataSource; AMimeType: String);
begin
  // informational (the mime the target would accept); nothing to do
end;

procedure TfpgwDataSource.wl_data_source_send(AWlDataSource: TWlDataSource; AMimeType: String; AFd: TWaylandFdStream);
var
  i: Integer;
  s: String;
begin
  { Write our payload to the stream. We do NOT close it — the message owns the
    stream and closes the fd after dispatch, which is what gives the reader EOF. }
  i := FMimes.IndexOf(AMimeType);
  if i >= 0 then
  begin
    s := FPayloads[i];
    if Length(s) > 0 then
      AFd.WriteBuffer(s[1], Length(s));
  end;
end;

procedure TfpgwDataSource.wl_data_source_cancelled(AWlDataSource: TWlDataSource);
begin
  { The source is no longer used (clipboard replaced, or drag cancelled). }
  if Assigned(FOnCancelled) then
    FOnCancelled(Self);
  if FDisplay.FClipboardSource = Self then
  begin
    FDisplay.FClipboardSource := nil;
    FDisplay.FOwnClipboardText := '';
  end;
  Free;
end;

procedure TfpgwDataSource.wl_data_source_dnd_drop_performed(AWlDataSource: TWlDataSource);
begin
  // drop happened; await dnd_finished
end;

procedure TfpgwDataSource.wl_data_source_dnd_finished(AWlDataSource: TWlDataSource);
begin
  FDndFinished := True;
end;

procedure TfpgwDataSource.wl_data_source_action(AWlDataSource: TWlDataSource; ADndAction: TWlDataDeviceManager.TDndAction);
begin
  FDndAction := ADndAction;
end;

function TfpgwDisplay.NextSerial: DWord;
begin
  Result := FSerial;
  Inc(FSerial);
end;

class function TfpgwDisplay.TryCreate(AOwner: TObject; AName: String): TfpgwDisplay;
begin
  Result := TfpgwDisplay.Create(AOwner, AName);
  if not Result.Connected then
  begin
    Result.Free;
    Result := nil;
  end;
end;

constructor TfpgwDisplay.Create(AOwner: TObject; AName: String);
begin
  FOwner := AOwner;
  FRegList := TfpgwRegistryList.Create(True);
  { Default to the wl_shm backend; the registry handler upgrades this to the
    dma-buf backend if zwp_linux_dmabuf_v1 and /dev/udmabuf are available. }
  FBufferPoolClass := TfpgwShmPool;

  { New binding: connect via TryCreateConnection (finds the compositor socket
    itself; the old per-name Connect is gone, so AName is currently unused). }
  TWlDisplay.TryCreateConnection(FDisplay);
  if not Connected then
    Exit; // ==>

  FRegistry:= FDisplay.GetRegistry;
  FRegistry.AddListener(Self);

  FUserDataList := TAVLTree.Create;
  FUserDataList.NodeClass:=TWaylandAvlNode;

end;

destructor TfpgwDisplay.Destroy;
begin

  inherited Destroy;
  FRegList.Free;
  //wl_display_flush(FDisplay);
  //wl_pointer_release(FMouse);
 // wl_keyboard_release(FKeyboard);

 { if Assigned(FShell) then wl_shell_destroy(FShell);
  if Assigned(FXDGShell) then zxdg_shell_v6_destroy(FXDGShell);
  if Assigned(FSeat) then wl_seat_release(FSeat);
  if Assigned(FShm) then wl_shm_destroy(FShm);
  if Assigned(FCompositor) then wl_compositor_destroy(FCompositor);
  if Assigned(FSubcompositor) then wl_subcompositor_destroy(FSubcompositor);
  if Assigned(FRegistry) then wl_registry_destroy(FRegistry);
  if Assigned(FQueue) then wl_event_queue_destroy(FQueue);}

  if Connected then
  begin
    Flush;
    if Assigned(FDisplay) then
      FreeAndNil(FDisplay);
    FUserDataList.Free;
  end;
end;

procedure TfpgwDisplay.AfterCreate;
begin
  { Two roundtrips: the first lets the registry advertise globals (handled in
    wl_registry_global, which binds them); the second lets those new objects'
    initial events (e.g. wl_shm formats, wl_seat capabilities) arrive. }
  FDisplay.SyncAndWait;
  FDisplay.SyncAndWait;
end;

procedure TfpgwDisplay.Flush;
begin
  { No-op: the pure-Pascal binding sends each request to the socket immediately
    (SendRequest is not buffered), so there is nothing to flush. Kept for API
    compatibility with callers that explicitly flushed under libwayland. }
end;

procedure TfpgwDisplay.Roundtrip;
begin
  FDisplay.SyncAndWait;
end;

procedure TfpgwDisplay.AddUserData(ALookup: Pointer; AData: TObject);
var
  lNode: TWaylandAvlNode;
begin
  lNode := TWaylandAvlNode(FUserDataList.NewNode);
  lnode.Data:=ALookup;
  lNode.UserData:=AData;

  FUserDataList.Add(TAVLTreeNode(lNode));
end;

function TfpgwDisplay.GetUserData(ALookup: Pointer): Pointer;
var
  lNode: TWaylandAvlNode;
begin
  Result := nil;
  lNode := TWaylandAvlNode(FUserDataList.Find(ALookup));
  if Assigned(lNode) then
    Result := lNode.UserData;
end;

procedure TfpgwDisplay.RemoveUserData(Alookup: Pointer);
begin
  FUserDataList.Remove(Alookup);
end;

function TfpgwDisplay.HasEvent(ATimeout: Integer = 0; AWillRead: Boolean = False): Boolean;
begin
  { Non-consuming readiness check (replaces the old PrepareRead/poll/CancelRead
    dance). MessagesPending polls the connection socket without reading, so this
    does not dispatch anything. AWillRead is retained for API compatibility but
    no longer changes behaviour. }
  Result := FDisplay.MessagesPending(ATimeout);
end;

procedure TfpgwDisplay.WaitEvent(ATimeOut: Integer);
begin
  { Wait up to ATimeOut for the first message, then drain the rest without
    blocking. WaitMessage(0) would block (IOTimeout 0 = no timeout), so it is only
    ever called once MessagesPending(0) has confirmed data is actually ready. }
  if FDisplay.MessagesPending(ATimeOut) then
    while FDisplay.MessagesPending(0) do
      FDisplay.WaitMessage(0);
  { Advance the pointer cursor's animation (no-op for static cursors). }
  if Assigned(FCursor) then
    FCursor.Tick;
end;

procedure TfpgwDisplay.Wakeup;
begin
  if Assigned(FDisplay) then
    FDisplay.Wakeup;
end;

procedure TfpgwDisplay.SetCursor(ACursors: array of String);
begin
  if Assigned(FCursor) then
    FCursor.SetCursor(ACursors);
end;

procedure TfpgwDisplay.SetCursorTheme(const AName: String; ASize: Integer);
begin
  { Remember the request. wl_shm may not be bound yet (globals are enumerated
    after the display is created), in which case the wl_shm handler creates the
    cursor with these values. If shm is already available, recreate now. }
  FCursorThemeName := AName;
  FCursorSize := ASize;
  if Assigned(FShm) then
  begin
    FreeAndNil(FCursor);
    FCursor := TfpgwCursor.Create(Self, AName, ASize);
  end;
end;



end.

