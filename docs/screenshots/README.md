# Screenshots

Images used by the root README's Screenshots section.

| File | Shows |
|---|---|
| `wl_window_demo.png` | `wl_window_demo` — a basic toplevel (solid fill) |
| `canvas_demo.png` | `canvas_demo` — `TWaylandCanvas` shapes in an shm buffer |
| `canvas_dmabuf.png` | `canvas_dmabuf` — the canvas in a CPU dma-buf |
| `cursor_demo.png` | `cursor_demo` — the cursor grid (the highlighted cell is the hovered one) |
| `themed_window.png` | `themed_window` — themed CSD title bar with rounded alpha corners (close button shown hovered) |

These are **offline renders of exactly what each example draws** — produced by
running the same `TWaylandCanvas` (and `xcursor`) code into a memory buffer and
saving it as PNG — not compositor captures. That's deliberate: GNOME/mutter
doesn't implement `wlr-screencopy`, so `grim` can't grab native Wayland windows
here, and a render is clean (no desktop clutter or decoration variance) and
deterministic. They therefore show the client content only, without the
compositor's window border.

On a wlroots compositor (Sway, etc.) you can capture the real windows with
`grim`/`slurp` if you want decorated shots instead.
