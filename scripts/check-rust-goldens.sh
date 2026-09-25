#!/bin/sh
# Run the MoonBit typify CLI on cargo-typify's integration-test inputs, format
# the output with rustfmt exactly as cargo-typify does (edition 2018), and
# compare with cargo-typify's expected outputs (tests/upstream/cli).
#
# Also formats the upstream token oracle (tests/oracle/typify/*.tokens) and
# checks it against the upstream schema goldens, validating the oracle.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
toolchain=${TOOLCHAIN:-1.97.1}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
printf 'edition = "2018"\n' > "$work/rustfmt.toml"
fmt() { rustup run "$toolchain" rustfmt --config-path="$work/rustfmt.toml"; }

cd "$root"
moon build --target wasm cmd/typify >/dev/null
wasm=$(ls _build/wasm/debug/build/cmd/typify/typify.wasm)
typify() { moonrun "$wasm" -- "$@"; }

fail=0
check_cli() {
  expected=$1; shift
  typify tests/upstream/cli/example.json "$@" --output - | fmt > "$work/out.rs"
  if diff -u "tests/upstream/cli/$expected" "$work/out.rs" > "$work/diff"; then
    echo "ok   cli $expected"
  else
    echo "FAIL cli $expected"; head -40 "$work/diff"; fail=1
  fi
}
check_cli builder.rs
check_cli builder.rs --builder
check_cli no-builder.rs --no-builder
check_cli derive.rs --no-builder --additional-derive ExtraDerive
check_cli attr.rs --no-builder --additional-attr '#[extra_attr]'
check_cli multi_derive.rs --no-builder --additional-derive ExtraDerive --additional-derive AnotherDerive
check_cli custom_btree_map.rs --map-type ::std::collections::BTreeMap

for tokens in tests/oracle/typify/*.tokens; do
  name=$(basename "$tokens" .tokens)
  case "$name" in
    github|vega) golden="tests/upstream/impl/$name.out"
      fmt < "$tokens" > "$work/g.rs" ;;
    *) golden="tests/upstream/schemas/$name.rs"
      { printf '#![deny(warnings)]\n'; cat "$tokens"; printf '\nfn main() {}\n'; } | fmt > "$work/g.rs" ;;
  esac
  if diff -q "$golden" "$work/g.rs" > /dev/null; then
    echo "ok   golden $name"
  else
    echo "FAIL golden $name"; diff -u "$golden" "$work/g.rs" | head -20; fail=1
  fi
done
exit $fail
