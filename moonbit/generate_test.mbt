///|
fn gen(schema : String) -> String raise {
  let space = @typify.TypeSpace::new(@typify.TypeSpaceSettings::default())
  ignore(space.add_root_schema(@schema.RootSchema::from_json_str(schema)))
  @moonbit.generate(space)
}

///|
test "string enum" {
  let code = gen(
    (
      #|{"title": "Color", "type": "string", "enum": ["red", "dark-blue"]}
    ),
  )
  assert_true(code.contains("pub(all) enum Color {\n  Red\n  DarkBlue\n}"))
  assert_true(code.contains("pub fn Color::parse("))
}

///|
test "struct with keyword field and optional" {
  let code = gen(
    (
      #|{"title": "Thing", "type": "object", "required": ["type"],
      #| "properties": {"type": {"type": "string"}, "member": {"type": "integer"}}}
    ),
  )
  assert_true(code.contains("  member_ : Int64?\n"))
  assert_true(code.contains("  type_ : String\n"))
  assert_true(code.contains("@typify_rt.Fields::new([\"member\", \"type\"])"))
}

///|
test "struct constructor" {
  let code = gen(
    (
      #|{"title": "Conf", "type": "object", "required": ["name", "maybe"],
      #| "properties": {
      #|   "name": {"type": "string"},
      #|   "maybe": {"type": ["string", "null"]},
      #|   "port": {"type": "integer", "format": "uint16", "default": 8080},
      #|   "tags": {"type": "array", "items": {"type": "string"}},
      #|   "note": {"type": "string"}}}
    ),
  )
  assert_true(
    code.contains(
      "pub fn Conf::Conf(maybe? : String, name~ : String, note? : String, port? : UInt16, tags? : Array[String] = []) -> Conf {",
    ),
  )
}
