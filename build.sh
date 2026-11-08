#!/bin/sh
# Concatenate the modular source into one pasteable Delta script.
set -e
cd "$(dirname "$0")"

FILES="
src/00_core.lua
src/10_recon.lua
src/20_gui.lua
src/30_features.lua
src/40_exploits.lua
src/50_boot.lua
"

mkdir -p dist
: > dist/SellDirt.lua

for f in $FILES; do
    if [ ! -f "$f" ]; then
        echo "missing: $f" >&2
        exit 1
    fi
    cat "$f" >> dist/SellDirt.lua
    printf '\n' >> dist/SellDirt.lua
done

LINES=$(wc -l < dist/SellDirt.lua)
BYTES=$(wc -c < dist/SellDirt.lua)
echo "built dist/SellDirt.lua  ${LINES} lines  ${BYTES} bytes"
