#!/bin/sh
# Generate conformance instances from the fixture schemas and record the
# behaviour of upstream typify's generated Rust (serde) on each of them.
#   conformance/cases/<name>.tsv       schema<TAB>Type<TAB>json
#   conformance/cases/<name>.expected  OK <json> | ERR <message> | NOTYPE
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
toolchain=${TOOLCHAIN:-1.97.1}
per_type=${PER_TYPE:-16}
cd "$root"
mkdir -p conformance/cases
moon build --target wasm conformance/gen >/dev/null
gen=_build/wasm/debug/build/conformance/gen/gen.wasm
(cd conformance/rust && rustup run "$toolchain" cargo build --offline -q --release)
harness=conformance/rust/target/release/conformance-rust
for name in $(ls tests/oracle/typify/*.tokens | xargs -n1 basename | sed 's/\.tokens$//'); do
  case "$name" in
    vega|various-enums-json-schema) continue ;;
    maps_custom) src=tests/upstream/schemas/maps.json ;;
    github) src=tests/upstream/impl/github.json ;;
    *) src=tests/upstream/schemas/$name.json ;;
  esac
  n=$per_type
  [ "$name" = github ] && n=4
  moonrun "$gen" -- "$src" "$name" "conformance/cases/$name.tsv" "$n"
  "$harness" < "conformance/cases/$name.tsv" > "conformance/cases/$name.expected"
  total=$(wc -l < "conformance/cases/$name.tsv")
  ok=$(grep -c '^OK' "conformance/cases/$name.expected" || true)
  notype=$(grep -c '^NOTYPE' "conformance/cases/$name.expected" || true)
  echo "$name: $total cases, $ok accepted, $notype without a type"
done
