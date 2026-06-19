# wayland-gen

The code generator for this project: it reads Wayland protocol XML and emits the
Free Pascal binding units (`wayland.pas` for the core protocol, and one
`<protocol>_protocol.pas` unit per extension protocol).

It is a build-time tool, run only when the bindings need regenerating — e.g.
after a `wayland-protocols` upgrade or a change to the generator itself. The
generated units are committed to the repo, so a normal build never invokes it.

## Layout

| Path | What |
|---|---|
| `src/main/pascal/regen_units.lpr` | CLI entry point. |
| `src/main/pascal/wayland_interface_reader.pas` | Parses a protocol XML into an interface tree (FCL `XMLRead`/`DOM`). |
| `src/main/pascal/wayland_unitwriter.pas` | `TWaylandUnitWriter` — turns that tree into a Pascal unit AST and serialises it. |
| `vendor/src/main/pascal/pascal_writer.pas` | Vendored Pascal-source AST writer (`TUnitNode`/`TClassNode`/…). Derived from json_easy and re-based off the RTL (a small `TVendNode`/`TVendList` object model), so the generator depends on **no Lazarus packages** — just the FPC RTL. |

`vendor/` is its own pasbuild library module (`wayland-gen-vendor`); `wayland-gen`
is an application module that depends on it. Both are registered in the top-level
aggregator as `activeByDefault="false"`, so a plain `pasbuild compile` skips them.

## Build

```sh
# from the repo root — builds wayland-gen/vendor then wayland-gen
pasbuild compile -m wayland-gen
```

The executable lands at `wayland-gen/target/regen_units`.

## Run

```
regen_units <outdir> <protocol.xml> [<protocol.xml> ...]
```

Every given XML — plus the core `/usr/share/wayland/wayland.xml`, always scanned —
is read to build a complete interface→unit map (so cross-protocol references emit
the right `uses` clause), then each given XML is written as
`<outdir>/<protocol>_protocol.pas` (the core protocol keeps its bare `wayland`
name). Each emitted unit carries an SPDX header.

Regenerate just the core protocol into the runtime module:

```sh
./wayland-gen/target/regen_units wayland-rt/src/main/pascal /usr/share/wayland/wayland.xml
```

Regenerate **all** tiers at once (stable + unstable + staging + core), then split
each unit into its tier package — this is the normal path:

```sh
scripts/regen-all.sh                      # defaults to /usr/share/wayland-protocols
scripts/regen-all.sh /path/to/wayland-protocols
```

After regenerating, `git diff` the generated units: the output should be
byte-identical apart from your intended change. That diff is the verification
oracle for any generator edit.

## Notes

- The reader **fails loud** on unknown XML elements and validates that the root
  element is `<protocol>`; `docs/wayland_fpc-fpdoc.xml` is FPDoc documentation,
  not protocol input, and is rejected.
- Class names drop the leading `z` of unstable interfaces
  (`zwp_linux_dmabuf_v1` → `TWpLinuxDmabufV1`).
- A pasbuild ICE / access violation in the compiler after changing generated
  units is usually a stale `.ppu` cache — run `pasbuild clean` then rebuild.
