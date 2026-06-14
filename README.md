# wayland (FPC)

A Free Pascal Wayland protocol binding, plus the code generator that produces it.

## Layout

The project is split by dependency footprint so the runtime binding stays free
of heavy build-time dependencies:

| Directory | What | Dependencies | Built with |
|---|---|---|---|
| `wayland-rt/` | Runtime Wayland binding (library). Hand-written core + generated `wayland.pas` / `xdg_shell.pas`. | FPC RTL only | **pasbuild** |
| `wayland-demo/` | Demo / dogfood app that connects to a live compositor. | `wayland-rt` only | **pasbuild** |
| `wayland-gen/` | Code generator: reads Wayland protocol XML, emits the binding units. | tiOPF + json_easy (Lazarus packages) | **lazbuild** |

The generator is intentionally *not* a pasbuild module: it depends on tiOPF and
`json_easy`, which are Lazarus `.lpk` packages and not in the pasbuild
repository. It is run rarely (only to regenerate bindings), so it keeps its own
lazbuild project.

## Build

Runtime library and demo (no tiOPF needed):

```sh
pasbuild compile            # builds wayland-rt then wayland-demo
pasbuild compile -m wayland-rt
```

Code generator:

```sh
lazbuild wayland-gen/regen_units.lpi
```

## Regenerating the bindings

```sh
lazbuild wayland-gen/regen_units.lpi
./wayland-gen/regen_units \
  /usr/share/wayland/wayland.xml \
    wayland-rt/src/main/pascal/wayland.pas \
  /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml \
    wayland-rt/src/main/pascal/xdg_shell.pas
```

The reader rejects non-protocol XML (it validates the root element is
`<protocol>`). `docs/wayland_fpc-fpdoc.xml` is FPDoc documentation, **not**
protocol input.
