# The accelerated canvas — `TwgCanvas` and its backends

Where [`wlg.canvas.raster`](wayland-canvas.md) pokes pixels in a CPU buffer, this is
the real drawing API: float coordinates, a transform stack, alpha blending,
anti-aliasing, textured image blits and FreeType text.

It has **two interchangeable backends** behind one API:

- `TwgGLCanvas` — OpenGL 3.3 core, presented to the compositor as a
  **dmabuf**, so the GPU writes exactly the memory the compositor scans out.
- `TwgSoftCanvas` — a CPU rasteriser writing into ordinary ARGB8888 memory
  such as a `wl_shm` buffer. Pure RTL, no libraries.

Code that draws sees only `TwgCanvas` and cannot tell which it has —
that is verified, not asserted: one scene routine renders through both and the
outputs differ only in anti-aliasing edge detail.

The two canvases are separate hierarchies that meet only at
[`IwgSurface`](#isurface--the-common-currency), so either can be a source for the
other.

## Layout

| Unit | Module | What it is |
|---|---|---|
| `wlg.surface` | `wayland-rt` | `IwgSurface` / `IwgPixelSurface` / `IwgTextureSurface`, `TwgImage`, the `TwgColor` pixel type and colour helpers |
| `wlg.canvas.base` | `wayland-rt` | `TwgCanvas` — the whole drawing API, and all the tessellation. Backend-agnostic |
| `wlg.canvas.software` | `wayland-rt` | `TwgSoftCanvas` — CPU backend. Half-space rasteriser, RTL-only |
| `wlg.text.atlas`, `freetype_fpc` | `wayland-text` | `TwgGlyphAtlas` — FreeType into coverage (`sfA8`) CPU pages, as an `IwgGlyphSource`. Serves **both** backends |
| `wlg.gl.context` | `wayland-gl` | `TwgGLContext` — surfaceless EGL + a GL 3.3 core context |
| `wlg.gl.texture` | `wayland-gl` | `TwgGLTexture` — a GL texture that is an `IwgTextureSurface` |
| `wlg.gl.target` | `wayland-gl` | `TwgGLRenderTarget` (texture + FBO), `TwgGLTargetRing` (dmabuf-exported presentation ring) |
| `wlg.canvas.gl` | `wayland-gl` | `TwgGLCanvas` — the OpenGL backend |
| `gl_core_fpc` | `wayland-gl` | GL 3.3 core entry-point loader |

`wayland-text` (links `libfreetype`) and `wayland-gl` (links `libEGL`/`libGL`)
are the only modules that are not RTL-only. Both are `activeByDefault="false"`
and nothing in the core stack depends on either, so code that only wants the
software canvas never pulls them in. Note the consequence: **`rt` alone can now
draw the full anti-aliased, transformed, blended API into a `wl_shm` buffer**,
with no external library at all — text is the only thing that needs
`wayland-text`.

## The device protocol

`TwgCanvas` owns the entire public vocabulary and reduces all of it —
rectangles, arcs, rounded rects, strokes with caps and joins, bezier paths, ear
clipped polygon fills, image blits, glyph runs — to five calls a backend
implements:

```pascal
procedure DeviceBeginFrame; / DeviceEndFrame;
procedure DeviceClear(AColor: TwgColor);
procedure DeviceSetClip(const ARect: TRect; AEnabled: Boolean);
procedure DeviceSetBlend(AMode: TwgBlendMode);
procedure DeviceDrawTriangles(const AVerts: TwgVertexArray;
  ACount: Integer; ATexture: IwgSurface);
```

A backend only has to fill triangles with a per-vertex colour, optionally
modulated by a texture. Everything else is portable Pascal, so a Vulkan or
software backend stays viable.

## Conventions that matter

**Coordinates** are floats in surface pixels, origin top-left, Y down — the same
as the software canvas and as Wayland surface coordinates.

**Colours** passed to primitives use **straight** (non-premultiplied) alpha, so
`wgARGB($80, 255, 0, 0)` is half-transparent red as you would expect. Pixels
*stored* in surfaces are **premultiplied**, which is what wl_shm and dma-buf
`ARGB8888` require. The conversion, plus the global `Opacity` multiply, happens
once as vertices are emitted.

**Orientation.** The vertex shader maps canvas Y straight onto NDC Y *without a
flip*. NDC −1 is window y 0, which is framebuffer memory row 0, so canvas row 0
lands in memory row 0 — which is what a `wl_buffer` means by its top row, and
what a CPU image upload puts in texel row 0. Flipping in the shader (the reflex
choice, since GL is nominally Y-up) stores every render target upside down and
presents mirrored frames. Consequences: render-target textures are top-down, so
`TwgGLTexture.FlipV` stays `False` for them, and `glScissor` needs no Y inversion.

## Anti-aliasing

Supersampling, owned by each backend. It renders into an offscreen target
`SuperSample`× larger per axis and resolves down to the presentation target.
Unlike MSAA this antialiases *everything* uniformly — polygon edges, glyph edges,
and the interiors of scaled-down images — because the scene really is rendered at
higher resolution. The cost is `SuperSample²` fill rate.

The resolve **halves repeatedly** rather than in one step: bilinear filtering
averages only a 2×2 neighbourhood, so a single 4×→1× pass would read 4 of the 16
texels it covers and alias. Each pass halves, so every source texel contributes
exactly once. Pass `1` to disable AA, `2` for the sensible default, `4` for
noticeably better thin diagonals.

## `IwgSurface` — the common currency

```pascal
IwgSurface         // Width, Height, HasAlpha, Generation
IwgPixelSurface    // + LockPixels(out AData, out AStride) / UnlockPixels
IwgTextureSurface  // + GetTextureHandle, GetTextureIsAlphaOnly, GetTextureUV
```

Implemented by `TwgImage` and `TwgAlphaImage` (CPU), the software
`TwgRasterCanvas` (CPU), `TwgGLTexture`, `TwgGLRenderTarget`'s texture,
`TwgSoftCanvas` and `TwgGLCanvas`. The GL backend prefers
`IwgTextureSurface` and uses it with no upload at all; otherwise it uploads through
`IwgPixelSurface` and caches the result. The software backend always takes the
`IwgPixelSurface` route, and skips a surface that offers only a GPU handle.

`IwgSurface.Format` distinguishes `sfARGB32` from `sfA8` — one byte of coverage per
pixel, no colour. That is what a glyph atlas page is, and putting it on `IwgSurface`
rather than only on the GPU-side interface is precisely what lets one FreeType
atlas feed both backends.

**`Generation`** is the cache key: process-wide, monotonic, bumped on every
content change, never reused. That is what lets the texture cache re-upload only
when pixels actually changed — and why a stale cache entry can never look
current. Mutate a surface behind the canvas's back (a `PutPixel` loop, or writes
through a locked pointer) and you must call `Changed` yourself.

**Lifetime**: these interfaces do *not* own their implementor. Following the
convention `wayland_core` established for protocol objects, implementors derive
from `TInterfacedObject` but make `_AddRef`/`_Release` no-ops. Holding an
`IwgSurface` neither keeps the object alive nor frees it at scope exit; surfaces are
freed explicitly by whoever created them.

## Text

`TwgGlyphAtlas` is an `IwgGlyphSource`: one font face at one pixel size, rasterising
glyphs on demand into coverage (`sfA8`) **CPU** pages. The canvas does layout
only — glyph lookup, kerning, newlines — and emits one textured quad per glyph,
so a whole run in one atlas page is a single draw call. Bold, italic and other
sizes are separate `TwgGlyphAtlas` instances.

Pages are CPU surfaces rather than GPU textures on purpose: the GL canvas picks
them up through its ordinary `IwgPixelSurface` cache (seeing `sfA8`, it allocates an
R8 texture) and the software canvas samples the same bytes directly, so neither
contains a line of atlas-specific code. The cost is that rasterising a new glyph
bumps the page's generation and re-uploads the whole page to the GPU; that
converges quickly, since glyphs are cached and steady-state text uploads nothing.

Packing is a shelf allocator, near-optimal for one font at one size. When a page
fills, a new larger page is allocated and glyphs already handed out keep pointing
at the old one, which stays alive — so a `TwgGlyphInfo` never dangles. Nothing is
evicted; a text editor cycling through thousands of CJK glyphs would want an LRU
instead.

`freetype_fpc` is a hand-written subset binding. Its record layouts were verified
field-by-field against the installed headers — note that `FT_Pos`/`FT_Long`/
`FT_Fixed` are C `signed long` (64-bit on LP64), so they are `clong`, not
`LongInt`, which would silently shift every following field.

## Presentation

There is no Wayland EGL platform and no `libwayland`. `TwgGLContext` creates
an `EGL_PLATFORM_SURFACELESS_MESA` display; frames are rendered into FBOs whose
textures are exported as dmabuf file descriptors via
`EGL_MESA_image_dma_buf_export`. `TwgGLTargetRing` holds several such targets so a
client never draws into the buffer the compositor is still displaying.

`wayland-gl` deliberately stops at file descriptors: it hands back an fd, stride,
offset, DRM fourcc and modifier, and turning those into a `wl_buffer` through
`zwp_linux_dmabuf_v1` is the caller's job. That is what keeps the module free of
any dependency on the generated protocol tiers.

**FD ownership**: each target owns its exported fd and closes it on `Free`. A
caller passing it to `zwp_linux_dmabuf_v1` is only *lending* it — the protocol
dups what it needs — so do not close it yourself.

Check `TwgGLContext.CanExportDmabuf` before relying on any of this; a driver
without the export extensions means falling back to shm.

## Example

```pascal
uses wlg.surface, wlg.canvas.base,
     wlg.gl.context, wlg.gl.target, wlg.canvas.gl,
     wlg.text.atlas;

lCtx    := TwgGLContext.Create(3, 3);
lRing   := TwgGLTargetRing.Create(lCtx, W, H, 2);   // dmabuf-exported
lCanvas := TwgGLCanvas.Create(lCtx, W, H, 2); // 2x supersampled
lFont   := TwgGlyphAtlas.Create('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 28);

// ... wrap each lRing[i].DmabufFd in a wl_buffer via zwp_linux_dmabuf_v1 ...

lSlot := lRing.Acquire;                // a target the compositor isn't holding
lCanvas.SetTarget(lRing[lSlot]);
lCanvas.BeginFrame;
try
  lCanvas.Clear(wgARGB(255, 20, 24, 34));
  lCanvas.FillRoundRect(20, 20, 200, 120, 14, 14, wgARGB(255, 50, 60, 90));
  lCanvas.LineWidth := 3;
  lCanvas.Circle(300, 80, 50, wgARGB(255, 255, 255, 255));

  lCanvas.Save;                        // transforms nest
  lCanvas.Translate(400, 90);
  lCanvas.Rotate(lAngle);
  lCanvas.FillPolygon(lStar, wgARGB(235, 255, 205, 90));
  lCanvas.Restore;

  lCanvas.DrawSurface(lImage, 20, 200, 96, 96);   // scaled blit
  lCanvas.Font := lFont;
  lCanvas.DrawTextTopLeft('Hello, Wayland!', 20, 320, wgARGB(255, 240, 240, 240));
finally
  lCanvas.EndFrame;                    // resolves the supersample buffer, glFinish
end;
// attach lRing[lSlot]'s wl_buffer, damage, commit; lRing.MarkBusy(lSlot)
```

See the `gl_canvas_demo` [example](../wayland-examples/README.md) for the whole
loop, including `wl_buffer.release` tracking and `wl_surface.frame` pacing. Build
it with `make examples`.
