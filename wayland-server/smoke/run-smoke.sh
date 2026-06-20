#!/usr/bin/env bash
# End-to-end smoke test for the server stack: a server process (built on the
# generated wayland_server bindings) and a real client process (the wayland
# client lib) exchange get_registry / wl_registry.global over a Unix socket.
#
# SAFETY: the whole test runs inside a throwaway XDG_RUNTIME_DIR, with
# WAYLAND_DISPLAY pinned and WAYLAND_SOCKET cleared, so it can ONLY touch its own
# socket file and never references the real compositor's socket.
#
# Usage: wayland-server/smoke/run-smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HERE="$ROOT/wayland-server/smoke"
FPC="${FPC:-fpc}"
FLAGS="-Mobjfpc -Sh -O1"
COMMON="$ROOT/wayland-common/src/main/pascal"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

echo ">> building smoke_server (uses wayland_server)"
mkdir -p "$BUILD/su"
"$FPC" $FLAGS -Fu"$ROOT/wayland-server/rt/src/main/pascal" -Fu"$COMMON" \
  -FU"$BUILD/su" -FE"$BUILD" "$HERE/smoke_server.pas" >/dev/null

echo ">> building smoke_client (uses wayland)"
mkdir -p "$BUILD/cu"
"$FPC" $FLAGS -Fu"$ROOT/wayland-client/rt/src/main/pascal" -Fu"$COMMON" \
  -FU"$BUILD/cu" -FE"$BUILD" "$HERE/smoke_client.pas" >/dev/null

# --- isolated run -----------------------------------------------------------
export XDG_RUNTIME_DIR="$BUILD/rt"
mkdir -p "$XDG_RUNTIME_DIR"
export WAYLAND_DISPLAY=wayland-0
unset WAYLAND_SOCKET
echo ">> running (isolated XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR)"

timeout 15 "$BUILD/smoke_server" >"$BUILD/server.log" 2>&1 &
srv=$!
sleep 0.5
crc=0; timeout 10 "$BUILD/smoke_client" || crc=$?
src=0; wait "$srv" || src=$?

echo "--- server log ---"; cat "$BUILD/server.log"
echo "------------------"
if [ "$crc" -eq 0 ] && [ "$src" -eq 0 ]; then
  echo "SMOKE TEST PASSED"
else
  echo "SMOKE TEST FAILED (client=$crc server=$src)"; exit 1
fi
