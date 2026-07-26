# Widget core — design

A retained widget toolkit drawing through `TwgCanvas`, so it runs on
the GPU (`TwgGLCanvas`) or the CPU (`TwgSoftCanvas`) unchanged.

New module `wayland-widgets/`, top level, `activeByDefault="false"` — the same
precedent as `wayland-gl`, so the repo stays adoptable as a plain Wayland
binding and later extraction to its own repo is a `moduleDependencies` →
`dependencies` swap.

## What it sits on

| Layer | Provides |
|---|---|
| `wayland-classes` | `TfpgwDisplay` (event loop, seat input), `TfpgwWindow` (xdg surface, double buffering, configure/paint/close), `TfpgwBuffer` (`Data`/`Stride`), `desktop_theme` |
| `wayland-rt` | `TwgCanvas` + `TwgSoftCanvas`, `IwgSurface` |
| `wayland-text` | `TwgGlyphAtlas` as `IwgGlyphSource` |
| `wayland-gl` | `TwgGLCanvas` (optional) |

Note how input arrives: it is **seat-level**, on `TfpgwDisplay`, not per window —
`OnMouseButton`, `OnMouseMotion`, `OnKeyboardKey` and friends. The display
already tracks which window has pointer/keyboard focus and dispatches with
`Sender = FActiveMouseWin.Owner`. So a `TWidgetWindow` makes itself the `Owner`
of its `TfpgwWindow`, and a single dispatcher installed on the display casts
`Sender` back to the right window. Multi-window falls out for free.

## Files

```
wayland_widget.pas          TWidget — tree, bounds, paint, invalidate, events
wayland_widget_types.pas    event records, layout hints, enums
wayland_layout.pas          TLayout + box / grid / anchor strategies
wayland_widget_theme.pas    TWidgetTheme — palette, metrics, primitive drawing
wayland_widget_window.pas   TWidgetWindow — binds window + canvas + root + loop
wayland_controls.pas        button, label, entry, checkbox, scrollbar, panel...
```

Font lookup deliberately does **not** live here. `fontconfig_fpc` (a subset
binding) and `wayland_font_cache` — `(family, size, weight, scale)` →
`IwgGlyphSource`, memoised — go in `wayland-text`, so anything drawing on a canvas
can resolve fonts by name without depending on the widget layer. That module
then links libfreetype *and* libfontconfig, which is the same class of
dependency and keeps them together.

## The tree

`TWidget = class(TComponent)`. `TComponent` for owner-based lifetime (a form
frees its children) and because it leaves the door open to `.lfm`-style
streaming and a UI designer later — which matters given fpGUI has one.

Careful: `TComponent.Owner` (lifetime) is **not** `TWidget.Parent` (visual
nesting). Keep both, and say so in the code, because conflating them is a
classic source of double-frees.

```pascal
property Parent: TWidget;         // visual nesting; setting it re-parents
property Children[i]: TWidget;
property Left, Top, Width, Height: Integer;   // parent coordinates
property Visible, Enabled: Boolean;
property ClipChildren: Boolean;               // default True
```

Bounds are **integer logical pixels**. Integers because widgets want pixel
alignment and float bounds invite seams; logical because of the next point.

## HiDPI comes free

Widget coordinates are logical pixels. The root applies `Canvas.Scale(factor)`
before painting, where the factor is the output scale (or a fractional scale).
Because the canvas is resolution-independent — float geometry, supersampled AA,
glyphs rasterised at the *device* pixel size — everything is crisp with no
per-widget scaling code. This is the main structural payoff of having built the
canvas first, and it is worth not squandering by letting device pixels leak into
widget code.

The one thing that must follow the scale is the font: the atlas is created at
`Round(pointSize * scale)` pixels and drawn through the scaled transform.

## Paint pass

```pascal
procedure Paint(ACanvas: TwgCanvas); virtual;   // self only
```

The core walks the tree; a widget never paints its own children:

```
Canvas.Save
Canvas.Translate(Left, Top)
if ClipChildren then Canvas.ClipRect(0, 0, Width, Height)
Paint(Canvas)                 // widget draws itself in local coordinates
for each visible child: recurse
Canvas.Restore
```

So `Paint` always works in local coordinates with (0,0) at its top-left, and
clipping/transform is handled once. Both already exist on the canvas.

## Damage

Full-window repaint every frame is the wrong default here: it is cheap on the
GPU but wasteful on the CPU backend and on battery, and Wayland wants precise
`damage_buffer` anyway.

```pascal
procedure Invalidate;                        // whole widget
procedure InvalidateRect(const R: TRect);    // local coordinates
```

Each maps to window coordinates and unions into the window's dirty region.

**Buffer age is the subtlety.** Windows are double buffered, so the buffer you
are about to paint is two frames stale — repainting only *this* frame's dirty
region would leave the previous frame's damage unrepaired in it. So dirty
regions accumulate **per buffer**: an invalidation adds to every buffer's
accumulator, and painting buffer *B* consumes and clears only *B*'s. Retrofitting
this later is painful, so it goes in from the start.

Painting a partial region means:

- clip the canvas to the dirty region;
- **do not** `Clear()` the whole canvas — each widget repaints its own
  background;
- pass the same region to `wl_surface.damage_buffer`.

Start with a single union rectangle per buffer. A rect *list* with coalescing is
a later optimisation and does not change the interface.

## Layout

Two-phase measure/arrange, as WPF and Android do, because it is the model that
handles intrinsic sizes — a label's width depends on its text — without
guessing:

```pascal
function  MeasureSize(AAvailW, AAvailH: Integer): TSize; virtual;
procedure ArrangeChildren; virtual;
```

Containers delegate both to a **layout strategy object**, so the model is not
baked into the widget hierarchy:

```pascal
TLayout = class
  function  Measure(AContainer: TWidget; AAvailW, AAvailH: Integer): TSize; virtual; abstract;
  procedure Arrange(AContainer: TWidget; const AClient: TRect); virtual; abstract;
end;
```

with `TBoxLayout` (direction, spacing, per-child weight), `TGridLayout`, and
`TAnchorLayout` (Delphi-style `Align`/`Anchors`) as implementations. Per-child
hints — margin, expand, alignment — live on the child in a small record, since
that is where users expect to set them.

Layout is invalidated separately from paint (`InvalidateLayout`), and runs at
most once per frame before painting.

## Input routing

One dispatcher installed on `TfpgwDisplay`, resolving `Sender` to a
`TWidgetWindow`, then per window:

- **Hit test** — deepest visible, enabled widget containing the point; walks
  children last-to-first so later siblings are on top.
- **Capture** — grab set on press and held until release, so a drag that leaves
  the widget still tracks. Without this, sliders and scrollbars are broken; it
  is not optional. Capture is keyed **per sequence id**, not global: two fingers
  on two different widgets must each keep their own grab, and a single global
  capture silently breaks multi-touch.
- **Enter/leave** — computed against the previous hit chain, so the whole
  ancestor path gets consistent enter/leave, not just the leaf.
- **Click synthesis** — press and release on the same widget.
- **Focus** — per window; `Tab`/`Shift+Tab` traversal in tree order (with an
  optional explicit `TabOrder`); `FocusIn`/`FocusOut`.
- **Keyboard** — delivered to the focused widget and bubbling to ancestors,
  with modifiers from the existing `xkb_classes` state.

Events are records passed by `var` with a `Handled` flag, bubbling until set:

```pascal
TWidgetMouseEvent = record
  X, Y: Integer;                 // widget-local
  Button: LongWord;
  Modifiers: TWidgetModifiers;
  Time: LongWord;
  Handled: Boolean;
end;
```

## Touch and gestures

The protocol side is available but **not yet wired**: `TWlTouch` is in the
generated core binding and `pointer_gestures_unstable_v1` and `tablet_v2` are in
the protocol tiers, but `fpg_wayland_classes` currently handles only pointer and
keyboard. Adding `wl_touch` to the classes layer — which is where the seat lives
— is a prerequisite for any of this, and is the honest first task of the input
work rather than something the widget layer should bind behind its back.

What the design has to get right up front, because these are the parts that are
expensive to retrofit:

- **Multi-pointer routing and per-sequence capture**, as above.
- **No hover on touch.** A finger has no position until it touches. Nothing
  essential may be reachable only via enter/leave — hover is decoration, never
  the sole affordance. Widgets get `Hovered` but must not depend on it.
- **Hit-target metrics belong to the theme.** A finger needs roughly 9mm; a
  mouse needs 2mm. `TwgMetrics` carries a minimum touch target that grows when
  the last input was touch, so controls stay usable without a separate layout.

Gestures come from two places and both feed one recogniser layer:

- **Synthesised from `wl_touch`** — tap, double-tap, long-press, pan, pinch,
  rotate, swipe/fling. This is where a tablet's gestures come from.
- **Native `zwp_pointer_gestures_v1`** — pinch, swipe and hold, which
  compositors report for *touchpads*. Worth using rather than synthesising,
  since the compositor has already done the finger-count disambiguation.

A recogniser is attached to a widget and observes the raw stream before normal
routing, claiming the sequence when it recognises:

```pascal
TwgGestureRecogniser = class
  function  Feed(const AEvent: TwgPointerEvent): TwgGestureState; virtual; abstract;
  // trPossible -> trRecognised claims the sequence and cancels the widget's
  // ordinary press/click handling, exactly as a scroll view must steal a drag
  // that began as a press on a button inside it.
end;
```

That claim/cancel handshake is the part worth designing now: without it, a
scrollable list containing buttons cannot work, because the button consumes the
press before the pan is recognised.

Kinetic (flick) scrolling belongs with the pan recogniser, not in each scrollable
widget.

## Theming

Widgets never hardcode colours or draw their own chrome — they ask a theme, so a
restyle is one class:

```pascal
TWidgetTheme = class
  Palette: TWidgetPalette;      // window, surface, text, accent, disabled...
  Metrics: TWidgetMetrics;      // padding, corner radius, border, min sizes
  procedure DrawButton(C: TwgCanvas; const R: TRect; AState: TWidgetState);
  procedure DrawEntry(...);  procedure DrawFrame(...);  procedure DrawFocusRing(...);
  function  DefaultFont: IwgGlyphSource;
end;
```

The default theme seeds its palette and font name from the existing
`desktop_theme` unit, which already reads GNOME/KDE settings — so the toolkit
looks native-ish on day one instead of shipping an invented palette.

## Backend selection

Explicit, not magic:

```pascal
Win := TWidgetWindow.CreateSoftware(Display, 'Title', 800, 600);
Win := TWidgetWindow.CreateGL(Display, 'Title', 800, 600);   // gl bridge unit
```

The widgets module depends on `rt` only, so the software path always works. The
GL constructor lives in a small bridge so that pulling in libEGL/libGL is a
deliberate act by the application, not a transitive surprise. An auto-detecting
helper (try GL, fall back) can sit on top later.

## Decisions taken

1. **Font family resolution: bind libfontconfig.** A subset binding
   (`FcInitLoadConfigAndFonts`, `FcPatternBuild`, `FcConfigSubstitute`,
   `FcFontMatch`, `FcPatternGetString`) in `wayland-text`. It gets real
   family/style/weight matching, honours the user's own fontconfig setup, and
   resolves generic aliases like `Sans` and `Monospace` — none of which a
   built-in path table can do correctly. `fc-match` as a subprocess was the
   cheap alternative but pays a fork per font and degrades silently when the CLI
   is absent.
2. **Base class: `TComponent`**, for owner-based lifetime and future streaming.
3. **Layout: box + grid + `Align`/`Anchors`.** The composable strategies for new
   code, and the Delphi-familiar model both to ease porting existing UI and to
   let simple forms skip layout objects entirely. All three are `TLayout`
   implementations, so they cost nothing structurally.

## Build order

1. `fontconfig_fpc` + `wayland_font_cache` in `wayland-text` — small, isolated,
   independently testable, and everything visual needs text.
2. `TWidget` + the paint pass + per-buffer damage + `TWidgetWindow`, with a
   throwaway coloured-rectangle widget to prove the loop on both backends.
3. Input routing: hit test, capture, enter/leave, focus, keyboard.
4. `TLayout` and the three strategies.
5. `TWidgetTheme` seeded from `desktop_theme`.
6. Controls, once 1–5 hold up.

## Deliberately out of scope for the core

Accessibility, input methods (`text-input-v3`), and a UI designer. None are
precluded — the retained tree and `TComponent` base are what keep them possible
— but none belong in the first cut.
