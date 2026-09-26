# Evolving a schema

This guide covers changing a JSON Schema after data and programs already use it.
Generated MoonBit and Rust decode JSON with serde's rules, so whether a change is safe
follows from those rules and from how typify maps the schema to types.

The compatibility table's rows are checked by
[`examples/evolution`](../examples/evolution):
- `v1/` and `v2/` are generated from `v1/schema.json` and `v2/schema.json`, one type
  per change;
- `evolution_test.mbt` decodes each version's output with the other version's types,
  in both directions, for representative values.

The recipes and other sections follow from the same rules, but are not all tested.

Compatibility has two directions:

- **forward:** *old* readers accept data from *new* writers (upgrade writers first);
- **backward:** *new* readers accept data from *old* writers, including stored data
  (upgrade readers first).

## Wire compatibility

| Change (v1 → v2) | Old reader, new data | New reader, old data |
|---|---|---|
| Add an optional property | ✅ ignored | ✅ `None` (empty for arrays and maps) |
| Add an optional property with a `default` | ✅ ignored | ✅ the default |
| Add an optional property to a closed object (`additionalProperties: false`) | ❌ ``unknown field `b`, expected `a` `` (✅ while the property is unset) | ✅ |
| Add a required property | ✅ ignored | ❌ ``missing field `b` `` |
| Add a required property *with a `default`* | ✅ ignored | ❌ ``missing field `b` `` (the default doesn't fill in a missing required property) |
| Remove a required property | ❌ ``missing field `b` `` | ✅ ignored |
| Remove an optional property | ✅ | ✅ ignored |
| Required → optional | ❌ ``missing field `b` `` when writers leave it unset (unset optionals are omitted) | ✅ |
| Required → optional *with a scalar `default`* (number, string, boolean) | ✅ still written | ✅ |
| Required → optional with a `[]`, `{}` or `null` default | ❌ empty or unset values are omitted | ✅ |
| Optional → required, even if nullable (`["string", "null"]`) | ✅ (unset is written as `null`) | ❌ ``missing field `b` ``; `null` is accepted, absence is not |
| Rename a required property | ❌ | ❌ (typify emits no serde `alias`) |
| Rename an optional property | ⚠️ accepted, but the value is silently lost | ⚠️ same |
| Tighten a validated constraint (string `maxLength`/`minLength`/`pattern`) | ✅ | ❌ e.g. `longer than 3 characters` for old values |
| Tighten a numeric bound | ✅ | ⚠️ often not enforced at all (see below) |
| Widen an integer (`int32` → `int64`) | ❌ ``invalid value: integer `5000000000`, expected i32`` for large values | ✅ |
| Add a value to a string `enum` | ❌ ``unknown variant `cancelled`, expected `pending` or `shipped` `` | ✅ |
| Add a value to an *open* enum (see below) | ✅ decoded as the catch-all string | ✅ |
| Change an array to a fixed length (equal `minItems`/`maxItems`) | ✅ | ❌ other lengths are rejected (e.g. `trailing characters`) |
| Change a property's `default` | ✅ | ⚠️ accepted, but stored data that omits the property now reads differently |

**Round trips through old readers lose data.** An old reader drops properties it
doesn't know. So a v1 program that reads v2 data, modifies it and writes it back
silently deletes the v2 fields (`{"a":"x","b":"y"}` becomes `{"a":"x"}`). Use
`additionalProperties: {}` when that matters (see below).

## Recipes

**Add properties as optional.** Leave new properties out of `required`. Give them a
`default` if readers should see a value rather than `None`. A `default` on a *required*
property does not make it optional: a missing value is still an error.

**Don't close objects that will grow.** `additionalProperties: false` becomes
`deny_unknown_fields`, which makes every new property a breaking change for old
readers. Close an object only if it is final.

**Preserve unknown properties** with `additionalProperties: {}`. typify then adds a
flattened `extra` map that collects unknown properties, and old readers write them
back. In MoonBit the map is `Map[String, Json]`; in Rust it is `serde_json::Map`.

```json
{ "type": "object", "properties": { "a": { "type": "string" } }, "additionalProperties": {} }
```

Some limits apply:
- The values are preserved, not the original text or key order. Keys are re-emitted
  after the known properties: sorted for `serde_json::Map`, in unspecified order for
  typed maps (`HashMap`).
- Omitting `additionalProperties`, or writing `true`, ignores unknown properties.
  (An object with *no* declared properties becomes a map either way.)

**Make enums open** when new values will appear. A plain `enum` is closed: old
readers reject new values. Use a `oneOf` of the known values and *any other* string:

```json
{ "oneOf": [
    { "type": "string", "enum": ["pending", "shipped"] },
    { "type": "string", "not": { "enum": ["pending", "shipped"] } } ] }
```

typify generates an untagged enum:
- `Variant0(Known)` for the listed values;
- `Variant1(Other)`, a string newtype that rejects the known values.

A v1 reader decodes a new value `"cancelled"` as `Variant1("cancelled")` and writes it
back unchanged, and a v2 reader decodes it as a known variant. Adding a value means
adding it to both lists.

The branches must be disjoint. The shorter `oneOf: [{enum: [...]}, {type: "string"}]`
is a valid schema, but it means something else: a known value matches both branches,
and `oneOf` requires exactly one, so strict JSON Schema validators *reject* the known
values. typify still generates a similar enum, but its catch-all is a plain string
without the check.

**Remove in stages.** A property that old readers require must keep being written
until those readers are retired:
1. Make it optional in the schema, but keep writing it.
2. Upgrade every reader.
3. Stop writing it.
4. Delete it from the schema.

**Rename by expand and contract.**
1. Add the new name as an optional property.
2. Write both names, and let readers accept either.
3. Once no reader or stored data depends on the old name, remove it (in stages, as
   above).

typify generates no serde `alias`. Renaming a required property in place breaks both
directions; renaming an optional one silently loses the value in both directions.

**Know which constraints are enforced.** Readers reject data violating:
- string `minLength`, `maxLength` and `pattern`;
- `enum` values;
- integer bounds, but only as far as they select a Rust integer type. Bounds of
  `0..=255` become `u8`; `minimum: 1` becomes a non-zero `u64`.

Other bounds are dropped. `minimum: 1, maximum: 100` accepts `500`, float bounds are
ignored, and so are recognised string `format`s beyond their own parsing (`uuid`,
`date-time`, …).

Tightening an enforced constraint can reject existing data, so check stored and
in-flight values first. Tightening an unenforced one changes nothing at runtime. In
Rust the validation is also available through `TryFrom`/`FromStr`; in MoonBit through
the validating `new` of constrained newtypes.

**Widen numbers readers first.** A wider integer (`int32` → `int64`, `uint8` →
`uint16`) is safe for new readers of old data. Old readers reject values outside the
old range, so upgrade readers before writers produce such values. Changing `integer`
to `number` also changes the type to a float: integers above 2^53 lose precision.

**Distinguish absent from `null`.**
- A required property must be present even if its type allows `null`.
- An optional nullable property accepts either, and writers omit it when unset.
- Making a property required, or dropping `null` from its type, breaks old data that
  omits it or stores `null`.

**Treat untagged unions carefully.** `oneOf`/`anyOf` members that typify can't
distinguish by a tag become an *untagged* enum. It tries the members in schema order
and picks the first that accepts the value. Adding or reordering members can change
which variant existing data decodes to, even though nothing is rejected. Put new
members last, and keep them from overlapping earlier ones. (typify reduces some unions
differently: nullable unions become `Option`, and objects that differ in a constant
property become tagged enums.)

**Tagged enums** (`oneOf` of objects with a common tag property):
- Adding a variant is like adding an enum value: old readers reject the new tag.
- Adding a property to a variant follows the object rules above, per variant.

Test a new variant and a changed variant separately.

**Changing a `default`** is accepted by every reader. But stored documents that omit
the property now read as the new value. Treat it as a data migration, not as a
compatible change.

**Generator-specific behaviour:**
- Renaming a definition renames the generated type. That breaks source code, but not
  the wire format.
- `const` on an ordinary property is ignored.
- `minItems`/`maxItems` are ignored, except that equal positive values turn an array
  into a fixed-size array or tuple. That changes the type, and the decoder then
  rejects other lengths.
- `x-rust-type` and replacement settings map a schema to an existing Rust type.
  Changing them changes the generated types. In MoonBit, recognised types (`Uuid`,
  dates, IP addresses, `String`) keep their mapping and others become `Json`. A
  replacement Rust type with custom serde code can also change the wire format.

## MoonBit source compatibility

Regenerating also changes the MoonBit API that code builds against:

- **New optional or defaulted property:** constructor calls `T(...)` keep compiling,
  because the new argument is optional. Struct literals `T::{ ... }` stop compiling,
  since every field must be given, and so do patterns that list every field without
  `..`.
- **New required property:** every construction site fails to compile until it
  supplies the value. That is intended: it is also a wire-breaking change. The
  exception is a required *nullable* property. Its constructor argument is optional,
  and it is written as `null` when left out.
- **New enum variant:** exhaustive `match`es fail to compile until they handle it.
- **Removed or renamed property, variant or definition:** every use fails to compile.

Prefer the generated constructors over struct literals in code that should survive
schema additions.

## Checking a change

1. **Keep the previous schema** next to the new one, and pin the generator version
   and settings (`--map-type`, derives, …).
2. **Generate both versions**, each into its own package.
3. **Test both directions** with representative values, as `examples/evolution` does:
   - absent versus `null` properties;
   - boundary values of constraints;
   - unknown properties, and every union and enum variant (new and existing);
   - a read-modify-write round trip through the old reader.
4. **Test Rust too** if the other side is Rust. It uses the same rules, so the MoonBit
   results carry over, but a test against the compiled Rust types covers settings that
   differ between the two builds.

A passing test shows that the tested values are compatible. It does not prove that
every value is.
