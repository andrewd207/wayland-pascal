#!/usr/bin/env bash
# Isolated check of the classes-layer example_server: run it as the compositor
# and point the server-smoke client (a real wayland client) at it, verifying the
# registry/global handshake driven by TWaylandServer. Fully isolated in a
# throwaway XDG_RUNTIME_DIR — never touches the real compositor.
#
# Usage: wayland-server/classes/example/run-example.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
FPC="${FPC:-fpc}"
FLAGS="-Mobjfpc -Sh -O1"
COMMON="$ROOT/wayland-common/src/main/pascal"
RT=$(mktemp -d); B=$(mktemp -d)
trap 'rm -rf "$RT" "$B"' EXIT

echo ">> compiling example_server (classes layer) + bind_client"
mkdir -p "$B/a" "$B/b"
"$FPC" $FLAGS -Fu"$ROOT/wayland-server/classes/src/main/pascal" \
              -Fu"$ROOT/wayland-server/rt/src/main/pascal" -Fu"$COMMON" \
              -FU"$B/a" -FE"$B" "$ROOT/wayland-server/classes/example/example_server.pas" >/dev/null
"$FPC" $FLAGS -Fu"$ROOT/wayland-client/rt/src/main/pascal" -Fu"$COMMON" \
              -FU"$B/b" -FE"$B" "$ROOT/wayland-server/classes/example/bind_client.pas" >/dev/null

export XDG_RUNTIME_DIR="$RT"
export WAYLAND_DISPLAY=wayland-0
unset WAYLAND_SOCKET
echo ">> isolated XDG_RUNTIME_DIR=$RT (real compositor untouched)"

timeout 12 "$B/example_server" >"$RT/server.log" 2>&1 &
srv=$!
sleep 0.5
crc=0; timeout 8 "$B/bind_client" || crc=$?
kill "$srv" 2>/dev/null || true

echo "--- server log ---"; cat "$RT/server.log"
echo "------------------"
[ "$crc" -eq 0 ] && echo "CLASSES EXAMPLE PASSED" || { echo "CLASSES EXAMPLE FAILED (client=$crc)"; exit 1; }
