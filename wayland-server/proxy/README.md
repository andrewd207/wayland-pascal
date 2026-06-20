# wlproxy — a transparent Wayland proxy that stress-tests the server binding

`wlproxy` advertises itself as a compositor on its own socket and forwards every
client through to the **real** compositor (`$WAYLAND_DISPLAY`). It is both a fun
toy (run real apps through it) and a stress test for our generated `wayland_server`
binding.

```
  client  ──connect──▶  wlproxy  ──connect──▶  real compositor
          ◀──events───            ◀──events───
```

Two things happen to every byte:

1. **Verbatim forwarding.** Each chunk (and its SCM_RIGHTS fds) is forwarded to
   the other side unchanged, in both directions. Because the client's object ids
   reach the compositor untouched, real apps just work. fd passing uses
   `RecvWithFds` / `SendWithFds` from `wayland-common`.
2. **Tee through the server binding.** Each *client → compositor* chunk is also
   fed into a per-connection `TWaylandServerClient.FeedRequests`, so our generated
   `wayland_server` handlers decode and dispatch the live request stream. On each
   `wl_registry.bind` the proxy resolves the interface name to its server class
   via `FindServerInterface` (every generated interface self-registers — the proxy
   links `wayland_server_all`) and seeds the bound global, so deeper requests
   (`create_surface`, `get_xdg_surface`, `get_keyboard`, …) dispatch through our
   handlers too — near-total request coverage, no hand-maintained table. The tee
   never sends anything, so it cannot perturb the session: if our binding
   mis-parses real traffic it surfaces here, and if it parses cleanly the app
   keeps running.

## Safety

The proxy **refuses to bind the same name as `$WAYLAND_DISPLAY`**, so it can never
clobber the real compositor's socket. It only unlinks/binds its own name.

## Build & run

```sh
# build (needs all server tiers: it links wayland_server_all so every interface
# self-registers and any bound global can be resolved by name)
fpc -Mobjfpc -Sh -O1 \
  -Fuwayland-server/rt/src/main/pascal \
  -Fuwayland-server/stable/src/main/pascal \
  -Fuwayland-server/unstable/src/main/pascal \
  -Fuwayland-server/staging/src/main/pascal \
  -Fuwayland-common/src/main/pascal \
  -FU/tmp/wlproxy-units -owlproxy wayland-server/proxy/wlproxy.pas

# run: forwards to your current $WAYLAND_DISPLAY, advertises wayland-proxy
./wlproxy                      # or: ./wlproxy <socket-name>

# in another terminal, point an app at it:
WAYLAND_DISPLAY=wayland-proxy weston-terminal     # any wayland client
```

The `[tee] …` lines show our server binding decoding the app's real requests.

## Test (isolated, no real compositor needed)

`run-proxy-test.sh` wires `smoke_client → wlproxy → smoke_server` (the server
smoke binary stands in as the compositor) inside a throwaway `XDG_RUNTIME_DIR`:

```sh
wayland-server/proxy/run-proxy-test.sh
```
