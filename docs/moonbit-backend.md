# MoonBit backend design

Goal: for every type the Rust backend emits, emit a MoonBit type whose JSON
encoding and decoding behave exactly like the serde-derived Rust type:

- **Acceptance:** the same inputs are accepted or rejected.
- **Values:** accepted inputs decode to the same value (in particular, the same
  untagged variant is chosen).
- **Output:** values serialize to the same JSON text.

Inputs:
- The IR from `bobzhang/typify` (identical to upstream's IR).
- The Rust type names in the IR (e.g. `"u8"`, `"::uuid::Uuid"`), which are
  mapped to MoonBit types.

## Output shape

The generated output is one `.mbt` file of top-level items, intended to be one
package, whose `moon.pkg` imports a runtime package:

```
import { "bobzhang/typify/runtime" @typify_rt }
```

The runtime holds:
- codec helpers;
- a serde_json-exact JSON reader and writer;
- flatten buffers;
- the format types (`Uuid`, `Date`, `DateTimeUtc`, `IpAddr`, `Ipv4Addr`,
  `Ipv6Addr`);
- the ECMAScript `Regex` (re-exported from `bobzhang/typify/regex`);
- `ConversionError`.

The CLI option `--lang moonbit` selects this backend.

## JSON representation

Generated codecs implement the core traits:
- `ToJson` (`to_json(self) -> Json`);
- `@json.FromJson` (`from_json(Json, JsonPath) -> Self raise JsonDecodeError`).

This lets users write `@json.from_json(json)` and `v.to_json()`. The builtin
`Json` can't represent serde_json's number classification or its key order by
itself, so the runtime supplies:

- **`@typify_rt.parse(text) -> Json`:** parses with the serde_json port. Every
  float gets `Json::Number(d, repr=Some(serde_json_display))`, so decoders can
  tell `1.0` from `1`. Integers get a `repr` only if they exceed 2^53. Objects are
  built in serde_json (sorted) order.
  - Plain `@json.parse` output is also accepted, but `1.0` and `1` are
    indistinguishable there. The decoders then treat a repr-less integral number
    as an integer, which is lenient.
- **`@typify_rt.stringify(Json) -> String`:** compact output identical to
  serde_json:
  - `repr` is used when present;
  - integral numbers without a repr print as integers, other floats via ryu;
  - escaping follows serde_json;
  - object entries are printed in insertion order.
- **Encoders:**
  - every `f32`/`f64` value is encoded with `repr` set to serde_json's float text
    (so `1.0` stays `1.0`);
  - `u64`/`i64` values beyond 2^53 are encoded with an exact `repr`;
  - struct objects are built in field declaration order (serde's order);
  - `serde_json::Map`/`Value` payloads are re-sorted by key (serde_json's
    BTreeMap order);
  - typed maps (`HashMap` upstream, which is unordered) are emitted in insertion
    order. Conformance tests compare them order-insensitively.

## Type mapping

| IR / Rust | MoonBit | Decode checks |
|---|---|---|
| `bool` | `Bool` | JSON bool |
| `String` | `String` | JSON string |
| `i8` | `Int` | integer in [-128, 127] |
| `u8` | `Byte` | integer in [0, 255] |
| `i16` / `u16` | `Int16` / `UInt16` | range |
| `i32` / `u32` | `Int` / `UInt` | range |
| `i64` / `u64` | `Int64` / `UInt64` | range, exact via `repr` |
| `NonZeroU8..U64` | the corresponding unsigned type | also `!= 0` |
| `f32` / `f64` | `Float` / `Double` | any number |
| `Option<T>` | `T?` | a nested `Option<Option<T>>` collapses (as in Rust) |
| `Box<T>` | `T` | — |
| `Vec<T>`, `Set` (emitted as `Vec`) | `Array[T]` | — |
| `[T; N]` | `FixedArray[T]` | length exactly N |
| `(A, B)` | `(A, B)` | array of exactly that length |
| `()` | `Unit` | `null` |
| `HashMap<K, V>` / custom map | `Map[K, V]` | keys decoded from strings like serde_json's `MapKey` (integers parsed from strings, enums by name, newtypes validated) |
| `serde_json::Map<String, Value>` | `Map[String, Json]` | — |
| `serde_json::Value` | `Json` | — |
| `::uuid::Uuid` | `@typify_rt.Uuid` | `Uuid::parse_str` forms; serializes lowercase hyphenated |
| `chrono NaiveDate` | `@typify_rt.Date` | `%Y-%m-%d` |
| `DateTime<Utc>` | `@typify_rt.DateTimeUtc` | RFC 3339 with offset, normalised to UTC, chrono's `AutoSi` output |
| `std::net::IpAddr/Ipv4Addr/Ipv6Addr` | runtime types | std `FromStr`/`Display` (RFC 5952) |
| other native (replacement / `x-rust-type` / conversion) | `Json`, plus a warning comment | the MoonBit type can be supplied via settings (`with_moonbit_type(rust_name, mbt_type)`) |

## Items per IR type

- **Struct:**
  - `pub(all) struct T { f : Ty, ... } derive(Debug, Eq)`;
  - `impl ToJson`;
  - `impl FromJson`;
  - `T::default()` when upstream has a `Default`;
  - `T::new(required~, optional? = default)` as a builder replacement.
- **Enum:**
  - `pub(all) enum T { V; V(Ty); V(a~ : Ty, ...) }`;
  - codecs by tag type;
  - for all-simple enums, `T::to_string` and `T::parse(String) -> T raise` (the
    Display/FromStr parity).
- **Newtype:**
  - unconstrained: `pub(all) struct T(Inner)`;
  - constrained (string length/pattern, enum or deny values):
    `pub struct T(Inner)` (read-only), `T::new(Inner) -> T raise ConversionError`
    with upstream's error messages, `T::inner(self)`, and decoding that
    validates.

## Serde semantics reproduced (per property)

| upstream attribute | decode | encode |
|---|---|---|
| none, `Required` | key must exist (`missing field \`x\``); for `Option`, a missing key is `None` | always emitted |
| `rename = "k"` | JSON key `k` | key `k` |
| `default` | missing key → `Default::default()` (MoonBit zero value of the type) | — |
| `default = "defaults::f"` | missing key → generated `default_T_prop()` | — |
| `skip_serializing_if = Option::is_none` | — | omit when `None` |
| `skip_serializing_if = Vec::is_empty` / `Map::is_empty` | — | omit when empty |
| `deserialize_with = Option::deserialize` (Required + Option) | key must exist; `null` → `None` | `None` → `null` |
| `flatten` (map `extra`) | receives all keys not consumed by named fields | entries appended |
| `flatten` (Option<struct> subtype, anyOf) | decoded from the shared buffer; failure → `None`; consumes nothing (struct-access consumption only applies to named fields of nested non-flatten structs, as in serde) | object entries merged, in order |
| `flatten` (struct subtype, allOf) | decoded from the shared buffer; a failure fails the whole value | merged |
| `deny_unknown_fields` | unknown keys → `unknown field \`k\`, expected ...` | — |

Enums:
- **External:**
  - a unit variant is `"V"`, or `{"V": null}`;
  - other variants are `{"V": payload}`, and exactly one key is required.
- **Internal tag:** the object must contain the tag. The variant fields come from
  the remaining keys, and unknown keys follow `deny_unknown_fields`.
- **Adjacent:** `{tag, content}`; a unit variant has no content, or null content.
- **Untagged:** variants are tried in order and the first success wins; a unit
  variant matches `null`. Error: `data did not match any variant of untagged
  enum T`.

Errors: `JsonDecodeError((path, message))`, with serde_json's message texts
where practical.

## Identifier mapping

Rust identifiers from the IR are re-sanitized:
- MoonBit keywords and reserved words get a trailing `_`;
- enum constructors and type names that don't start with an ASCII uppercase
  letter get an `X` prefix;
- field names that don't start with a lowercase letter or `_` get an `x_`
  prefix.

The JSON names always come from the IR (`rename` / `raw_name`).

## Testing

1. Golden snapshots of generated MoonBit for every fixture schema. Each generated
   package must pass `moon check`; they're compiled in `tests/moonbit-generated/`.
2. **Conformance.** `scripts/conformance.sh`:
   - builds the upstream-generated Rust (the goldens) into a harness binary, and
     the generated MoonBit into a harness package;
   - feeds both the same JSON instances;
   - compares, per case: accept/reject, the chosen variant (via re-serialization)
     and the canonical output.

   Instances come from hand-written edge cases plus quickcheck-style random
   instances generated from the schemas.
3. Unit tests for the runtime (uuid, dates, IP addresses, the number codecs),
   with a Rust oracle for the format types.
