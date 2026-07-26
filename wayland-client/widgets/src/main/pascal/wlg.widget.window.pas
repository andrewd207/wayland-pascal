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
  Classes, SysUtils, Types, Math,
  fpg_wayland_classes,
  wlg.surface, wlg.canvas.base, wlg.canvas.software,
  wlg.widget.types, wlg.widget.core;

type
  EwgWindow = class(Exception);

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

  TwgWindow = class(TComponent, IwgWidgetHost)
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
    FOnCloseQuery: TwgWindowCloseEvent;
    FOnLayout: TNotifyEvent;

    procedure HandleConfigure(Sender: TObject; AEdges: LongWord;
      AWidth, AHeight: LongInt);
    procedure HandleClose(Sender: TObject);
    procedure HandlePaint(Sender: TObject);
    function  GetClientWidth: Integer;
    function  GetClientHeight: Integer;
  protected
    { IwgWidgetHost }
    procedure WidgetInvalidated(const ARect: TRect);
    procedure WidgetLayoutInvalidated;
    function  HostFont: IwgGlyphSource;

    // Root gets the whole client area. Overridden once real layouts land.
    procedure DoLayout; virtual;
  public
    constructor Create(ADisplay: TfpgwDisplay; const ATitle: String;
      AWidth, AHeight: Integer); reintroduce;
    destructor Destroy; override;

    // Must be called before the first frame. Defaults to TwgShmPresenter, so
    // this is only needed to opt into the GL one.
    procedure SetPresenter(const APresenter: IwgPresenter);

    // Repaint everything next frame.
    procedure Invalidate;
    // Lay out if needed and paint if anything is damaged. Safe to call every
    // loop iteration; it does nothing when there is nothing to do.
    procedure ProcessFrame;
    // Convenience loop: pump events and frames until the window closes.
    procedure Run(APollMs: Integer = 30);
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
  end;

implementation

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

  FDamage.AddAll(AWidth, AHeight);
  FLayoutDirty := True;
end;

destructor TwgWindow.Destroy;
begin
  // Drop the tree before the surface: a widget's Invalidate reaches back into
  // this object, and the host reference must still be valid while it does.
  FreeAndNil(FRoot);
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
  FLayoutDirty := True;
end;

function TwgWindow.HostFont: IwgGlyphSource;
begin
  Result := FFont;
end;

{ --- frame --- }

procedure TwgWindow.Invalidate;
begin
  FDamage.AddAll(ClientWidth, ClientHeight);
end;

procedure TwgWindow.DoLayout;
begin
  FRoot.SetBounds(0, 0, ClientWidth, ClientHeight);
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
    Exit;   // every buffer still on screen; try again next tick

  lDamage := FDamage.Take(lIndex);
  if wgRectEmpty(lDamage) then
  begin
    // Another buffer is dirty but this one is already current — nothing to
    // repaint into it.
    FPresenter.AbortFrame;
    Exit;
  end;
  lDamage := wgIntersectRect(lDamage, Rect(0, 0, ClientWidth, ClientHeight));
  if wgRectEmpty(lDamage) then
  begin
    FPresenter.AbortFrame;
    Exit;
  end;

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
end;

procedure TwgWindow.Run(APollMs: Integer);
begin
  while not FClosed do
  begin
    FDisplay.WaitEvent(APollMs);
    ProcessFrame;
  end;
end;

procedure TwgWindow.Close;
begin
  FClosed := True;
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
