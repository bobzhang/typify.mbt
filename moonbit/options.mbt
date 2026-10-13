// Options for the MoonBit backend: how generated types fit into an existing
// package. They are MoonBit-specific, so they live outside the (language
// neutral) schema: in a JSON config file for the CLI (`--moonbit-config`), or
// built with this API. Types are named by their typify type names, as in
// `TypeSpaceSettings::with_patch`.

///|
/// The visibility of a generated type.
pub(all) enum Visibility {
  /// `pub(all)`: fields and constructors usable everywhere (the default).
  Public
  /// `pub`: readable everywhere, constructed only in its own package.
  ReadOnly
  /// No modifier: an abstract type; its representation is private.
  Abstract
  /// `priv`: invisible outside its package.
  Private
} derive(Eq, Debug)

///|
/// How generated code decodes and encodes a replacement type.
pub(all) enum Codec {
  /// The type implements `@typify_rt.Serde` (exact serde semantics).
  Serde
  /// Through the type's core `FromJson`/`ToJson` (object keys keep their
  /// order; duplicate keys are resolved by `Json` before the type sees them).
  Json
  /// Named functions `(@typify_rt.De) -> T raise @typify_rt.DeError` and
  /// `(T) -> @typify_rt.Content raise @typify_rt.SerError`.
  Functions(decode~ : String, encode~ : String)
} derive(Eq, Debug)

///|
/// Options for one generated type.
pub(all) struct TypeOptions {
  /// The MoonBit name instead of the generated one.
  mut name : String?
  mut visibility : Visibility?
  /// Whether to generate the constructor `T(...)`.
  mut constructor_ : Bool?
  /// Constructor names for variants, by their JSON name (tag value).
  variants : Map[String, String]
  /// Use an existing MoonBit type (e.g. `@protocol.Content`) instead of
  /// generating one; the schema still describes its JSON form.
  mut replace : (String, Codec)?
} derive(Debug)

///|
pub fn TypeOptions::new() -> TypeOptions {
  {
    name: None,
    visibility: None,
    constructor_: None,
    variants: Map([]),
    replace: None,
  }
}

///|
/// Options for the MoonBit backend.
pub(all) struct Options {
  /// Per-type options, by typify type name.
  types : Map[String, TypeOptions]
  /// Defaults for types without their own setting.
  mut visibility : Visibility
  mut constructor_ : Bool
  /// Emit only these types and what they reference (all types when empty).
  roots : Array[String]
  /// Also implement core `@json.FromJson` (needs `moonbitlang/core/json`).
  mut from_json : Bool
  /// Keep the generated codecs (`Serde` impl and its methods) private to the
  /// package: the public API is then only the types and their
  /// `ToJson`/`FromJson`.
  mut package_codecs : Bool
  /// Say where decoding failed: errors end with a JSON Pointer such as
  /// ` at /item/payload` (serde's messages have no path).
  mut error_paths : Bool
  /// Warning-free output under strict warning settings
  /// (`+implicit_impl_as_method`, `+unnecessary_annotation`).
  mut strict_warnings : Bool
} derive(Debug)

///|
pub fn Options::default() -> Options {
  {
    types: Map([]),
    visibility: Public,
    constructor_: true,
    roots: [],
    from_json: false,
    package_codecs: false,
    error_paths: false,
    strict_warnings: false,
  }
}

///|
/// Options for `type_name`, created on first use.
pub fn Options::for_type(self : Options, type_name : String) -> TypeOptions {
  match self.types.get(type_name) {
    Some(t) => t
    None => {
      let t = TypeOptions::new()
      self.types[type_name] = t
      t
    }
  }
}

///|
/// An error in a MoonBit config file.
pub(all) suberror OptionsError {
  OptionsError(String)
} derive(Debug)

///|
pub impl Show for OptionsError with fn output(self, logger) {
  let OptionsError(message) = self
  logger.write_string(message)
}

///|
fn visibility_of(v : Json, path : String) -> Visibility raise OptionsError {
  match v {
    String("pub(all)") => Public
    String("pub") => ReadOnly
    String("abstract") => Abstract
    String("priv") => Private
    _ =>
      raise OptionsError(
        "\{path}: expected \"pub(all)\", \"pub\", \"abstract\" or \"priv\"",
      )
  }
}

///|
fn bool_of(v : Json, path : String) -> Bool raise OptionsError {
  match v {
    True => true
    False => false
    _ => raise OptionsError("\{path}: expected true or false")
  }
}

///|
fn string_of(v : Json, path : String) -> String raise OptionsError {
  guard v is String(s) else { raise OptionsError("\{path}: expected a string") }
  s
}

///|
fn codec_of(v : Json, path : String) -> Codec raise OptionsError {
  match v {
    String("serde") => Serde
    String("json") => Json
    Object(o) => {
      for k, _ in o {
        if !(k is ("decode" | "encode")) {
          raise OptionsError("\{path}: unknown key `\{k}`")
        }
      }
      match (o.get("decode"), o.get("encode")) {
        (Some(d), Some(e)) =>
          Functions(
            decode=string_of(d, path + ".decode"),
            encode=string_of(e, path + ".encode"),
          )
        _ => raise OptionsError("\{path}: expected both `decode` and `encode`")
      }
    }
    _ =>
      raise OptionsError(
        "\{path}: expected \"serde\", \"json\" or {\"decode\", \"encode\"}",
      )
  }
}

///|
/// Parse a MoonBit config file:
///
/// ```json
/// {
///   "roots": ["SessionEvent"],
///   "defaults": { "visibility": "abstract", "constructor": false },
///   "from_json": true,
///   "codecs": "package",
///   "strict_warnings": true,
///   "types": {
///     "SessionItem": { "visibility": "pub(all)",
///                      "variants": { "tool_result": "Tool" } },
///     "Content": { "replace": "@protocol.Content", "codec": "json" }
///   }
/// }
/// ```
///
/// Unknown keys are errors. Type names are checked against the schema by
/// `generate`.
pub fn Options::from_json_str(text : String) -> Options raise OptionsError {
  let json = @json.parse(text) catch {
    e => raise OptionsError("invalid JSON: \{e}")
  }
  guard json is Object(top) else {
    raise OptionsError("the config must be a JSON object")
  }
  let options = Options::default()
  for key, v in top {
    match key {
      "roots" => {
        guard v is Array(xs) else {
          raise OptionsError("roots: expected an array of type names")
        }
        for i, x in xs {
          options.roots.push(string_of(x, "roots[\{i}]"))
        }
      }
      "from_json" => options.from_json = bool_of(v, key)
      "strict_warnings" => options.strict_warnings = bool_of(v, key)
      "error_paths" => options.error_paths = bool_of(v, key)
      "codecs" =>
        options.package_codecs = match v {
          String("public") => false
          String("package") => true
          _ => raise OptionsError("codecs: expected \"public\" or \"package\"")
        }
      "defaults" => {
        guard v is Object(d) else {
          raise OptionsError("defaults: expected an object")
        }
        for k, x in d {
          match k {
            "visibility" =>
              options.visibility = visibility_of(x, "defaults.visibility")
            "constructor" =>
              options.constructor_ = bool_of(x, "defaults.constructor")
            _ => raise OptionsError("defaults: unknown key `\{k}`")
          }
        }
      }
      "types" => {
        guard v is Object(types) else {
          raise OptionsError("types: expected an object")
        }
        for name, t in types {
          let path = "types.\{name}"
          guard t is Object(fields) else {
            raise OptionsError("\{path}: expected an object")
          }
          let opts = options.for_type(name)
          let mut codec : Codec? = None
          let mut replace : String? = None
          for k, x in fields {
            match k {
              "name" => opts.name = Some(string_of(x, path + ".name"))
              "visibility" =>
                opts.visibility = Some(visibility_of(x, path + ".visibility"))
              "constructor" =>
                opts.constructor_ = Some(bool_of(x, path + ".constructor"))
              "variants" => {
                guard x is Object(vs) else {
                  raise OptionsError("\{path}.variants: expected an object")
                }
                for raw, ctor in vs {
                  opts.variants[raw] = string_of(
                    ctor,
                    "\{path}.variants.\{raw}",
                  )
                }
              }
              "replace" => replace = Some(string_of(x, path + ".replace"))
              "codec" => codec = Some(codec_of(x, path + ".codec"))
              _ => raise OptionsError("\{path}: unknown key `\{k}`")
            }
          }
          match (replace, codec) {
            (Some(r), Some(c)) => opts.replace = Some((r, c))
            (Some(_), None) =>
              raise OptionsError(
                "\{path}: `replace` needs a `codec` (\"serde\", \"json\" or functions)",
              )
            (None, Some(_)) =>
              raise OptionsError("\{path}: `codec` applies only with `replace`")
            (None, None) => ()
          }
        }
      }
      "$schema" | "$comment" => ()
      _ => raise OptionsError("unknown key `\{key}`")
    }
  }
  options
}
