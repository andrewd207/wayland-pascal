# wayland-examples

Standalone example programs for the pure-Pascal Wayland binding (`wayland-rt` +
the protocol tiers) and the higher-level OOP layer (`wayland-classes`). Each
`.pas` is its own executable.

## Examples

| Example | What it shows | Needs |
|---|---|---|
| `wl_window_demo` | The canonical "use wayland-classes standalone": connect, open a toplevel (`TfpgwDisplay`/`TfpgwWindow`), paint on first configure, run the event loop, quit on close. | a Wayland compositor |
| `canvas_demo` | `TWaylandCanvas` drawing (rects, rounded rects, circles/ellipses, lines, a polygon) into an **shm** window buffer. | a Wayland compositor |
| `canvas_dmabuf` | The same canvas into a **CPU-mapped dma-buf** presented via `zwp_linux_dmabuf_v1` (LINEAR, ARGB8888) — shows the canvas is buffer-source agnostic. | `zwp_linux_dmabuf_v1` + `/dev/udmabuf` (usually the `kvm` group) |
| `cursor_demo` | Loads named cursors, paints them in a grid, and retargets the **live pointer** on hover; animated cursors (e.g. `watch`) cycle frames. Left-drag moves the window, right-click quits. | a Wayland compositor with a cursor theme |
| `themed_window` | A **client-side-decorated** window: title bar drawn from the desktop theme (`desktop_theme`), with rounded alpha corners. Working buttons (close/min/max), left-drag to move, right-click for the compositor's window menu. No title text (the canvas has no font). | a Wayland compositor; reads GNOME/KDE theme settings |
| `clipboard_test` | The `wl_data_device` clipboard path (out-of-band fd handling). `serve <text>` publishes a selection; `get` reads the current one. The core clipboard is focus-gated, so it opens a real window first. | a compositor; cross-check with `wl-copy`/`wl-paste` |
| `cursor_info` | Dumps the frames of a named cursor from an XCursor theme via the pure-Pascal loader. `cursor-info [theme] [name] [size]`. | nothing (no compositor; offline tool) |

## Building

These are **not** part of the default build. Build them all with the Makefile's
`examples` target (one executable each, into `wayland-examples/target/`):

```sh
make examples
```

pasbuild's application type builds only the module's `mainSource`
(`wl_window_demo`); the Makefile builds the rest. See the repository
[`README.md`](../README.md) for the overall layout.
