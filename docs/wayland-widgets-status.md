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
  wlg.widget.input            TwgInputRouter, IwgInputTarget, TwgKeyRepeat
  wlg.widget.gesture          TwgGestureRecogniser, pan, long-press
  wlg.widget.layout           box / grid / anchor
  wlg.widget.theme            TwgTheme, TwgDesktopTheme
  wlg.widget.controls         label, button, checkbox, radio, slider, panel,
                              spinner (the one continuous animation)
  wlg.widget.scroll           TwgScrollBox
  wlg.widget.text             TwgTextEdit (single line, UTF-8, clipboard)
  wlg.widget.window           TwgWindow, IwgPresenter, TwgShmPresenter,
                              IwgKeyTranslator, key repeat, clipboard host

wayland-client/widgets-gl/  [off by default] bridge
  wlg.widget.presenter.gl     TwgGLPresenter + wgUseGLPresenter

wayland-client/widgets-xkb/ [off by default] bridge
  wlg.widget.keyboard.xkb     TwgXkbTranslator + wgUseXkbKeyboard
                              (evdev codes + keymap fd -> keysyms and text)

wayland-client/classes/     gained wl_touch (was pointer + keyboard only)
```

Demo: `wayland-examples/gl_widget_demo`, software by default, `--gl` for the GPU
presenter, `--spin` to start the animation for benchmarking.

**The event loop is adaptive.** It blocks indefinitely when nothing is damaged
and nothing is animating, wakes on a deadline for the caret blink, and runs at
the compositor's frame rate while something is animating. Measured in a nested
weston, whole process:

| state | client CPU | compositor |
|---|---|---|
| idle | **0.0-0.1%** | 0.0-0.1% |
| spinner animating (software canvas) | **6.7%** | 2.0% |

The old figure of "190 fps" was the demo measuring itself: it rewrote a frame
counter into a label every loop iteration, which damaged the window every
iteration, and then reported the resulting repaint rate as a benchmark. That
cost **22.4% of a core to display a window doing nothing**. Do not reintroduce
a per-frame status update.

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
| Text entry: typing, UTF-8 stepping, selection, word moves, clipboard, password, max length, mouse | 33 |
| xkb translator against a real compiled keymap: the +8, shift levels, keysyms, repeat flags | 20 |
| Key repeat: delay then rate, key takeover, every stop path, no burst after a stall | 24 |
| Tick scheduler: deadlines, earliest wins, stop-by-not-asking, no dangling tick after Free | 16 |
| FreeType/fontconfig: aliases, weights, cache keying incl. HiDPI sharing | manual, confirmed |

Live on a compositor: nested weston screenshots for the canvas, the widget tree,
the controls with desktop theming, and the GPU path. Typing was confirmed live
too — a held key produced a run of repeated characters in the entry, which
exercises the whole chain (wl_keyboard -> xkb -> router -> TwgTextEdit) and
shows repeat both starting and stopping. That one was incidental rather than a
controlled test; there is no key injector here.

## What is NOT done

- **Touch is unexercised on real hardware.** The router's touch paths are
  covered by tests, but the `wl_touch` wire path in `fpg_wayland_classes` has
  never seen a real touchscreen — no touch device here and weston's nested
  backend will not synthesise one. It compiles and mirrors the pointer path
  exactly; treat it as unproven.
- **No pinch/rotate recognisers**, and `zwp_pointer_gestures_v1` (touchpad
  pinch/swipe/hold, which the compositor pre-disambiguates) is bound by nothing.
- **No `text-input-v3`, so no IME.** `TwgTextEdit` takes direct key input and
  handles XKB compose (dead keys), which covers Latin layouts; it does not
  speak to an input method, so CJK and friends cannot be typed.
- **No multi-line text.** `TwgTextEdit` is one line by design — wrapping, a
  line index, and up/down with a remembered goal column are enough of a
  different model to want a second widget rather than a flag.
- **No undo** in the text entry.
- **No accessibility**, no UI designer, no `.lfm`-style streaming (the
  `TComponent` base leaves room for it).
- `TwgGridLayout` has no row/column spans.
- The scroll bar is drawn, but there is no dragging it — it is an indicator, not
  a control. Wheel and drag-to-scroll are the ways to move the content.

## Constraints worth remembering

- **Asking a seat for a device it does not advertise crashes GNOME.**
  `get_pointer`/`get_keyboard`/`get_touch` are a protocol violation unless the
  capability is (or has been) present, and gnome-shell 46 answers with SIGSEGV
  rather than the error — so a client bug takes the whole session down. Create
  seat devices only from `wl_seat.capabilities`.
- **Test compositor-facing changes against NESTED gnome-shell**, not only
  weston: `dbus-run-session -- gnome-shell --nested --wayland --wayland-display
  wl-nested`. weston's seat advertises touch and is generally more forgiving,
  which is exactly why the above went unnoticed. (In any script driving it,
  write the pgrep/pkill pattern as `[g]nome-shell` — a plain one matches the
  script's own command line and kills the harness.)
- **Bind versions cost features, silently.** `wl_seat` was bound at version 1,
  which meant `wl_keyboard.repeat_info` (version 4) never arrived and key
  repeat could not work at all — no error, just a compositor that never
  mentions the rate. It now binds `Min(AVersion, 9)`. `wl_compositor` is still
  at 1; see below.
- **Never treat "damage pending" as "draw now".** The loop must sleep whenever
  the presenter has no buffer (`FStalled`), including when an animation frame
  is already due: the buffer release that unblocks it is a compositor event and
  wakes the poll anyway. Without that the wait for a buffer becomes a busy loop
  at 100% of a core — and it looks exactly like a runaway animation.
- **`RequestTick(0)` means "next frame", and the COMPOSITOR sets that rate.**
  Do not hard-code 16ms as a power saving: on a 100Hz display that caps a
  smooth animation at 62fps and saved nothing measurable here (12.1% vs 13.0%).
  `TwgSpinner.IntervalMs` exists for deliberate throttling.
- **XKB keycode = evdev code + 8.** Nothing in the wl_keyboard documentation
  says so, and getting it wrong produces plausible wrong letters rather than an
  error.
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

## Where the animating time goes

Profiled with `perf` (`-g -gw3` build, nested weston). A spinner damaging a
32x32 rectangle was costing 12.7%, which is far more than the area suggests.
The profile said 75% in `RasterTriangle` and 11% in `Frac`, and instrumenting
the rasteriser explained why: **47 triangles per frame, 20213 pixels tested,
3572 actually shaded**. Thin diagonal geometry — a stroked arc is exactly that
— covers very little of its own bounding box, and the rasteriser scanned the
box.

Two fixes, output byte-identical (verified by rendering the comparison scene
before and after):

- Per-row spans instead of the bounding box. Each edge is linear in x, so the
  inside region on a row is an interval; intersecting the three gives the span.
  The span is computed conservatively and the exact per-pixel test is
  unchanged, so the top-left rule still decides coverage — this only skips
  pixels that would have been rejected.
- Integer floor/ceil on Single instead of `Math.Floor`/`Ceil`, which take an
  Extended and route through `Frac`. That is per triangle, and a stroked arc is
  thousands of them.

Result 12.7% -> 6.7%. `RasterTriangle` is still ~76% of what remains; the next
step would be incremental edge functions (accumulate `w += dw/dx` instead of
recomputing), but that introduces float drift into the exact `= 0` comparisons
the top-left rule depends on, so it trades a seam risk for speed and has not
been done.

## Debugging damage

`-dWG_TRACE_RASTER` counts triangles, pixel tests and shaded pixels in the
software canvas — the numbers above came from it.

`-dWG_TRACE_DAMAGE` adds counters to the widget core and window: how many
invalidations happened and **which widget classes asked for them**
(`wgInvalidateReport`), plus layout invalidations, tick runs and the stalled
flag. That is what identified a repaint loop that three rounds of reading the
code had misdiagnosed.

## Naming

`Twg` / `Iwg` / `Ewg` types, dotted `wlg.*` units. Principle: prefix what we
author; leave generated code (the Wayland binding — byte-diff is the regen
oracle), the already-consistent `Tfpgw*` classes layer, and C-library bindings
named after their library (`egl_fpc`, `gl_fpc`, `freetype_fpc`,
`fontconfig_fpc`) alone.

## Plausible next steps

1. `text-input-v3`, so an input method can drive `TwgTextEdit` (IME, CJK).
2. Raise the `wl_compositor` bind version in `classes` and switch to
   `damage_buffer`; needed for fractional scaling anyway.
3. Pinch/rotate, plus `zwp_pointer_gestures_v1` for touchpads.
4. Real touchscreen validation.
