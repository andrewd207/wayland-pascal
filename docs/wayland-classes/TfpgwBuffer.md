# TfpgwBuffer

One of a window's CPU-addressable pixel buffers (windows are double-buffered).
You obtain one from `Window.NextBuffer`, write ARGB8888 pixels into it, then
`Window.Paint` it.

← back to [index](index.md)

## Members

```pascal
property Data: Pointer;        // first pixel; ARGB8888, little-endian (B,G,R,A)
property Width: Integer;
property Height: Integer;
property Stride: Integer;      // bytes per row — may exceed Width*4 (backend padding)
procedure SetPaintRect(AX, AY, AWidth, AHeight: Integer);  // damage region for the next Paint
property  PaintArea: TRect;
property  Busy: Boolean;       // held by the compositor until released
property  Buffer: TWlBuffer;   // underlying wl_buffer
```

Always index rows by `Stride`, not `Width*4` — the dma-buf backend pads rows to a
256-byte boundary.

## Backend: shm vs dma-buf

The pixel backing is chosen per display by `TfpgwBufferPool` (an abstraction that
mirrors the shell-surface split):

- **dma-buf** (`TfpgwDmabufPool`) — preferred (faster, zero-copy import) when
  `zwp_linux_dmabuf_v1` **and** `/dev/udmabuf` are available.
- **wl_shm** (`TfpgwShmPool`) — the fallback, always available.

This is transparent: your code only ever sees `Data`/`Width`/`Height`/`Stride`.
The selection happens at display setup; nothing in your draw code changes.

## Drawing with TWaylandCanvas

Rather than poking pixels by hand, wrap the buffer in a `TWaylandCanvas` (unit
`wayland_canvas`, in `wayland-rt` — protocol-agnostic, reusable for any ARGB8888
memory):

```pascal
uses wayland_canvas;
...
c := TWaylandCanvas.Create(lBuf.Data, lBuf.Width, lBuf.Height, lBuf.Stride);
try
  c.Clear(RGB(24, 24, 32));
  c.FillRoundRect(20, 20, 120, 80, 16, 16, RGB(60, 120, 200));
  c.RoundRect(20, 20, 120, 80, 16, 16, RGB(255, 255, 255));
  c.Circle(240, 70, 45, RGB(255, 255, 255));
finally
  c.Free;
end;
```

`TWaylandCanvas` **replaces** pixels (no alpha blending) and clips to bounds.
Primitives:

- pixels: `PutPixel`, `GetPixel`
- fills: `Clear`, `FillRect`
- lines/outlines: `HLine`, `VLine`, `Line`, `Rectangle`, `Polyline`, `Polygon`
- rounded rects: `RoundRect`, `FillRoundRect`
- ellipses/circles: `Ellipse`, `FillEllipse`, `Circle`, `FillCircle`
- images: `CopyImage` (from an fpimage `TFPCustomImage`)

Colour helpers: `ARGB(a,r,g,b)`, `RGB(r,g,b)` (opaque), `FPColorToCanvas`.

See the `canvas_demo` (shm) and `canvas_dmabuf` (dma-buf) examples.
