# Server smoke test

An end-to-end check that the server stack round-trips a real client over a Unix
socket. It is two separate programs (the client and server protocol unit trees
both define `TWlDisplay` etc., so they can't share one executable):

- `smoke_server.pas` — built on the generated `wayland_server` bindings. Binds a
  socket, accepts a client, binds `wl_display` at id 1, and answers
  `get_registry` by creating the registry resource and sending one
  `wl_registry.global` event.
- `smoke_client.pas` — the real `wayland` client lib. Connects, calls
  `get_registry`, and waits for that global.

This exercises the full path: socket listen/accept/connect, client request →
server `message` dispatch, a `new_id` agreed across the wire, and server
`SendEvent` → client event dispatch.

## Run

```sh
wayland-server/smoke/run-smoke.sh
```

**Safety:** the runner executes entirely inside a throwaway `XDG_RUNTIME_DIR`,
with `WAYLAND_DISPLAY` pinned to `wayland-0` and `WAYLAND_SOCKET` cleared, so it
can only ever touch its own socket file — it never references the real
compositor's socket.
