# MoonBit backend options

By default the MoonBit backend generates self-contained, fully public types. To make
the generated types *be* the types of an existing package, pass a config file:

```bash
typify schema.json --lang moonbit --moonbit-config schema.moonbit.json -o types.mbt
```

The config file is MoonBit-specific, so it lives next to the schema instead of inside
it. The schema stays language-neutral and can generate Rust too. The same options are
available from the library as `@moonbit.Options` and `@moonbit.generate_with`.
The library fields mirror the JSON keys, with one exception: the constructor
switch is `Options.constructor_` / `TypeOptions.constructor_` in MoonBit, since
`constructor` is a reserved word (reserved words take a trailing `_`). The JSON
key is still `"constructor"`.

Types are named by their typify type names (the names the Rust output uses). Unknown
keys, type names and variant names are errors.

## Example

openseek generates its session types this way. The generated file sits in the
`agent_session` package next to the hand-written constructors and methods:

```json
{
  "roots": ["SessionEvent"],
  "from_json": true,
  "codecs": "package",
  "error_paths": true,
  "strict_warnings": true,
  "defaults": { "visibility": "abstract", "constructor": false },
  "types": {
    "SessionItem": {
      "visibility": "pub(all)",
      "variants": { "tool_result": "Tool", "runtime_notice": "Runtime" }
    },
    "TokenUsage": { "visibility": "pub(all)" },
    "SessionToolCall": { "visibility": "priv" },
    "Content": { "replace": "Content", "codec": "json" },
    "TurnTerminal": { "replace": "TurnTerminal", "codec": "json" }
  }
}
```

## Top-level keys

| Key | Default | Meaning |
|---|---|---|
| `roots` | all types | Emit only these types and the types they reach. |
| `defaults.visibility` | `"pub(all)"` | Visibility for types without their own setting. |
| `defaults.constructor` | `true` | Whether to generate `T(...)` constructors. |
| `from_json` | `false` | Also implement core `FromJson` (the package must import `moonbitlang/core/json`). |
| `codecs` | `"public"` | `"package"` keeps the generated codecs private: the `Serde` impl and `deserialize`, `serialize`, `from_json_str`, `to_json_string`. The public API is then only the types, `ToJson` and `FromJson`. |
| `error_paths` | `false` | Errors say where decoding failed, e.g. ``missing field `x` at /item/payload``. serde's own messages carry no path. |
| `strict_warnings` | `false` | Warning-free output under strict settings (`+implicit_impl_as_method`, `+unnecessary_annotation`, `+missing_doc`), with no package-level override. |

Without `roots`, every type is emitted except replaced types and types only they
use.

## Per-type keys (`types.<Name>`)

| Key | Meaning |
|---|---|
| `name` | The MoonBit type name to use instead of the generated one. |
| `visibility` | `"pub(all)"`, `"pub"` (read-only), `"abstract"` (representation hidden) or `"priv"`. Methods and impls of a private type are private. |
| `constructor` | `false` to skip `T(...)`, e.g. when the package has its own. |
| `variants` | Constructor names for enum variants, by their JSON name: `{ "tool_result": "Tool" }`. |
| `replace` + `codec` | Use an existing type instead of generating one. The schema still documents its JSON. See below. |

## Replacement types

`"replace": "<type>"` names an existing MoonBit type, such as `Content` or
`@protocol.Content`. Generated code refers to it and decodes and encodes it with its
`codec`:

- `"serde"`: the type implements `@typify_rt.Serde`. This has exact serde semantics.
- `"json"`: through the type's core `FromJson` / `ToJson`. Keys keep their order, so
  output bytes match. Duplicate keys are resolved (last wins) before the type sees
  them, and error messages are the type's own.
- `{ "decode": "f", "encode": "g" }`: functions
  `(@typify_rt.De) -> T raise @typify_rt.DeError` and
  `(T) -> @typify_rt.Content raise @typify_rt.SerError`.

Use a replacement when the JSON needs interpretation that a schema cannot express.
openseek's `TurnTerminal`, for example, maps legacy encodings to dedicated variants.

## Keeping the generated file current

Generate from one recipe with a pinned generator version, and check in CI that the
committed file matches:

```bash
moonx bobzhang/typify/cmd/typify@0.2.0 schema.json --lang moonbit --preserve-order \
  --moonbit-config schema.moonbit.json -o - | diff -q - types.mbt
```

Mark the generated file as formatter-ignored in its package's `moon.pkg`:
`formatter = { "ignore": [ "types.mbt" ] }`.
