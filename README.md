# wayland (FPC)

A Free Pascal Wayland protocol binding, plus the code generator that produces it.

## Layout

The project is split by dependency footprint so the runtime binding stays free
of heavy build-time dependencies:

| Directory | What | Dependencies | Built with |
|---|---|---|---|
| `wayland-rt/` | Runtime Wayland binding (library). Hand-written core + generated `wayland.pas` (core protocol). | FPC RTL only | **pasbuild** |
| `wayland-stable/` | Stable wayland-protocols, generated as `<protocol>_protocol` units (xdg-shell, linux-dmabuf, viewporter, …). | `wayland-rt` | **pasbuild** |
| `wayland-unstable/` | Unstable (`z*`) wayland-protocols. | `wayland-rt`, `wayland-stable` | **pasbuild** |
| `wayland-staging/` | Staging (`ext_`/`wp_` v1) wayland-protocols. | `wayland-rt`, `wayland-stable`, `wayland-unstable` | **pasbuild** |
| `wayland-classes/` | Higher-level OOP convenience layer (library): a display/event loop, windows, double-buffered surfaces (shm or dma-buf), a software canvas, cursors and clipboard/drag-and-drop. Toolkit-friendly wrappers over the raw binding. | `wayland-rt` + protocol tiers | **pasbuild** |
| `wayland-demo/` | Demo / dogfood app that connects to a live compositor. | `wayland-rt`, `wayland-stable` | **pasbuild** |
| `wayland-examples/` | Standalone example programs, one executable each (window, canvas, dma-buf, cursor grid, clipboard). Not built by default. | `wayland-rt`, tiers, `wayland-classes` | **fpc** (`make examples`) |
| `wayland-gen/` | Code generator: reads Wayland protocol XML, emits the binding units. | tiOPF + json_easy (Lazarus packages) | **lazbuild** |

Every protocol unit is named `<protocol>_protocol` (e.g. `xdg_shell_protocol`,
`linux_dmabuf_v1_protocol`); the core `wayland` unit keeps its bare name as it is
integrated with the runtime. Class names drop the leading `z` of unstable
interfaces (`zwp_linux_dmabuf_v1` → `TWpLinuxDmabufV1`). The generator resolves
cross-protocol references automatically and emits the needed `uses` clause.

The generator is intentionally *not* a pasbuild module: it depends on tiOPF and
`json_easy`, which are Lazarus `.lpk` packages and not in the pasbuild
repository. It is run rarely (only to regenerate bindings), so it keeps its own
lazbuild project.

## Build

Runtime library and demo (no tiOPF needed):

```sh
pasbuild compile            # builds rt -> stable -> unstable -> staging -> classes -> demo
pasbuild compile -m wayland-rt
```

Or via the `Makefile`, which prefers `pasbuild` and falls back to invoking `fpc`
directly (compiling dependency units from source) when it is not on `PATH`:

```sh
make                        # runtime libraries + demo
make examples               # the standalone example programs (one exe each)
make clean
```

`make examples` builds every `wayland-examples/src/main/pascal/*.pas` into
`wayland-examples/target/`.

Code generator:

```sh
lazbuild wayland-gen/regen_units.lpi
```

## Regenerating the bindings

`regen_units <outdir> <protocol.xml> [<protocol.xml> ...]` pre-scans every given
XML (plus the core `wayland.xml`) to build the interface→unit map, then writes
`<outdir>/<protocol>_protocol.pas` for each. The core protocol:

```sh
lazbuild wayland-gen/regen_units.lpi
./wayland-gen/regen_units wayland-rt/src/main/pascal /usr/share/wayland/wayland.xml
```

All extension protocols (stable/unstable/staging) are regenerated together so
cross-protocol references resolve, then split into their tier package by source
directory — see `scripts/regen-all.sh`.

The reader rejects non-protocol XML (it validates the root element is
`<protocol>`). `docs/wayland_fpc-fpdoc.xml` is FPDoc documentation, **not**
protocol input.

## Licensing

This project's own code (the runtime, the OOP classes layer, the generator, the
demo and examples) is **BSD-3-Clause** — see [`LICENSE`](LICENSE). Every source
file carries an SPDX header; the generator re-emits it into each generated unit.

The generated protocol bindings (`wayland.pas` and the `*_protocol.pas` units)
are derived from the upstream `wayland` / `wayland-protocols` XML, which is
**MIT (Expat)** licensed by its respective authors. Their attribution and the
MIT permission notice are reproduced in
[`THIRD-PARTY-NOTICES.txt`](THIRD-PARTY-NOTICES.txt). MIT and BSD-3-Clause are
compatible permissive licenses.
