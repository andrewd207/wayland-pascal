// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.window — a Wayland window with a widget tree in it.

  TwgWindow ties the three halves together: a TfpgwWindow for the surface and
  its buffers, a TwgWidget tree for the content, and a TwgDamage for deciding
  how little of it has to be repainted. It is the IwgWidgetHost the tree talks
  back to, so a widget's Invalidate turns into damage here without the widget
  knowing anything about surfaces.

  PRESENTERS. How a frame actually reaches the compositor differs completely
  between the two canvas backends: the software one draws into the wl_shm
  buffer TfpgwWindow already owns, while the GL one renders into its own
  dmabuf-exported texture and attaches that instead. Rather than teach TwgWindow
  both, it drives an IwgPresenter:

      BeginFrame -> a canvas and which buffer index it is
      EndFrame   -> hand that buffer to the compositor with a damage rect

  TwgShmPresenter (here, RTL-only) is the software one. The GL presenter lives
  in the wayland-gl module, so pulling in libEGL/libGL stays a deliberate act by
  the application rather than something every widget program links.

  Note the buffer INDEX in that contract: it is what makes per-buffer damage
  work. See TwgDamage — the buffer we are about to paint is not the one painted
  last frame, so it has to repair everything that changed since IT was last
  drawn, not merely since the last frame.

  INPUT arrives seat-level on TfpgwDisplay, dispatched with Sender set to the
  window's Owner. TwgWindow therefore makes itself the Owner of its TfpgwWindow,
  which is what will let the router in the next step resolve an event straight
  back to the right TwgWindow with no lookup table. }
unit wlg.widget.window;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, BaseUnix,
  wayland,               // TWlPointer, for the seat event signatures
  fpg_wayland_classes,
  wlg.surface, wlg.canvas.base, wlg.canvas.software,
  wlg.widget.types, wlg.widget.core, wlg.widget.input;

type
  EwgWindow = class(Exception);

  { IwgKeyTranslator — evdev scancodes into keysyms and text.

    wl_keyboard delivers raw evdev codes plus an XKB keymap over an fd, and
    nothing else: turning "keycode 38 with these modifiers" into the keysym 'a'
    or the UTF-8 text "A" is the client's job, and doing it properly means
    compiling that keymap. libxkbcommon is what compiles it, and it is a C
    library — which the widget layer deliberately does not link, so that a
    software-rendered widget program stays RTL-only.

    Hence this seam. TwgWindow hooks the keyboard either way, but without a
    translator it can only report scancodes: no keysyms, no text, so nothing
    can be typed. wlg.widget.keyboard.xkb (in the widgets-xkb module) is the
    implementation; an application that wants a text field installs it, and one
    that does not never links libxkbcommon.

    Nothing here caches: a compositor may send a new keymap at any time, and
    modifiers change constantly. }
  IwgKeyTranslator = interface
    ['{4F82C6D1-9A37-4E05-B8C2-71D6E9038A5B}']
    // A new keymap arrived on this fd. The implementation must close it.
    procedure SetKeymap(AFd: LongInt; ASize: Integer);
    procedure UpdateModifiers(ADepressed, ALatched, ALocked, AGroup: LongWord);
    // Translate one key. False when it produces nothing at all (no keymap yet,
    // or a code the layout does not map).
    function  Translate(AEvdevCode: LongWord; out AKeySym: LongWord;
      out AText: String): Boolean;
    // Current modifier state, as the widget layer names it.
    function  Modifiers: TwgModifiers;
    // Should holding this key repeat it? Modifier keys must not.
    function  Repeats(AEvdevCode: LongWord): Boolean;
  end;

  { IwgPresenter — how finished frames reach the compositor. }

  IwgPresenter = interface
    ['{9A4C7E12-0F86-43B5-B27D-6E58C1A0D934}']
    // Acquire something to draw into. False when every buffer is still held by
    // the compositor, in which case the caller simply skips this frame.
    function  BeginFrame(out ACanvas: TwgCanvas; out ABufferIndex: Integer): Boolean;
    // Present the frame, telling the compositor which part changed. ADamage is
    // in surface (logical) pixels.
    procedure EndFrame(const ADamage: TRect);
    // Release an acquired frame WITHOUT presenting — used when it turns out
    // there was nothing to repaint, so CPU-access bracketing stays balanced.
    procedure AbortFrame;
    procedure Resize(AWidth, AHeight: Integer);
    function  BufferCount: Integer;
  end;

  { TwgShmPresenter — draws into the window's own buffers with the CPU. }

  TwgShmPresenter = class(TInterfacedObject, IwgPresenter)
  private
    FWindow: TfpgwWindow;
    FCanvas: TwgSoftCanvas;
    FCurrent: TfpgwBuffer;
    FSuperSample: Integer;
    // TfpgwWindow keeps a fixed pair of buffers but does not number them, so
    // identity is mapped to an index the first time each one is seen.
    FSeen: array of TfpgwBuffer;
    function IndexOf(ABuffer: TfpgwBuffer): Integer;
    procedure EnsureCanvas(AWidth, AHeight: Integer);
  public
    // ASuperSample > 1 antialiases at S^2 cost in fill rate and memory; on a
    // CPU that is rarely worth it, so it defaults to off.
    constructor Create(AWindow: TfpgwWindow; ASuperSample: Integer = 1);
    destructor Destroy; override;

    function  BeginFrame(out ACanvas: TwgCanvas; out ABufferIndex: Integer): Boolean;
    procedure EndFrame(const ADamage: TRect);
    procedure AbortFrame;
    procedure Resize(AWidth, AHeight: Integer);
    function  BufferCount: Integer;
  end;

  TwgWindowCloseEvent = procedure(Sender: TObject; var ACanClose: Boolean) of object;

  { TwgWindow }

  TwgWindow = class(TComponent, IwgWidgetHost, IwgClipboardHost, IwgTickHost)
  private
    FDisplay: TfpgwDisplay;
    FWindow: TfpgwWindow;
    FRoot: TwgWidget;
    FDamage: TwgDamage;
    FPresenter: IwgPresenter;
    FFont: IwgGlyphSource;
    FScale: Single;
    FLayoutDirty: Boolean;
    FClosed: Boolean;
    FRouter: TwgInputRouter;
    FInputHooked: Boolean;
    // wl_pointer.button and .axis carry no coordinates — only .motion and
    // .enter do — so the last known position is kept here for them.
    FLastMouseX, FLastMouseY: Integer;
    FKeys: IwgKeyTranslator;
    // When a held key should fire again. Owned here rather than by the router
    // because the timings come from the compositor, which only this layer
    // talks to.
    FRepeat: TwgKeyRepeat;
    { Widgets that asked to be woken, and when. Small and linear on purpose:
      a window has a handful of animating widgets at most, and a heap would
      cost more to maintain than it saves to search. }
    FTicks: array of record
      Widget: TwgWidget;
      At: QWord;
    end;
    FOnCloseQuery: TwgWindowCloseEvent;
    FOnLayout: TNotifyEvent;
    FOnPainted: TNotifyEvent;
    { Set when the presenter had nothing to draw into — every buffer is still
      with the compositor. Damage stays pending in that case, and treating
      "pending" as "draw now" turns the wait for a buffer release into a busy
      loop at 100% of a core. }
    FStalled: Boolean;

    procedure HandleConfigure(Sender: TObject; AEdges: LongWord;
      AWidth, AHeight: LongInt);
    procedure HookInput;
    // Seat events are dispatched with Sender = the window's Owner, which is
    // this object; anything addressed elsewhere belongs to another window.
    function  IsForMe(Sender: TObject): Boolean; inline;
    procedure HandleMouseEnter(Sender: TObject; AX, AY: Integer);
    procedure HandleMouseLeave(Sender: TObject);
    procedure HandleMouseMotion(Sender: TObject; ATime: LongWord; AX, AY: Integer);
    procedure HandleMouseButton(Sender: TObject; ATime: LongWord;
      AButton: LongWord; AState: TWlPointer.TButtonState);
    procedure HandleMouseAxis(Sender: TObject; ATime: LongWord;
      AAxis: TWlPointer.TAxis; AValue: LongInt);
    procedure HandleTouchDown(Sender: TObject; ATime: LongWord; AId: Integer;
      AX, AY: Integer);
    procedure HandleTouchUp(Sender: TObject; ATime: LongWord; AId: Integer);
    procedure HandleTouchMotion(Sender: TObject; ATime: LongWord; AId: Integer;
      AX, AY: Integer);
    procedure HandleTouchCancel(Sender: TObject);
    procedure HandleKeymap(Sender: TObject; AFormat: TWlKeyboard.TKeymapFormat;
      AFileDesc: LongInt; ASize: LongInt);
    procedure HandleKey(Sender: TObject; ATime: LongWord; AKey: LongWord;
      AState: TWlKeyboard.TKeyState);
    procedure HandleModifiers(Sender: TObject;
      AModsDepressed, AModsLatched, AModsLocked, AGroup: LongWord);
    procedure HandleKeyboardLeave(Sender: TObject);
    procedure HandleRepeatInfo(Sender: TObject; ARate, ADelay: LongInt);
    // Re-send the held key while it stays down. Driven from ProcessFrame,
    // because a held key produces exactly one wl_keyboard.key event.
    procedure PollKeyRepeat;
    procedure RunDueTicks;
    procedure DeliverKey(AEvdev: LongWord; ATime: LongWord; ARepeated: Boolean);
    procedure HandleClose(Sender: TObject);
    procedure HandlePaint(Sender: TObject);
    function  GetClientWidth: Integer;
    function  GetClientHeight: Integer;
  protected
    { IwgWidgetHost }
    procedure WidgetInvalidated(const ARect: TRect);
    procedure WidgetLayoutInvalidated;
    function  HostFont: IwgGlyphSource;

    { IwgClipboardHost — the wl_data_device selection, via the classes layer. }
    function  HostClipboardText: String;
    procedure HostSetClipboardText(const AText: String);

    { IwgTickHost }
    procedure WidgetRequestsTick(AWidget: TwgWidget; AAtMs: QWord);
    procedure WidgetCancelTick(AWidget: TwgWidget);

    // Root gets the whole client area. Overridden once real layouts land.
    procedure DoLayout; virtual;
  public
    constructor Create(ADisplay: TfpgwDisplay; const ATitle: String;
      AWidth, AHeight: Integer); reintroduce;
    destructor Destroy; override;

    // Must be called before the first frame. Defaults to TwgShmPresenter, so
    // this is only needed to opt into the GL one.
    procedure SetPresenter(const APresenter: IwgPresenter);

    // Install keysym/text translation. Without one, keys arrive as scancodes
    // with no text and nothing can be typed — see IwgKeyTranslator.
    procedure SetKeyTranslator(const ATranslator: IwgKeyTranslator);

    // Repaint everything next frame.
    procedure Invalidate;
    // Lay out if needed and paint if anything is damaged. Safe to call every
    // loop iteration; it does nothing when there is nothing to do.
    procedure ProcessFrame;
    { How long the event loop may sleep, in milliseconds, before it must call
      ProcessFrame again. -1 means "indefinitely": nothing is damaged and
      nothing has asked to be woken, so the only thing that can matter next is
      a compositor event, and those wake the poll by themselves.

      Pass it straight to TfpgwDisplay.WaitEvent. An application that instead
      hard-codes a timeout is choosing to burn that many wakeups a second
      forever, whether or not anything is moving. }
    function  WaitTimeout: Integer;
    // The soonest a widget has asked to be Ticked, or 0 for none.
    function  NextTickAt: QWord;
    // Convenience loop: pump events and frames until the window closes. Blocks
    // when idle and wakes for animation, using WaitTimeout.
    procedure Run;
    procedure Close;

    property Display: TfpgwDisplay read FDisplay;
    // The underlying surface, for anything the widget layer does not wrap.
    property Window: TfpgwWindow read FWindow;
    property Root: TwgWidget read FRoot;
    property Closed: Boolean read FClosed;
    property ClientWidth: Integer read GetClientWidth;
    property ClientHeight: Integer read GetClientHeight;
    // Default font for widgets that specify none.
    property Font: IwgGlyphSource read FFont write FFont;
    // Output scale. Widget coordinates stay logical; the canvas is scaled by
    // this before painting, which is the whole of the HiDPI story.
    property Scale: Single read FScale write FScale;
    // Return ACanClose False to veto a close request.
    property OnCloseQuery: TwgWindowCloseEvent read FOnCloseQuery write FOnCloseQuery;
    property OnLayout: TNotifyEvent read FOnLayout write FOnLayout;
    // Fired once per frame that actually reached the compositor — as opposed
    // to a loop iteration, which usually draws nothing.
    property OnPainted: TNotifyEvent read FOnPainted write FOnPainted;
    // Hit testing, capture, hover, focus and key routing for this window.
    property Router: TwgInputRouter read FRouter;
    {$IFDEF WG_TRACE_DAMAGE}
    function DebugDamageCount: Integer;
    function DebugAnyDirty: Boolean;
    function DebugStalled: Boolean;
    function DebugLayoutCount: Integer;
    function DebugTickRuns: Integer;
    function DebugPendingTicks: Integer;
    function DebugPaintPixels: Int64;
    function DebugLastDamage: TRect;
    {$ENDIF}
  end;

implementation

{$IFDEF WG_TRACE_DAMAGE}
var
  wgDamageCount: Integer = 0;
  wgLayoutCount: Integer = 0;
  wgTickRunCount: Integer = 0;
  wgPaintPixels: Int64 = 0;
  wgLastDamage: TRect;
{$ENDIF}

{ TwgShmPresenter }

constructor TwgShmPresenter.Create(AWindow: TfpgwWindow; ASuperSample: Integer);
begin
  inherited Create;
  if AWindow = nil then
    raise EwgWindow.Create('TwgShmPresenter: nil window');
  FWindow := AWindow;
  FSuperSample := Max(1, ASuperSample);
end;

destructor TwgShmPresenter.Destroy;
begin
  FCanvas.Free;
  inherited Destroy;
end;

function TwgShmPresenter.BufferCount: Integer;
begin
  // TfpgwWindow is fixed double-buffered (its FBuffers is array[0..1]).
  Result := 2;
end;

function TwgShmPresenter.IndexOf(ABuffer: TfpgwBuffer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FSeen) do
    if FSeen[i] = ABuffer then
      Exit(i);
  if Length(FSeen) >= BufferCount then
    // More distinct buffers than expected would silently break the per-buffer
    // damage accounting, so say so rather than aliasing them together.
    raise EwgWindow.CreateFmt(
      'more than %d distinct buffers seen; per-buffer damage cannot be tracked',
      [BufferCount]);
  SetLength(FSeen, Length(FSeen) + 1);
  FSeen[High(FSeen)] := ABuffer;
  Result := High(FSeen);
end;

procedure TwgShmPresenter.EnsureCanvas(AWidth, AHeight: Integer);
begin
  if (FCanvas <> nil) and (FCanvas.Width = AWidth) and (FCanvas.Height = AHeight) then
    Exit;
  FreeAndNil(FCanvas);
  if (AWidth > 0) and (AHeight > 0) then
    FCanvas := TwgSoftCanvas.Create(AWidth, AHeight, FSuperSample);
end;

function TwgShmPresenter.BeginFrame(out ACanvas: TwgCanvas;
  out ABufferIndex: Integer): Boolean;
var
  lBuf: TfpgwBuffer;
begin
  ACanvas := nil;
  ABufferIndex := -1;
  Result := False;

  lBuf := FWindow.NextBuffer;
  if lBuf = nil then
    Exit;   // both held by the compositor; skip this frame
  if (lBuf.Data = nil) or (lBuf.Width <= 0) or (lBuf.Height <= 0) then
    Exit;

  EnsureCanvas(lBuf.Width, lBuf.Height);
  if FCanvas = nil then
    Exit;

  FCurrent := lBuf;
  FCanvas.SetTarget(lBuf.Data, lBuf.Stride);
  ACanvas := FCanvas;
  ABufferIndex := IndexOf(lBuf);
  Result := True;
end;

procedure TwgShmPresenter.EndFrame(const ADamage: TRect);
begin
  if FCurrent = nil then
    Exit;
  FCurrent.SetPaintRect(ADamage.Left, ADamage.Top,
    ADamage.Right - ADamage.Left, ADamage.Bottom - ADamage.Top);
  FWindow.Paint(FCurrent);
  FCurrent := nil;
end;

procedure TwgShmPresenter.AbortFrame;
begin
  if FCurrent = nil then
    Exit;
  // NextBuffer opened CPU access; close it again so the dma-buf backend's
  // sync ioctls stay balanced. The buffer was never marked busy, so it simply
  // stays available.
  FCurrent.EndAccess;
  FCurrent := nil;
end;

procedure TwgShmPresenter.Resize(AWidth, AHeight: Integer);
begin
  // The canvas is rebuilt lazily in BeginFrame once the buffers have actually
  // been reallocated at the new size; nothing to do eagerly.
end;

{ TwgWindow }

constructor TwgWindow.Create(ADisplay: TfpgwDisplay; const ATitle: String;
  AWidth, AHeight: Integer);
begin
  inherited Create(nil);
  if ADisplay = nil then
    raise EwgWindow.Create('TwgWindow: nil display');
  if not ADisplay.Connected then
    raise EwgWindow.Create(
      'TwgWindow: not connected to a compositor (is WAYLAND_DISPLAY set?)');
  FDisplay := ADisplay;
  FScale := 1.0;

  // Self as Owner: seat input is dispatched with Sender = the window's Owner,
  // so this is what lets the router find us again.
  FWindow := TfpgwWindow.Create(Self, ADisplay, nil, 0, 0, AWidth, AHeight, nil);
  FWindow.OnConfigure := @HandleConfigure;
  FWindow.OnClose := @HandleClose;
  FWindow.OnPaint := @HandlePaint;
  FWindow.SurfaceShell.SetTitle(ATitle);

  // Presenter and damage BEFORE the root: attaching the root and sizing it
  // immediately invalidates, which routes straight back into WidgetInvalidated.
  FPresenter := TwgShmPresenter.Create(FWindow);
  FDamage := TwgDamage.Create(FPresenter.BufferCount);

  FRoot := TwgWidget.Create(Self);
  FRoot.SetHost(Self as IwgWidgetHost);
  FRoot.SetBounds(0, 0, AWidth, AHeight);
  FRoot.ClipChildren := True;

  FRouter := TwgInputRouter.Create(FRoot);
  FRepeat := TwgKeyRepeat.Create;
  FRoot.SetHost(Self as IwgWidgetHost);
  HookInput;

  FDamage.AddAll(AWidth, AHeight);
  FLayoutDirty := True;
end;

destructor TwgWindow.Destroy;
begin
  // Drop the tree before the surface: a widget's Invalidate reaches back into
  // this object, and the host reference must still be valid while it does.
  FreeAndNil(FRoot);
  FreeAndNil(FRouter);
  FreeAndNil(FRepeat);
  FPresenter := nil;
  FreeAndNil(FDamage);
  FreeAndNil(FWindow);
  inherited Destroy;
end;

procedure TwgWindow.SetPresenter(const APresenter: IwgPresenter);
begin
  if APresenter = nil then
    raise EwgWindow.Create('TwgWindow: nil presenter');
  FPresenter := APresenter;
  FDamage.SetBufferCount(APresenter.BufferCount);
  FDamage.AddAll(ClientWidth, ClientHeight);
end;

function TwgWindow.GetClientWidth: Integer;
begin
  Result := FWindow.ClientWidth;
end;

function TwgWindow.GetClientHeight: Integer;
begin
  Result := FWindow.ClientHeight;
end;

{ IwgWidgetHost }

procedure TwgWindow.WidgetInvalidated(const ARect: TRect);
var
  lClipped: TRect;
begin
  {$IFDEF WG_TRACE_DAMAGE}
  Inc(wgDamageCount);
  {$ENDIF}
  // A tree can be invalidated before the window has finished coming up, or
  // while it is being torn down; there is nothing to record in either case.
  if (FDamage = nil) or FClosed then
    Exit;
  // Clip to the surface: a widget may legitimately invalidate a rectangle that
  // extends past the window, and damaging outside it is a protocol error.
  lClipped := wgIntersectRect(ARect, Rect(0, 0, ClientWidth, ClientHeight));
  if wgRectEmpty(lClipped) then
    Exit;
  FDamage.Add(lClipped);
end;

procedure TwgWindow.WidgetLayoutInvalidated;
begin
  {$IFDEF WG_TRACE_DAMAGE}
  Inc(wgLayoutCount);
  {$ENDIF}
  FLayoutDirty := True;
end;

function TwgWindow.HostFont: IwgGlyphSource;
begin
  Result := FFont;
end;

function TwgWindow.HostClipboardText: String;
begin
  Result := '';
  if FDisplay <> nil then
    Result := FDisplay.ClipboardText;
end;

procedure TwgWindow.HostSetClipboardText(const AText: String);
begin
  if FDisplay <> nil then
    FDisplay.SetClipboardText(AText);
end;

procedure TwgWindow.SetKeyTranslator(const ATranslator: IwgKeyTranslator);
begin
  FKeys := ATranslator;
end;

{ --- frame --- }

procedure TwgWindow.Invalidate;
begin
  FDamage.AddAll(ClientWidth, ClientHeight);
end;

procedure TwgWindow.DoLayout;
begin
  // Sizing the root cascades: BoundsChanged runs its layout, which sizes the
  // children, which runs theirs. SetBounds is a no-op when nothing moved, so
  // the explicit PerformLayout covers the first pass and any case where only
  // the CONTENT changed.
  FRoot.SetBounds(0, 0, ClientWidth, ClientHeight);
  FRoot.PerformLayout;
  if Assigned(FOnLayout) then
    FOnLayout(Self);
end;

procedure TwgWindow.ProcessFrame;
var
  lCanvas: TwgCanvas;
  lIndex: Integer;
  lDamage: TRect;
begin
  if FClosed or (FWindow = nil) or (not FWindow.Configured) then
    Exit;

  // A held key sends exactly one wl_keyboard.key event, so repeat has to be
  // driven from the frame loop. Same reason TwgLongPressRecogniser needs Poll.
  PollKeyRepeat;
  // Whatever asked to be woken by now.
  RunDueTicks;

  if FLayoutDirty then
  begin
    FLayoutDirty := False;
    DoLayout;
  end;

  // Cheap test first: acquiring a buffer has side effects (CPU-access
  // bracketing), so do not do it just to discover there is nothing to draw.
  if not FDamage.AnyDirty then
    Exit;
  if not FPresenter.BeginFrame(lCanvas, lIndex) then
  begin
    // Every buffer is still on screen. The release (or the frame callback) is
    // a compositor event and will wake the poll, so there is nothing to do but
    // sleep until it arrives — see WaitTimeout.
    FStalled := True;
    Exit;
  end;
  FStalled := False;

  lDamage := FDamage.Take(lIndex);
  if wgRectEmpty(lDamage) then
  begin
    { Another buffer is dirty but THIS one is already current, so there is
      nothing to paint into it. No progress is possible until the compositor
      hands back the buffer that does need repairing — which is a stall, and
      must be reported as one. Without this the loop sees "damage pending",
      refuses to sleep, acquires this same up-to-date buffer again, and spins
      at 100% of a core. }
    FStalled := True;
    FPresenter.AbortFrame;
    Exit;
  end;
  lDamage := wgIntersectRect(lDamage, Rect(0, 0, ClientWidth, ClientHeight));
  if wgRectEmpty(lDamage) then
  begin
    // Damage entirely outside the surface (a stale rect after a resize).
    // Nothing to draw and nothing to wait for.
    FPresenter.AbortFrame;
    Exit;
  end;

  {$IFDEF WG_TRACE_DAMAGE}
  wgLastDamage := lDamage;
  Inc(wgPaintPixels, Int64(lDamage.Right - lDamage.Left) *
                     Int64(lDamage.Bottom - lDamage.Top));
  {$ENDIF}
  lCanvas.BeginFrame;
  try
    if FScale <> 1.0 then
      lCanvas.Scale(FScale, FScale);
    // Clip to the damage and let the tree walk skip everything outside it.
    // Deliberately NO Clear here: a partial repaint must not wipe the parts of
    // the buffer that are still valid, so every widget paints its own
    // background instead.
    lCanvas.ClipRect(lDamage.Left, lDamage.Top,
      lDamage.Right - lDamage.Left, lDamage.Bottom - lDamage.Top);
    FRoot.PaintTree(lCanvas, lDamage);
  finally
    lCanvas.EndFrame;
  end;

  FPresenter.EndFrame(lDamage);
  if Assigned(FOnPainted) then
    FOnPainted(Self);
end;

procedure TwgWindow.Run;
begin
  while not FClosed do
  begin
    FDisplay.WaitEvent(WaitTimeout);
    ProcessFrame;
  end;
end;

{$IFDEF WG_TRACE_DAMAGE}
function TwgWindow.DebugDamageCount: Integer;
begin Result := wgDamageCount; end;
function TwgWindow.DebugAnyDirty: Boolean;
begin Result := (FDamage <> nil) and FDamage.AnyDirty; end;
function TwgWindow.DebugStalled: Boolean;
begin Result := FStalled; end;
function TwgWindow.DebugLayoutCount: Integer;
begin Result := wgLayoutCount; end;
function TwgWindow.DebugTickRuns: Integer;
begin Result := wgTickRunCount; end;
function TwgWindow.DebugPendingTicks: Integer;
begin Result := Length(FTicks); end;
function TwgWindow.DebugPaintPixels: Int64;
begin Result := wgPaintPixels; end;
function TwgWindow.DebugLastDamage: TRect;
begin Result := wgLastDamage; end;
{$ENDIF}

{ --- ticks --- }

procedure TwgWindow.WidgetRequestsTick(AWidget: TwgWidget; AAtMs: QWord);
var
  i: Integer;
begin
  if (AWidget = nil) or FClosed then
    Exit;
  for i := 0 to High(FTicks) do
    if FTicks[i].Widget = AWidget then
    begin
      // One pending tick per widget, and the earlier deadline wins: a caret
      // asking for 530ms must not push back a spinner's next frame.
      if AAtMs < FTicks[i].At then
        FTicks[i].At := AAtMs;
      Exit;
    end;
  SetLength(FTicks, Length(FTicks) + 1);
  FTicks[High(FTicks)].Widget := AWidget;
  FTicks[High(FTicks)].At := AAtMs;
end;

procedure TwgWindow.WidgetCancelTick(AWidget: TwgWidget);
var
  i, j: Integer;
begin
  for i := 0 to High(FTicks) do
    if FTicks[i].Widget = AWidget then
    begin
      for j := i to High(FTicks) - 1 do
        FTicks[j] := FTicks[j + 1];
      SetLength(FTicks, Length(FTicks) - 1);
      Exit;
    end;
end;

function TwgWindow.NextTickAt: QWord;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FTicks) do
    if (Result = 0) or (FTicks[i].At < Result) then
      Result := FTicks[i].At;
end;

procedure TwgWindow.RunDueTicks;
var
  i: Integer;
  lNow: QWord;
  lDue: array of TwgWidget;
  lCount: Integer;
begin
  if Length(FTicks) = 0 then
    Exit;
  lNow := GetTickCount64;
  { Collect first, then call. Tick almost always calls RequestTick again, which
    mutates FTicks — iterating it while that happens would skip or repeat
    entries. Removing the entry before the call is also what makes "stop by
    not asking again" work. }
  SetLength(lDue, Length(FTicks));
  lCount := 0;
  for i := High(FTicks) downto 0 do
    if FTicks[i].At <= lNow then
    begin
      lDue[lCount] := FTicks[i].Widget;
      Inc(lCount);
      WidgetCancelTick(FTicks[i].Widget);
    end;
  for i := 0 to lCount - 1 do
  begin
    {$IFDEF WG_TRACE_DAMAGE}
    Inc(wgTickRunCount);
    {$ENDIF}
    lDue[i].Tick(lNow);
  end;
end;

function TwgWindow.WaitTimeout: Integer;
var
  lNext, lNow: QWord;
begin
  if FClosed then
    Exit(0);
  { Stalled: every buffer is with the compositor, so NOTHING this side can make
    progress — not a pending repaint, not an animation frame that is already
    due. The only thing that can help is a buffer release or a frame callback,
    and both are events that wake the poll. So block.

    This is what paces a continuous animation. A spinner asks for the next
    frame with RequestTick(0), which is due immediately; without this the loop
    would honour that literally and spin at half a million iterations a second
    to produce the sixty frames the display can actually show. Instead it
    paints until the buffers run out and then sleeps until the compositor is
    ready for more — which is exactly the right rate, defined by the
    compositor rather than guessed at here. }
  if FStalled then
    Exit(-1);
  // Something is waiting to be drawn and we can draw it: do not sleep.
  if (FDamage <> nil) and FDamage.AnyDirty then
    Exit(0);
  // A key is repeating; it needs waking even with no compositor traffic.
  if FRepeat.Active then
    Exit(Max(1, FRepeat.IntervalMs));
  lNext := NextTickAt;
  if lNext = 0 then
    // Nothing is animating and nothing is dirty. The next thing that can
    // possibly matter is a compositor event, and that wakes the poll on its
    // own — so block, rather than waking sixty times a second to discover
    // there is nothing to do.
    Exit(-1);
  lNow := GetTickCount64;
  if lNext <= lNow then
    Exit(0);
  Result := Integer(lNext - lNow);
end;

procedure TwgWindow.Close;
begin
  FClosed := True;
  FRepeat.Stop;
  SetLength(FTicks, 0);
end;

{ --- input --- }

function TwgWindow.IsForMe(Sender: TObject): Boolean;
begin
  Result := Sender = Self;
end;

procedure TwgWindow.HookInput;
begin
  if FInputHooked then
    Exit;
  FInputHooked := True;
  { Seat input is global to the display, not per window, so these handlers are
    shared: every TwgWindow installs the same ones and each ignores what is not
    addressed to it. Chaining rather than overwriting would be nicer for
    multi-window apps, but the display exposes one slot per event, so the
    Sender check is what keeps them apart. }
  FDisplay.OnMouseEnter := @HandleMouseEnter;
  FDisplay.OnMouseLeave := @HandleMouseLeave;
  FDisplay.OnMouseMotion := @HandleMouseMotion;
  FDisplay.OnMouseButton := @HandleMouseButton;
  FDisplay.OnMouseAxis := @HandleMouseAxis;
  FDisplay.OnTouchDown := @HandleTouchDown;
  FDisplay.OnTouchUp := @HandleTouchUp;
  FDisplay.OnTouchMotion := @HandleTouchMotion;
  FDisplay.OnTouchCancel := @HandleTouchCancel;
  FDisplay.OnKeyboardKeymap := @HandleKeymap;
  FDisplay.OnKeyboardKey := @HandleKey;
  FDisplay.OnKeyboardModifiers := @HandleModifiers;
  FDisplay.OnKeyboardLeave := @HandleKeyboardLeave;
  FDisplay.OnKeyBoardRepeatInfo := @HandleRepeatInfo;
end;

{ --- keyboard ---

  The classes layer hands up raw evdev codes and the keymap fd; everything
  that makes those into typing happens through IwgKeyTranslator. }

procedure TwgWindow.HandleKeymap(Sender: TObject;
  AFormat: TWlKeyboard.TKeymapFormat; AFileDesc: LongInt; ASize: LongInt);
begin
  // Note this one is NOT gated on IsForMe: the keymap belongs to the seat, not
  // to a window, and is dispatched with the focused window's owner as Sender —
  // which may be another window, or none at all when it first arrives.
  if FKeys <> nil then
    FKeys.SetKeymap(AFileDesc, ASize)
  else
    // Nobody will read it; leaving it open leaks an fd per keymap change.
    FpClose(AFileDesc);
end;

procedure TwgWindow.HandleModifiers(Sender: TObject;
  AModsDepressed, AModsLatched, AModsLocked, AGroup: LongWord);
begin
  if FKeys = nil then
    Exit;
  FKeys.UpdateModifiers(AModsDepressed, AModsLatched, AModsLocked, AGroup);
  FRouter.SetModifiers(FKeys.Modifiers);
end;

procedure TwgWindow.DeliverKey(AEvdev: LongWord; ATime: LongWord;
  ARepeated: Boolean);
var
  lSym: LongWord;
  lText: String;
begin
  if FKeys = nil then
  begin
    // No translator: the scancode is all we have. Deliver it anyway so a
    // program that only wants raw keys still gets them, but there is no
    // keysym and no text, so nothing can be typed.
    FRouter.KeyDown(0, AEvdev, '', ARepeated, ATime);
    Exit;
  end;
  if not FKeys.Translate(AEvdev, lSym, lText) then
    Exit;
  FRouter.KeyDown(lSym, AEvdev, lText, ARepeated, ATime);
end;

procedure TwgWindow.HandleKey(Sender: TObject; ATime: LongWord;
  AKey: LongWord; AState: TWlKeyboard.TKeyState);
var
  lSym: LongWord;
  lText: String;
begin
  if not IsForMe(Sender) then
    Exit;
  if AState = TWlKeyboard.TKeyState.kePressed then
  begin
    DeliverKey(AKey, ATime, False);
    // Arm the repeat. Only one key repeats at a time — the last one pressed,
    // which is what every toolkit does and what users expect when rolling
    // from one key onto another.
    if (FKeys = nil) or FKeys.Repeats(AKey) then
      FRepeat.Press(AKey, GetTickCount64);
  end
  else
  begin
    FRepeat.Release(AKey);
    if FKeys <> nil then
    begin
      if FKeys.Translate(AKey, lSym, lText) then
        FRouter.KeyUp(lSym, AKey, ATime);
    end
    else
      FRouter.KeyUp(0, AKey, ATime);
  end;
end;

procedure TwgWindow.HandleKeyboardLeave(Sender: TObject);
begin
  if not IsForMe(Sender) then
    Exit;
  { Focus left the window while a key was down. No release event is coming —
    the compositor stops telling us about the keyboard entirely — so without
    this the key repeats forever, typing into a widget the user is no longer
    looking at. This is the case that matters most, because it is the one that
    cannot fix itself. }
  FRepeat.Stop;
  { Modifiers go stale for the same reason: Alt+Tab away and the Alt release
    is delivered to whoever has focus now, leaving ours held forever — after
    which every plain keystroke looks like a shortcut. }
  FRouter.SetModifiers([]);
end;

procedure TwgWindow.HandleRepeatInfo(Sender: TObject; ARate, ADelay: LongInt);
begin
  // Seat-wide, not per window, so deliberately not gated on IsForMe.
  FRepeat.SetInfo(ARate, ADelay);
end;

procedure TwgWindow.PollKeyRepeat;
var
  lNow: QWord;
  lKey: LongWord;
begin
  lNow := GetTickCount64;
  while FRepeat.Poll(lNow, lKey) do
    DeliverKey(lKey, LongWord(lNow), True);
end;

procedure TwgWindow.HandleMouseEnter(Sender: TObject; AX, AY: Integer);
begin
  if not IsForMe(Sender) then
    Exit;
  FLastMouseX := AX;
  FLastMouseY := AY;
  FRouter.MouseMove(AX, AY, 0);
end;

procedure TwgWindow.HandleMouseLeave(Sender: TObject);
begin
  if IsForMe(Sender) then
    FRouter.MouseLeaveSurface;
end;

procedure TwgWindow.HandleMouseMotion(Sender: TObject; ATime: LongWord;
  AX, AY: Integer);
begin
  if not IsForMe(Sender) then
    Exit;
  FLastMouseX := AX;
  FLastMouseY := AY;
  FRouter.MouseMove(AX, AY, ATime);
end;

procedure TwgWindow.HandleMouseButton(Sender: TObject; ATime: LongWord;
  AButton: LongWord; AState: TWlPointer.TButtonState);
begin
  if not IsForMe(Sender) then
    Exit;
  if AState = TWlPointer.TButtonState.buPressed then
    FRouter.MouseDown(FLastMouseX, FLastMouseY, AButton, ATime)
  else
    FRouter.MouseUp(FLastMouseX, FLastMouseY, AButton, ATime);
end;

procedure TwgWindow.HandleMouseAxis(Sender: TObject; ATime: LongWord;
  AAxis: TWlPointer.TAxis; AValue: LongInt);
var
  lDX, lDY: Single;
begin
  if not IsForMe(Sender) then
    Exit;
  // wl_pointer.axis is wl_fixed already converted to an integer here; treat it
  // as logical pixels of scroll.
  lDX := 0;
  lDY := 0;
  if AAxis = TWlPointer.TAxis.axVerticalScroll then
    lDY := AValue
  else
    lDX := AValue;
  FRouter.MouseScroll(FLastMouseX, FLastMouseY, lDX, lDY, ATime);
end;

procedure TwgWindow.HandleTouchDown(Sender: TObject; ATime: LongWord;
  AId: Integer; AX, AY: Integer);
begin
  if IsForMe(Sender) then
    FRouter.TouchDown(AId, AX, AY, ATime);
end;

procedure TwgWindow.HandleTouchUp(Sender: TObject; ATime: LongWord; AId: Integer);
begin
  if IsForMe(Sender) then
    FRouter.TouchUp(AId, ATime);
end;

procedure TwgWindow.HandleTouchMotion(Sender: TObject; ATime: LongWord;
  AId: Integer; AX, AY: Integer);
begin
  if IsForMe(Sender) then
    FRouter.TouchMove(AId, AX, AY, ATime);
end;

procedure TwgWindow.HandleTouchCancel(Sender: TObject);
begin
  if IsForMe(Sender) then
    FRouter.TouchCancel;
end;

{ --- TfpgwWindow callbacks --- }

procedure TwgWindow.HandleConfigure(Sender: TObject; AEdges: LongWord;
  AWidth, AHeight: LongInt);
begin
  // A zero size means "you choose", so keep what we have.
  if (AWidth > 0) and (AHeight > 0) and
     ((AWidth <> ClientWidth) or (AHeight <> ClientHeight)) then
  begin
    FWindow.SetClientSize(AWidth, AHeight);
    FPresenter.Resize(AWidth, AHeight);
    FLayoutDirty := True;
  end;
  // Every buffer is stale after a resize, and the first configure is also the
  // first chance to draw anything at all.
  FDamage.AddAll(ClientWidth, ClientHeight);
end;

procedure TwgWindow.HandleClose(Sender: TObject);
var
  lCanClose: Boolean;
begin
  lCanClose := True;
  if Assigned(FOnCloseQuery) then
    FOnCloseQuery(Self, lCanClose);
  if lCanClose then
    FClosed := True;
end;

procedure TwgWindow.HandlePaint(Sender: TObject);
begin
  // TfpgwWindow.Redraw routes here. The frame pump does the real work, so this
  // only has to make sure something is pending.
  if not FDamage.AnyDirty then
    FDamage.AddAll(ClientWidth, ClientHeight);
  ProcessFrame;
end;

end.
