///|
fn parse(args : Array[String]) -> String {
  try @cli.parse_args(args) catch {
    e => "error: \{e}"
  } noraise {
    Run(a) =>
      "run input=\{a.input} lang=\{Repr(a.lang)} builder=\{a.builder} out=\{Repr(a.output_path())}"
    Help => "help"
    Version => "version"
  }
}

///|
test "argument parsing" {
  inspect(
    parse(["schema.json"]),
    content="run input=schema.json lang=Rust builder=true out=Some(\"schema.rs\")",
  )
  inspect(
    parse(["dir.v1/schema.json", "-B", "--lang", "moonbit"]),
    content="run input=dir.v1/schema.json lang=MoonBit builder=false out=Some(\"dir.v1/schema.mbt\")",
  )
  inspect(
    parse(["noext", "--output=-"]),
    content="run input=noext lang=Rust builder=true out=None",
  )
  inspect(parse(["--help"]), content="help")
  inspect(parse(["-V"]), content="version")
  inspect(
    parse([]),
    content=(
      #|error: the following required arguments were not provided:
      #|  <INPUT>
      #|
      #|Usage: typify [OPTIONS] <INPUT>
    ),
  )
  inspect(
    parse(["a.json", "-b", "-B"]),
    content="error: the argument '--builder' cannot be used with '--no-builder'",
  )
  inspect(
    parse(["a.json", "--crate", "bad"]),
    content="error: invalid value 'bad' for '--crate <CRATES>': crate specifier must be of the form 'cratename@version'",
  )
  inspect(
    parse(["a.json", "--crate", "my-crate=foo@1.2.3"]).has_prefix("run"),
    content="true",
  )
  inspect(
    parse(["a.json", "--crate", "foo@*"]).has_prefix("run"),
    content="true",
  )
  inspect(
    parse(["a.json", "--unknown-crates", "maybe"]),
    content="error: invalid value 'maybe' for '--unknown-crates <UNKNOWN_CRATES>'",
  )
  inspect(
    parse(["a.json", "--frob"]),
    content="error: unexpected argument '--frob' found",
  )
}

///|
test "convert example.json to Rust" {
  let text = @fs.read_file_to_string("tests/upstream/cli/example.json")
  guard @cli.parse_args(["example.json", "--no-builder"]) is Run(args) else {
    fail("expected run")
  }
  let out = @cli.convert(args, text)
  assert_true(out.has_prefix(@cli.rust_intro))
  assert_true(out.contains("pub struct Veggie"))
}
