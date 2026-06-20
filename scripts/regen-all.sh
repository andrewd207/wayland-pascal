#!/usr/bin/env bash
# Regenerate every wayland-protocols binding (stable + unstable + staging) and
# place each unit into its tier package, for BOTH the client and the server
# bindings. All protocols are generated in a single pass per side so
# cross-protocol references resolve into the correct uses clauses.
#
# Client units  -> wayland-client/<tier>/src/main/pascal/<proto>_protocol.pas
# Server units  -> wayland-server/rt/...  (core: wayland_server.pas)
#                  wayland-server/<tier>/src/main/pascal/<proto>_server.pas
#
# Usage: scripts/regen-all.sh [PROTOCOLS_DIR]
#   PROTOCOLS_DIR defaults to /usr/share/wayland-protocols
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROTO_DIR="${1:-/usr/share/wayland-protocols}"
CORE_XML="/usr/share/wayland/wayland.xml"
GEN="$ROOT/wayland-gen/target/regen_units"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -x "$GEN" ] || { echo "build the generator first: pasbuild compile -m wayland-gen" >&2; exit 1; }

mapfile -t XMLS < <(find "$PROTO_DIR"/stable "$PROTO_DIR"/unstable "$PROTO_DIR"/staging -name '*.xml' | sort)

# protocol name (<protocol name="...">) for a given XML file.
proto_name() { grep -o '<protocol name="[^"]*"' "$1" | head -1 | sed 's/.*name="//;s/"//'; }

# ---- Client side -----------------------------------------------------------
"$GEN" "$TMP/client" "${XMLS[@]}"
for tier in stable unstable staging; do
  dest="$ROOT/wayland-client/$tier/src/main/pascal"
  mkdir -p "$dest"
  while IFS= read -r xml; do
    cp "$TMP/client/$(proto_name "$xml")_protocol.pas" "$dest/"
  done < <(find "$PROTO_DIR/$tier" -name '*.xml' | sort)
  echo "wayland-$tier: $(ls "$dest"/*.pas | wc -l) units"
done

# ---- Server side -----------------------------------------------------------
# Generate the core (wayland_server.pas) alongside the extensions so the
# interface->unit map is complete, then distribute core to rt and each
# extension to its tier.
"$GEN" --server "$TMP/server" "$CORE_XML" "${XMLS[@]}"
cp "$TMP/server/wayland_server.pas" "$ROOT/wayland-server/rt/src/main/pascal/"
echo "wayland-server-rt: wayland_server.pas"
for tier in stable unstable staging; do
  dest="$ROOT/wayland-server/$tier/src/main/pascal"
  mkdir -p "$dest"
  while IFS= read -r xml; do
    cp "$TMP/server/$(proto_name "$xml")_server.pas" "$dest/"
  done < <(find "$PROTO_DIR/$tier" -name '*.xml' | sort)
  echo "wayland-server-$tier: $(ls "$dest"/*.pas | wc -l) units"
done
