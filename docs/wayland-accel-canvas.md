# The accelerated canvas — `TWaylandAccelCanvas` and `TWaylandGLCanvas`

Where [`wayland_canvas`](wayland-canvas.md) pokes pixels in a CPU buffer, this is
the GPU path: float coordinates, a transform stack, real alpha blending,
anti-aliasing, textured image blits and FreeType text — presented to the
compositor as a **dmabuf**, so the GPU writes exactly the memory the compositor
scans out.

The two canvases are separate hierarchies that meet only at
[`ISurface`](#isurface--the-common-currency), so either can be a source for the
other.

## Layout

| Unit | Module | What it is |
|---|---|---|
| `wayland_surface` | `wayland-rt` | `ISurface` / `IPixelSurface` / `ITextureSurface`, `TWaylandImage`, the `TCanvasColor` pixel type and colour helpers |
| `wayland_accel_canvas` | `wayland-rt` | `TWaylandAccelCanvas` — the whole drawing API, and all the tessellation. Backend-agnostic |
| `wayland_gl_context` | `wayland-gl` | `TWaylandGLContext` — surfaceless EGL + a GL 3.3 core context |
| `wayland_gl_texture` | `wayland-gl` | `TGLTexture` — a GL texture that is an `ITextureSurface` |
| `wayland_gl_target` | `wayland-gl` | `TGLRenderTarget` (texture + FBO), `TGLTargetRing` (dmabuf-exported presentation ring) |
| `wayland_glyph_atlas` | `wayland-gl` | `TGlyphAtlas` — FreeType rasterising into a GL atlas, as an `IGlyphSource` |
| `wayland_gl_canvas` | `wayland-gl` | `TWaylandGLCanvas` — the OpenGL backend |
| `gl_core_fpc`, `freetype_fpc` | `wayland-gl` | GL 3.3 core loader; hand-written FreeType 2 subset binding |

`wayland-gl` is the one module in the project that is **not** RTL-only — it links
`libEGL`, `libGL` and `libfreetype`. It is `activeByDefault="false"` and nothing
else in the stack depends on it, so code that only wants the software canvas
never pulls those in.

## The device protocol

`TWaylandAccelCanvas` owns the entire public vocabulary and reduces all of it —
rectangles, arcs, rounded rects, strokes with caps and joins, bezier paths, ear
clipped polygon fills, image blits, glyph runs — to five calls a backend
implements:

```pascal
procedure DeviceBeginFrame; / DeviceEndFrame;
procedure DeviceClear(AColor: TCanvasColor);
procedure DeviceSetClip(const ARect: TRect; AEnabled: Boolean);
procedure DeviceSetBlend(AMode: TCanvasBlendMode);
procedure DeviceDrawTriangles(const AVerts: TCanvasVertexArray;
  ACount: Integer; ATexture: ISurface);
```

A backend only has to fill triangles with a per-vertex colour, optionally
modulated by a texture. Everything else is portable Pascal, so a Vulkan or
software backend stays viable.

## Conventions that matter

**Coordinates** are floats in surface pixels, origin top-left, Y down — the same
as the software canvas and as Wayland surface coordinates.

**Colours** passed to primitives use **straight** (non-premultiplied) alpha, so
`ARGB($80, 255, 0, 0)` is half-transparent red as you would expect. Pixels
*stored* in surfaces are **premultiplied**, which is what wl_shm and dma-buf
`ARGB8888` require. The conversion, plus the global `Opacity` multiply, happens
once as vertices are emitted.

**Orientation.** The vertex shader maps canvas Y straight onto NDC Y *without a
flip*. NDC −1 is window y 0, which is framebuffer memory row 0, so canvas row 0
lands in memory row 0 — which is what a `wl_buffer` means by its top row, and
what a CPU image upload puts in texel row 0. Flipping in the shader (the reflex
choice, since GL is nominally Y-up) stores every render target upside down and
presents mirrored frames. Consequences: render-target textures are top-down, so
`TGLTexture.FlipV` stays `False` for them, and `glScissor` needs no Y inversion.

## Anti-aliasing

Supersampling, owned by the canvas. It renders into an offscreen target
`SuperSample`× larger per axis and resolves down to the presentation target.
Unlike MSAA this antialiases *everything* uniformly — polygon edges, glyph edges,
and the interiors of scaled-down images — because the scene really is rendered at
higher resolution. The cost is `SuperSample²` fill rate.

The resolve **halves repeatedly** rather than in one step: bilinear filtering
averages only a 2×2 neighbourhood, so a single 4×→1× pass would read 4 of the 16
texels it covers and alias. Each pass halves, so every source texel contributes
exactly once. Pass `1` to disable AA, `2` for the sensible default, `4` for
noticeably better thin diagonals.

## `ISurface` — the common currency

```pascal
ISurface         // Width, Height, HasAlpha, Generation
IPixelSurface    // + LockPixels(out AData, out AStride) / UnlockPixels
ITextureSurface  // + GetTextureHandle, GetTextureIsAlphaOnly, GetTextureUV
```

Implemented by `TWaylandImage` (CPU), the software `TWaylandCanvas` (CPU),
`TGLTexture`, `TGLRenderTarget`'s texture, and `TWaylandGLCanvas` itself. The GL
backend prefers `ITextureSurface` and uses it with no upload at all; otherwise it
uploads through `IPixelSurface` and caches the result.

**`Generation`** is the cache key: process-wide, monotonic, bumped on every
content change, never reused. That is what lets the texture cache re-upload only
when pixels actually changed — and why a stale cache entry can never look
current. Mutate a surface behind the canvas's back (a `PutPixel` loop, or writes
through a locked pointer) and you must call `Changed` yourself.

**Lifetime**: these interfaces do *not* own their implementor. Following the
convention `wayland_core` established for protocol objects, implementors derive
from `TInterfacedObject` but make `_AddRef`/`_Release` no-ops. Holding an
`ISurface` neither keeps the object alive nor frees it at scope exit; surfaces are
freed explicitly by whoever created them.

## Text

`TGlyphAtlas` is an `IGlyphSource`: one font face at one pixel size, rasterising
glyphs on demand into a single-channel (`R8`) GL texture. The canvas does layout
only — glyph lookup, kerning, newlines — and emits one textured quad per glyph,
so a whole run in one atlas page is a single draw call. Bold, italic and other
sizes are separate `TGlyphAtlas` instances.

Packing is a shelf allocator, near-optimal for one font at one size. When a page
fills, a new larger page is allocated and glyphs already handed out keep pointing
at the old one, which stays alive — so a `TGlyphInfo` never dangles. Nothing is
evicted; a text editor cycling through thousands of CJK glyphs would want an LRU
instead.

`freetype_fpc` is a hand-written subset binding. Its record layouts were verified
field-by-field against the installed headers — note that `FT_Pos`/`FT_Long`/
`FT_Fixed` are C `signed long` (64-bit on LP64), so they are `clong`, not
`LongInt`, which would silently shift every following field.

## Presentation

There is no Wayland EGL platform and no `libwayland`. `TWaylandGLContext` creates
an `EGL_PLATFORM_SURFACELESS_MESA` display; frames are rendered into FBOs whose
textures are exported as dmabuf file descriptors via
`EGL_MESA_image_dma_buf_export`. `TGLTargetRing` holds several such targets so a
client never draws into the buffer the compositor is still displaying.

`wayland-gl` deliberately stops at file descriptors: it hands back an fd, stride,
offset, DRM fourcc and modifier, and turning those into a `wl_buffer` through
`zwp_linux_dmabuf_v1` is the caller's job. That is what keeps the module free of
any dependency on the generated protocol tiers.

**FD ownership**: each target owns its exported fd and closes it on `Free`. A
caller passing it to `zwp_linux_dmabuf_v1` is only *lending* it — the protocol
dups what it needs — so do not close it yourself.

Check `TWaylandGLContext.CanExportDmabuf` before relying on any of this; a driver
without the export extensions means falling back to shm.

## Example

```pascal
uses wayland_surface, wayland_accel_canvas,
     wayland_gl_context, wayland_gl_target, wayland_gl_canvas,
     wayland_glyph_atlas;

lCtx    := TWaylandGLContext.Create(3, 3);
lRing   := TGLTargetRing.Create(lCtx, W, H, 2);   // dmabuf-exported
lCanvas := TWaylandGLCanvas.Create(lCtx, W, H, 2); // 2x supersampled
lFont   := TGlyphAtlas.Create('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 28);

// ... wrap each lRing[i].DmabufFd in a wl_buffer via zwp_linux_dmabuf_v1 ...

lSlot := lRing.Acquire;                // a target the compositor isn't holding
lCanvas.SetTarget(lRing[lSlot]);
lCanvas.BeginFrame;
try
  lCanvas.Clear(ARGB(255, 20, 24, 34));
  lCanvas.FillRoundRect(20, 20, 200, 120, 14, 14, ARGB(255, 50, 60, 90));
  lCanvas.LineWidth := 3;
  lCanvas.Circle(300, 80, 50, ARGB(255, 255, 255, 255));

  lCanvas.Save;                        // transforms nest
  lCanvas.Translate(400, 90);
  lCanvas.Rotate(lAngle);
  lCanvas.FillPolygon(lStar, ARGB(235, 255, 205, 90));
  lCanvas.Restore;

  lCanvas.DrawSurface(lImage, 20, 200, 96, 96);   // scaled blit
  lCanvas.Font := lFont;
  lCanvas.DrawTextTopLeft('Hello, Wayland!', 20, 320, ARGB(255, 240, 240, 240));
finally
  lCanvas.EndFrame;                    // resolves the supersample buffer, glFinish
end;
// attach lRing[lSlot]'s wl_buffer, damage, commit; lRing.MarkBusy(lSlot)
```

See the `gl_canvas_demo` [example](../wayland-examples/README.md) for the whole
loop, including `wl_buffer.release` tracking and `wl_surface.frame` pacing. Build
it with `make examples`.
