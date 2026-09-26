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
      #|{"title": "Conf", "type": "object", "required": ["name"],
      #| "properties": {
      #|   "name": {"type": "string"},
      #|   "level": {"type": ["integer", "null"], "default": 3},
      #|   "port": {"type": "integer", "format": "uint16", "default": 8080},
      #|   "mode": {"type": "string", "enum": ["fast", "slow"], "default": "slow"},
      #|   "tags": {"type": "array", "items": {"type": "string"}},
      #|   "note": {"type": "string"}}}
    ),
  )
  let start = code.find("pub fn Conf::Conf(").unwrap()
  let end = start + code[start:].find("{").unwrap()
  inspect(
    code[start:end],
    content="pub fn Conf::Conf(level? : Int64 = 3, mode? : ConfMode = ConfMode::Slow, name~ : String, note? : String, port? : UInt16 = 8080, tags? : Array[String] = []) -> Conf ",
  )
  assert_true(code.contains("    level: Some(level),\n"))
}

///|
test "preserve property order" {
  let schema =
    #|{"title": "Header", "type": "object", "required": ["version", "id"],
    #| "properties": {"version": {"type": "integer"}, "id": {"type": "string"},
    #|   "data": {}}}
  let gen_with = (preserve : Bool) => {
    let space = @typify.TypeSpace::new(
      @typify.TypeSpaceSettings::default().with_preserve_property_order(
        preserve,
      ),
    )
    ignore(
      space.add_root_schema(
        @schema.RootSchema::from_json_str(schema, preserve_order=preserve),
      ),
    )
    @moonbit.generate(space)
  }
  let sorted = gen_with(false)
  assert_true(
    sorted.contains("  data : Json?\n  id : String\n  version : Int64\n"),
  )
  assert_true(sorted.contains("@typify_rt.de_json)"))
  let ordered = gen_with(true)
  assert_true(
    ordered.contains("  version : Int64\n  id : String\n  data : Json?\n"),
  )
  assert_true(ordered.contains("@typify_rt.de_json_ordered"))
}
