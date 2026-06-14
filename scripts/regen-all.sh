#!/usr/bin/env bash
# Regenerate every wayland-protocols binding (stable + unstable + staging) and
# place each unit into its tier package. All protocols are generated in a single
# pass so cross-protocol references resolve into the correct uses clauses.
#
# Usage: scripts/regen-all.sh [PROTOCOLS_DIR]
#   PROTOCOLS_DIR defaults to /usr/share/wayland-protocols
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROTO_DIR="${1:-/usr/share/wayland-protocols}"
GEN="$ROOT/wayland-gen/regen_units"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -x "$GEN" ] || { echo "build the generator first: lazbuild wayland-gen/regen_units.lpi" >&2; exit 1; }

# Generate every protocol into one temp dir (complete interface->unit map).
mapfile -t XMLS < <(find "$PROTO_DIR"/stable "$PROTO_DIR"/unstable "$PROTO_DIR"/staging -name '*.xml' | sort)
"$GEN" "$TMP" "${XMLS[@]}"

# Distribute each generated unit into wayland-<tier>/src/main/pascal by source tier.
for tier in stable unstable staging; do
  dest="$ROOT/wayland-$tier/src/main/pascal"
  mkdir -p "$dest"
  while IFS= read -r xml; do
    name="$(grep -o '<protocol name="[^"]*"' "$xml" | head -1 | sed 's/.*name="//;s/"//')"
    unit="${name}_protocol"
    cp "$TMP/$unit.pas" "$dest/$unit.pas"
  done < <(find "$PROTO_DIR/$tier" -name '*.xml' | sort)
  echo "wayland-$tier: $(ls "$dest"/*.pas | wc -l) units"
done
