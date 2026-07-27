// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.widget.presenter.gl — draw a widget window on the GPU.

  The second IwgPresenter. Where TwgShmPresenter draws into the wl_shm buffers
  TfpgwWindow already owns, this one renders the tree with TwgGLCanvas into
  FBO-backed textures, exports each as a dmabuf, and attaches those to the
  surface — so the GPU writes exactly the memory the compositor scans out and
  nothing is ever copied.

  Nothing above the presenter changes. TwgWindow, the widget tree, the layouts,
  the theme and the controls are all identical; swapping the presenter is the
  whole difference between a CPU-rendered and a GPU-rendered window. That was
  the point of putting a seam there.

  IT BYPASSES TfpgwWindow.Paint on purpose. That method knows how to present the
  window's OWN buffers, and these are not those — they are wl_buffers wrapped
  around dmabuf fds this presenter exported. So it drives the surface directly:
  attach, damage, commit. TfpgwWindow's own frame bookkeeping stays idle
  (FReadyBuffer is never set), which is harmless.

  PACING is by wl_surface.frame, and it is not optional. Buffer release alone
  is backpressure but not a clock: with two targets the loop simply renders as
  fast as the compositor recycles them, which measured over 4700 fps here —
  thousands of frames a second nobody will ever see, burning GPU and battery to
  produce them. So a frame callback is requested on every commit and BeginFrame
  refuses until it fires. Both conditions must hold: the compositor has asked
  for a frame AND a target is free. (The shm presenter needs none of this
  because TfpgwWindow.Paint already does its own frame-callback bookkeeping.)

  Requires zwp_linux_dmabuf_v1 and a driver with EGL_MESA_image_dma_buf_export.
  IsAvailable answers that before anything is created, so an application can
  fall back to shm rather than failing to start. }
unit wlg.widget.presenter.gl;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Math,
  wayland, linux_dmabuf_v1_protocol,
  fpg_wayland_classes,
  wlg.canvas.base, wlg.gl.context, wlg.gl.target, wlg.canvas.gl,
  wlg.widget.types, wlg.widget.core, wlg.widget.window;

type
  EwgGLPresenter = class(Exception);

  { TwgGLPresenter }

  TwgGLPresenter = class(TInterfacedObject, IwgPresenter)
  private
    FWindow: TfpgwWindow;
    FDmabuf: TWpLinuxDmabufV1;
    FContext: TwgGLContext;
    FOwnsContext: Boolean;
    FRing: TwgGLTargetRing;
    FCanvas: TwgGLCanvas;
    FBuffers: array of TWlBuffer;
    FCurrent: Integer;
    FWidth, FHeight: Integer;
    FSuperSample: Integer;
    FSlots: Integer;
    // The compositor has invited us to draw. True initially so the first frame
    // is not waiting on a callback that was never requested.
    FFrameReady: Boolean;
    FPendingCallback: TWlCallback;

    procedure BuildTargets;
    procedure TearDownTargets;
    procedure HandleBufferRelease(Sender: TWlBuffer);
    procedure HandleFrameDone(Sender: TWlCallback; AData: DWord);
  public
    // ASuperSample must be a power of two; 2 is the sensible default on a GPU,
    // where the cost is fill rate the CPU path could not afford.
    constructor Create(AWindow: TfpgwWindow; ADmabuf: TWpLinuxDmabufV1;
      AWidth, AHeight: Integer; ASuperSample: Integer = 2;
      ASlots: Integer = 2);
    destructor Destroy; override;

    // True if this machine can present GL output as a dmabuf at all. Check
    // BEFORE constructing, and fall back to the shm presenter if not.
    class function IsAvailable(ADisplay: TfpgwDisplay): Boolean;

    function  BeginFrame(out ACanvas: TwgCanvas; out ABufferIndex: Integer): Boolean;
    procedure EndFrame(const ADamage: TRect);
    procedure AbortFrame;
    procedure Resize(AWidth, AHeight: Integer);
    function  BufferCount: Integer;

    property Context: TwgGLContext read FContext;
    property Canvas: TwgGLCanvas read FCanvas;
  end;

// Attach a GL presenter to AWindow, or leave it on shm and return False when
// the machine cannot do it. The usual way to opt in.
function wgUseGLPresenter(AWindow: TwgWindow; ASuperSample: Integer = 2): Boolean;

implementation

{ TwgGLPresenter }

class function TwgGLPresenter.IsAvailable(ADisplay: TfpgwDisplay): Boolean;
var
  lCtx: TwgGLContext;
begin
  Result := False;
  if (ADisplay = nil) or (ADisplay.Dmabuf = nil) then
    Exit;   // compositor has no zwp_linux_dmabuf_v1
  // The only honest test is to try: a driver can advertise EGL and still lack
  // the export extension, and creating a 3.3 core context can fail outright.
  try
    lCtx := TwgGLContext.Create(3, 3);
    try
      Result := lCtx.CanExportDmabuf;
    finally
      lCtx.Free;
    end;
  except
    Result := False;
  end;
end;

constructor TwgGLPresenter.Create(AWindow: TfpgwWindow; ADmabuf: TWpLinuxDmabufV1;
  AWidth, AHeight: Integer; ASuperSample: Integer; ASlots: Integer);
begin
  inherited Create;
  if AWindow = nil then
    raise EwgGLPresenter.Create('TwgGLPresenter: nil window');
  if ADmabuf = nil then
    raise EwgGLPresenter.Create(
      'TwgGLPresenter: the compositor does not offer zwp_linux_dmabuf_v1');
  FWindow := AWindow;
  FDmabuf := ADmabuf;
  FSuperSample := Max(1, ASuperSample);
  // Below two the compositor holds the only buffer and nothing can be drawn.
  FSlots := Max(2, ASlots);
  FWidth := Max(1, AWidth);
  FHeight := Max(1, AHeight);
  FCurrent := -1;
  FFrameReady := True;

  FContext := TwgGLContext.Create(3, 3);
  FOwnsContext := True;
  if not FContext.CanExportDmabuf then
    raise EwgGLPresenter.Create(
      'this driver cannot export GL textures as dmabufs ' +
      '(EGL_MESA_image_dma_buf_export missing)');
  BuildTargets;
end;

destructor TwgGLPresenter.Destroy;
begin
  TearDownTargets;
  FCanvas.Free;
  if FOwnsContext then
    FContext.Free;
  inherited Destroy;
end;

procedure TwgGLPresenter.BuildTargets;
var
  i: Integer;
  lParams: TWpLinuxBufferParamsV1;
  lFlags: TWpLinuxBufferParamsV1.TFlags;
  lTarget: TwgGLRenderTarget;
begin
  FContext.MakeCurrent;
  FRing := TwgGLTargetRing.Create(FContext, FWidth, FHeight, FSlots);

  if FCanvas = nil then
    FCanvas := TwgGLCanvas.Create(FContext, FWidth, FHeight, FSuperSample)
  else if (FCanvas.Width <> FWidth) or (FCanvas.Height <> FHeight) then
  begin
    FreeAndNil(FCanvas);
    FCanvas := TwgGLCanvas.Create(FContext, FWidth, FHeight, FSuperSample);
  end;

  SetLength(FBuffers, FRing.Count);
  for i := 0 to FRing.Count - 1 do
  begin
    lTarget := FRing[i];
    lParams := FDmabuf.CreateParams;
    // The fd stays owned by the target; zwp_linux_dmabuf dups what it needs,
    // so this is a lend, not a hand-off.
    lParams.Add(lTarget.DmabufFd, 0, lTarget.Offset, lTarget.Stride,
      DWord(lTarget.Modifier shr 32), DWord(lTarget.Modifier and $FFFFFFFF));
    lFlags.Value := 0;
    FBuffers[i] := lParams.CreateImmed(FWidth, FHeight,
      DWord(lTarget.Fourcc), lFlags);
    FBuffers[i].OnRelease := @HandleBufferRelease;
    lParams.Free;
  end;
end;

procedure TwgGLPresenter.TearDownTargets;
var
  i: Integer;
begin
  for i := 0 to High(FBuffers) do
    if FBuffers[i] <> nil then
    begin
      FBuffers[i].OnRelease := nil;
      FBuffers[i].Free;
      FBuffers[i] := nil;
    end;
  SetLength(FBuffers, 0);
  FreeAndNil(FRing);
  FCurrent := -1;
end;

function TwgGLPresenter.BufferCount: Integer;
begin
  Result := FSlots;
end;

procedure TwgGLPresenter.HandleBufferRelease(Sender: TWlBuffer);
var
  i: Integer;
begin
  for i := 0 to High(FBuffers) do
    if FBuffers[i] = Sender then
    begin
      FRing.MarkFree(i);
      Exit;
    end;
end;

function TwgGLPresenter.BeginFrame(out ACanvas: TwgCanvas;
  out ABufferIndex: Integer): Boolean;
var
  lSlot: Integer;
begin
  ACanvas := nil;
  ABufferIndex := -1;
  Result := False;
  if (FRing = nil) or (FCanvas = nil) then
    Exit;
  // Wait for the compositor's invitation, or we render frames nobody sees.
  if not FFrameReady then
    Exit;

  lSlot := FRing.Acquire;
  if lSlot < 0 then
    Exit;   // every target still on screen; skip this frame

  // Several presenters could share a context in principle, so make ours
  // current rather than assuming it still is.
  FContext.MakeCurrent;
  FCanvas.SetTarget(FRing[lSlot]);
  FCurrent := lSlot;
  ACanvas := FCanvas;
  ABufferIndex := lSlot;
  Result := True;
end;

procedure TwgGLPresenter.EndFrame(const ADamage: TRect);
var
  lSurface: TWlSurface;
  lW, lH: Integer;
begin
  if FCurrent < 0 then
    Exit;
  lSurface := FWindow.SurfaceShell.Surface;
  if lSurface = nil then
  begin
    FCurrent := -1;
    Exit;
  end;

  lW := ADamage.Right - ADamage.Left;
  lH := ADamage.Bottom - ADamage.Top;
  if (lW <= 0) or (lH <= 0) then
  begin
    AbortFrame;
    Exit;
  end;

  // TwgGLCanvas.EndFrame has already resolved the supersample buffer and
  // glFinished, so the dmabuf genuinely holds the finished frame before the
  // compositor is told to look at it.
  lSurface.Attach(FBuffers[FCurrent], 0, 0);
  // Damage, NOT DamageBuffer. wl_surface.damage_buffer needs wl_compositor
  // version 4, and the classes layer binds wl_compositor at version 1 — asking
  // for it is a protocol error, and the compositor drops the connection, which
  // surfaces here as an unrelated-looking "stream write error" on the next
  // write. The two are equivalent for us anyway: the canvas supersamples
  // internally and resolves to a 1:1 target, so buffer and surface coordinates
  // are the same.
  lSurface.Damage(ADamage.Left, ADamage.Top, lW, lH);

  // Ask to be told when this frame has been shown. Must be requested BEFORE
  // the commit that carries it.
  FPendingCallback := lSurface.Frame;
  if FPendingCallback <> nil then
  begin
    FPendingCallback.OnDone := @HandleFrameDone;
    FFrameReady := False;
  end;

  lSurface.Commit;

  FRing.MarkBusy(FCurrent);
  FCurrent := -1;
end;

procedure TwgGLPresenter.HandleFrameDone(Sender: TWlCallback; AData: DWord);
begin
  // A frame callback is one-shot; the object is ours to dispose of.
  if Sender = FPendingCallback then
    FPendingCallback := nil;
  Sender.Free;
  FFrameReady := True;
end;

procedure TwgGLPresenter.AbortFrame;
begin
  // Nothing was attached and the slot was never marked busy, so it simply
  // stays available. No CPU-access bracket to unwind, unlike the shm path.
  FCurrent := -1;
end;

procedure TwgGLPresenter.Resize(AWidth, AHeight: Integer);
begin
  if (AWidth <= 0) or (AHeight <= 0) then
    Exit;
  if (AWidth = FWidth) and (AHeight = FHeight) then
    Exit;
  FWidth := AWidth;
  FHeight := AHeight;
  // Targets are sized at creation, so a resize means new textures, new
  // exports and new wl_buffers. The compositor may still be holding old ones;
  // destroying a wl_buffer it holds is allowed — it keeps the contents until
  // it is done.
  TearDownTargets;
  BuildTargets;
  // A resize can strand a callback that will never arrive for a surface size
  // that no longer exists; unblock so the next frame can go out.
  FFrameReady := True;
end;

{ --- convenience --- }

function wgUseGLPresenter(AWindow: TwgWindow; ASuperSample: Integer): Boolean;
var
  lPresenter: TwgGLPresenter;
begin
  Result := False;
  if AWindow = nil then
    Exit;
  if not TwgGLPresenter.IsAvailable(AWindow.Display) then
    Exit;
  try
    lPresenter := TwgGLPresenter.Create(AWindow.Window, AWindow.Display.Dmabuf,
      AWindow.ClientWidth, AWindow.ClientHeight, ASuperSample);
  except
    // Anything went wrong bringing the GPU path up: stay on shm rather than
    // taking the application down with us.
    Exit;
  end;
  AWindow.SetPresenter(lPresenter);
  Result := True;
end;

end.
