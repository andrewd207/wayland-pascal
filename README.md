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
| `wayland-demo/` | Demo / dogfood app that connects to a live compositor. | `wayland-rt`, `wayland-stable` | **pasbuild** |
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
pasbuild compile            # builds rt -> stable -> unstable -> staging -> demo
pasbuild compile -m wayland-rt
```

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
