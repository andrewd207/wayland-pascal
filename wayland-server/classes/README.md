# wayland-server-classes

The server-side **protocol-ergonomics** layer — the counterpart of the client's
[`wayland-classes`](../../wayland-client/classes/README.md). It hides the
boilerplate every Wayland server repeats; it is **not** a compositor framework.

`TWaylandServer` wraps the runtime's `TWaylandServerDisplay` and handles:

- **`wl_display`** bound at id 1 on every client (automatically),
- **`get_registry`** → a `wl_registry` that announces your globals,
- **`bind`** → instantiates the right resource, **version-clamped** to
  `min(advertised, client-requested)`, then calls your `OnBind` so you wire its
  request handlers,
- **`sync`** → `wl_callback.done` + teardown,
- a monotonic **serial** source (`NextSerial`) for input/configure events.

`wl_display.delete_id` (acknowledging a freed client id) is handled in the
runtime, so it applies to every server, not just this layer.

```pascal
Server := TWaylandServer.Create;
Server.AddGlobal(TWlCompositor, 4, @OnCompositorBound); // cap at v4
Server.AddGlobal(TWlShm, 1);
Server.AddGlobal(TWlSeat, 5);
Server.AddSocket('wayland-0');   // '' => first free wayland-N
Server.Run;

// OnCompositorBound(AClient, AResource):
//   (AResource as TWlCompositor).OnCreateSurface := @OnCreateSurface;
```

## Scope (what it deliberately does NOT do)

Compositing, buffer access, scanout, window placement/stacking, input devices,
cursors. The layer stops at "here is a resource (and, after commit, its
`wl_buffer`)" — what that *means* is a backend you supply (DRM/KMS, GL, etc.).
It's glue, not a compositor.

## Example & test

[`example/example_server.pas`](example/example_server.pas) is a runnable server
built on the layer. [`example/run-example.sh`](example/run-example.sh) drives it
with a small client (`bind_client`) entirely inside a throwaway
`XDG_RUNTIME_DIR` — it binds `wl_compositor`, creates a surface, and syncs,
exercising bind / version-clamp / dispatch / sync / `delete_id`:

```sh
wayland-server/classes/example/run-example.sh
```
