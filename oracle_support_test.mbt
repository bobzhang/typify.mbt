// Shared helpers for tests that compare against upstream typify's output
// (tests/oracle/typify, produced by scripts/typify-oracle).

///|
fn read_file(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    e => abort("cannot read \{path}: \{Repr(e)}")
  }
}

///|
fn file_exists(path : String) -> Bool {
  try @fs.read_file_to_string(path) catch {
    _ => false
  } noraise {
    _ => true
  }
}

///|
/// The settings upstream's typify/tests/schemas.rs uses.
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
/// (fixture name, input path, settings) for every oracle case.
fn oracle_cases() -> Array[(String, String, @typify.TypeSpaceSettings, Bool)] raise {
  let cases = []
  for name in upstream_schema_names {
    cases.push(
      (
        name,
        "tests/upstream/schemas/\{name}.json",
        schemas_settings(@typify.TypeSpaceSettings::default()),
        false,
      ),
    )
  }
  cases.push(
    (
      "maps_custom",
      "tests/upstream/schemas/maps.json",
      schemas_settings(
        @typify.TypeSpaceSettings::default().with_map_type(
          "std::collections::BTreeMap",
        ),
      ),
      false,
    ),
  )
  cases.push(
    (
      "various-enums-json-schema",
      "tests/upstream/schemas/various-enums.json",
      schemas_settings(
        @typify.TypeSpaceSettings::default().with_derive("schemars::JsonSchema"),
      ),
      false,
    ),
  )
  cases.push(
    (
      "github",
      "tests/upstream/impl/github.json",
      @typify.TypeSpaceSettings::default(),
      true,
    ),
  )
  guard @serde_json.parse(
      "{\"enum\": [null, \"normal\", \"bold\", \"lighter\", \"bolder\", \"100\", \"200\", \"300\", \"400\", \"500\", \"600\", \"700\", \"800\", \"900\", 100, 200, 300, 400, 500, 600, 700, 800, 900]}",
    )
    is Object(conv) else {
    fail("bad conversion schema")
  }
  cases.push(
    (
      "vega",
      "tests/upstream/impl/vega.json",
      @typify.TypeSpaceSettings::default()
      .with_conversion(@schema.decode_schema_object(conv), "MyEnum", [FromStr])
      .with_replacement("ColorValue", "ColorValue", []),
      true,
    ),
  )
  cases
}

///|
/// Load a fixture, setting the root title to "Everything" when requested
/// (as upstream's github/vega tests do).
fn load_root(path : String, everything : Bool) -> @schema.RootSchema raise {
  let root = @schema.RootSchema::from_json_str(read_file(path))
  if !everything {
    return root
  }
  let metadata = root.schema.metadata.unwrap_or(@schema.Metadata::default())
  {
    ..root,
    schema: {
      ..root.schema,
      metadata: Some({ ..metadata, title: Some("Everything"), }),
    },
  }
}

///|
let upstream_schema_names : Array[String] = [
  "arrays-and-tuples", "deny-list", "extraneous-enum", "flatten-default", "id-or-name",
  "maps", "merged-schemas", "more_types", "multiple-instance-types", "noisy-types",
  "property-pattern", "reflexive", "rust-collisions", "simple-types", "string-enum-with-default",
  "type-with-modified-generation", "types-with-defaults", "types-with-more-impls",
  "untyped-enum-with-null", "various-enums", "x-rust-type",
]
