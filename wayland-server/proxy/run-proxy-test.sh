#!/usr/bin/env bash
# Isolated integration test for wlproxy: smoke_client -> wlproxy -> smoke_server.
# The server smoke binary stands in as the "real compositor", so this never
# touches the actual compositor. Everything runs inside a throwaway
# XDG_RUNTIME_DIR. Verifies the proxy forwards both directions AND tees the
# request stream through our server binding (the [tee] log line).
#
# Usage: wayland-server/proxy/run-proxy-test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FPC="${FPC:-fpc}"
FLAGS="-Mobjfpc -Sh -O1"
COMMON="$ROOT/wayland-common/src/main/pascal"
SRT="$ROOT/wayland-server/rt/src/main/pascal"
SST="$ROOT/wayland-server/stable/src/main/pascal"
CRT="$ROOT/wayland-client/rt/src/main/pascal"
RT=$(mktemp -d); B=$(mktemp -d)
trap 'rm -rf "$RT" "$B"' EXIT

echo ">> compiling smoke_server, smoke_client, wlproxy"
mkdir -p "$B/a" "$B/b" "$B/c"
"$FPC" $FLAGS -Fu"$SRT" -Fu"$COMMON" -FU"$B/a" -FE"$B" "$ROOT/wayland-server/smoke/smoke_server.pas" >/dev/null
"$FPC" $FLAGS -Fu"$CRT" -Fu"$COMMON" -FU"$B/b" -FE"$B" "$ROOT/wayland-server/smoke/smoke_client.pas" >/dev/null
"$FPC" $FLAGS -Fu"$SRT" -Fu"$SST" -Fu"$COMMON" -FU"$B/c" -FE"$B" "$ROOT/wayland-server/proxy/wlproxy.pas" >/dev/null

export XDG_RUNTIME_DIR="$RT"
echo ">> isolated XDG_RUNTIME_DIR=$RT (real compositor untouched)"

WAYLAND_DISPLAY=wayland-0 timeout 12 "$B/smoke_server" >"$RT/upstream.log" 2>&1 &
srv=$!
sleep 0.5
WAYLAND_DISPLAY=wayland-0 timeout 12 "$B/wlproxy" wayland-proxy >"$RT/proxy.log" 2>&1 &
prx=$!
sleep 0.5
crc=0; WAYLAND_DISPLAY=wayland-proxy timeout 8 "$B/smoke_client" || crc=$?
kill "$prx" 2>/dev/null || true
wait "$srv" 2>/dev/null || true

echo "--- upstream (smoke_server) ---"; cat "$RT/upstream.log"
echo "--- proxy ---"; cat "$RT/proxy.log"
echo "------------------"
if [ "$crc" -eq 0 ] && grep -q '\[tee\] get_registry' "$RT/proxy.log"; then
  echo "PROXY TEST PASSED (forwarded + teed through the server binding)"
else
  echo "PROXY TEST FAILED (client=$crc)"; exit 1
fi
