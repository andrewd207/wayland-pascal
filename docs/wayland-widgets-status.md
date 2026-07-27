# Widget toolkit — status

Everything below is on `main` and pushed. `make && make examples` is clean, and
`pasbuild compile -m <module>` succeeds for every module.

## What exists

```
wayland-client/rt/          RTL-ONLY. Complete drawing stack with no C library:
  wlg.surface                 IwgSurface / IwgPixelSurface / IwgTextureSurface,
                              TwgImage, TwgAlphaImage, TwgColor, sfARGB32/sfA8
  wlg.canvas.base             TwgCanvas — the whole API + all tessellation
  wlg.canvas.software         TwgSoftCanvas — CPU backend (half-space rasteriser)
  wlg.canvas.raster           the old integer/replace pixel canvas (unrelated)

wayland-client/text/        [off by default] libfreetype + libfontconfig
  freetype_fpc, fontconfig_fpc
  wlg.text.atlas              TwgGlyphAtlas -> sfA8 CPU pages (serves BOTH backends)
  wlg.text.fontcache          ("Sans", 11pt, bold, scale) -> IwgGlyphSource

wayland-client/gl/          [off by default] libEGL + libGL
  wlg.gl.context/texture/target, wlg.canvas.gl (TwgGLCanvas)

wayland-client/widgets/     [off by default] RTL-only
  wlg.widget.types            events (multi-pointer), layout hints, keysyms
  wlg.widget.core             TwgWidget, TwgLayout base, TwgDamage
  wlg.widget.input            TwgInputRouter, IwgInputTarget
  wlg.widget.gesture          TwgGestureRecogniser, pan, long-press
  wlg.widget.layout           box / grid / anchor
  wlg.widget.theme            TwgTheme, TwgDesktopTheme
  wlg.widget.controls         label, button, checkbox, radio, slider, panel
  wlg.widget.scroll           TwgScrollBox
  wlg.widget.window           TwgWindow, IwgPresenter, TwgShmPresenter

wayland-client/widgets-gl/  [off by default] bridge
  wlg.widget.presenter.gl     TwgGLPresenter + wgUseGLPresenter

wayland-client/classes/     gained wl_touch (was pointer + keyboard only)
```

Demo: `wayland-examples/gl_widget_demo`, software by default, `--gl` for the GPU
presenter. Software ~190 fps, GL ~263 fps (paced).

## Verified

Headless harnesses, all passing:

| What | Assertions |
|---|---|
| Both canvas backends render one scene identically | 1.1% of pixels differ, all AA edge detail |
| Widget core: tree, clipping, coords, per-buffer damage, partial repaint | backends agree 0.00% |
| Input router: capture, chain enter/leave, multi-touch, focus, cancel | 28 |
| Layouts: box weights, margins, hidden, grid, anchors, resize deltas | 25 |
| Gesture claim/cancel handshake | 15 |
| Scroll box in a real layout: sizing, overflow, clipping, wheel, drag-vs-click, coast | 18 |
| FreeType/fontconfig: aliases, weights, cache keying incl. HiDPI sharing | manual, confirmed |

Live on a compositor: nested weston screenshots for the canvas, the widget tree,
the controls with desktop theming, and the GPU path.

## What is NOT done

- **Touch is unexercised on real hardware.** The router's touch paths are
  covered by tests, but the `wl_touch` wire path in `fpg_wayland_classes` has
  never seen a real touchscreen — no touch device here and weston's nested
  backend will not synthesise one. It compiles and mirrors the pointer path
  exactly; treat it as unproven.
- **No pinch/rotate recognisers**, and `zwp_pointer_gestures_v1` (touchpad
  pinch/swipe/hold, which the compositor pre-disambiguates) is bound by nothing.
- **No text input widget**, so no `text-input-v3`, no IME, no caret.
- **No accessibility**, no UI designer, no `.lfm`-style streaming (the
  `TComponent` base leaves room for it).
- `TwgGridLayout` has no row/column spans.
- The scroll bar is drawn, but there is no dragging it — it is an indicator, not
  a control. Wheel and drag-to-scroll are the ways to move the content.

## Constraints worth remembering

- **`wl_compositor` is bound at version 1** by the classes layer. Anything above
  v1 is a protocol error — notably `wl_surface.damage_buffer` (needs v4), which
  fails as a baffling "stream write error" when the compositor disconnects. Use
  `Damage`. Raising the bind version is a `classes` change nobody has made yet.
- **Buffer release is backpressure, not a clock.** Anything presenting directly
  must request `wl_surface.frame` or it free-runs (measured 4751 fps).
- **Stale `.ppu` files** across the `wlg.*` rename make fpc die with
  "Compilation raised exception internally". `make clean` first.
- **The root widget needs a layout**, or nothing below it is ever given bounds.
- A weight-0 child of a type reporting no intrinsic size collapses to nothing —
  correct, but wants a `MinHeight` hint.
- **A control with a layout measures its content, not its caption.** `TwgPanel`
  used to inherit the caption measurement, so a panel asked for its intrinsic
  size reported one control's worth. It never mattered while every panel had a
  weight; the scroll box's content is the first thing that asks.
- `pasbuild compile --all` fails on `wayland-common`, which is documented as not
  standalone-buildable. Pre-existing, not a regression.

## Naming

`Twg` / `Iwg` / `Ewg` types, dotted `wlg.*` units. Principle: prefix what we
author; leave generated code (the Wayland binding — byte-diff is the regen
oracle), the already-consistent `Tfpgw*` classes layer, and C-library bindings
named after their library (`egl_fpc`, `gl_fpc`, `freetype_fpc`,
`fontconfig_fpc`) alone.

## Plausible next steps

1. A text entry widget (caret, selection, clipboard), then `text-input-v3`.
2. Raise the `wl_compositor` bind version in `classes` and switch to
   `damage_buffer`; needed for fractional scaling anyway.
3. Pinch/rotate, plus `zwp_pointer_gestures_v1` for touchpads.
4. Real touchscreen validation.
