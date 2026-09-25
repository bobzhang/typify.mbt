#!/bin/sh
# Conformance of the MoonBit backend on random schemas: upstream typify's
# Rust (compiled with serde) versus the generated MoonBit, on instances
# generated from each schema. Everything is written to conformance/random
# (git-ignored); remove it afterwards to keep `moon check` fast.
#   scripts/random-conformance.sh [cases.jsonl] [schemas] [instances-per-type]
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cases=${1:-tests/oracle/typify-random/cases.jsonl}
count=${2:-200}
per_type=${3:-12}
toolchain=${TOOLCHAIN:-1.97.1}
cd "$root"
rm -rf conformance/random
moon build --target wasm conformance/codegen conformance/gen >/dev/null
codegen=_build/wasm/debug/build/conformance/codegen/codegen.wasm
moonrun "$codegen" random "$cases" "$count"

# Upstream sometimes emits Rust that does not compile (e.g. duplicate type
# names); drop those schemas until the harness builds.
tokens="$root/conformance/random/tokens"
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if (cd conformance/rust && CONFORMANCE_RANDOM="$tokens" \
      rustup run "$toolchain" cargo build --offline -q --release 2> "$root/conformance/random/rustc.log"); then
    break
  fi
  gen_rs=$(ls -t conformance/rust/target/release/build/conformance-rust-*/out/generated.rs | head -1)
  lines=$(grep -o 'generated.rs:[0-9]*' conformance/random/rustc.log | cut -d: -f2 | sort -un)
  [ -n "$lines" ] || { cat conformance/random/rustc.log; exit 1; }
  for l in $lines; do
    m=$(sed -n "${l}p" "$gen_rs" | grep -o '^pub mod [a-z0-9_]*' | cut -d' ' -f3 || true)
    [ -n "$m" ] && rm -f "$tokens/$m.tokens" "$tokens/$m.types"
  done
done
ls "$tokens" | grep '\.tokens$' | sed 's/\.tokens$//' > conformance/random/keep.txt
echo "$(wc -l < conformance/random/keep.txt) schemas compile with upstream's Rust"
rm -rf conformance/random/fx_*
moonrun "$codegen" random "$cases" "$count"

mkdir -p conformance/random/cases
gen=_build/wasm/debug/build/conformance/gen/gen.wasm
harness=conformance/rust/target/release/conformance-rust
for schema in conformance/random/schemas/*.json; do
  name=$(basename "$schema" .json)
  grep -qx "$name" conformance/random/keep.txt || continue
  moonrun "$gen" -- "$schema" "$name" "conformance/random/cases/$name.tsv" "$per_type"
  "$harness" < "conformance/random/cases/$name.tsv" > "conformance/random/cases/$name.expected"
done
moon test conformance/random
