# typify.mbt: detailed porting plan

## Status (v0.1.0)

All milestones below are done. The verification is summarised in README.md ("How it
is verified"):

- **Rust output:** the IR and tokens match upstream on every fixture and on
  thousands of random schemas.
- **MoonBit output:** it agrees exactly with serde, including error texts:
  - about 5k fixture instances (26k in stress runs);
  - about 35k instances over 1,020 random schemas.

Known limitations:

- The CLI prints Rust as an unformatted token stream (pipe it through rustfmt).
- Rust types without a MoonBit equivalent are represented as `Json`: user
  conversions, replacements and `x-rust-type`.

## 1. Goal and non-goals

**Goal.** A pure-MoonBit port of [oxidecomputer/typify](https://github.com/oxidecomputer/typify)
(upstream `5ccedd1`, 2026-09-23, checked out in `.repos/typify`) that turns one JSON Schema into:

- **Rust** code equivalent to upstream `cargo typify` output, and
- **MoonBit** code whose `ToJson`/`FromJson` accept and produce the *same JSON* as the serde-derived
  Rust code.

It ships as a MoonBit CLI runnable with `moonx bobzhang/typify/cmd/typify` (wasm backend).

**Non-goals (v1).**

- The proc-macro (`import_types!`) and `build.rs` integration. These are Rust-only; users run the
  CLI instead.
- JSON Schema features upstream does not support: `prefixItems`, `if/then/else`,
  `unevaluated*`, `dependent*`, external or nested `$ref`, and `$id`-based resolution.
- Running `rustfmt` from inside the wasm CLI.

## 2. Verified environment facts

| Fact | Consequence |
|---|---|
| `moonx` runs on the linear-memory `wasm` backend. `@env.args()` works (argv[0] = wasm path), and `moonbitlang/x/fs` can read and write files. | The CLI can be pure wasm. `moon.mod` sets `preferred-target: wasm`. |
| `Json::Number(Double, repr~ : String?)` keeps the lexeme only for some numbers; `1`, `1.0`, `1e0` become indistinguishable. | **Not usable.** We ship our own lossless `serde_json` port (`PosInt`/`NegInt`/`Float`, serde_json 1.0.151 parse rules without `float_roundtrip`, ryu printing, BTreeMap key order). |
| `moonbitlang/core/sorted_map` exists. | It replaces `BTreeMap` wherever iteration order is observable. |
| Core has no XID_Start / XID_Continue predicates. | We generate tables from Rust 1.97.1 `char` + unicode-ident 1.0.26 (Unicode 18 XID). |
| MoonBit `String::compare` orders by length first. | `collections.compare_str` / `StrMap` give Rust `BTreeMap<String,_>` order. |
| Core `ToJson` encodes `Int64`/`UInt64` as strings and `Some(x)` as `[x]`. | Generated MoonBit codecs never delegate to core instances; they're emitted per IR type. |
| `moonbitlang/regexp@0.3.5` is a Thompson-VM engine with no lookaround/backrefs. | We write our own backtracking ECMAScript engine matching `regress` 0.12 (§5.6), needed from M3 on. |
| Rust 1.89 is installed with rustfmt; upstream pins 1.97.1 through rustup. | The oracle and conformance harnesses can run locally. |

## 3. Architecture

```
            ┌────────────┐   ┌──────────────────────────────┐   ┌────────────┐
 schema.json│  schema/   │   │ typify (root)                │   │  rust/     │──► .rs
 ──────────►│ Json → ADT │──►│ TypeSpace IR: convert, merge,│──►├────────────┤
            │ (schemars) │   │ enums, structs, defaults,    │   │  moonbit/  │──► .mbt
            └────────────┘   │ cycles, naming               │   └────────────┘
                             └──────────────────────────────┘
```

### Packages

| Package | Contents | Upstream source |
|---|---|---|
| `internal/unicode` | XID_Start/XID_Continue tables (generated) | `unicode-ident` |
| `internal/heck` | heck 0.5 word splitting; Pascal/snake/kebab | `heck` |
| `collections` | `compare_str`, `StrMap` (BTreeMap<String,_>) | `std::collections` |
| `serde_json` | lossless `Value`/`Number`, parser, compact+pretty writer | `serde_json` 1.0.151 |
| `regex` | backtracking ECMAScript regex (lookaround, backrefs) | `regress` 0.12 |
| `runtime` | support for generated MoonBit: codec helpers, flatten buffer, uuid/date/datetime/ip, ConversionError | serde/chrono/uuid/std::net behaviour |
| `schema` | Schema ADT + decoder from `Json` | `schemars::schema` 0.8 |
| root `bobzhang/typify` | `TypeSpace`, `TypeSpaceSettings`, IR, conversion, `Type`/`TypeDetails` views | `typify-impl/src/*` minus emission |
| `rust` | Rust emitter + `OutputSpace` | `type_entry.rs` output_*, `value.rs`, `output.rs`, `rust_extension.rs`, `defaults.rs` default_fn |
| `moonbit` | MoonBit emitter | new |
| `cmd/typify` | CLI | `cargo-typify` |
| `conformance/` (not a moon package) | Rust harness crate + scripts | new |

### IR design decisions (backend-neutral)

- `TypeId = Int`, allocated from 1. The store is `SortedMap[Int, TypeEntry]`.
- `TypeEntryDetails` mirrors upstream, with Rust type-name strings replaced by semantic tags:
  - `Integer(IntKind)` where `IntKind = I8 | U8 | … | I64 | U64 | NonZeroU8 | … | NonZeroU64`
    (the IR records how the kind was chosen; a backend never parses Rust names).
  - `Float(F32 | F64)`.
  - `Native(NativeType)` where `NativeType = Uuid | Date | DateTime | Ip | Ipv4 | Ipv6 |
    Path(String, Array[TypeId]) | Replacement(String)`. The last two exist for x-rust-type and
    settings.
- **Dedup parity** (lib.rs:995): named types dedup by *name only* (first wins, no structural
  check); unnamed types dedup structurally via `type_to_id`. The canonical key replicates upstream
  derived `Ord` exactly: `WrappedValue`/`SchemaWrapper` compare Equal, but `Option<WrappedValue>`
  still distinguishes `None`/`Some`, vector lengths still count, and native params/impls are
  included.
- **Cycle breaking parity** (cycles.rs:20–144): same root order, same (reverse) child traversal,
  *immediate* mutation, and Box id reuse. `get_child_ids` returns `(child, setter)` pairs where
  `setter` writes the replacement id into the owning IR node at once.
- **Metadata lifetimes**: `convert_*` returns `(TypeEntry, Metadata?)` by value.
- **Errors**: `suberror TypifyError { BadValue(String, Json); InvalidTypeId; InvalidValue;
  InvalidSchema(type_name~ : String?, reason~ : String); Unsupported(String) }`. Upstream
  `todo!`/`unimplemented!` map to `Unsupported`. Upstream `panic!` stays `abort` only for true
  invariant violations.
- **Capabilities** (`has_impl`): a backend-neutral query `TypeSpaceImpl = FromStr |
  FromStringIrrefutable | Display | Default`.

## 4. Milestones

Every milestone ends with green `moon check`, `moon test` and `moon fmt`, plus one or more git
commits. There are no big-bang commits.

### M0: Infrastructure (in progress)

- [x] Module scaffold, CLI stub runnable with `moon run`.
- [x] Git repository; `.repos/` ignored.
- [ ] `scripts/` for golden diffs (§6.1), `README.md`, CI-ready `moon test`.
- [ ] Decide the answers to §9.

### M1: Leaf libraries (done: unicode, heck, collections; in progress: serde_json)

1. `internal/unicode`: generate tables from `DerivedCoreProperties.txt` (Unicode 16, matching
   `unicode-ident`) with a script under `scripts/`. Check the generated file in.
2. `internal/heck`: port heck 0.5 `transform`/word boundaries. Tests: heck's own test cases plus
   `util.rs:1133+` cases (`Ipv6Net`, `urn:…:2.0:user_`, …).
3. `serde_json`: lossless port with a differential oracle against the real crate (numbers,
   escapes, errors, recursion limit 128, duplicate keys = last wins).
4. `regex`: backtracking ECMAScript engine with `regress` 0.12 flags/semantics; differential
   oracle against `regress` (match/no-match and match position on generated corpora).
5. `sanitize`, `recase`, `accept_as_ident` (Rust keywords). The MoonBit keyword list lives in the
   `moonbit` backend, not here, because upstream sanitizes names once in the IR (§5.3).

Accepted when: all ported `util.rs` naming tests pass.

### M2: Schema model

- Decoding follows serde exactly for schemars' derive: `#[serde(default)]`, flattened
  sub-structs that *consume* recognised keys from a shared buffer, `skip_if_default` (a
  validation block equal to its default becomes `None`, which matters for the dispatch arms),
  `allow_null` for `const`/`default`, untagged `Schema`/`SingleOrVec`.
- ADT: `Schema = Bool(Bool) | Object(SchemaObject)`. `SchemaObject`, `Metadata`, `InstanceType`,
  `SingleOrVec`, and `Subschema`/`Number`/`String`/`Array`/`ObjectValidation` as in schemars 0.8.
  Unknown keys go to `extensions : SortedMap[String, Json]`.
- Decoder quirks to reproduce:
  - `definitions` and `$defs` (alias).
  - `exclusiveMinimum`/`exclusiveMaximum` numeric (draft 6+). Check what schemars does with draft-4
    booleans.
  - `required` becomes a sorted set.
  - `properties`/`patternProperties` become sorted maps (schemars without `preserve_order`).
  - `examples`, `readOnly`, `writeOnly`, `deprecated`, `$id` go into `Metadata`.
- `ref_key` (util.rs:557): `"#"` → `RefKey::Root`; otherwise last `/` segment with `~1`/`~0`
  decoding.
- Round-trip test: decode every schema in `.repos/typify/typify/tests/schemas/*.json`,
  `github.json` and `vega.json` without error.

### M3: IR + conversion core

Port in dependency order, each with its upstream unit tests (about 102 `#[test]`s, rewritten as
`moon test` snapshots of an IR dump):

0. Settings, `SchemaCache` (`conversions.rs`), replacement and `x-rust-type` hooks first, since
   `convert_schema` consults them before dispatch (convert.rs:24–58). `validate.rs` early, since
   merge filtering uses it.
1. `type_entry.rs` data types, `TypeSpace` store, `assign_type`, `id_for_schema`,
   `add_ref_types` (3-pass), `add_root_schema`, `add_type[_with_name]`.
2. `convert.rs` dispatch. Port **arm by arm in the same order** (lines 58–792), with one predicate
   helper per arm documenting the upstream line. Leaves: `convert_string` / `integer` / `number` /
   `bool` / `array` / `option` / `reference` / `enum_string` / `typed_enum` / `unknown_enum`.
3. `structs.rs`: `struct_members`, `struct_property`, `has_default`, `make_map`,
   `flattened_union_struct`.
4. `enums.rs`: option, external, adjacent, internal (in this order), singleton, untagged; variant
   naming with the collision retry; common-prefix stripping.
5. `util.rs` schema helpers and mutual exclusion (`all_mutually_exclusive` and friends).
6. `merge.rs`: `try_merge_schema` and per-field merges, subschema folding, not-subtraction,
   `Roughly`. Port its tests (merge.rs:1339+) together with it.
7. `cycles.rs`, `defaults.rs` (`validate_value`, `check_defaults`), `TypeEntryEnum::finalize`,
   `has_impl`.
8. `TypeSpaceSettings`: builder, derives, attrs, patch, replacement, conversion (`SchemaCache`),
   crates / unknown crates, map type, type_mod.

Accepted when: all 21+2 test schemas plus github/vega convert without `Unsupported`, and the ported
unit tests pass.

### M4: Rust backend (oracle-checked)

- `OutputSpace`: `SortedMap[(Section, String), StringBuilder]` with sections
  `Crate < Builder < Defaults < Error`.
- Emitters: `output_enum`, `output_struct` (+ builder), `output_newtype` (the 4 constraint kinds),
  `type_ident`, `output_value`, `default_fn`, `generate_serde_attr`, `make_doc`, stock default
  fns, `ConversionError`. Upstream decides whether to emit these by substring search over the
  output; we keep that behavior on purpose, to stay golden-exact.
- Output is emitted as **token-ish text**: upstream `TokenStream::to_string()` spacing isn't
  needed, because the golden check normalizes with rustfmt. We aim for readable, roughly formatted
  text so CLI output is usable without rustfmt.
- `x-rust-type` (`rust_extension.rs`) with a small semver-requirement matcher.
- CLI parity: `-b/-B`, `-d`, `-a`, `-o` (default `input.rs`, `-` for stdout), `--crate`,
  `--map-type`, `--unknown-crates`, and the 4 `#![allow(clippy::…)]` prelude lines.

Accepted when: `scripts/check-rust-goldens.sh` passes for **all 23 schema goldens and the 3 `.out`
files**, byte-equal after `rustfmt` on both sides (§6.1).

### M5: MoonBit backend

Type mapping (proposal, see §9 Q2):

| IR | MoonBit |
|---|---|
| Boolean / String / Unit / JsonValue | `Bool` / `String` / `Unit` / `Json` |
| I8, I16 / U8 / U16 / I32 / U32 / I64 / U64 | `Int` with range check, `Int16` / `Byte` / `UInt16` / `Int` / `UInt` / `Int64` / `UInt64` |
| NonZero* | underlying type + nonzero check in `from_json` |
| F32 / F64 | `Float` / `Double` |
| Option(T) | `T?` |
| Box(T) | `T` (MoonBit values are references, so recursion needs no Box) |
| Vec / Set | `Array[T]` (upstream also emits Set as Vec) |
| Array(T, n) | `FixedArray[T]` + length check |
| Tuple | `(A, B, …)` ↔ JSON array |
| Map(K, V) | `Map[K, V]`; serialize keys sorted, like `serde_json::Map` |
| Uuid / Date / DateTime / Ip* | runtime newtypes (`@runtime.Uuid`, `NaiveDate`, `DateTimeUtc`, `IpAddr`…) that validate and normalise exactly like uuid/chrono/std::net serde impls |
| Replacement / x-rust-type natives | require an explicit MoonBit mapping in settings; otherwise `Json` with a documented warning |
| Struct | `pub(all) struct` + manual `ToJson`/`FromJson` |
| Enum | `pub(all) enum`; struct variants use labeled fields `V(a~ : T)` |
| Newtype | `pub(all) struct N(T)`; constrained → `N::new(..) -> N raise ConversionError` with a private field |

Serde semantics to reproduce in generated `from_json`/`to_json`:

1. Field `rename`: JSON key vs identifier.
2. `skip_serializing_if` for `Option::is_none`, `Vec::is_empty`, `Map::is_empty`.
3. `default`: a missing key gives an intrinsic default; `default = "defaults::f"` calls a generated
   `fn default_<type>_<prop>()`.
4. `deserialize_with = Option::deserialize` (Required + Option): the key must be present but may be
   `null`.
5. `deny_unknown_fields` exactly as serde_derive (struct_.rs:347 checks leftovers after flattened
   decoding), and as typify emits it (structs.rs:94 disables it in some paths).
6. `flatten` via a shared entry buffer: each flattened struct *consumes* the keys it recognises;
   a flattened Map takes the leftovers; `Option<T>` flatten yields `None` on failure. Serialize
   by concatenating entries (duplicate keys are possible and must be preserved in the writer).
7. Nested `Option<Option<T>>` collapse (type_entry.rs:1751).
8. Enums:
   - external `{"V": payload}` or `"V"`;
   - internal: the tag merged into the struct fields;
   - adjacent `{tag, content}`;
   - untagged: try each variant in declaration order, first success wins.
9. `transparent` newtypes.
10. Unit/null variants.
11. Constraint checks: string length in **chars** (code points, not UTF-16 units), patterns,
    enum/deny lists. Error messages must match upstream.
12. Integer range checks for every integer kind. Read `Number(_, repr~)` so values above 2^53 are
    exact.
13. Struct fields in declaration order (upstream sorts them by Rust name). Typed maps are
    `HashMap` upstream (unordered), so conformance compares maps order-insensitively; MoonBit keeps
    insertion order. `serde_json::Map` (String→Json) is sorted.

Generated support code: a small runtime (decode helpers, `ConversionError`, `JsonPath`
bookkeeping). Emitted inline or as a dependency package (§9 Q1).

Also for MoonBit output:

- Keyword and reserved-name handling for MoonBit.
- `Show`/`Debug`/`Eq`/`Default` derives where valid.
- Display / FromStr equivalents (`to_string`, `T::parse`).
- Builders: replaced by a constructor with labeled/optional args (§9 Q4).
- Doc comments as `///|` + `/// …`.

Accepted when: generated MoonBit for every test schema passes `moon check`, and M6 passes.

### M6: Cross-language conformance

- `conformance/rust/`: a cargo crate that `include!`s the upstream golden `.rs` for each schema and
  exposes `roundtrip <Type> < instance.json`, printing `OK <canonical json>` or `ERR`.
- `conformance/moonbit/`: a moon package with the generated MoonBit and the same interface.
- Corpus `conformance/cases/<schema>/<Type>/*.json`:
  - hand-written edge cases (missing, null and empty fields; unknown keys; each enum form; big
    integers; unicode lengths);
  - later, schema-driven random instances.
- `scripts/conformance.sh` runs both sides and diffs. Requirement: the two sides agree on
  accept/reject and on the canonical output.
- Extra fixtures for gaps with no upstream golden: adjacent tagging (enums.rs:922),
  `default_u64` / `default_i64` (defaults.rs:851+), and custom `HashMap` map type.
- Differential checks cover acceptance, *which untagged variant was chosen*, and serialization
  (not just roundtrip equality); raw duplicate-key fixtures; numeric categories.
- A minimal version of this harness is brought up during M4 (not after M5), so codec semantics
  are tested as soon as the first MoonBit output exists.

### M7: Validation, polish, release

- The `pattern` runtime for generated MoonBit (§5.6), the `regress`-equivalent compile check, and
  the enum filtering in the generator.
- CLI `--lang moonbit`: `-o` default `input.mbt`, and options for the package name/visibility.
- README with `moonx` usage. Publish to mooncakes (`moon publish`). Tag `v0.1.0`.

## 5. Hard problems and approach

1. **Golden-exact naming**: heck 0.5 semantics and XID tables must match exactly. Mitigation:
   port heck's test suite and fuzz against the Rust heck through the conformance crate.
2. **Ordered pattern-match dispatch** in `convert_schema_object`: port arm by arm, with a comment
   giving the upstream line, and add a regression test per arm.
3. **Name sanitizing is Rust-centric** (`accept_as_ident` appends `_` to Rust keywords). The IR
   stores the raw name *and* the Rust identifier. The MoonBit backend re-sanitizes from the raw
   name using its own keyword set and collision handling, so MoonBit identifiers are not polluted
   by Rust rules.
4. **merge.rs** is dense and lightly tested. Port its tests first, then add golden coverage through
   `merged-schemas.json`.
5. **Float math for integer bounds** (f64 comparisons, int64/uint64 edge values): reproduce upstream
   comparisons literally, using `Double`, and test the edge values.
6. **Regex**: `(?=a)(?=b)` requires both assertions at the *same* position, so splitting into
   independent searches is wrong. We implement a backtracking ECMAScript engine with regress
   0.12's default flags (lookahead/lookbehind, backrefs, classes, Unicode escapes), used both by
   the generator (pattern validity, enum filtering via `find`) and by generated MoonBit code via
   `runtime`. Differentially tested against regress.
7. **Struct field order and map order** affect serialized output. Tests compare canonical JSON with
   sorted keys, plus one strict-order test for struct fields.

## 6. Testing strategy

Unit tests (ported upstream `#[test]`s plus our own) and property tests
(`moonbitlang/core/quickcheck`) are written from M1 on: properties for leaf libraries
(ordering, parse/print roundtrips), bounded random schemas (conversion never crashes, generated
code type-checks), naming-collision generators, and random instances for codec agreement.

### 6.1 Rust golden oracle (`scripts/check-rust-goldens.sh`)

For each `typify/tests/schemas/*.json` (with the settings from `typify/tests/schemas.rs`: builder,
the `HandGeneratedType` replacement, the `TypeThatNeedsMoreDerives` patch, the `{"enum":[1,"one"]}`
conversion, `with_crate("std")`), and for the `.out` tests with their settings:

1. `moon run cmd/typify -- --config tests/settings/<name>.json <schema> -o /tmp/x.rs`
2. Wrap it the way `schemas.rs` does, then run `rustfmt` on it.
3. `diff` against the golden.

The settings that `schemas.rs` passes through the Rust API need a CLI-reachable form, so there is a
`--config <settings.json>` flag for patches, replacements and conversions. This also gives a
feature upstream's CLI lacks.

### 6.2 MoonBit unit and snapshot tests

- Ported upstream unit tests.
- IR dumps via `debug_inspect`.
- Generated MoonBit snapshots per schema, in `tests/moonbit_golden/*.mbt`, checked with
  `moon test --update`.

### 6.3 Cross-language conformance (M6), and generated-code compile checks

- `moon check` on the generated MoonBit.
- Optionally `cargo check` on the generated Rust.

## 7. Git workflow

- `main` is always green (`moon check && moon test`). Use a branch per milestone (`m1-leaf-libs`,
  …), merged with `--no-ff` when its acceptance criteria are met.
- Small commits, one ported upstream file or feature each, with messages like
  `port: convert_integer (convert.rs:979)`.
- The upstream commit is recorded in `UPSTREAM.md`. Syncing = diff upstream `5ccedd1..new` and port
  the changes.
- `pkg.generated.mbti` files are committed; `moon info` diffs are reviewed.
- Test fixtures copied from upstream keep their Apache-2.0 notice.

## 8. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Golden mismatch caused by rustfmt spacing, not logic | Med | Normalize both sides with rustfmt; if still noisy, compare `syn`-parsed ASTs in the conformance crate |
| wasm backend performance on vega (46k lines of output) | Low–Med | Use StringBuilder everywhere; benchmark in M4 |
| `moonbitlang/regexp` semantics ≠ ECMAScript | Med | §5.6; conformance tests |
| schemars decoding quirks not visible in source (not in cargo cache) | Med | `cargo vendor` schemars 0.8.22 into `.repos/` in M2 |
| Scope creep in the MoonBit backend (builders, Display, …) | Med | M5 MVP = types + to/from_json; extras after M6 |

## 9. Open questions for the owner

1. **Runtime for generated MoonBit**: inline helpers in each generated file (self-contained,
   duplicated), or depend on a published `bobzhang/typify/runtime` package (smaller output, extra
   dependency)? *Proposal: runtime package.*
2. **Integer mapping**: map `i8`/`i16`/`u16` to precise MoonBit types (`Int16`, `UInt16`, `Byte`)
   or to `Int` with range checks? *Proposal: precise types where MoonBit has them.*
3. **Formats** (`uuid`, `date`, `date-time`, `ip`): validated runtime newtypes matching the Rust
   crates' serde behaviour (decided after review: plain `String` would break wire parity).
4. **Builders in MoonBit**: skip them in favor of labeled/optional constructor args? *Proposal:
   yes.*
5. **Module name** `bobzhang/typify` (from the mooncakes credentials): OK?
6. **Rust output exactness**: byte-equal after rustfmt (strict), or semantically equivalent?
   *Proposal: strict.*
