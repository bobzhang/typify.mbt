# typify.mbt

Generate **Rust** and **MoonBit** types from JSON Schema. This is a MoonBit port of
[oxidecomputer/typify](https://github.com/oxidecomputer/typify), and it runs anywhere
MoonBit's Wasm backend runs, with no Rust toolchain needed.

- **Rust output** is identical to upstream typify's for the same schema and settings.
  It emits the same token stream as `typify-impl`, with the same type names,
  derives, serde attributes, builders and `TryFrom` validation.
- **MoonBit output** mirrors the Rust types and adds JSON codecs that behave like
  the serde-derived Rust code:
  - the same inputs are accepted and rejected, with the same error messages;
  - accepted inputs decode to the same values;
  - values encode to byte-identical JSON.

  So a Rust service and a MoonBit program can share one schema and exchange JSON
  without surprises.

## Command line

```bash
moonx bobzhang/typify/cmd/typify schema.json                  # writes schema.rs
moonx bobzhang/typify/cmd/typify schema.json --lang moonbit   # writes schema.mbt
moonx bobzhang/typify/cmd/typify schema.json -o -             # to stdout
```

The options are the same as `cargo typify`'s, plus `--lang`:

| option | |
|---|---|
| `-l, --lang <rust\|moonbit>` | language to generate (default `rust`) |
| `-b, --builder` / `-B, --no-builder` | builder-style interface for Rust structs (default on) |
| `-d, --additional-derive <derive>` | extra derive for every type |
| `-a, --additional-attr <attr>` | extra attribute for every type |
| `-o, --output <file>` | output file, `-` for stdout (default: input with `.rs`/`.mbt`) |
| `--crate <name@version>` | crates assumed available for `x-rust-type` |
| `--map-type <type>` | map type (default `::std::collections::HashMap`) |
| `--unknown-crates <generate\|allow\|deny>` | policy for unknown `x-rust-type` crates |

Rust output is printed as a token stream, exactly as upstream typify produces it.
`cargo typify` runs rustfmt on it; you can do the same:

```bash
moonx bobzhang/typify/cmd/typify schema.json -o - | rustfmt --edition 2021 > schema.rs
```

## Generated MoonBit

The generated file is one MoonBit package. It depends on the runtime package:

```
// moon.pkg of the package holding the generated file
import {
  "bobzhang/typify/runtime" @typify_rt,
}
```

Every generated type `T` has the following:

- `T::from_json_str(text)`: decode JSON text, like `serde_json::from_str`.
- `value.to_json_string()`: encode as compact JSON, like `serde_json::to_string`.
- `T::from_json(json)` and `value.to_json()`: conversions to and from the builtin `Json`.
  These are lossy: duplicate keys and number spellings are not representable in `Json`.
- `T::deserialize(de)` and `value.serialize()`: the underlying `@typify_rt.Serde` trait.
- `T::default()` when the schema gives a default.
- For string enums: `to_string`, `parse` and `variant_index`.

For example, with this schema (upstream typify's README example):

```json
{
  "title": "Veggies",
  "type": "object",
  "properties": {
    "fruits": { "type": "array", "items": { "type": "string" } },
    "vegetables": { "type": "array", "items": { "$ref": "#/definitions/veggie" } }
  },
  "definitions": {
    "veggie": {
      "type": "object",
      "required": ["veggieName", "veggieLike"],
      "properties": {
        "veggieName": { "type": "string" },
        "veggieLike": { "type": "boolean" }
      }
    }
  }
}
```

the generated MoonBit can be used like this:

```moonbit
let veggies = Veggies::from_json_str(
  "{\"fruits\":[\"apple\"],\"vegetables\":[{\"veggieName\":\"leek\",\"veggieLike\":true}]}",
)
println(veggies.vegetables[0].veggie_name) // leek
println(veggies.to_json_string()) // same JSON as serde_json::to_string
```

### Type mapping

| JSON Schema / Rust | MoonBit |
|---|---|
| `bool`, `String` | `Bool`, `String` |
| `i8`/`i32`, `i16`, `i64` | `Int`, `Int16`, `Int64` |
| `u8`, `u16`, `u32`, `u64`, `NonZeroU*` | `Byte`, `UInt16`, `UInt`, `UInt64` (non-zero is checked) |
| `f32`, `f64` | `Float`, `Double` (serialized with the shortest `f32`/`f64` digits, as serde_json does) |
| `Option<T>`, `Box<T>` | `T?`, `T` |
| `Vec<T>`, sets, `[T; N]`, tuples | `Array[T]`, `Array[T]`, `FixedArray[T]`, tuples |
| `HashMap<K, V>` / `BTreeMap` | `Map[K, V]` (`BTreeMap` output is key-sorted) |
| `serde_json::Value` | `Json` |
| `uuid::Uuid`, `chrono::NaiveDate`, `chrono::DateTime<Utc>` | `@typify_rt.Uuid`, `@typify_rt.NaiveDate`, `@typify_rt.DateTimeUtc` |
| `std::net::{IpAddr, Ipv4Addr, Ipv6Addr}` | `@typify_rt.IpAddr`, `Ipv4Addr`, `Ipv6Addr` |
| constrained strings, numbers and enums | newtypes validated on construction and decoding |

Structs, enums (external, internal, adjacent and untagged tagging), `flatten`,
`deny_unknown_fields`, defaults, positional (array) struct input and
duplicate-key rejection all follow serde's rules.

## Library

```moonbit
let root = @schema.RootSchema::from_json_str(schema_text)
let space = @typify.TypeSpace::new(@typify.TypeSpaceSettings::default())
space.add_root_schema(root)
let rust : String = @rust.to_stream(space).to_string()
let moonbit : String = @moonbit.generate(space)
```

`TypeSpaceSettings` supports the same builder methods as upstream typify:
`with_derive`, `with_attr`, `with_struct_builder`, `with_replacement`, `with_patch`,
`with_conversion`, `with_crate`, `with_unknown_crates`, `with_map_type` and `with_type_mod`.

## How it is verified

Every layer is checked differentially against the real Rust crates it ports.
The oracles live in `scripts/` and `conformance/rust`.

- **typify IR and Rust tokens:**
  - upstream typify's type descriptions and token streams, compared token for
    token, for every upstream fixture (including the github and vega schemas);
  - thousands of random schemas covering tagged unions, merges, defaults,
    references and formats;
  - upstream's errors and panics.
- **serde behaviour of the generated MoonBit:**
  - upstream's generated Rust is compiled with serde and fed the same instances,
    including duplicate keys, reordered keys, escapes, edge-case numbers,
    positional arrays and deep nesting;
  - output text and error messages must match exactly, across all upstream
    fixtures and hundreds of random schemas.
- **Building blocks:**
  - `serde_json` parsing, errors and number formatting (including zmij's `f32`/`f64` output);
  - `regress` regular expressions;
  - `schemars` schema decoding;
  - `heck` case conversion;
  - Unicode identifier tables;
  - `semver`;
  - the uuid, chrono and `std::net` parsers and printers.

## License

Apache-2.0, like upstream typify. The upstream fixtures in `tests/upstream` are
copied from oxidecomputer/typify.
