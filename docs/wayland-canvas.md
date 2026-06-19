# wayland_canvas — a minimal software canvas

`TWaylandCanvas` (unit `wayland_canvas`, in `wayland-rt`) is a small software
drawing canvas over a raw ARGB8888 pixel buffer.

It is **deliberately not** a comprehensive canvas — no anti-aliasing, no alpha
blending, no transforms, no text. Its only job is to make it easy to *write into
a memory buffer* with a handful of primitives, so the examples (and the
[`wayland-classes`](wayland-classes/index.md) buffers) have something to draw
with out of the box. It is intentionally a starting point:

- **extend it** — subclass or add primitives (blended fills, gradients, glyphs…);
  or
- **ignore it** — a window buffer is just CPU memory. Hand its `Data` + `Stride`
  to any other raster/canvas library and let that write the pixels. The canvas
  has no special status; it's one convenient way to fill the buffer.

It knows nothing about Wayland — give it any CPU-addressable ARGB8888 memory (a
wl_shm buffer's data, a CPU-mapped dma-buf, a plain heap block) plus its stride.

## Pixel format

Each pixel is a 32-bit `0xAARRGGBB` value stored as a host `DWord`
(little-endian bytes B, G, R, A) — i.e. wl_shm `ARGB8888`/`XRGB8888`. Primitives
**replace** pixels (the colour's alpha byte is written verbatim), which is what
opaque shm/dma-buf content wants. All primitives clip to the canvas bounds, so
off-edge coordinates are safe.

## Construction

```pascal
constructor Create(AData: Pointer; AWidth, AHeight: Integer; AStride: Integer = 0);
```

`AData` must hold at least `AHeight * AStride` bytes and stay alive for the
canvas's lifetime (the canvas does **not** own it). `AStride` is bytes per row;
pass `<= 0` for tightly packed (`AWidth * 4`). Always use the buffer's real
stride — backends may pad rows (e.g. the dma-buf backend aligns to 256 bytes).

```pascal
property Width, Height, Stride: Integer;
property Data: PByte;
```

## Primitives

```pascal
{ pixels }       PutPixel(X, Y, AColor);  GetPixel(X, Y): TCanvasColor
{ fills }        Clear(AColor);  FillRect(X, Y, W, H, AColor)
{ lines }        HLine(X, Y, W, AColor);  VLine(X, Y, H, AColor)
                 Line(X1, Y1, X2, Y2, AColor)            { Bresenham }
                 Rectangle(X, Y, W, H, AColor)
                 Polyline(const APoints: array of TPoint; AColor)
                 Polygon(const APoints: array of TPoint; AColor)   { closed }
{ rounded }      RoundRect(X, Y, W, H, RX, RY, AColor)
                 FillRoundRect(X, Y, W, H, RX, RY, AColor)
                 RoundCorners(X, Y, W, H, R)    { carve alpha: AA rounded, transparent corners }
{ ellipses }     Ellipse(CX, CY, RX, RY, AColor);  FillEllipse(...)
                 Circle(CX, CY, R, AColor);  FillCircle(...)
{ images }       CopyImage(AImage: TFPCustomImage; ADestX, ADestY)
                 CopyImage(AImage; ADestX, ADestY, ASrcX, ASrcY, ASrcW, ASrcH)
```

`CopyImage` blits an fpimage `TFPCustomImage` 1:1 (no scaling), clipped to the
canvas; the source's 16-bit channels are reduced to 8-bit and the alpha byte is
copied verbatim.

`RoundCorners` is the one primitive that touches the **alpha** channel: draw your
window opaque, then `RoundCorners(0, 0, W, H, R)` carves anti-aliased rounded
corners by setting the outside-corner pixels transparent and scaling edge pixels'
alpha by coverage. The surface must not be marked opaque for the compositor to
honour it — see the `themed_window` example.

## Colour helpers

```pascal
function ARGB(A, R, G, B: Byte): TCanvasColor;   // explicit alpha
function RGB(R, G, B: Byte): TCanvasColor;        // opaque (A = 255)
function FPColorToCanvas(const AColor: TFPColor): TCanvasColor;
```

## Example

```pascal
uses wayland_canvas;
...
c := TWaylandCanvas.Create(lBuf.Data, lBuf.Width, lBuf.Height, lBuf.Stride);
try
  c.Clear(RGB(24, 24, 32));
  c.FillRoundRect(20, 20, 120, 80, 16, 16, RGB(60, 120, 200));
  c.RoundRect(20, 20, 120, 80, 16, 16, RGB(255, 255, 255));
  c.FillCircle(240, 70, 45, RGB(220, 80, 80));
  c.Line(0, 0, c.Width - 1, c.Height - 1, RGB(120, 120, 140));
finally
  c.Free;
end;
```

With `wayland-classes`, `lBuf` is a [`TfpgwBuffer`](wayland-classes/TfpgwBuffer.md)
from `Window.NextBuffer`; the same code works whether the buffer is shm- or
dma-buf-backed. See the `canvas_demo` (shm) and `canvas_dmabuf` (CPU dma-buf)
[examples](../wayland-examples/README.md).
