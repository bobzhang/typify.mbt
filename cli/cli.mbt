// Command-line interface logic (mirrors cargo-typify), independent of IO so
// it can be tested.

///|
pub(all) enum Lang {
  Rust
  MoonBit
} derive(Eq, Debug)

///|
/// Parsed command-line arguments.
pub(all) struct CliArgs {
  input : String
  lang : Lang
  builder : Bool
  additional_derives : Array[String]
  additional_attrs : Array[String]
  /// `None`: default path; `Some("-")`: stdout.
  output : String?
  crates : Array[(String, @typify.CrateVers, String?)]
  map_type : String?
  unknown_crates : @typify.UnknownPolicy?
} derive(Debug)

///|
/// What the CLI should do.
pub(all) enum Command {
  Run(CliArgs)
  Help
  Version
} derive(Debug)

///|
pub(all) suberror CliError {
  CliError(String)
} derive(Debug)

///|
pub impl Show for CliError with fn output(self, logger) {
  let CliError(msg) = self
  logger.write_string(msg)
}

///|
pub let version : String = "0.1.4"

///|
pub let help : String =
  #|Generate Rust or MoonBit types from a JSON Schema (a MoonBit port of typify)
  #|
  #|Usage: typify [OPTIONS] <INPUT>
  #|
  #|Arguments:
  #|  <INPUT>
  #|          The input file to read from
  #|
  #|Options:
  #|  -l, --lang <LANG>
  #|          The language to generate
  #|
  #|          [possible values: rust, moonbit] [default: rust]
  #|
  #|  -b, --builder
  #|          Whether to include a builder-style interface, this is the default (Rust)
  #|
  #|  -B, --no-builder
  #|          Inverse of `--builder`. When set the builder-style interface will not be included
  #|
  #|  -d, --additional-derive <derive>
  #|          Add an additional derive macro to apply to all defined types
  #|
  #|  -a, --additional-attr <attr>
  #|          Add an additional attribute to apply to all defined types
  #|
  #|  -o, --output <OUTPUT>
  #|          The output file to write to. If not specified, the input file name will be used with a
  #|          `.rs` (Rust) or `.mbt` (MoonBit) extension.
  #|
  #|          If `-` is specified, the output will be written to stdout.
  #|
  #|      --crate <CRATES>
  #|          Specify each crate@version that can be assumed to be in use for types found in the schema
  #|          with the x-rust-type extension
  #|
  #|      --map-type <MAP_TYPE>
  #|          Specify the map like type to use
  #|
  #|      --unknown-crates <UNKNOWN_CRATES>
  #|          Specify the policy unknown crates found in schemas with the x-rust-type extension
  #|
  #|          [possible values: generate, allow, deny]
  #|
  #|  -h, --help
  #|          Print help
  #|
  #|  -V, --version
  #|          Print version
  #|

///|
fn is_crate_name(s : String) -> Bool {
  match s.get_char(0) {
    Some(c) if c.is_ascii_alphabetic() || c == '_' || c.to_int() > 0x7F =>
      s
      .iter()
      .all(c => {
        c.is_ascii_alphabetic() ||
        c.is_ascii_digit() ||
        c == '-' ||
        c == '_' ||
        c.to_int() > 0x7F
      })
    _ => false
  }
}

///|
/// Parse `[rename=]name@version` (version: semver, `*` or `!`).
fn parse_crate_spec(s : String) -> (String, @typify.CrateVers, String?)? {
  let (rename, rest) = match s.find("=") {
    Some(i) => {
      let rename = s.unsafe_substring(start=0, end=i)
      if !is_crate_name(rename) {
        return None
      }
      (Some(rename), s.unsafe_substring(start=i + 1, end=s.length()))
    }
    None => (None, s)
  }
  guard rest.find("@") is Some(i) else { return None }
  let name = rest.unsafe_substring(start=0, end=i)
  let vers = rest.unsafe_substring(start=i + 1, end=rest.length())
  if !is_crate_name(name) {
    return None
  }
  guard @typify.CrateVers::parse(vers) is Some(version) else { return None }
  Some((name, version, rename))
}

///|
/// Parse arguments (without the program name).
pub fn parse_args(args : ArrayView[String]) -> Command raise CliError {
  let mut input = None
  let mut lang = Lang::Rust
  let mut builder = true
  let mut saw_builder = false
  let mut saw_no_builder = false
  let derives = []
  let attrs = []
  let mut output = None
  let crates = []
  let mut map_type = None
  let mut unknown_crates = None
  let mut i = 0
  let value = (flag : String) => {
    // Supports `--flag value` and `--flag=value`.
    if i + 1 >= args.length() {
      raise CliError("a value is required for '\{flag}' but none was supplied")
    }
    i += 1
    args[i]
  }
  while i < args.length() {
    let arg = args[i]
    let (flag, inline) = match arg.find("=") {
      Some(eq) if arg.has_prefix("--") =>
        (
          arg.unsafe_substring(start=0, end=eq),
          Some(arg.unsafe_substring(start=eq + 1, end=arg.length())),
        )
      _ => (arg, None)
    }
    let take = () => {
      match inline {
        Some(v) => v
        None => value(flag)
      }
    }
    match flag {
      "-h" | "--help" => return Help
      "-V" | "--version" => return Version
      "-l" | "--lang" =>
        lang = match take() {
          "rust" | "rs" => Rust
          "moonbit" | "mbt" => MoonBit
          other =>
            raise CliError("invalid value '\{other}' for '--lang <LANG>'")
        }
      "-b" | "--builder" => {
        saw_builder = true
        builder = true
      }
      "-B" | "--no-builder" => {
        saw_no_builder = true
        builder = false
      }
      "-d" | "--additional-derive" => derives.push(take())
      "-a" | "--additional-attr" => attrs.push(take())
      "-o" | "--output" => output = Some(take())
      "--crate" => {
        let spec = take()
        match parse_crate_spec(spec) {
          Some(c) => crates.push(c)
          None =>
            raise CliError(
              "invalid value '\{spec}' for '--crate <CRATES>': crate specifier must be of the form 'cratename@version'",
            )
        }
      }
      "--map-type" => map_type = Some(take())
      "--unknown-crates" =>
        unknown_crates = Some(
          match take() {
            "generate" => @typify.UnknownPolicy::Generate
            "allow" => Allow
            "deny" => Deny
            other =>
              raise CliError(
                "invalid value '\{other}' for '--unknown-crates <UNKNOWN_CRATES>'",
              )
          },
        )
      _ if flag.has_prefix("-") && flag != "-" =>
        raise CliError("unexpected argument '\{flag}' found")
      _ =>
        if input is None {
          input = Some(arg)
        } else {
          raise CliError("unexpected argument '\{arg}' found")
        }
    }
    i += 1
  }
  if saw_builder && saw_no_builder {
    raise CliError(
      "the argument '--builder' cannot be used with '--no-builder'",
    )
  }
  guard input is Some(input) else {
    raise CliError(
      "the following required arguments were not provided:\n  <INPUT>\n\nUsage: typify [OPTIONS] <INPUT>",
    )
  }
  Run({
    input,
    lang,
    builder,
    additional_derives: derives,
    additional_attrs: attrs,
    output,
    crates,
    map_type,
    unknown_crates,
  })
}

///|
/// Where to write the output: `None` means stdout.
pub fn CliArgs::output_path(self : CliArgs) -> String? {
  match self.output {
    Some("-") => None
    Some(path) => Some(path)
    None => {
      let ext = match self.lang {
        Rust => "rs"
        MoonBit => "mbt"
      }
      // Replace the extension of the last path component.
      let slash = self.input.rev_find("/").unwrap_or(-1)
      let base = match self.input.rev_find(".") {
        Some(dot) if dot > slash + 1 =>
          self.input.unsafe_substring(start=0, end=dot)
        _ => self.input
      }
      Some("\{base}.\{ext}")
    }
  }
}

///|
/// Build type-space settings from the arguments.
pub fn CliArgs::settings(self : CliArgs) -> @typify.TypeSpaceSettings {
  let settings = @typify.TypeSpaceSettings::default().with_struct_builder(
    self.builder,
  )
  for d in self.additional_derives {
    ignore(settings.with_derive(d))
  }
  for a in self.additional_attrs {
    ignore(settings.with_attr(a))
  }
  for c in self.crates {
    let (name, version, rename) = c
    ignore(settings.with_crate(name, version, rename?))
  }
  if self.map_type is Some(m) {
    ignore(settings.with_map_type(m))
  }
  if self.unknown_crates is Some(p) {
    ignore(settings.with_unknown_crates(p))
  }
  settings
}

///|
/// The lint allowances cargo-typify prepends to Rust output.
pub let rust_intro : String =
  #|#![allow(clippy::redundant_closure_call)]
  #|#![allow(clippy::needless_lifetimes)]
  #|#![allow(clippy::match_single_binding)]
  #|#![allow(clippy::clone_on_copy)]
  #|

///|
/// Convert schema text to generated code.
pub fn convert(args : CliArgs, schema_text : String) -> String raise {
  let root = @schema.RootSchema::from_json_str(schema_text) catch {
    e => raise CliError("Failed to parse input file as JSON Schema: \{e}")
  }
  let space = @typify.TypeSpace::new(args.settings())
  ignore(
    space.add_root_schema(root) catch {
      e => raise CliError("Schema conversion failed: \{e}")
    },
  )
  match args.lang {
    Rust => "\{rust_intro}\n\{@rust.to_stream(space)}"
    MoonBit => @moonbit.generate(space)
  }
}
