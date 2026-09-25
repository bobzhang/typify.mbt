// Compare the Rust output token-for-token with upstream typify's
// `to_stream().to_string()` (tests/oracle/typify/*.tokens).

///|
fn read_file(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    e => abort("cannot read \{path}: \{Repr(e)}")
  }
}

///|
fn schemas_settings(
  settings : @typify.TypeSpaceSettings,
) -> @typify.TypeSpaceSettings raise {
  guard @serde_json.parse("{\"enum\": [1, \"one\"]}") is Object(o) else {
    fail("bad conversion schema")
  }
  settings
  .with_replacement("HandGeneratedType", "String", [Display])
  .with_patch(
    "TypeThatNeedsMoreDerives",
    @typify.TypeSpacePatch::new()
    .with_rename("TypeThatHasMoreDerives")
    .with_derive("Eq")
    .with_derive("PartialEq"),
  )
  .with_conversion(@schema.decode_schema_object(o), "serde_json::Value", [
    Display,
  ])
  .with_crate("std", Version(@semver.Version::parse("1.0.0")))
  .with_struct_builder(true)
}

///|
let schema_names : Array[String] = [
  "arrays-and-tuples", "deny-list", "extraneous-enum", "flatten-default", "id-or-name",
  "maps", "merged-schemas", "more_types", "multiple-instance-types", "noisy-types",
  "property-pattern", "reflexive", "rust-collisions", "simple-types", "string-enum-with-default",
  "type-with-modified-generation", "types-with-defaults", "types-with-more-impls",
  "untyped-enum-with-null", "various-enums", "x-rust-type",
]

///|
fn first_diff(a : String, b : String) -> String {
  let n = a.length().min(b.length())
  let mut i = 0
  while i < n && a[i] == b[i] {
    i += 1
  }
  let from = (i - 80).max(0)
  let want = a.unsafe_substring(start=from, end=(i + 120).min(a.length()))
  let got = b.unsafe_substring(start=from, end=(i + 120).min(b.length()))
  "at offset \{i}:\n    want: …\{want}\n    got:  …\{got}"
}

///|
fn check(
  name : String,
  path : String,
  settings : @typify.TypeSpaceSettings,
  everything : Bool,
) -> String? raise {
  let root = @schema.RootSchema::from_json_str(read_file(path))
  let root = if everything {
    let metadata = root.schema.metadata.unwrap_or(@schema.Metadata::default())
    {
      ..root,
      schema: {
        ..root.schema,
        metadata: Some({ ..metadata, title: Some("Everything"), }),
      },
    }
  } else {
    root
  }
  let space = @typify.TypeSpace::new(settings)
  ignore(space.add_root_schema(root))
  let got = @rust.to_stream(space).to_string()
  let want = read_file("tests/oracle/typify/\{name}.tokens")
  if got == want {
    None
  } else {
    Some("\{name}: \{first_diff(want, got)}")
  }
}

///|
test "Rust output matches upstream typify token-for-token" {
  let failures = []
  for name in schema_names {
    if check(
        name,
        "tests/upstream/schemas/\{name}.json",
        schemas_settings(@typify.TypeSpaceSettings::default()),
        false,
      )
      is Some(f) {
      failures.push(f)
    }
  }
  if check(
      "maps_custom",
      "tests/upstream/schemas/maps.json",
      schemas_settings(
        @typify.TypeSpaceSettings::default().with_map_type(
          "std::collections::BTreeMap",
        ),
      ),
      false,
    )
    is Some(f) {
    failures.push(f)
  }
  if check(
      "various-enums-json-schema",
      "tests/upstream/schemas/various-enums.json",
      schemas_settings(
        @typify.TypeSpaceSettings::default().with_derive("schemars::JsonSchema"),
      ),
      false,
    )
    is Some(f) {
    failures.push(f)
  }
  if check(
      "github",
      "tests/upstream/impl/github.json",
      @typify.TypeSpaceSettings::default(),
      true,
    )
    is Some(f) {
    failures.push(f)
  }
  guard @serde_json.parse(
      "{\"enum\": [null, \"normal\", \"bold\", \"lighter\", \"bolder\", \"100\", \"200\", \"300\", \"400\", \"500\", \"600\", \"700\", \"800\", \"900\", 100, 200, 300, 400, 500, 600, 700, 800, 900]}",
    )
    is Object(conv) else {
    fail("bad conversion schema")
  }
  if check(
      "vega",
      "tests/upstream/impl/vega.json",
      @typify.TypeSpaceSettings::default()
      .with_conversion(@schema.decode_schema_object(conv), "MyEnum", [FromStr])
      .with_replacement("ColorValue", "ColorValue", []),
      true,
    )
    is Some(f) {
    failures.push(f)
  }
  if !failures.is_empty() {
    fail("\{failures.length()} mismatches:\n\{failures.join("\n")}")
  }
}
