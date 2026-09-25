#!/bin/sh
# Copy upstream typify test fixtures into tests/upstream (see its README).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
up="$root/.repos/typify"
rm -rf "$root/tests/upstream/schemas" "$root/tests/upstream/impl"
mkdir -p "$root/tests/upstream/schemas" "$root/tests/upstream/impl"
cp "$up"/typify/tests/schemas/* "$root/tests/upstream/schemas/"
cp "$up"/typify-impl/tests/github.json "$up"/typify-impl/tests/github.out \
  "$up"/typify-impl/tests/vega.json "$up"/typify-impl/tests/vega.out \
  "$up"/typify-impl/tests/generator.out "$root/tests/upstream/impl/"
cp "$up/LICENSE" "$root/tests/upstream/LICENSE"
echo "upstream commit: $(git -C "$up" rev-parse --short HEAD)"
