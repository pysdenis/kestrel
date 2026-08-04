#!/usr/bin/env bash
# Regenerate Resources/AppIcon.icns from the brand marks. Renders a 1024pt master via
# scripts/make-icon.swift, downscales to every iconset size, and packs an .icns.
# Original artwork — no CleanMyMac assets (docs/LEGAL.md). Run: bash scripts/make-icns.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MASTER="dist/icon-master.png"
ICONSET="dist/Kestrel.iconset"

mkdir -p dist
echo "Rendering master…"
swift scripts/make-icon.swift "$MASTER"

rm -rf "$ICONSET"; mkdir -p "$ICONSET"
while read -r px name; do
    [[ -z "$name" ]] && continue
    sips -z "$px" "$px" "$MASTER" --out "$ICONSET/$name.png" >/dev/null
done <<'SIZES'
16 icon_16x16
32 icon_16x16@2x
32 icon_32x32
64 icon_32x32@2x
128 icon_128x128
256 icon_128x128@2x
256 icon_256x256
512 icon_256x256@2x
512 icon_512x512
1024 icon_512x512@2x
SIZES

mkdir -p Resources
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
