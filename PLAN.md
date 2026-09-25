# typify.mbt porting plan

Goal: a pure-MoonBit port of [oxidecomputer/typify](https://github.com/oxidecomputer/typify)
that generates **Rust** and **MoonBit** types from one JSON Schema, with identical JSON wire
format on both sides. Runs via `moonx bobzhang/typify/cmd/typify` (wasm backend).

Upstream source lives in `.repos/typify` (reference only, not built).

## Architecture

```
JSON Schema ──► schema/   (port of schemars::schema model + Json parsing)
            ──► typify    (TypeSpace IR: convert, merge, enums, structs, defaults, cycles, naming)
            ──► rust/     (Rust backend: text emission replacing syn/quote)
            ──► moonbit/  (MoonBit backend: types + ToJson/FromJson matching serde semantics)
cmd/typify   CLI: --lang rust|moonbit, -o OUTPUT, settings flags from cargo-typify
```

## Upstream → package mapping

| upstream (`typify-impl/src`)          | lines | here                     |
|---------------------------------------|------:|--------------------------|
| schemars `schema` model               |     – | `schema/`                |
| `lib.rs` (TypeSpace, settings)        |  1580 | root                     |
| `convert.rs`                          |  2435 | root                     |
| `type_entry.rs`                       |  2158 | root (IR) + `rust/` emit |
| `merge.rs`                            |  1922 | root                     |
| `enums.rs`, `structs.rs`              |  2125 | root                     |
| `util.rs` (naming, sanitize, Case)    |  1270 | root (+ heck port)       |
| `value.rs`, `defaults.rs`             |  2216 | root + backends          |
| `cycles.rs`, `validate.rs`            |   345 | root                     |
| `output.rs`, `rust_extension.rs`      |   233 | `rust/`                  |
| `conversions.rs` (format → type)      |     – | root                     |

## Phases

1. **Schema model**: port schemars' `RootSchema`/`SchemaObject`/validation structs, parse from
   `Json`, keeping unknown `x-*` extensions.
2. **IR + conversion**: `TypeSpace`, `TypeEntry`, `convert`, `structs`, `enums`, `merge`,
   `cycles`, naming. Backend-agnostic; snapshot-test the IR.
3. **Rust backend**: emit text that is token-for-token equal to upstream after `rustfmt`.
   Oracle: `.repos/typify/typify/tests/schemas/*.{json,rs}` (22 pairs) plus
   `typify-impl/tests/{github,vega}.{json,out}`.
4. **MoonBit backend**: structs/enums + hand-generated `ToJson`/`FromJson` reproducing serde:
   external/internal/adjacent/untagged enums, `rename`, `flatten`, `default`,
   `skip_serializing_if`, `deny_unknown_fields`, `Option` vs nullable, big integers via
   `Json::Number(_, repr~)`.
5. **Cross-language conformance**: for each schema, round-trip sample JSON through generated Rust
   and generated MoonBit; outputs must be equal.
6. **Validation & extras**: `pattern` (moonbitlang/regexp), length/range checks, builders,
   `x-rust-type`, CLI settings parity, publish to mooncakes.

## Verified environment facts

- `moonx` runs packages on the linear-memory `wasm` backend; `@env.args()` (argv[0] = wasm path)
  and `moonbitlang/x/fs` read/write work there.
- `Json::Number(Double, repr~ : String?)` keeps the original number text → no u64 precision loss.
- `moonbitlang/regexp` exists for `pattern` support (check compatibility with `regress` semantics).
