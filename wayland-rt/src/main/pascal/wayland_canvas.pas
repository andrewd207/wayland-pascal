{ wayland_canvas — a minimal, reusable software drawing canvas over a raw
  ARGB8888 pixel buffer.

  It is deliberately NOT a full compositing/anti-aliasing/alpha-blending canvas:
  primitives REPLACE pixels (the colour's alpha byte is written verbatim, which
  is what wl_shm ARGB8888 wants for opaque content). The point is to make filling
  a buffer with simple shapes — rectangles, lines, circles, ellipses — easy and
  reusable, independent of where the buffer comes from. It knows nothing about
  Wayland: hand it any CPU-addressable ARGB8888 memory (a wl_shm buffer's data, a
  linearly-tiled CPU-mapped dma-buf, a plain heap block) plus its stride.

  Pixel format: each pixel is a 32-bit ARGB value 0xAARRGGBB as a host DWord,
  stored little-endian (byte order B,G,R,A) — i.e. wl_shm ARGB8888/XRGB8888.

  All primitives clip to the canvas bounds, so off-edge coordinates are safe. }
unit wayland_canvas;

{$mode ObjFPC}{$H+}
{$ModeSwitch typehelpers}

interface

uses
  Classes, SysUtils, Types, FPImage;

type
  // 0xAARRGGBB as a host DWord (little-endian bytes B,G,R,A = wl_shm ARGB8888).
  TCanvasColor = type DWord;

  { TWaylandCanvas }

  TWaylandCanvas = class
  private
    FData: PByte;
    FWidth: Integer;
    FHeight: Integer;
    FStride: Integer; // bytes per row (>= Width*4)
    function RowPtr(Y: Integer): PDWord; inline;
  public
    // Wrap existing memory. AData must hold at least AHeight*AStride bytes and
    // stay alive for the canvas's lifetime (the canvas does not own it). AStride
    // defaults to AWidth*4 (tightly packed) when passed <= 0.
    constructor Create(AData: Pointer; AWidth, AHeight: Integer; AStride: Integer = 0);

    { --- pixels --- }
    procedure PutPixel(X, Y: Integer; AColor: TCanvasColor); inline;
    function  GetPixel(X, Y: Integer): TCanvasColor;

    { --- fills --- }
    procedure Clear(AColor: TCanvasColor);
    procedure FillRect(X, Y, W, H: Integer; AColor: TCanvasColor);

    { --- outlines / lines --- }
    procedure HLine(X, Y, W: Integer; AColor: TCanvasColor);
    procedure VLine(X, Y, H: Integer; AColor: TCanvasColor);
    procedure Line(X1, Y1, X2, Y2: Integer; AColor: TCanvasColor);
    procedure Rectangle(X, Y, W, H: Integer; AColor: TCanvasColor);
    // Connect consecutive points with straight lines. Polyline leaves the path
    // open; Polygon also draws the closing edge from the last point to the first.
    procedure Polyline(const APoints: array of TPoint; AColor: TCanvasColor);
    procedure Polygon(const APoints: array of TPoint; AColor: TCanvasColor);

    { --- rounded rectangles --- }
    // Rectangle (X,Y,W,H) with quarter-ellipse corners of radii (RX,RY). Radii
    // are clamped to half the width/height; a zero radius falls back to the
    // square Rectangle/FillRect.
    procedure RoundRect(X, Y, W, H, RX, RY: Integer; AColor: TCanvasColor);
    procedure FillRoundRect(X, Y, W, H, RX, RY: Integer; AColor: TCanvasColor);

    { --- ellipses / circles --- }
    procedure Ellipse(CX, CY, RX, RY: Integer; AColor: TCanvasColor);
    procedure FillEllipse(CX, CY, RX, RY: Integer; AColor: TCanvasColor);
    procedure Circle(CX, CY, R: Integer; AColor: TCanvasColor); inline;
    procedure FillCircle(CX, CY, R: Integer; AColor: TCanvasColor); inline;

    { --- images (fpimage) --- }
    // Blit AImage 1:1 at (ADestX, ADestY), clipped to the canvas. No scaling.
    // The image's 16-bit channels are reduced to 8-bit; the alpha byte is copied
    // (set the source opaque if you want opaque output). Optionally restrict the
    // source to the rectangle (ASrcX, ASrcY, ASrcW, ASrcH); pass ASrcW<0 for the
    // whole image.
    procedure CopyImage(AImage: TFPCustomImage; ADestX, ADestY: Integer);
    procedure CopyImage(AImage: TFPCustomImage; ADestX, ADestY,
      ASrcX, ASrcY, ASrcW, ASrcH: Integer);

    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    property Stride: Integer read FStride;
    property Data: PByte read FData;
  end;

// Pack/convert helpers.
function ARGB(A, R, G, B: Byte): TCanvasColor; inline;       // explicit alpha
function RGB(R, G, B: Byte): TCanvasColor; inline;           // opaque (A=255)
function FPColorToCanvas(const AColor: TFPColor): TCanvasColor; inline;

implementation

function ARGB(A, R, G, B: Byte): TCanvasColor;
begin
  Result := (TCanvasColor(A) shl 24) or (TCanvasColor(R) shl 16) or
            (TCanvasColor(G) shl 8) or TCanvasColor(B);
end;

function RGB(R, G, B: Byte): TCanvasColor;
begin
  Result := $FF000000 or (TCanvasColor(R) shl 16) or
            (TCanvasColor(G) shl 8) or TCanvasColor(B);
end;

function FPColorToCanvas(const AColor: TFPColor): TCanvasColor;
begin
  // FPColor channels are 16-bit; take the high byte of each.
  Result := ARGB(AColor.alpha shr 8, AColor.red shr 8,
                 AColor.green shr 8, AColor.blue shr 8);
end;

{ TWaylandCanvas }

constructor TWaylandCanvas.Create(AData: Pointer; AWidth, AHeight: Integer;
  AStride: Integer);
begin
  FData := AData;
  FWidth := AWidth;
  FHeight := AHeight;
  if AStride > 0 then
    FStride := AStride
  else
    FStride := AWidth * 4;
end;

function TWaylandCanvas.RowPtr(Y: Integer): PDWord;
begin
  Result := PDWord(FData + Y * FStride);
end;

procedure TWaylandCanvas.PutPixel(X, Y: Integer; AColor: TCanvasColor);
begin
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then
    Exit;
  RowPtr(Y)[X] := AColor;
end;

function TWaylandCanvas.GetPixel(X, Y: Integer): TCanvasColor;
begin
  if (X < 0) or (Y < 0) or (X >= FWidth) or (Y >= FHeight) then
    Exit(0);
  Result := RowPtr(Y)[X];
end;

procedure TWaylandCanvas.Clear(AColor: TCanvasColor);
begin
  FillRect(0, 0, FWidth, FHeight, AColor);
end;

procedure TWaylandCanvas.FillRect(X, Y, W, H: Integer; AColor: TCanvasColor);
var
  lRow, lCol, lX2, lY2: Integer;
  p: PDWord;
begin
  // clip to canvas
  lX2 := X + W;
  lY2 := Y + H;
  if X < 0 then X := 0;
  if Y < 0 then Y := 0;
  if lX2 > FWidth then lX2 := FWidth;
  if lY2 > FHeight then lY2 := FHeight;
  for lRow := Y to lY2 - 1 do
  begin
    p := RowPtr(lRow);
    for lCol := X to lX2 - 1 do
      p[lCol] := AColor;
  end;
end;

procedure TWaylandCanvas.HLine(X, Y, W: Integer; AColor: TCanvasColor);
begin
  FillRect(X, Y, W, 1, AColor);
end;

procedure TWaylandCanvas.VLine(X, Y, H: Integer; AColor: TCanvasColor);
begin
  FillRect(X, Y, 1, H, AColor);
end;

procedure TWaylandCanvas.Line(X1, Y1, X2, Y2: Integer; AColor: TCanvasColor);
var
  dx, dy, sx, sy, err, e2: Integer;
begin
  // Bresenham's line algorithm (integer, all octants).
  dx := Abs(X2 - X1);
  dy := -Abs(Y2 - Y1);
  if X1 < X2 then sx := 1 else sx := -1;
  if Y1 < Y2 then sy := 1 else sy := -1;
  err := dx + dy;
  while True do
  begin
    PutPixel(X1, Y1, AColor);
    if (X1 = X2) and (Y1 = Y2) then
      Break;
    e2 := 2 * err;
    if e2 >= dy then
    begin
      err := err + dy;
      X1 := X1 + sx;
    end;
    if e2 <= dx then
    begin
      err := err + dx;
      Y1 := Y1 + sy;
    end;
  end;
end;

procedure TWaylandCanvas.Rectangle(X, Y, W, H: Integer; AColor: TCanvasColor);
begin
  if (W <= 0) or (H <= 0) then
    Exit;
  HLine(X, Y, W, AColor);
  HLine(X, Y + H - 1, W, AColor);
  VLine(X, Y, H, AColor);
  VLine(X + W - 1, Y, H, AColor);
end;

procedure TWaylandCanvas.Polyline(const APoints: array of TPoint; AColor: TCanvasColor);
var
  i: Integer;
begin
  for i := Low(APoints) to High(APoints) - 1 do
    Line(APoints[i].X, APoints[i].Y, APoints[i + 1].X, APoints[i + 1].Y, AColor);
end;

procedure TWaylandCanvas.Polygon(const APoints: array of TPoint; AColor: TCanvasColor);
begin
  if Length(APoints) < 2 then
    Exit;
  Polyline(APoints, AColor);
  // closing edge
  Line(APoints[High(APoints)].X, APoints[High(APoints)].Y,
       APoints[Low(APoints)].X, APoints[Low(APoints)].Y, AColor);
end;

procedure TWaylandCanvas.RoundRect(X, Y, W, H, RX, RY: Integer; AColor: TCanvasColor);
var
  x0, y0: Integer;

  procedure PlotCorners(px, py: Integer); // place one arc point at all 4 corners
  begin
    PutPixel(x0 + RX - px, y0 + RY - py, AColor);              // top-left
    PutPixel(x0 + W - 1 - RX + px, y0 + RY - py, AColor);      // top-right
    PutPixel(x0 + RX - px, y0 + H - 1 - RY + py, AColor);      // bottom-left
    PutPixel(x0 + W - 1 - RX + px, y0 + H - 1 - RY + py, AColor); // bottom-right
  end;

var
  px, py: Integer;
  rx2, ry2, twoRx2, twoRy2, p, dx, dy: Int64;
begin
  if (W <= 0) or (H <= 0) then
    Exit;
  if RX * 2 > W then RX := W div 2;
  if RY * 2 > H then RY := H div 2;
  if (RX <= 0) or (RY <= 0) then
  begin
    Rectangle(X, Y, W, H, AColor);
    Exit;
  end;
  x0 := X; y0 := Y;
  // straight edges between the corner arcs
  HLine(X + RX, Y, W - 2 * RX, AColor);
  HLine(X + RX, Y + H - 1, W - 2 * RX, AColor);
  VLine(X, Y + RY, H - 2 * RY, AColor);
  VLine(X + W - 1, Y + RY, H - 2 * RY, AColor);
  // midpoint quarter-ellipse, mirrored onto each corner
  rx2 := Int64(RX) * RX;
  ry2 := Int64(RY) * RY;
  twoRx2 := 2 * rx2;
  twoRy2 := 2 * ry2;
  px := 0; py := RY;
  dx := 0; dy := twoRx2 * py;
  p := Round(ry2 - (rx2 * RY) + (0.25 * rx2));
  PlotCorners(px, py);
  while dx < dy do
  begin
    Inc(px);
    dx := dx + twoRy2;
    if p < 0 then
      p := p + ry2 + dx
    else
    begin
      Dec(py);
      dy := dy - twoRx2;
      p := p + ry2 + dx - dy;
    end;
    PlotCorners(px, py);
  end;
  p := Round(ry2 * (px + 0.5) * (px + 0.5) + rx2 * (py - 1) * (py - 1) - rx2 * ry2);
  while py > 0 do
  begin
    Dec(py);
    dy := dy - twoRx2;
    if p > 0 then
      p := p + rx2 - dy
    else
    begin
      Inc(px);
      dx := dx + twoRy2;
      p := p + rx2 - dy + dx;
    end;
    PlotCorners(px, py);
  end;
end;

procedure TWaylandCanvas.FillRoundRect(X, Y, W, H, RX, RY: Integer; AColor: TCanvasColor);
var
  dy, hx, inset: Integer;
begin
  if (W <= 0) or (H <= 0) then
    Exit;
  if RX * 2 > W then RX := W div 2;
  if RY * 2 > H then RY := H div 2;
  if (RX <= 0) or (RY <= 0) then
  begin
    FillRect(X, Y, W, H, AColor);
    Exit;
  end;
  // full-width middle band
  FillRect(X, Y + RY, W, H - 2 * RY, AColor);
  // rounded top/bottom bands: per row, inset by the corner ellipse's half-width
  for dy := 0 to RY - 1 do
  begin
    hx := Round(RX * Sqrt(1 - Sqr((RY - dy - 0.5) / RY)));
    inset := RX - hx;
    HLine(X + inset, Y + dy, W - 2 * inset, AColor);          // top
    HLine(X + inset, Y + H - 1 - dy, W - 2 * inset, AColor);  // bottom
  end;
end;

procedure TWaylandCanvas.Ellipse(CX, CY, RX, RY: Integer; AColor: TCanvasColor);
var
  x, y: Integer;
  rx2, ry2, twoRx2, twoRy2, p, px, py: Int64;

  procedure Plot4; // 4-way symmetry
  begin
    PutPixel(CX + x, CY + y, AColor);
    PutPixel(CX - x, CY + y, AColor);
    PutPixel(CX + x, CY - y, AColor);
    PutPixel(CX - x, CY - y, AColor);
  end;

begin
  if (RX <= 0) or (RY <= 0) then
    Exit;
  // Midpoint ellipse algorithm.
  rx2 := Int64(RX) * RX;
  ry2 := Int64(RY) * RY;
  twoRx2 := 2 * rx2;
  twoRy2 := 2 * ry2;
  x := 0;
  y := RY;
  px := 0;
  py := twoRx2 * y;

  // region 1
  p := Round(ry2 - (rx2 * RY) + (0.25 * rx2));
  Plot4;
  while px < py do
  begin
    Inc(x);
    px := px + twoRy2;
    if p < 0 then
      p := p + ry2 + px
    else
    begin
      Dec(y);
      py := py - twoRx2;
      p := p + ry2 + px - py;
    end;
    Plot4;
  end;
  // region 2
  p := Round(ry2 * (x + 0.5) * (x + 0.5) + rx2 * (y - 1) * (y - 1) - rx2 * ry2);
  while y > 0 do
  begin
    Dec(y);
    py := py - twoRx2;
    if p > 0 then
      p := p + rx2 - py
    else
    begin
      Inc(x);
      px := px + twoRy2;
      p := p + rx2 - py + px;
    end;
    Plot4;
  end;
end;

procedure TWaylandCanvas.FillEllipse(CX, CY, RX, RY: Integer; AColor: TCanvasColor);
var
  x, y: Integer;
  rx2, ry2, twoRx2, twoRy2, p, px, py: Int64;

  procedure Span; // fill the two scanlines for the current y
  begin
    HLine(CX - x, CY + y, 2 * x + 1, AColor);
    HLine(CX - x, CY - y, 2 * x + 1, AColor);
  end;

begin
  if (RX <= 0) or (RY <= 0) then
    Exit;
  rx2 := Int64(RX) * RX;
  // (fall through to the shared midpoint walk below)
  ry2 := Int64(RY) * RY;
  twoRx2 := 2 * rx2;
  twoRy2 := 2 * ry2;
  x := 0;
  y := RY;
  px := 0;
  py := twoRx2 * y;

  p := Round(ry2 - (rx2 * RY) + (0.25 * rx2));
  Span;
  while px < py do
  begin
    Inc(x);
    px := px + twoRy2;
    if p < 0 then
      p := p + ry2 + px
    else
    begin
      Dec(y);
      py := py - twoRx2;
      p := p + ry2 + px - py;
    end;
    Span;
  end;
  p := Round(ry2 * (x + 0.5) * (x + 0.5) + rx2 * (y - 1) * (y - 1) - rx2 * ry2);
  while y > 0 do
  begin
    Dec(y);
    py := py - twoRx2;
    if p > 0 then
      p := p + rx2 - py
    else
    begin
      Inc(x);
      px := px + twoRy2;
      p := p + rx2 - py + px;
    end;
    Span;
  end;
end;

procedure TWaylandCanvas.Circle(CX, CY, R: Integer; AColor: TCanvasColor);
begin
  Ellipse(CX, CY, R, R, AColor);
end;

procedure TWaylandCanvas.FillCircle(CX, CY, R: Integer; AColor: TCanvasColor);
begin
  FillEllipse(CX, CY, R, R, AColor);
end;

procedure TWaylandCanvas.CopyImage(AImage: TFPCustomImage; ADestX, ADestY: Integer);
begin
  CopyImage(AImage, ADestX, ADestY, 0, 0, -1, -1);
end;

procedure TWaylandCanvas.CopyImage(AImage: TFPCustomImage; ADestX, ADestY,
  ASrcX, ASrcY, ASrcW, ASrcH: Integer);
var
  sx, sy, dx, dy: Integer;
  p: PDWord;
begin
  if AImage = nil then
    Exit;
  if ASrcW < 0 then ASrcW := AImage.Width - ASrcX;
  if ASrcH < 0 then ASrcH := AImage.Height - ASrcY;
  for sy := 0 to ASrcH - 1 do
  begin
    dy := ADestY + sy;
    if (dy < 0) or (dy >= FHeight) then
      Continue;
    if (ASrcY + sy < 0) or (ASrcY + sy >= AImage.Height) then
      Continue;
    p := RowPtr(dy);
    for sx := 0 to ASrcW - 1 do
    begin
      dx := ADestX + sx;
      if (dx < 0) or (dx >= FWidth) then
        Continue;
      if (ASrcX + sx < 0) or (ASrcX + sx >= AImage.Width) then
        Continue;
      p[dx] := FPColorToCanvas(AImage.Colors[ASrcX + sx, ASrcY + sy]);
    end;
  end;
end;

end.
