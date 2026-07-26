// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.canvas.software — a CPU implementation of the accelerated canvas.

  TwgSoftCanvas is the second backend behind TwgCanvas's five-call
  device protocol. Same API as TwgGLCanvas, same tessellation, same results
  — it just rasterises the triangles itself, into ordinary ARGB8888 memory such
  as a wl_shm buffer. That is what lets a widget layer target ONE drawing API and
  still run where there is no GL 3.3 core context, no EGL, or no dma-buf export.

  It has no dependencies beyond the RTL, so it lives in rt alongside the abstract
  canvas rather than in the (libEGL/libGL-linking) gl module. Text is the one
  exception: glyphs come from an IwgGlyphSource, and the FreeType-backed atlas that
  provides them lives in the text module — but the atlas hands out ordinary
  sfA8 CPU surfaces, which this backend samples with no special casing.

  DO NOT confuse this with TwgRasterCanvas in wlg.canvas.raster. That one is an
  integer-coordinate pixel poker with replace semantics and no transform; this is
  the full float/transform/blend/anti-aliased API, implemented in software.

  FILL RULE. The rasteriser is half-space based and applies the standard
  TOP-LEFT rule. That is not a nicety: the tessellation upstream emits adjacent
  triangles that share edges — a rectangle is two of them — and with alpha
  blending, a pixel covered by both would be composited twice and show as a
  visible seam along every diagonal. The top-left rule makes shared edges belong
  to exactly one triangle.

  ANTI-ALIASING is supersampling, as in the GL backend, but it defaults to OFF
  (SuperSample = 1) because on a CPU it costs SuperSample^2 in both fill rate and
  memory. Pass 2 when quality matters more than time; the box-filter resolve
  averages the whole SxS block, so unlike the GL path a single resolve pass is
  correct at any factor. }
unit wlg.canvas.software;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, wlg.surface, wlg.canvas.base;

type
  EwgSoftCanvas = class(Exception);

  { TwgSoftCanvas }

  TwgSoftCanvas = class(TwgCanvas, IwgPixelSurface)
  private
    // Destination supplied by the caller (a wl_shm buffer, say).
    FTarget: PByte;
    FTargetStride: Integer;
    // Render buffer. With SuperSample = 1 this IS the target; otherwise it is a
    // private SxS buffer resolved into the target by EndFrame.
    FBuffer: PByte;
    FBufferStride: Integer;
    FBufferWidth: Integer;
    FBufferHeight: Integer;
    FOwnsBuffer: Boolean;
    FSuperSample: Integer;

    FClip: TRect;          // in RENDER-buffer pixels
    FBlend: TwgBlendMode;
    FLocked: Boolean;

    // Texture source for the batch being drawn.
    FTexData: PByte;
    FTexStride: Integer;
    FTexWidth: Integer;
    FTexHeight: Integer;
    FTexFormat: TwgSurfaceFormat;
    FTexLocked: IwgPixelSurface;

    procedure EnsureBuffer;
    procedure ReleaseBuffer;
    function  RowPtr(Y: Integer): PwgColor; inline;
    procedure BlendPixel(X, Y: Integer; AColor: TwgColor); inline;
    function  SampleTexture(U, V: Single): TwgColor;
    procedure RasterTriangle(const V0, V1, V2: TwgVertex; ATextured: Boolean);
    procedure Resolve;
  protected
    function GetSurfaceWidth: Integer; override;
    function GetSurfaceHeight: Integer; override;

    function LockPixels(out AData: PByte; out AStride: Integer): Boolean;
    procedure UnlockPixels;

    procedure DeviceBeginFrame; override;
    procedure DeviceEndFrame; override;
    procedure DeviceClear(AColor: TwgColor); override;
    procedure DeviceSetClip(const ARect: TRect; AEnabled: Boolean); override;
    procedure DeviceSetBlend(AMode: TwgBlendMode); override;
    procedure DeviceDrawTriangles(const AVerts: TwgVertexArray;
      ACount: Integer; ATexture: IwgSurface); override;
  public
    // ASuperSample must be a power of two; 1 (the default) disables AA.
    constructor Create(AWidth, AHeight: Integer; ASuperSample: Integer = 1);
    destructor Destroy; override;

    // Where EndFrame delivers the finished image: ARGB8888 memory holding at
    // least Height * AStride bytes, owned by the caller. AStride <= 0 means
    // tightly packed. Must be set before BeginFrame.
    procedure SetTarget(AData: Pointer; AStride: Integer = 0);

    property SuperSample: Integer read FSuperSample;
  end;

implementation

{ TwgSoftCanvas }

constructor TwgSoftCanvas.Create(AWidth, AHeight: Integer;
  ASuperSample: Integer);
begin
  inherited Create(AWidth, AHeight);
  if (ASuperSample < 1) or ((ASuperSample and (ASuperSample - 1)) <> 0) then
    raise EwgSoftCanvas.CreateFmt(
      'TwgSoftCanvas: SuperSample must be a power of two, got %d',
      [ASuperSample]);
  FSuperSample := ASuperSample;
  FBlend := cbmSourceOver;
end;

destructor TwgSoftCanvas.Destroy;
begin
  ReleaseBuffer;
  inherited Destroy;
end;

procedure TwgSoftCanvas.ReleaseBuffer;
begin
  if FOwnsBuffer and (FBuffer <> nil) then
    FreeMem(FBuffer);
  FBuffer := nil;
  FOwnsBuffer := False;
end;

procedure TwgSoftCanvas.SetTarget(AData: Pointer; AStride: Integer);
begin
  if InFrame then
    raise EwgSoftCanvas.Create('SetTarget called during a frame');
  if AData = nil then
    raise EwgSoftCanvas.Create('TwgSoftCanvas: nil target');
  FTarget := AData;
  if AStride > 0 then
    FTargetStride := AStride
  else
    FTargetStride := Width * 4;
end;

procedure TwgSoftCanvas.EnsureBuffer;
begin
  if FSuperSample = 1 then
  begin
    // Render straight into the caller's memory; no intermediate, no resolve.
    ReleaseBuffer;
    FBuffer := FTarget;
    FBufferStride := FTargetStride;
    FBufferWidth := Width;
    FBufferHeight := Height;
    FOwnsBuffer := False;
    Exit;
  end;
  if FOwnsBuffer and (FBufferWidth = Width * FSuperSample) and
     (FBufferHeight = Height * FSuperSample) then
    Exit;
  ReleaseBuffer;
  FBufferWidth := Width * FSuperSample;
  FBufferHeight := Height * FSuperSample;
  FBufferStride := FBufferWidth * 4;
  FBuffer := GetMem(PtrUInt(FBufferStride) * PtrUInt(FBufferHeight));
  FOwnsBuffer := True;
end;

function TwgSoftCanvas.RowPtr(Y: Integer): PwgColor;
begin
  Result := PwgColor(FBuffer + PtrUInt(Y) * PtrUInt(FBufferStride));
end;

function TwgSoftCanvas.GetSurfaceWidth: Integer;
begin
  Result := Width;
end;

function TwgSoftCanvas.GetSurfaceHeight: Integer;
begin
  Result := Height;
end;

function TwgSoftCanvas.LockPixels(out AData: PByte; out AStride: Integer): Boolean;
begin
  if FLocked then
    raise EwgSoftCanvas.Create('TwgSoftCanvas: pixels are already locked');
  FLocked := True;
  AData := FTarget;
  AStride := FTargetStride;
  Result := FTarget <> nil;
end;

procedure TwgSoftCanvas.UnlockPixels;
begin
  FLocked := False;
end;

{ --- compositing --- }

procedure TwgSoftCanvas.BlendPixel(X, Y: Integer; AColor: TwgColor);
var
  p: PwgColor;
  d: TwgColor;
  sa, ia: Cardinal;
  dr, dg, db, da: Cardinal;
begin
  p := RowPtr(Y) + X;
  case FBlend of
    cbmSource:
      begin
        p^ := AColor;
        Exit;
      end;
    cbmAdd:
      begin
        d := p^;
        p^ := wgARGB(
          Min(255, ((d shr 24) and $FF) + ((AColor shr 24) and $FF)),
          Min(255, ((d shr 16) and $FF) + ((AColor shr 16) and $FF)),
          Min(255, ((d shr 8) and $FF) + ((AColor shr 8) and $FF)),
          Min(255, (d and $FF) + (AColor and $FF)));
        Exit;
      end;
    cbmMultiply:
      begin
        d := p^;
        p^ := wgARGB(
          (((d shr 24) and $FF) * ((AColor shr 24) and $FF) + 127) div 255,
          (((d shr 16) and $FF) * ((AColor shr 16) and $FF) + 127) div 255,
          (((d shr 8) and $FF) * ((AColor shr 8) and $FF) + 127) div 255,
          ((d and $FF) * (AColor and $FF) + 127) div 255);
        Exit;
      end;
    cbmSourceOver:
      ; // handled below, where the early-out cases can be taken first
  end;

  // cbmSourceOver on premultiplied colours: dst = src + dst * (1 - src.a).
  sa := (AColor shr 24) and $FF;
  if sa = 0 then
    Exit;
  if sa = 255 then
  begin
    p^ := AColor;
    Exit;
  end;
  d := p^;
  ia := 255 - sa;
  da := ((AColor shr 24) and $FF) + ((((d shr 24) and $FF) * ia + 127) div 255);
  dr := ((AColor shr 16) and $FF) + ((((d shr 16) and $FF) * ia + 127) div 255);
  dg := ((AColor shr 8) and $FF) + ((((d shr 8) and $FF) * ia + 127) div 255);
  db := (AColor and $FF) + (((d and $FF) * ia + 127) div 255);
  p^ := wgARGB(Min(255, da), Min(255, dr), Min(255, dg), Min(255, db));
end;

// Bilinear sample of the bound texture. U/V are already mapped into the
// texture's own space by the caller.
function TwgSoftCanvas.SampleTexture(U, V: Single): TwgColor;
var
  fx, fy: Single;
  x0, y0, x1, y1: Integer;
  wx, wy: Cardinal;
  c00, c01, c10, c11: TwgColor;

  function Texel(X, Y: Integer): TwgColor; inline;
  var
    lCov: Byte;
  begin
    // Clamp to edge; wrapping would bleed one side of an atlas into the other.
    if X < 0 then X := 0 else if X >= FTexWidth then X := FTexWidth - 1;
    if Y < 0 then Y := 0 else if Y >= FTexHeight then Y := FTexHeight - 1;
    if FTexFormat = sfA8 then
    begin
      lCov := (FTexData + PtrUInt(Y) * PtrUInt(FTexStride) + PtrUInt(X))^;
      // Coverage only: white at that alpha, premultiplied — the vertex colour
      // supplies the actual colour when the two are multiplied.
      Result := wgARGB(lCov, lCov, lCov, lCov);
    end
    else
      Result := PwgColor(FTexData + PtrUInt(Y) * PtrUInt(FTexStride))[X];
  end;

  function Lerp2(A, B, C, D: TwgColor; AShift: Integer): Cardinal; inline;
  var
    top, bot: Cardinal;
  begin
    top := (((A shr AShift) and $FF) * (256 - wx) + ((B shr AShift) and $FF) * wx) shr 8;
    bot := (((C shr AShift) and $FF) * (256 - wx) + ((D shr AShift) and $FF) * wx) shr 8;
    Result := (top * (256 - wy) + bot * wy) shr 8;
  end;

begin
  // -0.5 puts the sample at the texel centre, matching GL's convention.
  fx := U * FTexWidth - 0.5;
  fy := V * FTexHeight - 0.5;
  x0 := Floor(fx);
  y0 := Floor(fy);
  x1 := x0 + 1;
  y1 := y0 + 1;
  wx := Round((fx - x0) * 256);
  wy := Round((fy - y0) * 256);
  if wx > 256 then wx := 256;
  if wy > 256 then wy := 256;

  c00 := Texel(x0, y0);
  c01 := Texel(x1, y0);
  c10 := Texel(x0, y1);
  c11 := Texel(x1, y1);

  Result := wgARGB(Lerp2(c00, c01, c10, c11, 24), Lerp2(c00, c01, c10, c11, 16),
                 Lerp2(c00, c01, c10, c11, 8), Lerp2(c00, c01, c10, c11, 0));
end;

{ Half-space triangle rasteriser with per-vertex colour (and optionally texture)
  interpolation. }
procedure TwgSoftCanvas.RasterTriangle(const V0, V1, V2: TwgVertex;
  ATextured: Boolean);
var
  lMinX, lMinY, lMaxX, lMaxY, x, y: Integer;
  lArea, w0, w1, w2, lInvArea: Single;
  lR, lG, lB, lA: Single;
  lU, lV: Single;
  lColor, lTexel: TwgColor;
  lTopLeft0, lTopLeft1, lTopLeft2: Boolean;

  function Edge(const AX, AY, BX, BY, PX, PY: Single): Single; inline;
  begin
    Result := (BX - AX) * (PY - AY) - (BY - AY) * (PX - AX);
  end;

  // An edge "owns" the pixels exactly on it when it is a top or a left edge.
  function IsTopLeft(const AX, AY, BX, BY: Single): Boolean; inline;
  begin
    Result := ((AY = BY) and (BX < AX)) or (BY < AY);
  end;

begin
  lArea := Edge(V0.X, V0.Y, V1.X, V1.Y, V2.X, V2.Y);
  if Abs(lArea) < 1e-9 then
    Exit;  // degenerate

  lMinX := Max(FClip.Left, Floor(Min(V0.X, Min(V1.X, V2.X))));
  lMaxX := Min(FClip.Right - 1, Ceil(Max(V0.X, Max(V1.X, V2.X))));
  lMinY := Max(FClip.Top, Floor(Min(V0.Y, Min(V1.Y, V2.Y))));
  lMaxY := Min(FClip.Bottom - 1, Ceil(Max(V0.Y, Max(V1.Y, V2.Y))));
  if (lMinX > lMaxX) or (lMinY > lMaxY) then
    Exit;

  lInvArea := 1.0 / lArea;
  // Which edges own their boundary pixels. Winding flips the sense, so the
  // test is taken on the edge as traversed in the triangle's own order.
  if lArea > 0 then
  begin
    lTopLeft0 := IsTopLeft(V1.X, V1.Y, V2.X, V2.Y);
    lTopLeft1 := IsTopLeft(V2.X, V2.Y, V0.X, V0.Y);
    lTopLeft2 := IsTopLeft(V0.X, V0.Y, V1.X, V1.Y);
  end
  else
  begin
    lTopLeft0 := IsTopLeft(V2.X, V2.Y, V1.X, V1.Y);
    lTopLeft1 := IsTopLeft(V0.X, V0.Y, V2.X, V2.Y);
    lTopLeft2 := IsTopLeft(V1.X, V1.Y, V0.X, V0.Y);
  end;

  for y := lMinY to lMaxY do
    for x := lMinX to lMaxX do
    begin
      // Barycentric weights at the pixel centre.
      w0 := Edge(V1.X, V1.Y, V2.X, V2.Y, x + 0.5, y + 0.5);
      w1 := Edge(V2.X, V2.Y, V0.X, V0.Y, x + 0.5, y + 0.5);
      w2 := Edge(V0.X, V0.Y, V1.X, V1.Y, x + 0.5, y + 0.5);
      if lArea < 0 then
      begin
        w0 := -w0; w1 := -w1; w2 := -w2;
      end;
      // Inside, with the top-left rule deciding pixels exactly on an edge, so
      // triangles sharing that edge do not both composite the pixel.
      if (w0 < 0) or (w1 < 0) or (w2 < 0) then
        Continue;
      if ((w0 = 0) and not lTopLeft0) or ((w1 = 0) and not lTopLeft1)
         or ((w2 = 0) and not lTopLeft2) then
        Continue;

      w0 := w0 * Abs(lInvArea);
      w1 := w1 * Abs(lInvArea);
      w2 := w2 * Abs(lInvArea);

      lA := w0 * ((V0.Color shr 24) and $FF) + w1 * ((V1.Color shr 24) and $FF)
          + w2 * ((V2.Color shr 24) and $FF);
      lR := w0 * ((V0.Color shr 16) and $FF) + w1 * ((V1.Color shr 16) and $FF)
          + w2 * ((V2.Color shr 16) and $FF);
      lG := w0 * ((V0.Color shr 8) and $FF) + w1 * ((V1.Color shr 8) and $FF)
          + w2 * ((V2.Color shr 8) and $FF);
      lB := w0 * (V0.Color and $FF) + w1 * (V1.Color and $FF)
          + w2 * (V2.Color and $FF);
      lColor := wgARGB(Round(lA), Round(lR), Round(lG), Round(lB));

      if ATextured then
      begin
        lU := w0 * V0.U + w1 * V1.U + w2 * V2.U;
        lV := w0 * V0.V + w1 * V1.V + w2 * V2.V;
        lTexel := SampleTexture(lU, lV);
        // Componentwise modulate, exactly as the GL fragment shader does.
        lColor := wgARGB(
          ((((lTexel shr 24) and $FF) * ((lColor shr 24) and $FF)) + 127) div 255,
          ((((lTexel shr 16) and $FF) * ((lColor shr 16) and $FF)) + 127) div 255,
          ((((lTexel shr 8) and $FF) * ((lColor shr 8) and $FF)) + 127) div 255,
          (((lTexel and $FF) * (lColor and $FF)) + 127) div 255);
      end;

      BlendPixel(x, y, lColor);
    end;
end;

procedure TwgSoftCanvas.Resolve;
var
  x, y, sx, sy, s: Integer;
  lA, lR, lG, lB, lCount: Cardinal;
  c: TwgColor;
  lSrc: PwgColor;
  lDst: PwgColor;
begin
  s := FSuperSample;
  lCount := Cardinal(s) * Cardinal(s);
  for y := 0 to Height - 1 do
  begin
    lDst := PwgColor(FTarget + PtrUInt(y) * PtrUInt(FTargetStride));
    for x := 0 to Width - 1 do
    begin
      // Box filter over the whole SxS block: unlike a bilinear GPU resolve this
      // is exact at any factor, so no repeated halving is needed.
      lA := 0; lR := 0; lG := 0; lB := 0;
      for sy := 0 to s - 1 do
      begin
        lSrc := PwgColor(FBuffer
          + PtrUInt(y * s + sy) * PtrUInt(FBufferStride)) + x * s;
        for sx := 0 to s - 1 do
        begin
          c := lSrc[sx];
          Inc(lA, (c shr 24) and $FF);
          Inc(lR, (c shr 16) and $FF);
          Inc(lG, (c shr 8) and $FF);
          Inc(lB, c and $FF);
        end;
      end;
      lDst[x] := wgARGB(lA div lCount, lR div lCount, lG div lCount, lB div lCount);
    end;
  end;
end;

{ --- device protocol --- }

procedure TwgSoftCanvas.DeviceBeginFrame;
begin
  if FTarget = nil then
    raise EwgSoftCanvas.Create('BeginFrame without a target; call SetTarget first');
  EnsureBuffer;
  FClip := Rect(0, 0, FBufferWidth, FBufferHeight);
  FBlend := cbmSourceOver;
end;

procedure TwgSoftCanvas.DeviceEndFrame;
begin
  if FSuperSample > 1 then
    Resolve;
end;

procedure TwgSoftCanvas.DeviceClear(AColor: TwgColor);
var
  x, y: Integer;
  p: PwgColor;
begin
  // Clear covers the whole target, ignoring the clip.
  for y := 0 to FBufferHeight - 1 do
  begin
    p := RowPtr(y);
    for x := 0 to FBufferWidth - 1 do
      p[x] := AColor;
  end;
end;

procedure TwgSoftCanvas.DeviceSetClip(const ARect: TRect; AEnabled: Boolean);
begin
  if not AEnabled then
  begin
    FClip := Rect(0, 0, FBufferWidth, FBufferHeight);
    Exit;
  end;
  // Canvas pixels scale straight to render-buffer pixels; both are top-down,
  // so unlike the GL backend's scissor there is no axis to flip.
  FClip := Rect(
    Max(0, ARect.Left * FSuperSample),
    Max(0, ARect.Top * FSuperSample),
    Min(FBufferWidth, ARect.Right * FSuperSample),
    Min(FBufferHeight, ARect.Bottom * FSuperSample));
  if FClip.Right < FClip.Left then FClip.Right := FClip.Left;
  if FClip.Bottom < FClip.Top then FClip.Bottom := FClip.Top;
end;

procedure TwgSoftCanvas.DeviceSetBlend(AMode: TwgBlendMode);
begin
  FBlend := AMode;
end;

procedure TwgSoftCanvas.DeviceDrawTriangles(const AVerts: TwgVertexArray;
  ACount: Integer; ATexture: IwgSurface);
var
  i: Integer;
  lTextured: Boolean;
  lU0, lV0, lU1, lV1: Single;
  lNative: IwgTextureSurface;
  lVerts: array[0..2] of TwgVertex;

  // Map surface-normalised UVs into the texture's own extent, as the GL
  // backend does when pushing vertices.
  procedure MapUV(var AVert: TwgVertex); inline;
  begin
    AVert.U := lU0 + AVert.U * (lU1 - lU0);
    AVert.V := lV0 + AVert.V * (lV1 - lV0);
  end;

  // Vertices arrive in CANVAS pixels. The GL backend gets the supersample
  // scaling for free because its projection covers an SxS-larger viewport;
  // here the rasteriser writes buffer pixels directly, so it has to be applied
  // by hand — otherwise the whole scene lands in the top-left 1/S of the
  // buffer and the resolve shrinks it.
  procedure ScaleToBuffer(var AVert: TwgVertex); inline;
  begin
    AVert.X := AVert.X * FSuperSample;
    AVert.Y := AVert.Y * FSuperSample;
  end;

begin
  if ACount <= 0 then
    Exit;

  lTextured := False;
  FTexLocked := nil;
  lU0 := 0; lV0 := 0; lU1 := 1; lV1 := 1;
  try
    if ATexture <> nil then
    begin
      // A GPU-only surface has no pixels this backend can read. Skip it rather
      // than draw a wrong colour; nothing else can be done in software.
      if not Supports(ATexture, IwgPixelSurface, FTexLocked) then
        Exit;
      if not FTexLocked.LockPixels(FTexData, FTexStride) then
        Exit;
      FTexWidth := ATexture.Width;
      FTexHeight := ATexture.Height;
      FTexFormat := ATexture.Format;
      lTextured := True;
      if Supports(ATexture, IwgTextureSurface, lNative) then
        lNative.GetTextureUV(lU0, lV0, lU1, lV1);
    end;

    i := 0;
    while i + 2 < ACount do
    begin
      lVerts[0] := AVerts[i];
      lVerts[1] := AVerts[i + 1];
      lVerts[2] := AVerts[i + 2];
      if FSuperSample > 1 then
      begin
        ScaleToBuffer(lVerts[0]);
        ScaleToBuffer(lVerts[1]);
        ScaleToBuffer(lVerts[2]);
      end;
      if lTextured then
      begin
        MapUV(lVerts[0]);
        MapUV(lVerts[1]);
        MapUV(lVerts[2]);
      end;
      RasterTriangle(lVerts[0], lVerts[1], lVerts[2], lTextured);
      Inc(i, 3);
    end;
  finally
    if lTextured and (FTexLocked <> nil) then
      FTexLocked.UnlockPixels;
    FTexLocked := nil;
  end;
end;

end.
