// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ gl_canvas_demo — TwgGLCanvas drawing an animated scene, presented over
  Wayland as a dmabuf with no libwayland anywhere in the process.

  It exercises the parts of the accelerated canvas that are easy to get wrong:

    * anti-aliased fills and strokes — a rotating polygon, circles and arcs,
      all of which look obviously wrong if the supersample resolve is broken
    * the transform stack — the rotating star is drawn in its own local space
    * clipping — one panel is drawn under a clip rectangle
    * blend modes — an additive glow over the background
    * DrawSurface — a procedurally built TwgImage blitted and scaled,
      which also proves the IwgSurface texture cache re-uploads only on change
    * text — FreeType glyphs through TwgGlyphAtlas, including kerning and a
      second size, which proves atlas paging and the alpha-only shader path

  Left-drag moves the window, right-click quits.

  Build with the Makefile's `examples` target. }
program gl_canvas_demo;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  ctypes, SysUtils, Math, BaseUnix,
  Wayland_Core, wayland, linux_dmabuf_v1_protocol, xdg_shell_protocol,
  wlg.surface, wlg.canvas.base,
  wlg.gl.context, wlg.gl.texture, wlg.gl.target, wlg.canvas.gl,
  wlg.text.atlas;

const
  WIN_W = 900;
  WIN_H = 620;
  SUPERSAMPLE = 2;
  FRAME_SLOTS = 2;

  BTN_LEFT  = $110;
  BTN_RIGHT = $111;

  FONT_CANDIDATES: array[0..3] of String = (
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
    '/usr/share/fonts/TTF/DejaVuSans.ttf'
  );

type

  { TGLCanvasDemo }

  TGLCanvasDemo = class
  private
    // GPU
    FContext: TwgGLContext;
    FRing: TwgGLTargetRing;
    FCanvas: TwgGLCanvas;
    FFont: TwgGlyphAtlas;
    FFontSmall: TwgGlyphAtlas;
    FLogo: TwgImage;

    // Wayland
    FDisplay:    TWlDisplay;
    FRegistry:   TWlRegistry;
    FCompositor: TWlCompositor;
    FWM:         TXdgWmBase;
    FSurface:    TWlSurface;
    FXdgSurface: TXdgSurface;
    FToplevel:   TXdgToplevel;
    FDmabuf:     TWpLinuxDmabufV1;
    FSeat:       TWlSeat;
    FPointer:    TWlPointer;
    FBuffers:    array of TWlBuffer;

    FConfigured: Boolean;
    FQuit:       Boolean;
    FFrameReady: Boolean;
    FStartTick:  QWord;
    FFrames:     Integer;

    function  FindFont: String;
    procedure InitGpu;
    procedure InitWayland;
    procedure BuildWlBuffers;
    procedure BuildLogo;

    procedure DrawScene(ACanvas: TwgGLCanvas; ATime: Double);
    procedure TryDraw;
    procedure DrawFrame;

    procedure OnRegistryGlobal(Sender: TWlRegistry; aName: DWord; aInterface: String; aVersion: DWord);
    procedure OnError(Sender: TWlDisplay; aObjectId: Cardinal; aCode: DWord; aMessage: String);
    procedure OnPing(Sender: TXdgWmBase; aSerial: DWord);
    procedure OnXdgConfigure(Sender: TXdgSurface; aSerial: DWord);
    procedure OnToplevelConfigure(Sender: TXdgToplevel; aWidth, aHeight: Integer; aStates: TBytes);
    procedure OnToplevelClose(Sender: TXdgToplevel);
    procedure OnSeatCapabilities(Sender: TWlSeat; aCapabilities: TWlSeat.TCapability);
    procedure OnPointerButton(Sender: TWlPointer; aSerial, aTime, aButton: DWord; aState: TWlPointer.TButtonState);
    procedure OnBufferRelease(Sender: TWlBuffer);
    procedure OnFrameDone(Sender: TWlCallback; aData: DWord);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run;
  end;

{ TGLCanvasDemo }

function TGLCanvasDemo.FindFont: String;
var
  i: Integer;
begin
  for i := Low(FONT_CANDIDATES) to High(FONT_CANDIDATES) do
    if FileExists(FONT_CANDIDATES[i]) then
      Exit(FONT_CANDIDATES[i]);
  raise Exception.Create('no usable TrueType font found; install fonts-dejavu');
end;

procedure TGLCanvasDemo.InitGpu;
begin
  FContext := TwgGLContext.Create(3, 3);
  if not FContext.CanExportDmabuf then
    raise Exception.Create(
      'the driver cannot export GL textures as dmabufs; this demo needs ' +
      'EGL_MESA_image_dma_buf_export');

  FRing := TwgGLTargetRing.Create(FContext, WIN_W, WIN_H, FRAME_SLOTS);
  FCanvas := TwgGLCanvas.Create(FContext, WIN_W, WIN_H, SUPERSAMPLE);

  FFont := TwgGlyphAtlas.Create(FindFont, 28);
  FFontSmall := TwgGlyphAtlas.Create(FindFont, 14);
  // Rasterise ASCII up front so the first frame does not stall on uploads.
  FFont.Prewarm('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:—');
  FFontSmall.Prewarm('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:');

  BuildLogo;
end;

procedure TGLCanvasDemo.BuildLogo;
var
  x, y: Integer;
  lR, lG, lB, lA: Byte;
  lDist: Double;
begin
  // A procedural RGBA image: a soft radial disc over a checkerboard, so both
  // the colour path and premultiplied alpha are visible when it is blitted.
  FLogo := TwgImage.Create(64, 64);
  for y := 0 to 63 do
    for x := 0 to 63 do
    begin
      lDist := Sqrt(Sqr(x - 31.5) + Sqr(y - 31.5)) / 31.5;
      if lDist > 1.0 then
        lA := 0
      else
        lA := Round(255 * Min(1.0, (1.0 - lDist) * 3.0));
      if ((x div 8) + (y div 8)) mod 2 = 0 then
      begin
        lR := 250; lG := 190; lB := 60;
      end
      else
      begin
        lR := 60; lG := 130; lB := 245;
      end;
      // TwgImage holds premultiplied pixels.
      FLogo.PutPixel(x, y, wgPremultiply(wgARGB(lA, lR, lG, lB)));
    end;
  FLogo.Changed;
end;

procedure TGLCanvasDemo.DrawScene(ACanvas: TwgGLCanvas; ATime: Double);
var
  i: Integer;
  lStar: array[0..9] of TwgPointF;
  lAngle, lRadius: Double;
  lPath: TwgPath;
  lPulse: Double;
begin
  // --- background: a vertical gradient, so the gradient path gets exercised
  ACanvas.Clear(wgARGB(255, 18, 20, 28));
  ACanvas.FillRectGradient(0, 0, WIN_W, WIN_H,
    wgARGB(255, 28, 32, 48), wgARGB(255, 28, 32, 48),
    wgARGB(255, 12, 13, 20), wgARGB(255, 12, 13, 20));

  // --- title
  ACanvas.Font := FFont;
  ACanvas.DrawTextTopLeft('TwgGLCanvas', 32, 24, wgARGB(255, 235, 238, 245));
  ACanvas.Font := FFontSmall;
  ACanvas.DrawTextTopLeft(
    'accelerated primitives · supersampled AA · FreeType text · dmabuf present',
    32, 60, wgARGB(190, 150, 170, 200));

  // --- panel 1: anti-aliased shapes
  ACanvas.FillRoundRect(32, 96, 400, 240, 14, 14, wgARGB(255, 32, 38, 54));
  ACanvas.RoundRect(32, 96, 400, 240, 14, 14, wgARGB(120, 120, 150, 200));

  // circles, stroked with increasing width
  for i := 0 to 4 do
  begin
    ACanvas.LineWidth := 1 + i * 1.5;
    ACanvas.Circle(90 + i * 70, 170, 26,
      wgARGB(255, 90 + i * 30, 200 - i * 20, 240 - i * 30));
  end;
  ACanvas.LineWidth := 1;

  // filled ellipses with decreasing alpha, to show real blending
  for i := 0 to 4 do
    ACanvas.FillEllipse(90 + i * 70, 250, 30, 20, wgARGB(220 - i * 40, 250, 140, 90));

  // an arc and a pie
  ACanvas.LineWidth := 4;
  ACanvas.LineCap := clcRound;
  ACanvas.Arc(120, 305, 40, 22, Pi * 1.1, Pi * 0.8, wgARGB(255, 120, 230, 160));
  ACanvas.LineWidth := 1;
  ACanvas.FillPie(300, 300, 34, 34, -Pi / 2, Pi * 1.2 + Sin(ATime) * 0.6,
    wgARGB(230, 240, 200, 80));

  // --- panel 2: transform stack — a star spinning in its own space
  ACanvas.FillRoundRect(456, 96, 200, 240, 14, 14, wgARGB(255, 32, 38, 54));
  ACanvas.RoundRect(456, 96, 200, 240, 14, 14, wgARGB(120, 120, 150, 200));

  ACanvas.Save;
  ACanvas.Translate(556, 216);
  ACanvas.Rotate(ATime * 0.8);
  for i := 0 to 9 do
  begin
    lAngle := i * Pi / 5;
    if (i mod 2) = 0 then
      lRadius := 78
    else
      lRadius := 32;
    lStar[i] := wgPointF(Cos(lAngle) * lRadius, Sin(lAngle) * lRadius);
  end;
  ACanvas.FillPolygon(lStar, wgARGB(235, 255, 205, 90));
  // Light, not dark: half the stroke falls OUTSIDE the fill onto the dark
  // panel, so a dark outline would be invisible exactly where it matters.
  ACanvas.LineWidth := 2.5;
  ACanvas.LineJoin := cljMiter;
  ACanvas.Polygon(lStar, wgARGB(255, 255, 250, 235));
  ACanvas.Restore;

  // --- panel 3: clipping + additive glow
  ACanvas.FillRoundRect(680, 96, 188, 240, 14, 14, wgARGB(255, 32, 38, 54));
  ACanvas.RoundRect(680, 96, 188, 240, 14, 14, wgARGB(120, 120, 150, 200));

  ACanvas.Save;
  ACanvas.ClipRect(696, 112, 156, 208);
  // Diagonal stripes, clipped to the panel — the clip is what keeps them inside.
  for i := -8 to 20 do
  begin
    ACanvas.LineWidth := 10;
    ACanvas.Line(696 + i * 20 - 60, 112, 696 + i * 20 + 60, 320,
      wgARGB(70, 130, 190, 255));
  end;
  // An additive pulse on top, to show the blend mode actually changes.
  lPulse := 0.5 + 0.5 * Sin(ATime * 2.0);
  ACanvas.BlendMode := cbmAdd;
  ACanvas.FillCircle(774, 216, 40 + lPulse * 25,
    wgARGB(Round(60 + 80 * lPulse), 90, 140, 220));
  ACanvas.BlendMode := cbmSourceOver;
  ACanvas.Restore;

  // --- bezier path along the bottom
  lPath := TwgPath.Create;
  try
    lPath.MoveTo(48, 470);
    lPath.CurveTo(200, 380 + Sin(ATime) * 50, 340, 560 - Sin(ATime) * 50, 480, 470);
    lPath.CurveTo(620, 380 + Cos(ATime) * 40, 740, 560, 860, 460);
    ACanvas.LineWidth := 3;
    ACanvas.LineCap := clcRound;
    ACanvas.StrokePath(lPath, wgARGB(255, 120, 220, 255));
  finally
    lPath.Free;
  end;

  // --- image blits: natural size, scaled, tinted, and rotated
  ACanvas.DrawSurface(FLogo, 48, 500);
  ACanvas.DrawSurface(FLogo, 130, 500, 110, 110);
  ACanvas.DrawSurface(FLogo, 0, 0, FLogo.Width, FLogo.Height,
    266, 500, 80, 80, wgARGB(255, 255, 140, 140));

  ACanvas.Save;
  ACanvas.Translate(400, 545);
  ACanvas.Rotate(-ATime * 1.3);
  ACanvas.DrawSurface(FLogo, -40, -40, 80, 80);
  ACanvas.Restore;

  // --- opacity ramp, proving the global alpha multiply
  ACanvas.Font := FFontSmall;
  for i := 0 to 5 do
  begin
    ACanvas.Opacity := (i + 1) / 6;
    ACanvas.FillRect(490 + i * 42, 505, 34, 34, wgARGB(255, 120, 230, 170));
  end;
  ACanvas.Opacity := 1.0;

  ACanvas.DrawTextTopLeft(Format('frame %d — %.1fs', [FFrames, ATime]),
    490, 552, wgARGB(160, 190, 200, 220));
  ACanvas.DrawTextTopLeft('left-drag to move · right-click to quit',
    490, 572, wgARGB(160, 190, 200, 220));
end;

procedure TGLCanvasDemo.InitWayland;
begin
  TWlDisplay.TryCreateConnection(FDisplay);
  FDisplay.OnError := @OnError;
  FRegistry := FDisplay.GetRegistry;
  FRegistry.OnGlobal := @OnRegistryGlobal;
  FDisplay.SyncAndWait;
  FDisplay.SyncAndWait;

  if not Assigned(FCompositor) then raise Exception.Create('no wl_compositor');
  if not Assigned(FWM) then raise Exception.Create('no xdg_wm_base');
  if not Assigned(FDmabuf) then raise Exception.Create('no zwp_linux_dmabuf_v1');

  FSurface := FCompositor.CreateSurface;
  FXdgSurface := FWM.GetXdgSurface(FSurface);
  FXdgSurface.OnConfigure := @OnXdgConfigure;
  FToplevel := FXdgSurface.GetToplevel;
  FToplevel.SetTitle('wayl — accelerated canvas');
  FToplevel.OnConfigure := @OnToplevelConfigure;
  FToplevel.OnClose := @OnToplevelClose;
end;

procedure TGLCanvasDemo.BuildWlBuffers;
var
  i: Integer;
  lParams: TWpLinuxBufferParamsV1;
  lFlags: TWpLinuxBufferParamsV1.TFlags;
  lTarget: TwgGLRenderTarget;
begin
  SetLength(FBuffers, FRing.Count);
  for i := 0 to FRing.Count - 1 do
  begin
    lTarget := FRing[i];
    lParams := FDmabuf.CreateParams;
    // The fd stays owned by the target; the protocol dups what it needs.
    lParams.Add(lTarget.DmabufFd, 0, lTarget.Offset, lTarget.Stride,
      DWord(lTarget.Modifier shr 32), DWord(lTarget.Modifier and $FFFFFFFF));
    lFlags.Value := 0;
    FBuffers[i] := lParams.CreateImmed(WIN_W, WIN_H, DWord(lTarget.Fourcc), lFlags);
    FBuffers[i].OnRelease := @OnBufferRelease;
    lParams.Free;
  end;
end;

procedure TGLCanvasDemo.TryDraw;
begin
  if FQuit or not FFrameReady then
    Exit;
  if FRing.Acquire < 0 then
    Exit;
  FFrameReady := False;
  DrawFrame;
end;

procedure TGLCanvasDemo.DrawFrame;
var
  lSlot: Integer;
  lCb: TWlCallback;
  lTime: Double;
begin
  lSlot := FRing.Acquire;
  if lSlot < 0 then
    Exit;

  lTime := (GetTickCount64 - FStartTick) / 1000.0;

  FCanvas.SetTarget(FRing[lSlot]);
  FCanvas.BeginFrame;
  try
    DrawScene(FCanvas, lTime);
  finally
    FCanvas.EndFrame;   // resolves the supersample buffer and glFinishes
  end;

  lCb := FSurface.Frame;
  lCb.OnDone := @OnFrameDone;

  FRing.MarkBusy(lSlot);
  FSurface.Attach(FBuffers[lSlot], 0, 0);
  FSurface.DamageBuffer(0, 0, WIN_W, WIN_H);
  FSurface.Commit;

  Inc(FFrames);
end;

{ --- Wayland callbacks --- }

procedure TGLCanvasDemo.OnRegistryGlobal(Sender: TWlRegistry; aName: DWord;
  aInterface: String; aVersion: DWord);
begin
  if aInterface = 'wl_compositor' then
    Sender.Bind(aName, aInterface, aVersion, TWlCompositor, FCompositor)
  else if aInterface = 'xdg_wm_base' then
  begin
    Sender.Bind(aName, aInterface, aVersion, TXdgWmBase, FWM);
    FWM.OnPing := @OnPing;
  end
  else if aInterface = 'zwp_linux_dmabuf_v1' then
    Sender.Bind(aName, aInterface, aVersion, TWpLinuxDmabufV1, FDmabuf)
  else if aInterface = 'wl_seat' then
  begin
    Sender.Bind(aName, aInterface, aVersion, TWlSeat, FSeat);
    FSeat.OnCapabilities := @OnSeatCapabilities;
  end;
end;

procedure TGLCanvasDemo.OnError(Sender: TWlDisplay; aObjectId: Cardinal;
  aCode: DWord; aMessage: String);
begin
  WriteLn(Format('wayland error: obj[%d] code %d: %s', [aObjectId, aCode, aMessage]));
  FQuit := True;
end;

procedure TGLCanvasDemo.OnPing(Sender: TXdgWmBase; aSerial: DWord);
begin
  Sender.Pong(aSerial);
end;

procedure TGLCanvasDemo.OnXdgConfigure(Sender: TXdgSurface; aSerial: DWord);
begin
  Sender.AckConfigure(aSerial);
  if not FConfigured then
  begin
    FConfigured := True;
    FFrameReady := True;
    TryDraw;
  end;
end;

procedure TGLCanvasDemo.OnToplevelConfigure(Sender: TXdgToplevel; aWidth,
  aHeight: Integer; aStates: TBytes);
begin
  // Fixed-size demo: the canvas, the target ring and the wl_buffers are all
  // built for WIN_W x WIN_H, so a resize is acknowledged and ignored.
end;

procedure TGLCanvasDemo.OnToplevelClose(Sender: TXdgToplevel);
begin
  FQuit := True;
end;

procedure TGLCanvasDemo.OnSeatCapabilities(Sender: TWlSeat;
  aCapabilities: TWlSeat.TCapability);
begin
  if aCapabilities.Pointer and not Assigned(FPointer) then
  begin
    FPointer := Sender.GetPointer;
    FPointer.OnButton := @OnPointerButton;
  end;
end;

procedure TGLCanvasDemo.OnPointerButton(Sender: TWlPointer; aSerial, aTime,
  aButton: DWord; aState: TWlPointer.TButtonState);
begin
  if aState <> TWlPointer.TButtonState.buPressed then
    Exit;
  case aButton of
    BTN_LEFT:  FToplevel.Move(FSeat, aSerial);
    BTN_RIGHT: FQuit := True;
  end;
end;

procedure TGLCanvasDemo.OnBufferRelease(Sender: TWlBuffer);
var
  i: Integer;
begin
  for i := 0 to High(FBuffers) do
    if FBuffers[i] = Sender then
    begin
      FRing.MarkFree(i);
      Break;
    end;
  TryDraw;
end;

procedure TGLCanvasDemo.OnFrameDone(Sender: TWlCallback; aData: DWord);
begin
  Sender.Free;
  FFrameReady := True;
  TryDraw;
end;

constructor TGLCanvasDemo.Create;
begin
  inherited Create;
  InitGpu;
  InitWayland;
  BuildWlBuffers;
  FStartTick := GetTickCount64;
end;

destructor TGLCanvasDemo.Destroy;
begin
  FLogo.Free;
  FFontSmall.Free;
  FFont.Free;
  FCanvas.Free;
  FRing.Free;
  FContext.Free;
  inherited Destroy;
end;

procedure TGLCanvasDemo.Run;
begin
  WriteLn(Format('gl_canvas_demo: %dx%d, %dx supersampling. Right-click to quit.',
    [WIN_W, WIN_H, SUPERSAMPLE]));
  Flush(Output);
  FSurface.Commit;   // buffer-less commit -> first configure -> first frame
  while not FQuit do
    FDisplay.WaitMessage(100);
  WriteLn(Format('presented %d frames', [FFrames]));
end;

var
  lApp: TGLCanvasDemo;
begin
  lApp := TGLCanvasDemo.Create;
  try
    lApp.Run;
  finally
    lApp.Free;
  end;
end.
