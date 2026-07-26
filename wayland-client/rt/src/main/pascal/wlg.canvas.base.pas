// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2026 Andrew Haines <https://github.com/andrewd207>

{ wlg.canvas.base — the drawing API for hardware-accelerated backends, and
  everything needed to reduce it to triangles.

  TwgCanvas is where the entire public vocabulary lives: transforms,
  clipping, pens and brushes, rectangles, ellipses, arcs, rounded rectangles,
  bezier paths, image blits and text. None of it is backend-specific. Every one
  of those primitives is tessellated HERE, in portable Pascal, down to a
  deliberately tiny device protocol that a backend implements:

      DeviceBeginFrame / DeviceEndFrame
      DeviceClear      (AColor)
      DeviceSetClip    (ARect, AEnabled)
      DeviceSetBlend   (AMode)
      DeviceDrawTriangles (AVerts, ATexture)

  That is the whole contract. A backend has to know how to fill triangles with a
  per-vertex colour, optionally modulated by a texture — nothing else. The
  OpenGL implementation is TwgGLCanvas in the wayland-gl module; a Vulkan
  or a software rasteriser could sit behind the same five calls.

  This is a SEPARATE class hierarchy from the software TwgRasterCanvas in
  wlg.canvas.raster. That one is a direct pixel poker with integer coordinates and
  replace semantics; this one has float coordinates, a transform stack and real
  blending, and assumes filling triangles is cheap. They meet only at IwgSurface,
  so either can be a source for the other.

  COORDINATES are floats in surface pixels, with the origin at the TOP-LEFT and
  Y increasing downward — the same convention as the software canvas and as
  Wayland surface coordinates. Backends whose native framebuffer is bottom-up
  (OpenGL) flip in their projection, not here.

  COLOURS passed to primitives use STRAIGHT (non-premultiplied) alpha, so
  wgARGB($80, 255, 0, 0) is what you would expect: half-transparent red. Pixels
  stored in surfaces are premultiplied, per wlg.surface; the conversion, and
  the global Opacity multiply, happen once in ResolveColor as vertices are
  emitted.

  ANTI-ALIASING is a backend property, not something the tessellation here
  emits coverage geometry for. Backends are expected to render at a higher
  sample rate and resolve; see TwgGLCanvas's supersampling. }
unit wlg.canvas.base;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, wlg.surface;

type
  EwgCanvas = class(Exception);

  TwgPointF = record
    X, Y: Single;
  end;
  TwgPointFArray = array of TwgPointF;

  TwgRectF = record
    Left, Top, Right, Bottom: Single;
  end;

  { TwgMatrix — a 2x3 affine transform.

      X' = A*X + C*Y + E
      Y' = B*X + D*Y + F }
  TwgMatrix = record
    A, B, C, D, E, F: Single;
  end;

  { TwgVertex — the one thing backends consume.

    X/Y are FINAL device pixels: the transform has already been applied. U/V are
    normalised over the source surface's own extent (0..1 across its Width and
    Height), NOT over the backing texture — a backend blitting from an atlas
    page maps them through IwgTextureSurface.GetTextureUV. Color is premultiplied
    and modulates the sampled texel; with no texture it IS the colour. }
  TwgVertex = record
    X, Y: Single;
    U, V: Single;
    Color: TwgColor;
  end;
  TwgVertexArray = array of TwgVertex;

  TwgBlendMode = (
    cbmSourceOver,   // normal alpha compositing (default)
    cbmSource,       // replace the destination, alpha included
    cbmAdd,          // additive; for glows and light accumulation
    cbmMultiply      // modulate the destination; for shadows and tints
  );

  TwgLineCap  = (clcButt, clcSquare, clcRound);
  TwgLineJoin = (cljMiter, cljRound, cljBevel);

  TwgFillRule = (
    cfrNonZero,      // standard winding rule
    cfrEvenOdd       // alternate; self-intersections punch holes
  );

  { --- text --- }

  { TwgGlyphInfo — where one rasterised glyph lives and how to place it.

    Texture is the atlas page, exposed as an ordinary IwgSurface so the canvas
    blits it with the same path as any image. U/V bound the glyph within that
    page, normalised over the page's extent. Width/Height are the bitmap's size
    in pixels. BearingX/BearingY offset the bitmap from the pen position, with
    BearingY measured UP from the baseline (FreeType's convention). Advance is
    how far the pen moves afterwards. }
  TwgGlyphInfo = record
    Texture: IwgSurface;
    U0, V0, U1, V1: Single;
    Width, Height: Single;
    BearingX, BearingY: Single;
    Advance: Single;
  end;

  { IwgGlyphSource — a sized font face that can produce rasterised glyphs.

    Implemented in the backend (TwgGlyphAtlas in the wayland-gl module wraps
    FreeType), because rasterising into a texture is inherently backend work.
    The canvas only does layout: it asks for glyph indices, metrics and kerning,
    and emits one textured quad per glyph. }
  IwgGlyphSource = interface
    ['{2D9A6F03-4E81-4C7B-A053-8F1D6B29E4C7}']
    function GetAscent: Single;        // pixels above the baseline, positive
    function GetDescent: Single;       // pixels below the baseline, positive
    function GetLineHeight: Single;    // baseline-to-baseline distance

    // Opaque per-face glyph id for a Unicode code point; 0 means "not present".
    function GetGlyphIndex(ACodePoint: LongWord): LongWord;
    // Rasterise if needed and describe the glyph. False if it cannot be had.
    function GetGlyph(AGlyphIndex: LongWord; out AGlyph: TwgGlyphInfo): Boolean;
    // Horizontal adjustment between an adjacent pair, 0 when unkerned.
    function GetKerning(ALeftIndex, ARightIndex: LongWord): Single;
  end;

  { TwgCanvasState — everything Save/Restore preserves. }
  TwgCanvasState = record
    Matrix: TwgMatrix;
    ClipRect: TRect;
    ClipEnabled: Boolean;
    BlendMode: TwgBlendMode;
    LineWidth: Single;
    LineCap: TwgLineCap;
    LineJoin: TwgLineJoin;
    MiterLimit: Single;
    Opacity: Single;
    Font: IwgGlyphSource;
  end;

  { TwgPath — a builder for bezier outlines.

    Curves are flattened to line segments on the fly using the current
    flatness tolerance, so by the time a path reaches the canvas it is just
    polygons. Coordinates are in USER space; the transform is applied when the
    path is filled or stroked, not when it is built. }
  TwgPath = class
  private
    FSubPaths: array of TwgPointFArray;
    FCurrent: TwgPointFArray;
    FCurrentCount: Integer;
    FClosed: array of Boolean;
    FStart: TwgPointF;
    FLast: TwgPointF;
    FHasCurrent: Boolean;
    FFlatness: Single;
    procedure AddPoint(const APoint: TwgPointF);
    procedure FinishSubPath(AClosed: Boolean);
    procedure FlattenQuad(const P0, P1, P2: TwgPointF; ADepth: Integer);
    procedure FlattenCubic(const P0, P1, P2, P3: TwgPointF; ADepth: Integer);
  public
    constructor Create;
    procedure Clear;

    procedure MoveTo(X, Y: Single);
    procedure LineTo(X, Y: Single);
    procedure QuadTo(ACX, ACY, X, Y: Single);
    procedure CurveTo(AC1X, AC1Y, AC2X, AC2Y, X, Y: Single);
    procedure ClosePath;
    // Append a whole polygon as one closed sub-path.
    procedure AddPolygon(const APoints: array of TwgPointF);

    function SubPathCount: Integer;
    function SubPath(AIndex: Integer): TwgPointFArray;
    function SubPathClosed(AIndex: Integer): Boolean;
    function IsEmpty: Boolean;

    // Maximum deviation, in user units, allowed when flattening curves.
    property Flatness: Single read FFlatness write FFlatness;
  end;

  { TwgCanvas }

  TwgCanvas = class(TwgSurfaceObject)
  private
    FWidth: Integer;
    FHeight: Integer;
    FState: TwgCanvasState;
    FStack: array of TwgCanvasState;
    FStackCount: Integer;
    FInFrame: Boolean;
    FCurveTolerance: Single;
    FScratch: TwgVertexArray;
    FScratchCount: Integer;

    procedure PushVertex(const AX, AY, AU, AV: Single; AColor: TwgColor);
    procedure ResetScratch;
    procedure FlushScratch(ATexture: IwgSurface);
    procedure EmitTriangleUV(const P0, P1, P2: TwgPointF;
      const AUV0, AUV1, AUV2: TwgPointF; AColor: TwgColor);
    procedure EmitTriangle(const P0, P1, P2: TwgPointF; AColor: TwgColor);
    // Fill a simple polygon (already in device space) by ear clipping.
    procedure EmitSimplePolygon(const APoints: TwgPointFArray; AColor: TwgColor);
    // Fill a CONVEX polygon (already in device space) as a triangle fan.
    procedure EmitConvexFan(const APoints: TwgPointFArray; AColor: TwgColor);
    procedure EmitStroke(const APoints: TwgPointFArray; AClosed: Boolean;
      AColor: TwgColor);
    procedure EmitRoundJoin(const ACenter: TwgPointF; ARadius: Single;
      AFrom, ATo: Single; AColor: TwgColor);
    procedure EmitJoin(const AAt, ADirIn, ADirOut: TwgPointF;
      AHalf: Single; AColor: TwgColor);
    procedure EmitCap(const AAt, ADir: TwgPointF; AHalf: Single;
      AColor: TwgColor);

    function  BuildEllipse(CX, CY, RX, RY, AStart, ASweep: Single;
      AIncludeCentre: Boolean): TwgPointFArray;
    function  BuildRoundRect(const R: TwgRectF; ARX, ARY: Single): TwgPointFArray;
    procedure CheckInFrame;
  protected
    { --- the device protocol a backend implements --- }

    // Bracket all drawing. Backends bind their framebuffer, set up the
    // projection for FWidth x FHeight, and (on End) resolve and flush.
    procedure DeviceBeginFrame; virtual; abstract;
    procedure DeviceEndFrame; virtual; abstract;
    // Fill the whole target, ignoring the clip. AColor is premultiplied.
    procedure DeviceClear(AColor: TwgColor); virtual; abstract;
    // Restrict drawing to ARect (device pixels). Disabled means "no clip".
    procedure DeviceSetClip(const ARect: TRect; AEnabled: Boolean); virtual; abstract;
    procedure DeviceSetBlend(AMode: TwgBlendMode); virtual; abstract;
    // Draw ACount/3 triangles. Vertices are device-space and premultiplied.
    // ATexture nil means flat shading; otherwise modulate by that surface.
    procedure DeviceDrawTriangles(const AVerts: TwgVertexArray;
      ACount: Integer; ATexture: IwgSurface); virtual; abstract;

    function GetSurfaceWidth: Integer; override;
    function GetSurfaceHeight: Integer; override;

    // Apply Opacity and convert straight alpha to premultiplied.
    function ResolveColor(AColor: TwgColor): TwgColor;
    // Map a user-space point through the current matrix into device space.
    function MapPoint(X, Y: Single): TwgPointF; inline;
    procedure SetSize(AWidth, AHeight: Integer);
    procedure ApplyClipToDevice;
  public
    constructor Create(AWidth, AHeight: Integer);
    destructor Destroy; override;

    { --- frame --- }
    procedure BeginFrame;
    procedure EndFrame;

    { --- state --- }
    procedure Save;
    procedure Restore;
    procedure ResetState;

    { --- transform --- }
    procedure Translate(DX, DY: Single);
    procedure Scale(SX, SY: Single);
    procedure Rotate(ARadians: Single);
    procedure Skew(AX, AY: Single);
    procedure SetMatrix(const AMatrix: TwgMatrix);
    procedure MultiplyMatrix(const AMatrix: TwgMatrix);
    procedure ResetMatrix;
    function  Matrix: TwgMatrix;

    { --- clipping ---

      The clip is an axis-aligned device rectangle. ClipRect intersects with the
      current clip (it never widens it). Under a rotated or skewed transform an
      axis-aligned rectangle cannot express the true region, so the transformed
      bounding box is used: the clip is then CONSERVATIVE — it may admit pixels
      a true rotated clip would have excluded, but never excludes ones it would
      have kept. }
    procedure ClipRect(X, Y, W, H: Single);
    procedure ResetClip;

    { --- fills --- }
    procedure Clear(AColor: TwgColor);
    procedure FillRect(X, Y, W, H: Single; AColor: TwgColor);
    procedure FillRoundRect(X, Y, W, H, RX, RY: Single; AColor: TwgColor);
    procedure FillEllipse(CX, CY, RX, RY: Single; AColor: TwgColor);
    procedure FillCircle(CX, CY, R: Single; AColor: TwgColor);
    // Pie slice: a wedge from AStartRadians through ASweepRadians, including
    // the centre. Angles run clockwise from the +X axis (Y is down).
    procedure FillPie(CX, CY, RX, RY, AStartRadians, ASweepRadians: Single;
      AColor: TwgColor);
    procedure FillPolygon(const APoints: array of TwgPointF; AColor: TwgColor);
    procedure FillPath(APath: TwgPath; AColor: TwgColor;
      AFillRule: TwgFillRule = cfrNonZero);
    // Four-corner gradient over a rectangle; the backend interpolates.
    procedure FillRectGradient(X, Y, W, H: Single;
      ATopLeft, ATopRight, ABottomRight, ABottomLeft: TwgColor);

    { --- strokes --- }
    procedure Line(X1, Y1, X2, Y2: Single; AColor: TwgColor);
    procedure Rectangle(X, Y, W, H: Single; AColor: TwgColor);
    procedure RoundRect(X, Y, W, H, RX, RY: Single; AColor: TwgColor);
    procedure Ellipse(CX, CY, RX, RY: Single; AColor: TwgColor);
    procedure Circle(CX, CY, R: Single; AColor: TwgColor);
    procedure Arc(CX, CY, RX, RY, AStartRadians, ASweepRadians: Single;
      AColor: TwgColor);
    procedure Polyline(const APoints: array of TwgPointF; AColor: TwgColor);
    procedure Polygon(const APoints: array of TwgPointF; AColor: TwgColor);
    procedure StrokePath(APath: TwgPath; AColor: TwgColor);

    { --- surfaces --- }
    // Blit ASurface with its top-left at (X, Y), at its natural size.
    procedure DrawSurface(ASurface: IwgSurface; X, Y: Single);
    // Blit scaled into the destination rectangle.
    procedure DrawSurface(ASurface: IwgSurface; X, Y, W, H: Single);
    // Blit the source sub-rectangle (in source pixels) into the destination
    // rectangle, scaling as needed. ATint modulates; use wgWhiteOpaque for none.
    procedure DrawSurface(ASurface: IwgSurface;
      const ASrcX, ASrcY, ASrcW, ASrcH: Single;
      const ADstX, ADstY, ADstW, ADstH: Single;
      ATint: TwgColor);

    { --- text ---

      Layout only: the glyphs come from the current Font (an IwgGlyphSource) and
      are emitted as textured quads. (X, Y) is the pen origin ON THE BASELINE,
      not the top-left of the text — use DrawTextTopLeft, or offset by
      Font.GetAscent, if you want the latter. }
    procedure DrawText(const AText: String; X, Y: Single; AColor: TwgColor);
    procedure DrawTextTopLeft(const AText: String; X, Y: Single; AColor: TwgColor);
    // Advance width of AText under the current Font, in user units.
    function  TextWidth(const AText: String): Single;
    function  TextHeight: Single;
    // Bounding box of AText drawn at the origin with the baseline at y = 0.
    function  TextExtent(const AText: String): TwgRectF;

    { --- properties --- }
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property InFrame: Boolean read FInFrame;

    property BlendMode: TwgBlendMode read FState.BlendMode write FState.BlendMode;
    property LineWidth: Single read FState.LineWidth write FState.LineWidth;
    property LineCap: TwgLineCap read FState.LineCap write FState.LineCap;
    property LineJoin: TwgLineJoin read FState.LineJoin write FState.LineJoin;
    property MiterLimit: Single read FState.MiterLimit write FState.MiterLimit;
    // Multiplies the alpha of everything drawn, 0..1.
    property Opacity: Single read FState.Opacity write FState.Opacity;
    property Font: IwgGlyphSource read FState.Font write FState.Font;
    // Maximum deviation, in device pixels, when flattening curves and arcs.
    property CurveTolerance: Single read FCurveTolerance write FCurveTolerance;
  end;

const
  // Fully opaque white — the identity tint for DrawSurface.
  wgWhiteOpaque = TwgColor($FFFFFFFF);

{ --- helpers --- }

function wgPointF(X, Y: Single): TwgPointF; inline;
function wgRectF(ALeft, ATop, ARight, ABottom: Single): TwgRectF; inline;

function wgMatrixIdentity: TwgMatrix;
function wgMatrixTranslation(DX, DY: Single): TwgMatrix;
function wgMatrixScaling(SX, SY: Single): TwgMatrix;
function wgMatrixRotation(ARadians: Single): TwgMatrix;
// AFirst applied, then ASecond.
function wgMatrixMultiply(const AFirst, ASecond: TwgMatrix): TwgMatrix;
function wgMatrixTransform(const AMatrix: TwgMatrix; X, Y: Single): TwgPointF; inline;

implementation

const
  // Below this the stroke degenerates; treat as a hairline.
  MinLineWidth = 0.05;
  // Cap on bezier subdivision, so a pathological control polygon terminates.
  MaxCurveDepth = 16;

function wgPointF(X, Y: Single): TwgPointF;
begin
  Result.X := X;
  Result.Y := Y;
end;

function wgRectF(ALeft, ATop, ARight, ABottom: Single): TwgRectF;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

function wgMatrixIdentity: TwgMatrix;
begin
  Result.A := 1; Result.B := 0;
  Result.C := 0; Result.D := 1;
  Result.E := 0; Result.F := 0;
end;

function wgMatrixTranslation(DX, DY: Single): TwgMatrix;
begin
  Result := wgMatrixIdentity;
  Result.E := DX;
  Result.F := DY;
end;

function wgMatrixScaling(SX, SY: Single): TwgMatrix;
begin
  Result := wgMatrixIdentity;
  Result.A := SX;
  Result.D := SY;
end;

function wgMatrixRotation(ARadians: Single): TwgMatrix;
var
  s, c: Double;
begin
  SinCos(ARadians, s, c);
  Result.A := c;  Result.B := s;
  Result.C := -s; Result.D := c;
  Result.E := 0;  Result.F := 0;
end;

function wgMatrixMultiply(const AFirst, ASecond: TwgMatrix): TwgMatrix;
begin
  // Result = ASecond * AFirst, so a point goes through AFirst first.
  Result.A := AFirst.A * ASecond.A + AFirst.B * ASecond.C;
  Result.B := AFirst.A * ASecond.B + AFirst.B * ASecond.D;
  Result.C := AFirst.C * ASecond.A + AFirst.D * ASecond.C;
  Result.D := AFirst.C * ASecond.B + AFirst.D * ASecond.D;
  Result.E := AFirst.E * ASecond.A + AFirst.F * ASecond.C + ASecond.E;
  Result.F := AFirst.E * ASecond.B + AFirst.F * ASecond.D + ASecond.F;
end;

function wgMatrixTransform(const AMatrix: TwgMatrix; X, Y: Single): TwgPointF;
begin
  Result.X := AMatrix.A * X + AMatrix.C * Y + AMatrix.E;
  Result.Y := AMatrix.B * X + AMatrix.D * Y + AMatrix.F;
end;

{ TwgPath }

constructor TwgPath.Create;
begin
  inherited Create;
  FFlatness := 0.25;
end;

procedure TwgPath.Clear;
begin
  SetLength(FSubPaths, 0);
  SetLength(FClosed, 0);
  SetLength(FCurrent, 0);
  FCurrentCount := 0;
  FHasCurrent := False;
end;

procedure TwgPath.AddPoint(const APoint: TwgPointF);
begin
  if FCurrentCount = Length(FCurrent) then
    SetLength(FCurrent, Max(8, Length(FCurrent) * 2));
  FCurrent[FCurrentCount] := APoint;
  Inc(FCurrentCount);
  FLast := APoint;
end;

procedure TwgPath.FinishSubPath(AClosed: Boolean);
var
  n: Integer;
begin
  if not FHasCurrent or (FCurrentCount < 2) then
  begin
    FCurrentCount := 0;
    FHasCurrent := False;
    Exit;
  end;
  n := Length(FSubPaths);
  SetLength(FSubPaths, n + 1);
  SetLength(FClosed, n + 1);
  SetLength(FSubPaths[n], FCurrentCount);
  Move(FCurrent[0], FSubPaths[n][0], FCurrentCount * SizeOf(TwgPointF));
  FClosed[n] := AClosed;
  FCurrentCount := 0;
  FHasCurrent := False;
end;

procedure TwgPath.MoveTo(X, Y: Single);
begin
  FinishSubPath(False);
  FStart := wgPointF(X, Y);
  FHasCurrent := True;
  AddPoint(FStart);
end;

procedure TwgPath.LineTo(X, Y: Single);
begin
  if not FHasCurrent then
    MoveTo(X, Y)
  else
    AddPoint(wgPointF(X, Y));
end;

procedure TwgPath.FlattenQuad(const P0, P1, P2: TwgPointF; ADepth: Integer);
var
  lMidX, lMidY, lDX, lDY, lDev: Single;
  a, b, c: TwgPointF;
begin
  // Deviation of the control point from the chord decides whether to split.
  lMidX := (P0.X + P2.X) * 0.5;
  lMidY := (P0.Y + P2.Y) * 0.5;
  lDX := P1.X - lMidX;
  lDY := P1.Y - lMidY;
  lDev := lDX * lDX + lDY * lDY;
  if (ADepth >= MaxCurveDepth) or (lDev <= FFlatness * FFlatness) then
  begin
    AddPoint(P2);
    Exit;
  end;
  // de Casteljau split at t = 0.5
  a := wgPointF((P0.X + P1.X) * 0.5, (P0.Y + P1.Y) * 0.5);
  b := wgPointF((P1.X + P2.X) * 0.5, (P1.Y + P2.Y) * 0.5);
  c := wgPointF((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5);
  FlattenQuad(P0, a, c, ADepth + 1);
  FlattenQuad(c, b, P2, ADepth + 1);
end;

procedure TwgPath.FlattenCubic(const P0, P1, P2, P3: TwgPointF; ADepth: Integer);
var
  lDX, lDY, lD1, lD2: Single;
  a, b, c, d, e, f: TwgPointF;
begin
  // Flat when both control points lie close to the chord.
  lDX := P3.X - P0.X;
  lDY := P3.Y - P0.Y;
  lD1 := Abs((P1.X - P3.X) * lDY - (P1.Y - P3.Y) * lDX);
  lD2 := Abs((P2.X - P3.X) * lDY - (P2.Y - P3.Y) * lDX);
  if (ADepth >= MaxCurveDepth) or
     (Sqr(lD1 + lD2) <= FFlatness * (lDX * lDX + lDY * lDY)) then
  begin
    AddPoint(P3);
    Exit;
  end;
  a := wgPointF((P0.X + P1.X) * 0.5, (P0.Y + P1.Y) * 0.5);
  b := wgPointF((P1.X + P2.X) * 0.5, (P1.Y + P2.Y) * 0.5);
  c := wgPointF((P2.X + P3.X) * 0.5, (P2.Y + P3.Y) * 0.5);
  d := wgPointF((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5);
  e := wgPointF((b.X + c.X) * 0.5, (b.Y + c.Y) * 0.5);
  f := wgPointF((d.X + e.X) * 0.5, (d.Y + e.Y) * 0.5);
  FlattenCubic(P0, a, d, f, ADepth + 1);
  FlattenCubic(f, e, c, P3, ADepth + 1);
end;

procedure TwgPath.QuadTo(ACX, ACY, X, Y: Single);
var
  lFrom: TwgPointF;
begin
  if not FHasCurrent then
    MoveTo(ACX, ACY);
  lFrom := FLast;
  FlattenQuad(lFrom, wgPointF(ACX, ACY), wgPointF(X, Y), 0);
end;

procedure TwgPath.CurveTo(AC1X, AC1Y, AC2X, AC2Y, X, Y: Single);
var
  lFrom: TwgPointF;
begin
  if not FHasCurrent then
    MoveTo(AC1X, AC1Y);
  lFrom := FLast;
  FlattenCubic(lFrom, wgPointF(AC1X, AC1Y), wgPointF(AC2X, AC2Y), wgPointF(X, Y), 0);
end;

procedure TwgPath.ClosePath;
begin
  FinishSubPath(True);
end;

procedure TwgPath.AddPolygon(const APoints: array of TwgPointF);
var
  i: Integer;
begin
  if Length(APoints) < 2 then
    Exit;
  MoveTo(APoints[0].X, APoints[0].Y);
  for i := 1 to High(APoints) do
    LineTo(APoints[i].X, APoints[i].Y);
  ClosePath;
end;

function TwgPath.SubPathCount: Integer;
begin
  // An unterminated sub-path still counts; callers see it via SubPath.
  Result := Length(FSubPaths);
  if FHasCurrent and (FCurrentCount >= 2) then
    Inc(Result);
end;

function TwgPath.SubPath(AIndex: Integer): TwgPointFArray;
begin
  if AIndex < Length(FSubPaths) then
    Exit(FSubPaths[AIndex]);
  // The still-open sub-path, materialised on demand.
  SetLength(Result, FCurrentCount);
  if FCurrentCount > 0 then
    Move(FCurrent[0], Result[0], FCurrentCount * SizeOf(TwgPointF));
end;

function TwgPath.SubPathClosed(AIndex: Integer): Boolean;
begin
  if AIndex < Length(FClosed) then
    Result := FClosed[AIndex]
  else
    Result := False;
end;

function TwgPath.IsEmpty: Boolean;
begin
  Result := SubPathCount = 0;
end;

{ TwgCanvas }

constructor TwgCanvas.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  FWidth := AWidth;
  FHeight := AHeight;
  FCurveTolerance := 0.25;
  SetLength(FScratch, 1024);
  ResetState;
end;

destructor TwgCanvas.Destroy;
begin
  SetLength(FScratch, 0);
  SetLength(FStack, 0);
  inherited Destroy;
end;

function TwgCanvas.GetSurfaceWidth: Integer;
begin
  Result := FWidth;
end;

function TwgCanvas.GetSurfaceHeight: Integer;
begin
  Result := FHeight;
end;

procedure TwgCanvas.SetSize(AWidth, AHeight: Integer);
begin
  if (AWidth = FWidth) and (AHeight = FHeight) then
    Exit;
  FWidth := AWidth;
  FHeight := AHeight;
  Changed;
end;

procedure TwgCanvas.CheckInFrame;
begin
  if not FInFrame then
    raise EwgCanvas.Create('drawing outside BeginFrame/EndFrame');
end;

procedure TwgCanvas.ResetState;
begin
  FState.Matrix := wgMatrixIdentity;
  FState.ClipRect := Rect(0, 0, FWidth, FHeight);
  FState.ClipEnabled := False;
  FState.BlendMode := cbmSourceOver;
  FState.LineWidth := 1.0;
  FState.LineCap := clcButt;
  FState.LineJoin := cljMiter;
  FState.MiterLimit := 10.0;
  FState.Opacity := 1.0;
  FState.Font := nil;
  FStackCount := 0;
end;

procedure TwgCanvas.BeginFrame;
begin
  if FInFrame then
    raise EwgCanvas.Create('BeginFrame called while already in a frame');
  ResetState;
  DeviceBeginFrame;
  FInFrame := True;
  DeviceSetBlend(FState.BlendMode);
  ApplyClipToDevice;
end;

procedure TwgCanvas.EndFrame;
begin
  CheckInFrame;
  FlushScratch(nil);
  DeviceEndFrame;
  FInFrame := False;
  Changed;
end;

procedure TwgCanvas.Save;
begin
  if FStackCount = Length(FStack) then
    SetLength(FStack, Max(8, Length(FStack) * 2));
  FStack[FStackCount] := FState;
  Inc(FStackCount);
end;

procedure TwgCanvas.Restore;
begin
  if FStackCount = 0 then
    raise EwgCanvas.Create('Restore without a matching Save');
  Dec(FStackCount);
  FState := FStack[FStackCount];
  if FInFrame then
  begin
    DeviceSetBlend(FState.BlendMode);
    ApplyClipToDevice;
  end;
end;

{ --- transform --- }

procedure TwgCanvas.Translate(DX, DY: Single);
begin
  FState.Matrix := wgMatrixMultiply(wgMatrixTranslation(DX, DY), FState.Matrix);
end;

procedure TwgCanvas.Scale(SX, SY: Single);
begin
  FState.Matrix := wgMatrixMultiply(wgMatrixScaling(SX, SY), FState.Matrix);
end;

procedure TwgCanvas.Rotate(ARadians: Single);
begin
  FState.Matrix := wgMatrixMultiply(wgMatrixRotation(ARadians), FState.Matrix);
end;

procedure TwgCanvas.Skew(AX, AY: Single);
var
  m: TwgMatrix;
begin
  m := wgMatrixIdentity;
  m.C := Tan(AX);
  m.B := Tan(AY);
  FState.Matrix := wgMatrixMultiply(m, FState.Matrix);
end;

procedure TwgCanvas.SetMatrix(const AMatrix: TwgMatrix);
begin
  FState.Matrix := AMatrix;
end;

procedure TwgCanvas.MultiplyMatrix(const AMatrix: TwgMatrix);
begin
  FState.Matrix := wgMatrixMultiply(AMatrix, FState.Matrix);
end;

procedure TwgCanvas.ResetMatrix;
begin
  FState.Matrix := wgMatrixIdentity;
end;

function TwgCanvas.Matrix: TwgMatrix;
begin
  Result := FState.Matrix;
end;

function TwgCanvas.MapPoint(X, Y: Single): TwgPointF;
begin
  Result := wgMatrixTransform(FState.Matrix, X, Y);
end;

{ --- clipping --- }

procedure TwgCanvas.ApplyClipToDevice;
begin
  if FInFrame then
    DeviceSetClip(FState.ClipRect, FState.ClipEnabled);
end;

procedure TwgCanvas.ClipRect(X, Y, W, H: Single);
var
  p: array[0..3] of TwgPointF;
  i: Integer;
  lMinX, lMinY, lMaxX, lMaxY: Single;
  lNew: TRect;
begin
  // Transform all four corners and take the bounding box, so rotation degrades
  // to a conservative (never-too-tight) axis-aligned clip.
  p[0] := MapPoint(X, Y);
  p[1] := MapPoint(X + W, Y);
  p[2] := MapPoint(X + W, Y + H);
  p[3] := MapPoint(X, Y + H);
  lMinX := p[0].X; lMaxX := p[0].X;
  lMinY := p[0].Y; lMaxY := p[0].Y;
  for i := 1 to 3 do
  begin
    lMinX := Min(lMinX, p[i].X);
    lMaxX := Max(lMaxX, p[i].X);
    lMinY := Min(lMinY, p[i].Y);
    lMaxY := Max(lMaxY, p[i].Y);
  end;
  lNew := Rect(Floor(lMinX), Floor(lMinY), Ceil(lMaxX), Ceil(lMaxY));

  FlushScratch(nil);
  if FState.ClipEnabled then
  begin
    // Intersect: a clip only ever narrows.
    lNew.Left := Max(lNew.Left, FState.ClipRect.Left);
    lNew.Top := Max(lNew.Top, FState.ClipRect.Top);
    lNew.Right := Min(lNew.Right, FState.ClipRect.Right);
    lNew.Bottom := Min(lNew.Bottom, FState.ClipRect.Bottom);
  end;
  if lNew.Right < lNew.Left then lNew.Right := lNew.Left;
  if lNew.Bottom < lNew.Top then lNew.Bottom := lNew.Top;
  FState.ClipRect := lNew;
  FState.ClipEnabled := True;
  ApplyClipToDevice;
end;

procedure TwgCanvas.ResetClip;
begin
  FlushScratch(nil);
  FState.ClipRect := Rect(0, 0, FWidth, FHeight);
  FState.ClipEnabled := False;
  ApplyClipToDevice;
end;

{ --- vertex emission --- }

function TwgCanvas.ResolveColor(AColor: TwgColor): TwgColor;
var
  a: Integer;
begin
  a := wgAlphaOf(AColor);
  if FState.Opacity < 1.0 then
  begin
    if FState.Opacity <= 0 then
      Exit(0);
    a := Round(a * FState.Opacity);
    if a > 255 then a := 255;
  end;
  Result := wgPremultiply((AColor and $00FFFFFF) or (TwgColor(Byte(a)) shl 24));
end;

procedure TwgCanvas.ResetScratch;
begin
  FScratchCount := 0;
end;

procedure TwgCanvas.PushVertex(const AX, AY, AU, AV: Single;
  AColor: TwgColor);
begin
  if FScratchCount = Length(FScratch) then
    SetLength(FScratch, Length(FScratch) * 2);
  with FScratch[FScratchCount] do
  begin
    X := AX;
    Y := AY;
    U := AU;
    V := AV;
    Color := AColor;
  end;
  Inc(FScratchCount);
end;

procedure TwgCanvas.FlushScratch(ATexture: IwgSurface);
begin
  if FScratchCount = 0 then
    Exit;
  DeviceDrawTriangles(FScratch, FScratchCount, ATexture);
  FScratchCount := 0;
end;

procedure TwgCanvas.EmitTriangleUV(const P0, P1, P2: TwgPointF;
  const AUV0, AUV1, AUV2: TwgPointF; AColor: TwgColor);
begin
  PushVertex(P0.X, P0.Y, AUV0.X, AUV0.Y, AColor);
  PushVertex(P1.X, P1.Y, AUV1.X, AUV1.Y, AColor);
  PushVertex(P2.X, P2.Y, AUV2.X, AUV2.Y, AColor);
end;

procedure TwgCanvas.EmitTriangle(const P0, P1, P2: TwgPointF;
  AColor: TwgColor);
begin
  PushVertex(P0.X, P0.Y, 0, 0, AColor);
  PushVertex(P1.X, P1.Y, 0, 0, AColor);
  PushVertex(P2.X, P2.Y, 0, 0, AColor);
end;

procedure TwgCanvas.EmitConvexFan(const APoints: TwgPointFArray;
  AColor: TwgColor);
var
  i: Integer;
begin
  for i := 1 to High(APoints) - 1 do
    EmitTriangle(APoints[0], APoints[i], APoints[i + 1], AColor);
end;

procedure TwgCanvas.EmitSimplePolygon(const APoints: TwgPointFArray;
  AColor: TwgColor);
var
  lIdx: array of Integer;
  lCount, i, lPrev, lCur, lNext, lGuard: Integer;
  lArea: Double;

  function Cross(const A, B, C: TwgPointF): Double; inline;
  begin
    Result := (B.X - A.X) * (C.Y - A.Y) - (B.Y - A.Y) * (C.X - A.X);
  end;

  function InTriangle(const P, A, B, C: TwgPointF): Boolean;
  var
    d1, d2, d3: Double;
    lNeg, lPos: Boolean;
  begin
    d1 := Cross(A, B, P);
    d2 := Cross(B, C, P);
    d3 := Cross(C, A, P);
    lNeg := (d1 < 0) or (d2 < 0) or (d3 < 0);
    lPos := (d1 > 0) or (d2 > 0) or (d3 > 0);
    Result := not (lNeg and lPos);
  end;

  function IsEar(AAt: Integer): Boolean;
  var
    j: Integer;
    a, b, c: TwgPointF;
  begin
    a := APoints[lIdx[(AAt + lCount - 1) mod lCount]];
    b := APoints[lIdx[AAt]];
    c := APoints[lIdx[(AAt + 1) mod lCount]];
    // Reflex vertices are never ears (the polygon has been made CCW).
    if Cross(a, b, c) <= 0 then
      Exit(False);
    for j := 0 to lCount - 1 do
    begin
      if (j = AAt) or (j = (AAt + lCount - 1) mod lCount) or
         (j = (AAt + 1) mod lCount) then
        Continue;
      if InTriangle(APoints[lIdx[j]], a, b, c) then
        Exit(False);
    end;
    Result := True;
  end;

begin
  lCount := Length(APoints);
  if lCount < 3 then
    Exit;
  if lCount = 3 then
  begin
    EmitTriangle(APoints[0], APoints[1], APoints[2], AColor);
    Exit;
  end;

  // Signed area decides the winding; ear clipping below assumes CCW.
  lArea := 0;
  for i := 0 to lCount - 1 do
    lArea := lArea + (APoints[i].X * APoints[(i + 1) mod lCount].Y
                    - APoints[(i + 1) mod lCount].X * APoints[i].Y);

  SetLength(lIdx, lCount);
  if lArea >= 0 then
    for i := 0 to lCount - 1 do
      lIdx[i] := i
  else
    for i := 0 to lCount - 1 do
      lIdx[i] := lCount - 1 - i;

  lCur := 0;
  // Each successful clip removes a vertex; the guard bounds the search for the
  // next ear so a degenerate or self-intersecting polygon cannot spin forever.
  lGuard := 0;
  while (lCount > 3) and (lGuard < lCount * 2) do
  begin
    if IsEar(lCur) then
    begin
      lPrev := (lCur + lCount - 1) mod lCount;
      lNext := (lCur + 1) mod lCount;
      EmitTriangle(APoints[lIdx[lPrev]], APoints[lIdx[lCur]],
                   APoints[lIdx[lNext]], AColor);
      for i := lCur to lCount - 2 do
        lIdx[i] := lIdx[i + 1];
      Dec(lCount);
      if lCur >= lCount then
        lCur := 0;
      lGuard := 0;
    end
    else
    begin
      lCur := (lCur + 1) mod lCount;
      Inc(lGuard);
    end;
  end;
  // Whatever is left is either the final triangle or, if no ear could be found,
  // a degenerate remnant; fan it so nothing silently disappears.
  for i := 1 to lCount - 2 do
    EmitTriangle(APoints[lIdx[0]], APoints[lIdx[i]], APoints[lIdx[i + 1]], AColor);
end;

procedure TwgCanvas.EmitRoundJoin(const ACenter: TwgPointF;
  ARadius: Single; AFrom, ATo: Single; AColor: TwgColor);
var
  lSteps, i: Integer;
  lSweep, lAngle, lNext: Single;
  s, c: Double;
  p0, p1: TwgPointF;
begin
  lSweep := ATo - AFrom;
  // Take the short way round.
  while lSweep > Pi do lSweep := lSweep - 2 * Pi;
  while lSweep < -Pi do lSweep := lSweep + 2 * Pi;
  if IsZero(lSweep) or (ARadius <= 0) then
    Exit;
  lSteps := Max(2, Ceil(Abs(lSweep) / ArcCos(Max(0.0,
    1.0 - FCurveTolerance / Max(ARadius, FCurveTolerance)))));
  for i := 0 to lSteps - 1 do
  begin
    lAngle := AFrom + lSweep * (i / lSteps);
    lNext := AFrom + lSweep * ((i + 1) / lSteps);
    SinCos(lAngle, s, c);
    p0 := wgPointF(ACenter.X + ARadius * c, ACenter.Y + ARadius * s);
    SinCos(lNext, s, c);
    p1 := wgPointF(ACenter.X + ARadius * c, ACenter.Y + ARadius * s);
    EmitTriangle(ACenter, p0, p1, AColor);
  end;
end;

// Unit vector from A towards B; zero if they coincide.
function UnitDir(const A, B: TwgPointF): TwgPointF;
var
  lLen: Single;
begin
  Result.X := B.X - A.X;
  Result.Y := B.Y - A.Y;
  lLen := Sqrt(Result.X * Result.X + Result.Y * Result.Y);
  if lLen < 1e-6 then
  begin
    Result.X := 0;
    Result.Y := 0;
    Exit;
  end;
  Result.X := Result.X / lLen;
  Result.Y := Result.Y / lLen;
end;

{ Fill the wedge two consecutive segments leave open at their shared vertex.

  ADirIn/ADirOut are UNIT direction vectors of the incoming and outgoing
  segments. Only the OUTER side of the turn has a gap — the inner side is
  already covered twice by the two segment quads — so the sign of the cross
  product picks which side to work on. }
procedure TwgCanvas.EmitJoin(const AAt, ADirIn, ADirOut: TwgPointF;
  AHalf: Single; AColor: TwgColor);
var
  lCross, lDenom, lT, lSide: Single;
  lNIn, lNOut, a, b, m: TwgPointF;
  lMiterLen: Single;
begin
  lCross := ADirIn.X * ADirOut.Y - ADirIn.Y * ADirOut.X;
  // Collinear (or a full reversal): no wedge to fill.
  if Abs(lCross) < 1e-6 then
    Exit;
  if lCross > 0 then
    lSide := 1
  else
    lSide := -1;

  // Left-hand normals, scaled to the half width. The outer offset points are on
  // the side opposite the turn.
  lNIn := wgPointF(-ADirIn.Y * AHalf, ADirIn.X * AHalf);
  lNOut := wgPointF(-ADirOut.Y * AHalf, ADirOut.X * AHalf);
  a := wgPointF(AAt.X - lSide * lNIn.X, AAt.Y - lSide * lNIn.Y);
  b := wgPointF(AAt.X - lSide * lNOut.X, AAt.Y - lSide * lNOut.Y);

  case FState.LineJoin of
    cljRound:
      EmitRoundJoin(AAt, AHalf,
        ArcTan2(a.Y - AAt.Y, a.X - AAt.X),
        ArcTan2(b.Y - AAt.Y, b.X - AAt.X), AColor);

    cljMiter:
      begin
        // Where the two outer edges would meet if extended.
        lDenom := lCross;
        lT := ((b.X - a.X) * ADirOut.Y - (b.Y - a.Y) * ADirOut.X) / lDenom;
        m := wgPointF(a.X + ADirIn.X * lT, a.Y + ADirIn.Y * lT);
        lMiterLen := Sqrt(Sqr(m.X - AAt.X) + Sqr(m.Y - AAt.Y));
        // A near-reversal sends the spike to infinity; the miter limit is what
        // caps it, falling back to a bevel exactly as PostScript/SVG specify.
        if lMiterLen <= FState.MiterLimit * AHalf then
        begin
          EmitTriangle(AAt, a, m, AColor);
          EmitTriangle(AAt, m, b, AColor);
        end
        else
          EmitTriangle(AAt, a, b, AColor);
      end;

    else // cljBevel: just close the gap with the shortest edge.
      EmitTriangle(AAt, a, b, AColor);
  end;
end;

{ Round off an open end. Butt caps need nothing, and square caps are handled by
  extending the segment itself, so only the round case does work here. }
procedure TwgCanvas.EmitCap(const AAt, ADir: TwgPointF;
  AHalf: Single; AColor: TwgColor);
var
  lBase: Single;
begin
  if FState.LineCap <> clcRound then
    Exit;
  // Semicircle centred on the endpoint, spanning the two edge normals and
  // bulging along ADir (which points OUT of the line at this end).
  lBase := ArcTan2(-ADir.X, ADir.Y);   // angle of the left-hand normal
  EmitRoundJoin(AAt, AHalf, lBase, lBase + Pi, AColor);
end;

procedure TwgCanvas.EmitStroke(const APoints: TwgPointFArray;
  AClosed: Boolean; AColor: TwgColor);
var
  i, n, lLast: Integer;
  lHalf, lLen, lDX, lDY, lNX, lNY: Single;
  a, b: TwgPointF;
  lPts: TwgPointFArray;
  lPoly: TwgPointFArray;

  // Scale the pen by the transform so a 1px line stays 1px under zoom. The
  // geometric mean of the axis scales is the standard isotropic approximation.
  function DeviceHalfWidth: Single;
  var
    lSX, lSY: Single;
  begin
    lSX := Sqrt(Sqr(FState.Matrix.A) + Sqr(FState.Matrix.B));
    lSY := Sqrt(Sqr(FState.Matrix.C) + Sqr(FState.Matrix.D));
    Result := Max(FState.LineWidth, MinLineWidth) * Sqrt(Max(lSX * lSY, 1e-6)) * 0.5;
  end;

begin
  n := Length(APoints);
  if n < 2 then
  begin
    // A closed single point with a round cap is still a visible dot.
    if (n = 1) and (FState.LineCap = clcRound) then
    begin
      lHalf := DeviceHalfWidth;
      EmitRoundJoin(APoints[0], lHalf, 0, Pi, AColor);
      EmitRoundJoin(APoints[0], lHalf, Pi, 2 * Pi, AColor);
    end;
    Exit;
  end;

  lHalf := DeviceHalfWidth;

  // Drop consecutive duplicates; zero-length segments have no normal.
  SetLength(lPts, n);
  lLast := 0;
  lPts[0] := APoints[0];
  for i := 1 to n - 1 do
    if (Abs(APoints[i].X - lPts[lLast].X) > 1e-6) or
       (Abs(APoints[i].Y - lPts[lLast].Y) > 1e-6) then
    begin
      Inc(lLast);
      lPts[lLast] := APoints[i];
    end;
  n := lLast + 1;
  SetLength(lPts, n);
  if n < 2 then
    Exit;

  SetLength(lPoly, 4);
  for i := 0 to n - 2 do
  begin
    a := lPts[i];
    b := lPts[i + 1];
    lDX := b.X - a.X;
    lDY := b.Y - a.Y;
    lLen := Sqrt(lDX * lDX + lDY * lDY);
    if lLen < 1e-6 then
      Continue;
    lNX := -lDY / lLen * lHalf;   // left-hand normal, scaled to half width
    lNY := lDX / lLen * lHalf;

    // Square caps extend the segment by half a width at the open ends.
    if (FState.LineCap = clcSquare) and not AClosed then
    begin
      if i = 0 then
      begin
        a.X := a.X - lDX / lLen * lHalf;
        a.Y := a.Y - lDY / lLen * lHalf;
      end;
      if i = n - 2 then
      begin
        b.X := b.X + lDX / lLen * lHalf;
        b.Y := b.Y + lDY / lLen * lHalf;
      end;
    end;

    lPoly[0] := wgPointF(a.X + lNX, a.Y + lNY);
    lPoly[1] := wgPointF(b.X + lNX, b.Y + lNY);
    lPoly[2] := wgPointF(b.X - lNX, b.Y - lNY);
    lPoly[3] := wgPointF(a.X - lNX, a.Y - lNY);
    EmitTriangle(lPoly[0], lPoly[1], lPoly[2], AColor);
    EmitTriangle(lPoly[0], lPoly[2], lPoly[3], AColor);
  end;

  if AClosed and (n > 2) then
  begin
    // The closing segment back to the first point.
    a := lPts[n - 1];
    b := lPts[0];
    lDX := b.X - a.X;
    lDY := b.Y - a.Y;
    lLen := Sqrt(lDX * lDX + lDY * lDY);
    if lLen >= 1e-6 then
    begin
      lNX := -lDY / lLen * lHalf;
      lNY := lDX / lLen * lHalf;
      EmitTriangle(wgPointF(a.X + lNX, a.Y + lNY), wgPointF(b.X + lNX, b.Y + lNY),
                   wgPointF(b.X - lNX, b.Y - lNY), AColor);
      EmitTriangle(wgPointF(a.X + lNX, a.Y + lNY), wgPointF(b.X - lNX, b.Y - lNY),
                   wgPointF(a.X - lNX, a.Y - lNY), AColor);
    end;
  end;

  // Joins at every interior vertex, plus the two seam vertices when closed.
  for i := 1 to n - 2 do
    EmitJoin(lPts[i], UnitDir(lPts[i - 1], lPts[i]), UnitDir(lPts[i], lPts[i + 1]),
      lHalf, AColor);

  if AClosed and (n > 2) then
  begin
    // Where the closing segment meets the first, and where the last meets it.
    EmitJoin(lPts[0], UnitDir(lPts[n - 1], lPts[0]), UnitDir(lPts[0], lPts[1]),
      lHalf, AColor);
    EmitJoin(lPts[n - 1], UnitDir(lPts[n - 2], lPts[n - 1]),
      UnitDir(lPts[n - 1], lPts[0]), lHalf, AColor);
  end
  else
  begin
    // Open ends: the outward direction at each is away from its neighbour.
    EmitCap(lPts[0], UnitDir(lPts[1], lPts[0]), lHalf, AColor);
    EmitCap(lPts[n - 1], UnitDir(lPts[n - 2], lPts[n - 1]), lHalf, AColor);
  end;
end;

{ --- geometry builders (results are in DEVICE space) --- }

function TwgCanvas.BuildEllipse(CX, CY, RX, RY, AStart, ASweep: Single;
  AIncludeCentre: Boolean): TwgPointFArray;
var
  lSteps, i, lBase: Integer;
  lRadius, lAngle: Single;
  s, c: Double;
begin
  Result := nil; // SetLength below initialises it; this quiets the flow warning
  // Segment count from the tolerance, using the larger radius scaled into
  // device space so a zoomed circle stays smooth.
  lRadius := Max(Abs(RX), Abs(RY)) *
    Max(Sqrt(Sqr(FState.Matrix.A) + Sqr(FState.Matrix.B)),
        Sqrt(Sqr(FState.Matrix.C) + Sqr(FState.Matrix.D)));
  if lRadius <= FCurveTolerance then
    lSteps := 4
  else
    lSteps := Max(4, Ceil(Abs(ASweep) /
      (2 * ArcCos(1.0 - Min(0.999, FCurveTolerance / lRadius)))));
  lSteps := Min(lSteps, 4096);

  if AIncludeCentre then
  begin
    SetLength(Result, lSteps + 2);
    Result[0] := MapPoint(CX, CY);
    lBase := 1;
  end
  else
  begin
    SetLength(Result, lSteps + 1);
    lBase := 0;
  end;
  for i := 0 to lSteps do
  begin
    lAngle := AStart + ASweep * (i / lSteps);
    SinCos(lAngle, s, c);
    Result[lBase + i] := MapPoint(CX + RX * c, CY + RY * s);
  end;
end;

function TwgCanvas.BuildRoundRect(const R: TwgRectF;
  ARX, ARY: Single): TwgPointFArray;
var
  lW, lH: Single;
  lCorner: array[0..3] of TwgPointFArray;
  i, j, n, k: Integer;
begin
  Result := nil; // as BuildEllipse
  lW := R.Right - R.Left;
  lH := R.Bottom - R.Top;
  ARX := Min(Abs(ARX), Abs(lW) / 2);
  ARY := Min(Abs(ARY), Abs(lH) / 2);
  if (ARX <= 0) or (ARY <= 0) then
  begin
    SetLength(Result, 4);
    Result[0] := MapPoint(R.Left, R.Top);
    Result[1] := MapPoint(R.Right, R.Top);
    Result[2] := MapPoint(R.Right, R.Bottom);
    Result[3] := MapPoint(R.Left, R.Bottom);
    Exit;
  end;
  // Four quarter-arcs, walked clockwise from the top-left corner. Y is down, so
  // the sweep from Pi to 3Pi/2 is the top-left quadrant.
  lCorner[0] := BuildEllipse(R.Left + ARX, R.Top + ARY, ARX, ARY, Pi, Pi / 2, False);
  lCorner[1] := BuildEllipse(R.Right - ARX, R.Top + ARY, ARX, ARY, -Pi / 2, Pi / 2, False);
  lCorner[2] := BuildEllipse(R.Right - ARX, R.Bottom - ARY, ARX, ARY, 0, Pi / 2, False);
  lCorner[3] := BuildEllipse(R.Left + ARX, R.Bottom - ARY, ARX, ARY, Pi / 2, Pi / 2, False);
  n := 0;
  for i := 0 to 3 do
    Inc(n, Length(lCorner[i]));
  SetLength(Result, n);
  k := 0;
  for i := 0 to 3 do
    for j := 0 to High(lCorner[i]) do
    begin
      Result[k] := lCorner[i][j];
      Inc(k);
    end;
end;

{ --- fills --- }

procedure TwgCanvas.Clear(AColor: TwgColor);
begin
  CheckInFrame;
  FlushScratch(nil);
  DeviceClear(ResolveColor(AColor));
end;

procedure TwgCanvas.FillRect(X, Y, W, H: Single; AColor: TwgColor);
var
  p0, p1, p2, p3: TwgPointF;
  lColor: TwgColor;
begin
  CheckInFrame;
  if (W = 0) or (H = 0) then
    Exit;
  lColor := ResolveColor(AColor);
  p0 := MapPoint(X, Y);
  p1 := MapPoint(X + W, Y);
  p2 := MapPoint(X + W, Y + H);
  p3 := MapPoint(X, Y + H);
  EmitTriangle(p0, p1, p2, lColor);
  EmitTriangle(p0, p2, p3, lColor);
  FlushScratch(nil);
end;

procedure TwgCanvas.FillRectGradient(X, Y, W, H: Single;
  ATopLeft, ATopRight, ABottomRight, ABottomLeft: TwgColor);
var
  p0, p1, p2, p3: TwgPointF;
  c0, c1, c2, c3: TwgColor;
begin
  CheckInFrame;
  if (W = 0) or (H = 0) then
    Exit;
  p0 := MapPoint(X, Y);
  p1 := MapPoint(X + W, Y);
  p2 := MapPoint(X + W, Y + H);
  p3 := MapPoint(X, Y + H);
  c0 := ResolveColor(ATopLeft);
  c1 := ResolveColor(ATopRight);
  c2 := ResolveColor(ABottomRight);
  c3 := ResolveColor(ABottomLeft);
  // Per-vertex colours; the backend interpolates across each triangle.
  PushVertex(p0.X, p0.Y, 0, 0, c0);
  PushVertex(p1.X, p1.Y, 0, 0, c1);
  PushVertex(p2.X, p2.Y, 0, 0, c2);
  PushVertex(p0.X, p0.Y, 0, 0, c0);
  PushVertex(p2.X, p2.Y, 0, 0, c2);
  PushVertex(p3.X, p3.Y, 0, 0, c3);
  FlushScratch(nil);
end;

procedure TwgCanvas.FillRoundRect(X, Y, W, H, RX, RY: Single;
  AColor: TwgColor);
var
  lPoly: TwgPointFArray;
begin
  CheckInFrame;
  if (W <= 0) or (H <= 0) then
    Exit;
  lPoly := BuildRoundRect(wgRectF(X, Y, X + W, Y + H), RX, RY);
  // A rounded rectangle is convex, so a fan is exact and cheaper than clipping.
  EmitConvexFan(lPoly, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.FillEllipse(CX, CY, RX, RY: Single; AColor: TwgColor);
var
  lPoly: TwgPointFArray;
begin
  CheckInFrame;
  if (RX <= 0) or (RY <= 0) then
    Exit;
  lPoly := BuildEllipse(CX, CY, RX, RY, 0, 2 * Pi, False);
  EmitConvexFan(lPoly, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.FillCircle(CX, CY, R: Single; AColor: TwgColor);
begin
  FillEllipse(CX, CY, R, R, AColor);
end;

procedure TwgCanvas.FillPie(CX, CY, RX, RY, AStartRadians,
  ASweepRadians: Single; AColor: TwgColor);
var
  lPoly: TwgPointFArray;
begin
  CheckInFrame;
  if (RX <= 0) or (RY <= 0) or IsZero(ASweepRadians) then
    Exit;
  lPoly := BuildEllipse(CX, CY, RX, RY, AStartRadians, ASweepRadians, True);
  // With the centre first, the fan is exactly the wedge — but only while the
  // sweep stays under a half turn, beyond which the wedge is not star-shaped
  // about a fan pivot on its rim. The centre pivot keeps it valid to a full turn.
  EmitConvexFan(lPoly, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.FillPolygon(const APoints: array of TwgPointF;
  AColor: TwgColor);
var
  lPoly: TwgPointFArray;
  i: Integer;
begin
  CheckInFrame;
  if Length(APoints) < 3 then
    Exit;
  SetLength(lPoly, Length(APoints));
  for i := 0 to High(APoints) do
    lPoly[i] := MapPoint(APoints[i].X, APoints[i].Y);
  EmitSimplePolygon(lPoly, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.FillPath(APath: TwgPath; AColor: TwgColor;
  AFillRule: TwgFillRule);
var
  i, j: Integer;
  lSub, lPoly: TwgPointFArray;
  lColor: TwgColor;
begin
  CheckInFrame;
  if (APath = nil) or APath.IsEmpty then
    Exit;
  lColor := ResolveColor(AColor);
  // Each sub-path is filled independently. That is exactly the even-odd result
  // for disjoint contours and the non-zero result for non-overlapping ones;
  // overlapping contours differ, and true multi-contour hole handling would
  // need a full trapezoidal tessellator, which this does not attempt.
  for i := 0 to APath.SubPathCount - 1 do
  begin
    lSub := APath.SubPath(i);
    if Length(lSub) < 3 then
      Continue;
    SetLength(lPoly, Length(lSub));
    for j := 0 to High(lSub) do
      lPoly[j] := MapPoint(lSub[j].X, lSub[j].Y);
    EmitSimplePolygon(lPoly, lColor);
  end;
  FlushScratch(nil);
end;

{ --- strokes --- }

procedure TwgCanvas.Line(X1, Y1, X2, Y2: Single; AColor: TwgColor);
var
  lPts: TwgPointFArray;
begin
  CheckInFrame;
  SetLength(lPts, 2);
  lPts[0] := MapPoint(X1, Y1);
  lPts[1] := MapPoint(X2, Y2);
  EmitStroke(lPts, False, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.Rectangle(X, Y, W, H: Single; AColor: TwgColor);
var
  lPts: TwgPointFArray;
begin
  CheckInFrame;
  if (W = 0) or (H = 0) then
    Exit;
  SetLength(lPts, 4);
  lPts[0] := MapPoint(X, Y);
  lPts[1] := MapPoint(X + W, Y);
  lPts[2] := MapPoint(X + W, Y + H);
  lPts[3] := MapPoint(X, Y + H);
  EmitStroke(lPts, True, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.RoundRect(X, Y, W, H, RX, RY: Single;
  AColor: TwgColor);
var
  lPoly: TwgPointFArray;
begin
  CheckInFrame;
  if (W <= 0) or (H <= 0) then
    Exit;
  lPoly := BuildRoundRect(wgRectF(X, Y, X + W, Y + H), RX, RY);
  EmitStroke(lPoly, True, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.Ellipse(CX, CY, RX, RY: Single; AColor: TwgColor);
var
  lPoly: TwgPointFArray;
begin
  CheckInFrame;
  if (RX <= 0) or (RY <= 0) then
    Exit;
  lPoly := BuildEllipse(CX, CY, RX, RY, 0, 2 * Pi, False);
  EmitStroke(lPoly, True, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.Circle(CX, CY, R: Single; AColor: TwgColor);
begin
  Ellipse(CX, CY, R, R, AColor);
end;

procedure TwgCanvas.Arc(CX, CY, RX, RY, AStartRadians,
  ASweepRadians: Single; AColor: TwgColor);
var
  lPoly: TwgPointFArray;
begin
  CheckInFrame;
  if (RX <= 0) or (RY <= 0) or IsZero(ASweepRadians) then
    Exit;
  lPoly := BuildEllipse(CX, CY, RX, RY, AStartRadians, ASweepRadians, False);
  EmitStroke(lPoly, False, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.Polyline(const APoints: array of TwgPointF;
  AColor: TwgColor);
var
  lPts: TwgPointFArray;
  i: Integer;
begin
  CheckInFrame;
  if Length(APoints) < 2 then
    Exit;
  SetLength(lPts, Length(APoints));
  for i := 0 to High(APoints) do
    lPts[i] := MapPoint(APoints[i].X, APoints[i].Y);
  EmitStroke(lPts, False, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.Polygon(const APoints: array of TwgPointF;
  AColor: TwgColor);
var
  lPts: TwgPointFArray;
  i: Integer;
begin
  CheckInFrame;
  if Length(APoints) < 2 then
    Exit;
  SetLength(lPts, Length(APoints));
  for i := 0 to High(APoints) do
    lPts[i] := MapPoint(APoints[i].X, APoints[i].Y);
  EmitStroke(lPts, True, ResolveColor(AColor));
  FlushScratch(nil);
end;

procedure TwgCanvas.StrokePath(APath: TwgPath; AColor: TwgColor);
var
  i, j: Integer;
  lSub, lPts: TwgPointFArray;
  lColor: TwgColor;
begin
  CheckInFrame;
  if (APath = nil) or APath.IsEmpty then
    Exit;
  lColor := ResolveColor(AColor);
  for i := 0 to APath.SubPathCount - 1 do
  begin
    lSub := APath.SubPath(i);
    if Length(lSub) < 2 then
      Continue;
    SetLength(lPts, Length(lSub));
    for j := 0 to High(lSub) do
      lPts[j] := MapPoint(lSub[j].X, lSub[j].Y);
    EmitStroke(lPts, APath.SubPathClosed(i), lColor);
  end;
  FlushScratch(nil);
end;

{ --- surfaces --- }

procedure TwgCanvas.DrawSurface(ASurface: IwgSurface; X, Y: Single);
begin
  if ASurface = nil then
    Exit;
  DrawSurface(ASurface, 0, 0, ASurface.Width, ASurface.Height,
    X, Y, ASurface.Width, ASurface.Height, wgWhiteOpaque);
end;

procedure TwgCanvas.DrawSurface(ASurface: IwgSurface; X, Y, W, H: Single);
begin
  if ASurface = nil then
    Exit;
  DrawSurface(ASurface, 0, 0, ASurface.Width, ASurface.Height,
    X, Y, W, H, wgWhiteOpaque);
end;

procedure TwgCanvas.DrawSurface(ASurface: IwgSurface;
  const ASrcX, ASrcY, ASrcW, ASrcH: Single;
  const ADstX, ADstY, ADstW, ADstH: Single; ATint: TwgColor);
var
  p0, p1, p2, p3: TwgPointF;
  u0, v0, u1, v1: Single;
  lColor: TwgColor;
begin
  CheckInFrame;
  if (ASurface = nil) or (ADstW = 0) or (ADstH = 0) then
    Exit;
  if (ASurface.Width <= 0) or (ASurface.Height <= 0) then
    Exit;

  // UVs are normalised over the SURFACE, not the backing texture; the backend
  // remaps into an atlas sub-rect if there is one.
  u0 := ASrcX / ASurface.Width;
  v0 := ASrcY / ASurface.Height;
  u1 := (ASrcX + ASrcW) / ASurface.Width;
  v1 := (ASrcY + ASrcH) / ASurface.Height;

  lColor := ResolveColor(ATint);
  p0 := MapPoint(ADstX, ADstY);
  p1 := MapPoint(ADstX + ADstW, ADstY);
  p2 := MapPoint(ADstX + ADstW, ADstY + ADstH);
  p3 := MapPoint(ADstX, ADstY + ADstH);

  // A pending flat batch must not be drawn with this texture bound.
  FlushScratch(nil);
  PushVertex(p0.X, p0.Y, u0, v0, lColor);
  PushVertex(p1.X, p1.Y, u1, v0, lColor);
  PushVertex(p2.X, p2.Y, u1, v1, lColor);
  PushVertex(p0.X, p0.Y, u0, v0, lColor);
  PushVertex(p2.X, p2.Y, u1, v1, lColor);
  PushVertex(p3.X, p3.Y, u0, v1, lColor);
  FlushScratch(ASurface);
end;

{ --- text --- }

// Decode one UTF-8 code point starting at AIndex (1-based), advancing it past
// the sequence. Malformed bytes yield U+FFFD and consume one byte, so a bad
// string cannot stall the caller's loop.
function NextCodePoint(const AText: String; var AIndex: Integer): LongWord;
var
  b: Byte;
  lExtra, i: Integer;
begin
  b := Byte(AText[AIndex]);
  Inc(AIndex);
  if b < $80 then
    Exit(b);
  if (b and $E0) = $C0 then
  begin
    Result := b and $1F;
    lExtra := 1;
  end
  else if (b and $F0) = $E0 then
  begin
    Result := b and $0F;
    lExtra := 2;
  end
  else if (b and $F8) = $F0 then
  begin
    Result := b and $07;
    lExtra := 3;
  end
  else
    Exit($FFFD);
  for i := 1 to lExtra do
  begin
    if (AIndex > Length(AText)) or ((Byte(AText[AIndex]) and $C0) <> $80) then
      Exit($FFFD);
    Result := (Result shl 6) or (Byte(AText[AIndex]) and $3F);
    Inc(AIndex);
  end;
end;

procedure TwgCanvas.DrawText(const AText: String; X, Y: Single;
  AColor: TwgColor);
var
  i: Integer;
  lCP, lGlyph, lPrev: LongWord;
  lInfo: TwgGlyphInfo;
  lPenX, lPenY, lX0, lY0, lX1, lY1: Single;
  lColor: TwgColor;
  p0, p1, p2, p3: TwgPointF;
  lFont: IwgGlyphSource;
  lBatchTex: IwgSurface;
begin
  CheckInFrame;
  lFont := FState.Font;
  if (lFont = nil) or (AText = '') then
    Exit;

  lColor := ResolveColor(AColor);
  lPenX := X;
  lPenY := Y;
  lPrev := 0;
  lBatchTex := nil;
  FlushScratch(nil);

  i := 1;
  while i <= Length(AText) do
  begin
    lCP := NextCodePoint(AText, i);
    if lCP = 10 then  // newline: return to the start column, drop a line
    begin
      lPenX := X;
      lPenY := lPenY + lFont.GetLineHeight;
      lPrev := 0;
      Continue;
    end;
    lGlyph := lFont.GetGlyphIndex(lCP);
    if lPrev <> 0 then
      lPenX := lPenX + lFont.GetKerning(lPrev, lGlyph);
    lPrev := lGlyph;

    if not lFont.GetGlyph(lGlyph, lInfo) then
      Continue;

    if (lInfo.Width > 0) and (lInfo.Height > 0) and (lInfo.Texture <> nil) then
    begin
      // Glyphs from different atlas pages cannot share one draw.
      if (lBatchTex <> nil) and (lBatchTex <> lInfo.Texture) then
        FlushScratch(lBatchTex);
      lBatchTex := lInfo.Texture;

      // BearingY is measured up from the baseline; Y grows down here.
      lX0 := lPenX + lInfo.BearingX;
      lY0 := lPenY - lInfo.BearingY;
      lX1 := lX0 + lInfo.Width;
      lY1 := lY0 + lInfo.Height;

      p0 := MapPoint(lX0, lY0);
      p1 := MapPoint(lX1, lY0);
      p2 := MapPoint(lX1, lY1);
      p3 := MapPoint(lX0, lY1);

      PushVertex(p0.X, p0.Y, lInfo.U0, lInfo.V0, lColor);
      PushVertex(p1.X, p1.Y, lInfo.U1, lInfo.V0, lColor);
      PushVertex(p2.X, p2.Y, lInfo.U1, lInfo.V1, lColor);
      PushVertex(p0.X, p0.Y, lInfo.U0, lInfo.V0, lColor);
      PushVertex(p2.X, p2.Y, lInfo.U1, lInfo.V1, lColor);
      PushVertex(p3.X, p3.Y, lInfo.U0, lInfo.V1, lColor);
    end;
    lPenX := lPenX + lInfo.Advance;
  end;
  FlushScratch(lBatchTex);
end;

procedure TwgCanvas.DrawTextTopLeft(const AText: String; X, Y: Single;
  AColor: TwgColor);
begin
  if FState.Font = nil then
    Exit;
  DrawText(AText, X, Y + FState.Font.GetAscent, AColor);
end;

function TwgCanvas.TextWidth(const AText: String): Single;
var
  i: Integer;
  lCP, lGlyph, lPrev: LongWord;
  lInfo: TwgGlyphInfo;
  lPen, lMax: Single;
  lFont: IwgGlyphSource;
begin
  lFont := FState.Font;
  if (lFont = nil) or (AText = '') then
    Exit(0);
  lPen := 0;
  lMax := 0;
  lPrev := 0;
  i := 1;
  while i <= Length(AText) do
  begin
    lCP := NextCodePoint(AText, i);
    if lCP = 10 then
    begin
      lMax := Max(lMax, lPen);
      lPen := 0;
      lPrev := 0;
      Continue;
    end;
    lGlyph := lFont.GetGlyphIndex(lCP);
    if lPrev <> 0 then
      lPen := lPen + lFont.GetKerning(lPrev, lGlyph);
    lPrev := lGlyph;
    if lFont.GetGlyph(lGlyph, lInfo) then
      lPen := lPen + lInfo.Advance;
  end;
  Result := Max(lMax, lPen);
end;

function TwgCanvas.TextHeight: Single;
begin
  if FState.Font = nil then
    Exit(0);
  Result := FState.Font.GetLineHeight;
end;

function TwgCanvas.TextExtent(const AText: String): TwgRectF;
var
  lFont: IwgGlyphSource;
  lLines, i: Integer;
begin
  lFont := FState.Font;
  if lFont = nil then
    Exit(wgRectF(0, 0, 0, 0));
  lLines := 1;
  for i := 1 to Length(AText) do
    if AText[i] = #10 then
      Inc(lLines);
  Result := wgRectF(0, -lFont.GetAscent, TextWidth(AText),
    lFont.GetDescent + (lLines - 1) * lFont.GetLineHeight);
end;

end.
