///|
let session_schema : String =
  #|{
  #|  "definitions": {
  #|    "Event": { "type": "object", "required": ["seq", "item"],
  #|      "properties": { "seq": { "type": "integer", "format": "int32" },
  #|                      "item": { "$ref": "#/definitions/Item" } } },
  #|    "Item": { "oneOf": [
  #|      { "type": "object", "required": ["kind", "payload"], "properties": {
  #|          "kind": { "type": "string", "enum": ["note"] },
  #|          "payload": { "$ref": "#/definitions/Note" } } },
  #|      { "type": "object", "required": ["kind", "payload"], "properties": {
  #|          "kind": { "type": "string", "enum": ["tool_result"] },
  #|          "payload": { "$ref": "#/definitions/Body" } } } ] },
  #|    "Note": { "type": "object", "required": ["text"],
  #|      "properties": { "text": { "type": "string" },
  #|                      "tags": { "type": "array", "items": { "type": "string" } } } },
  #|    "Body": { "oneOf": [ { "type": "string" },
  #|      { "type": "array", "items": { "$ref": "#/definitions/Part" } } ] },
  #|    "Part": { "type": "object", "required": ["t"], "properties": { "t": { "type": "string" } } },
  #|    "Unused": { "type": "object", "properties": { "x": { "type": "string" } } }
  #|  }
  #|}

///|
fn gen_with(config : String) -> String raise {
  let space = @typify.TypeSpace::new(@typify.TypeSpaceSettings::default())
  ignore(
    space.add_root_schema(@schema.RootSchema::from_json_str(session_schema)),
  )
  @moonbit.generate_with(space, @moonbit.Options::from_json_str(config))
}

///|
test "roots, replacements, visibility, variants" {
  let code = gen_with(
    (
      #|{ "roots": ["Event"],
      #|  "defaults": { "visibility": "abstract", "constructor": false },
      #|  "types": {
      #|    "Item": { "visibility": "pub(all)", "variants": { "tool_result": "Tool" } },
      #|    "Body": { "replace": "@protocol.Content", "codec": "json" } } }
    ),
  )
  // Only what Event reaches; Body is replaced and Part is only used by it.
  assert_true(code.contains("\nstruct Event {"))
  assert_true(code.contains("\npub(all) enum Item {"))
  assert_true(code.contains("\nstruct Note {"))
  assert_false(code.contains("Unused"))
  assert_false(code.contains("struct Part"))
  assert_false(code.contains("enum Body"))
  // The replacement is referenced with its codec.
  assert_true(code.contains("Tool(@protocol.Content)"))
  assert_true(code.contains("@typify_rt.de_from_json"))
  // No constructors.
  assert_false(code.contains("pub fn Event::Event("))
}

///|
test "private types, package codecs, strict warnings, error paths" {
  let code = gen_with(
    (
      #|{ "roots": ["Note"], "codecs": "package", "strict_warnings": true,
      #|  "error_paths": true, "from_json": true,
      #|  "types": { "Note": { "name": "NoteRecord", "visibility": "priv" } } }
    ),
  )
  assert_true(code.contains("\npriv struct NoteRecord {"))
  assert_false(code.contains("pub impl"))
  assert_true(code.contains("impl FromJson for NoteRecord"))
  assert_true(code.contains("\nextend NoteRecord with Debug::{to_repr}"))
  assert_true(code.contains("paths=true"))
}

///|
test "config errors name the problem" {
  let err = (config : String) => {
    try gen_with(config) catch {
      e => e.to_string()
    } noraise {
      _ => "ok"
    }
  }
  inspect(
    err("{ \"types\": { \"Missing\": { \"visibility\": \"priv\" } } }"),
    content="types.Missing: no type of that name in the schema (known: Body, Event, Item, Note, Part, Unused)",
  )
  inspect(
    err("{ \"types\": { \"Item\": { \"variants\": { \"nope\": \"X\" } } } }"),
    content="types.Item.variants: no variant `nope` (variants: note, tool_result)",
  )
  inspect(
    err("{ \"types\": { \"Body\": { \"replace\": \"T\" } } }"),
    content="types.Body: `replace` needs a `codec` (\"serde\", \"json\" or functions)",
  )
  inspect(err("{ \"colour\": 1 }"), content="unknown key `colour`")
  inspect(
    err("{ \"defaults\": { \"visibility\": \"public\" } }"),
    content="defaults.visibility: expected \"pub(all)\", \"pub\", \"abstract\" or \"priv\"",
  )
}
