///|
let upstream_schemas : Array[String] = [
  "arrays-and-tuples.json", "deny-list.json", "extraneous-enum.json", "flatten-default.json",
  "id-or-name.json", "maps.json", "merged-schemas.json", "more_types.json", "multiple-instance-types.json",
  "noisy-types.json", "property-pattern.json", "reflexive.json", "rust-collisions.json",
  "simple-types.json", "string-enum-with-default.json", "type-with-modified-generation.json",
  "types-with-defaults.json", "types-with-more-impls.json", "untyped-enum-with-null.json",
  "various-enums.json", "x-rust-type.json",
]

///|
fn read(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    e => abort("cannot read \{path}: \{Repr(e)}")
  }
}

///|
test "all upstream fixture schemas decode" {
  for name in upstream_schemas {
    let text = read("tests/upstream/schemas/\{name}")
    ignore(@schema.RootSchema::from_json_str(text)) catch {
      e => fail("\{name}: \{e}")
    }
  }
  for name in ["github.json", "vega.json"] {
    let root = @schema.RootSchema::from_json_str(
      read("tests/upstream/impl/\{name}"),
    )
    assert_true(root.definitions.length() > 100)
  }
}

///|
fn decode(text : String) -> @schema.SchemaObject raise {
  guard @serde_json.parse(text) is Object(o) else { fail("not an object") }
  @schema.decode_schema_object(o)
}

///|
test "groups equal to their default are None (skip_if_default)" {
  let s = decode(
    "{\"title\": null, \"required\": [], \"properties\": {}, \"examples\": [], \"deprecated\": false}",
  )
  debug_inspect(s.metadata, content="None")
  debug_inspect(s.object, content="None")
  assert_eq(s, @schema.SchemaObject::default())
}

///|
test "null handling: Option fields vs allow_null" {
  let s = decode(
    "{\"format\": null, \"const\": null, \"default\": null, \"type\": null}",
  )
  debug_inspect(s.format, content="None")
  debug_inspect(s.instance_type, content="None")
  debug_inspect(s.const_value, content="Some(Null)")
  debug_inspect(s.metadata.map(m => m.default), content="Some(Some(Null))")
}

///|
test "unknown keys become extensions; known groups are consumed" {
  let s = decode(
    "{\"type\": \"string\", \"maxLength\": 5, \"x-rust-type\": {\"crate\": \"a\"}, \"definitions\": {}, \"$comment\": \"hi\"}",
  )
  debug_inspect(
    s.extensions.keys(),
    content=(
      #|["$comment", "definitions", "x-rust-type"]
    ),
  )
  debug_inspect(
    s.string,
    content=(
      #|Some({ max_length: Some(5), min_length: None, pattern: None })
    ),
  )
}

///|
test "root definitions and $defs alias" {
  let a = @schema.RootSchema::from_json_str(
    "{\"$schema\": \"x\", \"definitions\": {\"A\": true}, \"title\": \"T\"}",
  )
  let b = @schema.RootSchema::from_json_str(
    "{\"$schema\": \"x\", \"$defs\": {\"A\": true}, \"title\": \"T\"}",
  )
  assert_eq(a, b)
  debug_inspect(a.definitions.keys(), content="[\"A\"]")
  let err = try
    @schema.RootSchema::from_json_str("{\"definitions\": {}, \"$defs\": {}}")
  catch {
    e => e.to_string()
  } noraise {
    _ => "ok"
  }
  inspect(err, content="duplicate field `definitions`")
}

///|
test "type errors" {
  let cases = [
    "{\"minimum\": \"x\"}", "{\"maxLength\": -1}", "{\"maxLength\": 1.0}", "{\"type\": \"any\"}",
    "{\"properties\": {\"a\": 1}}", "{\"required\": null}",
  ]
  let out = cases.map(c => {
    try decode(c) catch {
      e => e.to_string()
    } noraise {
      _ => "ok"
    }
  })
  debug_inspect(
    out,
    content=(
      #|[
      #|  "invalid type: string \"x\", expected f64 at /minimum",
      #|  "invalid value: integer `-1`, expected u32 at /maxLength",
      #|  "invalid type: floating point `1.0`, expected u32 at /maxLength",
      #|  "data did not match any variant of untagged enum SingleOrVec at /type",
      #|  "data did not match any variant of untagged enum Schema at /properties/a",
      #|  "invalid type: null, expected a sequence at /required",
      #|]
    ),
  )
}

///|
test "into_object" {
  debug_inspect(
    @schema.Schema::Bool(false).into_object().subschemas.map(s => s.not),
    content=(
      #|Some(
      #|  Some(
      #|    Object(
      #|      {
      #|        metadata: None,
      #|        instance_type: None,
      #|        format: None,
      #|        enum_values: None,
      #|        const_value: None,
      #|        subschemas: None,
      #|        number: None,
      #|        string: None,
      #|        array: None,
      #|        object: None,
      #|        reference: None,
      #|        extensions: {},
      #|      },
      #|    ),
      #|  ),
      #|)
    ),
  )
}
