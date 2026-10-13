///|
/// Random schemas (tests/oracle/typify-random/cases.jsonl, written by
/// `scripts/typify-oracle random`): the IR descriptions and the Rust token
/// stream must match upstream typify's exactly; upstream errors must be the
/// same errors, and upstream panics must be panics here too.
test "random schemas agree with upstream typify" {
  let text = @fs.read_file_to_string("tests/oracle/typify-random/cases.jsonl")
  let failures = []
  let mut compared = 0
  for i, line in text.split("\n").map(l => l.to_owned()).collect() {
    if line.is_empty() {
      continue
    }
    guard @serde_json.parse(line) is Object(case) else { fail("bad line \{i}") }
    guard case.get("schema") is Some(schema) else { fail("no schema \{i}") }
    if case.get("crash") is Some(_) {
      continue
    }
    compared += 1
    let result = try {
      let root = @schema.RootSchema::from_json_str(schema.to_string())
      let space = @typify.TypeSpace::new(@typify.TypeSpaceSettings::default())
      ignore(space.add_root_schema(root))
      let types = space
        .entries()
        .mapi((i, e) => "\{i + 1}: \{e.1.describe()}")
        .join("\n") +
        "\n"
      Ok((types, @rust.to_stream(space).to_string()))
    } catch {
      @typify.TypifyError::Panic(msg) => Err("panic: \{msg}")
      e => Err("error: \{e}")
    }
    let schema_text = schema.to_string()
    match (case.get("types"), case.get("tokens"), case.get("error"), result) {
      (Some(String(types)), Some(String(tokens)), _, Ok((got_types, got_tokens))
      ) =>
        if got_types != types {
          failures.push(
            "case \{i}: types differ\n  schema: \{schema_text}\n  want: \{types}\n  got:  \{got_types}",
          )
        } else if got_tokens != tokens {
          failures.push("case \{i}: tokens differ\n  schema: \{schema_text}")
        }
      (_, _, Some(String(e)), Err(got)) =>
        if got != "error: \{e}" {
          failures.push(
            "case \{i}: want error \{e}, got \{got}\n  schema: \{schema_text}",
          )
        }
      (None, None, None, Err(got)) =>
        if !got.has_prefix("panic: ") {
          failures.push(
            "case \{i}: want a panic, got \{got}\n  schema: \{schema_text}",
          )
        }
      (_, _, _, got) => {
        let want = case.get("panic").map(p => "panic: \{p}").unwrap_or(line)
        failures.push(
          "case \{i}: want \{want}\n  got \{Repr(got.map(p => p.0))}\n  schema: \{schema_text}",
        )
      }
    }
  }
  if !failures.is_empty() {
    fail(
      "\{failures.length()} of \{compared} differ:\n" +
      failures[:failures.length().min(10)].join("\n"),
    )
  }
}
