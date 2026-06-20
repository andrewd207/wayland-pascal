# wayland-classes

A convenience wrapper around the Wayland protocols (the pure-Pascal binding in
`wayland-rt` + the protocol tiers), with some niceties that make them friendlier
to use: a display/event loop, double-buffered windows, shell roles, a cursor
loader, a software canvas, and clipboard/drag-and-drop helpers. RTL-only; named
after fpGUI's Wayland backend (the `fpgw` prefix) but usable on its own.

The single unit is `src/main/pascal/fpg_wayland_classes.pas`.

## Documentation

Full API docs for the `Tfpgw*` classes live in
[`docs/wayland-classes/`](../../docs/wayland-classes/index.md) — an overview + quick
start plus one page per class:

- [`TfpgwDisplay`](../../docs/wayland-classes/TfpgwDisplay.md) — connection + event loop
- [`TfpgwWindow`](../../docs/wayland-classes/TfpgwWindow.md) — surface + double-buffering
- [`TfpgwShellSurfaceCommon`](../../docs/wayland-classes/TfpgwShellSurfaceCommon.md) — shell role (title, move, decorations…)
- [`TfpgwBuffer`](../../docs/wayland-classes/TfpgwBuffer.md) — pixel buffers + `TWaylandCanvas`
- [`TfpgwCursor`](../../docs/wayland-classes/TfpgwCursor.md) — pointer cursor
- [`TfpgwDataOffer`](../../docs/wayland-classes/TfpgwDataOffer.md) / [`TfpgwDataSource`](../../docs/wayland-classes/TfpgwDataSource.md) — clipboard / drag-and-drop
- [event reference](../../docs/wayland-classes/events.md)

See the [examples](../../wayland-examples/README.md) (`wl_window_demo`,
`canvas_demo`, `cursor_demo`, `clipboard_test`, …) for working programs.
