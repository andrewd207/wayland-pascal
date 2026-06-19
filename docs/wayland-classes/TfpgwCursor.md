# TfpgwCursor

The pointer cursor. Resolves named cursors from an XCursor theme (via a
pure-Pascal loader — no libXcursor) and drives frame animation. It is created
automatically by `TfpgwDisplay`; you usually drive it through the display rather
than touching this class directly.

← back to [index](index.md)

## Usage (via TfpgwDisplay)

```pascal
Display.SetCursorTheme('Adwaita', 24);          // optional; '' + <=0 = defaults (24)
Display.SetCursor(['hand2', 'pointing_hand']);  // first candidate that resolves wins
```

- `SetCursor` takes a list of candidate names because themes vary; the first one
  found in the theme chain is used.
- Animated cursors (e.g. `watch`) cycle their frames automatically while the
  pointer is over your surface — `Display.WaitEvent` advances the timing using
  each frame's authored delay.

## The class

```pascal
constructor Create(ADisplay: TfpgwDisplay; AThemeName: String; ADesiredSize: Integer);
procedure   SetCursor(ANames: array of String);
procedure   Tick;                 // advance animation; called from the event loop
property    Surface: TWlSurface;  // the dedicated cursor surface
```

Internally it caches one shm buffer per frame per cursor name, sets the pointer
to its surface once (`wl_pointer.set_cursor`), then re-attaches successive frames
on `Tick`.

The `cursor_demo` example builds a grid of cursors and retargets the live pointer
on hover (animated cursors animate both in the grid and on the pointer);
`cursor_info` dumps a cursor's frames offline (no compositor needed).
