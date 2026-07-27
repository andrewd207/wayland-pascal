# Widget toolkit — roadmap

What exists is in [`wayland-widgets-status.md`](wayland-widgets-status.md). This
is what is planned, in what order, and the reasoning behind the shape.

The organising principle: **most of these widgets are cheap once the thing they
need exists.** A combo box is a list in a popup; a tooltip is a label in a
popup; a menu is a list of buttons in a popup. Build the popup and three
widgets fall out. So the ordering below is by infrastructure, not by widget.

## Inheritance tree

```
TwgWidget                       geometry, tree, paint, damage, ticks
│
├─ TwgControl                   theme + caption + IwgInputTarget defaults
│  │
│  ├─ TwgLabel                  DONE
│  ├─ TwgImageView              draws an IwgSurface; fit/fill/centre/tile
│  ├─ TwgSeparator              a themed rule
│  ├─ TwgProgressBar            determinate; TwgSpinner is the indeterminate one
│  ├─ TwgSpinner                DONE
│  │
│  ├─ TwgButtonBase             press state, Space/Enter activate, repeat-on-hold
│  │  ├─ TwgButton              DONE (to be re-based)
│  │  ├─ TwgToggleButton        stays down
│  │  ├─ TwgToolButton          icon-first, flat until hovered
│  │  └─ TwgMenuButton          opens a popup
│  │
│  ├─ TwgCheckBox               DONE
│  │  └─ TwgRadioButton         DONE
│  │
│  ├─ TwgTrackControl           track + thumb, drag with capture, keyboard step
│  │  ├─ TwgSlider              DONE (to be re-based)
│  │  └─ TwgScrollBar           thumb sized by viewport/content ratio
│  │
│  ├─ TwgTextBase               caret, selection anchor, clipboard, blink
│  │  ├─ TwgTextEdit            DONE (to be re-based) — single line
│  │  │  └─ TwgNumberEdit       numeric constraint + step buttons
│  │  └─ TwgTextMemo            multi-line: line index, goal column, v-scroll
│  │
│  ├─ TwgItemView               VIRTUALISED: item count + paint callback
│  │  ├─ TwgListBox             selection model, type-ahead
│  │  ├─ TwgTreeView            expand/collapse over a flattened index
│  │  └─ TwgTableView           columns, header, resize/sort
│  │
│  ├─ TwgScrollBox              DONE — gains real TwgScrollBars
│  │
│  ├─ TwgPanel                  DONE — the container
│  │  ├─ TwgGroupBox            titled frame
│  │  ├─ TwgToolBar             + overflow when it does not fit
│  │  ├─ TwgStatusBar           sections, size grip
│  │  ├─ TwgSplitPanel          two children + a draggable splitter
│  │  └─ TwgTabPanel            tab strip + page stack
│  │
│  ├─ TwgDecoration             client-side title bar: caption, buttons,
│  │                            drag-to-move, edge resize, window menu
│  └─ TwgPopup                  escapes clipping, grabs input, closes on Esc
│     ├─ TwgMenu                items, submenus, accelerators, keyboard nav
│     ├─ TwgTooltip             hover-delay driven by the tick scheduler
│     └─ (a TwgListBox in a popup is the combo box's dropdown)
│
└─ (composed, not inherited)
   TwgComboBox    = TwgTextEdit/TwgLabel + TwgButton + popup list
   TwgSearchEdit  = TwgTextEdit + a clear button
   TwgDialog      = a TwgWindow with a modal focus scope
```

Three new intermediate bases, each because the alternative is duplicated code:

- **`TwgButtonBase`** — five widgets activate identically (click, Space, Enter,
  press state, optional repeat-on-hold).
- **`TwgTrackControl`** — a scroll bar is a slider with a proportional thumb.
  The drag-past-the-edge-with-capture logic is already written once in
  `TwgSlider` and should not be written twice.
- **`TwgTextBase`** — caret, selection anchor, clipboard and blink are ~200
  lines that single-line and multi-line both need.

Note what is NOT inherited. A combo box is not a text edit with a list bolted
on; it owns one. Inheriting would drag the whole editing surface into a widget
that is usually read-only.

## Infrastructure, in dependency order

| Needed | Unblocks |
|---|---|
| **Popups** (below) | menu, combo, tooltip, context menu, date picker |
| **Virtualised items** | list, tree, table |
| **Selection model** | every item view |
| **Modality + focus scope** | dialogs, popups |
| **Cursor per widget** | I-beam over text, resize over a splitter |
| **Accelerators / mnemonics** | menus, Alt+letter |
| **Drag and drop** | trees, tabs, lists; then `wl_data_device` |

The tick scheduler already covers tooltip hover delays and scroll-bar
press-repeat, so those come free.

## Popups: BOTH backends, chosen at runtime

A popup is the one thing the one-surface design cannot express, and there are
two ways out. This toolkit implements **both**, behind one `TwgPopup` API, and
picks per-popup at the moment it opens.

**Overlay** — the content is parented into an overlay layer inside the existing
window, painted after everything else and hit-tested before it. No new
compositor objects, no configure round trip, no protocol at all. It cannot
extend past the window edge.

**`xdg_popup`** — a real `wl_surface` with its own buffers, positioned by the
compositor relative to an anchor rectangle. It can extend anywhere on screen,
the compositor may flip or slide it to keep it on the output, and it can take a
real input grab. It costs a surface, a buffer pair and a configure round trip.

**The choice is made at runtime, by fit.** When the popup's anchored rectangle
lies entirely within the window's client area, the overlay is used, because it
is free. When it does not — a combo near the bottom edge, a menu near the right
edge, a tooltip at the window border — an `xdg_popup` is used, because the
overlay would clip it and a clipped menu is a broken menu. The same rule
applies to tooltips.

This is deliberately not a global setting. The right answer genuinely differs
per popup and per window position, and it is cheap to decide: measure the
content, anchor it, intersect with the client area.

The classes layer already supports popup surfaces — `TfpgwWindow` takes an
`APopupFor` parent with a grab serial, and reports the compositor's chosen
position through `OnPopupConfigure` — so the surface backend is mostly wiring
rather than new protocol work.

Two things the surface backend forces, both worth having anyway:

- **Input handler chaining.** Seat handlers on `TfpgwDisplay` are single slots,
  and every `TwgWindow` currently overwrites them and then ignores events that
  are not its own. With one window that works. With a popup surface the second
  window silently receives nothing. Needs a display-level registry dispatching
  by `Sender`.
- **Child window pumping.** A popup window has its own damage, presenter and
  tick deadlines. The parent's `ProcessFrame` and `WaitTimeout` have to include
  its children, or the popup never paints and the loop sleeps through its
  animations.

## Window decoration

**GNOME does not implement server-side decorations for xdg-toplevel.** The demo
asks for them and the request is simply not honoured, so on mutter our windows
have no title bar, no close button and no drag-to-move at all — the toolkit is
relying on a decoration that is never going to arrive. That makes a client-side
decorator not a nicety but the difference between a window a user can move and
one they cannot.

`TwgDecoration` is a widget like any other, wrapped around the content:

```
TwgWindow
  Root
    TwgDecoration        title bar + resize borders, drawn from the theme
      <application content>
```

It needs, in rough order:

- caption, icon and the close/minimise/maximise buttons;
- **drag to move** (`xdg_toplevel.move`) and **edge resize**
  (`xdg_toplevel.resize`) — both are compositor requests, so the decorator
  hands the gesture straight over rather than moving anything itself;
- right-click for the compositor's window menu (`show_window_menu`);
- rounded corners with an alpha edge, which needs the surface to be
  non-opaque, and a shadow if we want to match GNOME;
- honouring `xdg_toplevel.configure` states — a maximised window has square
  corners and no drag-to-move.

The existing `themed_window` example already does most of this by hand against
`desktop_theme`; the work is largely moving it into a widget and driving it
from the theme rather than from literals.

It must be OPTIONAL and negotiated: when a compositor does support
`zxdg_decoration_manager_v1` and chooses server-side, the decorator has to
stay out of the way, or the window gets two title bars.

## Build order

1. **`TwgTrackControl` + `TwgScrollBar`** — completes `TwgScrollBox`, which
   today draws a bar you cannot drag. Self-contained.
2. **`TwgProgressBar`, `TwgSeparator`, `TwgGroupBox`, `TwgImageView`** — no new
   concepts, and they are what make a real form buildable.
3. **`TwgButtonBase`** + toggle/tool buttons + `TwgToolBar`.
4. **Popups**: overlay layer, `TwgPopup`, the fit rule, then the `xdg_popup`
   backend (with input chaining and child pumping). DONE except that surface
   popups are placed at the parent's origin instead of at the anchor — see the
   status document. Then `TwgMenu`, `TwgComboBox`.
5. **`TwgDecoration`**, because on GNOME there is otherwise no title bar at
   all.
6. **`TwgItemView` → `TwgListBox`**, then `TwgTreeView`, `TwgTableView`.
7. **`TwgTextBase` refactor + `TwgTextMemo`**; `TwgSplitPanel`, `TwgTabPanel`,
   `TwgDialog`.

## Open questions

- **Accessibility** has no plan at all. AT-SPI is D-Bus rather than Wayland, so
  it is a separate axis; deciding late usually means retrofitting a tree that
  was not designed to be walked.
- **`text-input-v3`** is still absent, so no IME. `TwgTextMemo` makes that gap
  more visible, not less.
- **Theming beyond the desktop palette** — no way yet to restyle a single
  control without subclassing it.
