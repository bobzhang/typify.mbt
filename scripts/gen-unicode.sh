#!/bin/sh
# Regenerate internal/unicode/tables.mbt using the same Rust toolchain that
# upstream typify pins (see .repos/typify/rust-toolchain.toml).
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
toolchain=${TOOLCHAIN:-1.97.1}
cd "$root/scripts/gen-unicode"
GEN_RUSTC_VERSION=$(rustup run "$toolchain" rustc --version) \
  rustup run "$toolchain" cargo run --offline -q > "$root/internal/unicode/tables.mbt"
moon -C "$root" fmt >/dev/null 2>&1 || true
