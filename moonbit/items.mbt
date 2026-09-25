// Generated items: type declarations, codecs and helpers.

///|
fn indent(code : String, n : Int) -> String {
  let pad = " ".repeat(n)
  code
  .split("\n")
  .map(l => if l.is_empty() { l.to_owned() } else { pad + l.to_owned() })
  .collect()
  .join("\n")
}

///|
/// Doc comment lines for a description.
fn doc_comment(description : String?) -> String {
  match description {
    None => ""
    Some(d) =>
      d
      .split("\n")
      .map(l => if l.is_empty() { "///" } else { "/// \{l}" })
      .collect()
      .join("\n") +
      "\n"
  }
}

///|
fn json_name(p : @typify.StructProperty) -> String? {
  match p.rename {
    NoRename => Some(p.name)
    Rename(r) => Some(r)
    Flatten => None
  }
}

///|
/// The zero value used by `#[serde(default)]` for the types typify applies it
/// to (Rust `Default::default()`).
fn Gen::zero_value(self : Gen, id : @typify.TypeId) -> String {
  match entry(self.space, id).details {
    Option(_) => "None"
    Vec(_) | Set(_) => "[]"
    Map(_, _) => "Map([])"
    Unit => "()"
    Boolean => "false"
    Integer(_) => "0"
    Float(_) => "0.0"
    String => "\"\""
    JsonValue => "Json::null()"
    Box(inner) => self.zero_value(inner)
    _ => abort("no intrinsic default for type \{id}")
  }
}

///|
/// A global function producing a custom default value (upstream's
/// `defaults::<type>_<prop>`), decoding the schema's JSON default.
fn Gen::default_fn(
  self : Gen,
  out : StringBuilder,
  type_name : String,
  prop_name : String,
  id : @typify.TypeId,
  value : @serde_json.Value,
) -> String {
  let name = self.globals.alloc(
    lower_ident(@typify.sanitize("default_\{type_name}_\{prop_name}", Snake)),
  )
  out.write_string(
    (
      $|///|
      $|fn \{name}() -> \{self.mbt_type(id)} raise @typify_rt.DeError {
      $|  @typify_rt.default_value(\{str_lit(value.to_string())}, \{self.de_fn(id)})
      $|}
      $|
      $|
    ),
  )
  name
}

///|
/// Decoding code for struct fields from the deserializer expression `d`,
/// using the runtime's table-driven `de_fields`; `build` receives the
/// decoded field variables (`v0`, `v1`, ...) in property order.
fn Gen::struct_decode(
  self : Gen,
  out : StringBuilder,
  owner : String,
  props : Array[@typify.StructProperty],
  expecting : String,
  deny_unknown_fields : Bool,
  allow_seq : Bool,
  d : String,
  build : String,
  external_variant? : Bool = false,
) -> String {
  let has_flatten = props.iter().any(p => p.rename is Flatten)
  // Named fields: (property index, JSON name).
  let named : Array[(Int, String)] = []
  for i, p in props {
    if json_name(p) is Some(n) {
      named.push((i, n))
    }
  }
  let table = self.globals.alloc(
    lower_ident(@typify.sanitize("\{owner}_fields", Snake)),
  )
  out.write_string(
    "///|\nlet \{table} : @typify_rt.Fields = @typify_rt.Fields::new(\{str_array(named.map(n => n.1))})\n\n",
  )
  let buf = StringBuilder()
  for n in named {
    buf.write_string(
      "let mut f\{n.0} : \{self.mbt_type(props[n.0].type_id)}? = None\n",
    )
  }
  // One callback decodes field `j` (in `named` order) as its key is read.
  buf.write_string(
    "let r = @typify_rt.de_fields(\{d}, \{str_lit(expecting)}, \{table}, (j, v) => match j {\n",
  )
  for j, n in named {
    buf.write_string(
      "  \{j} => f\{n.0} = Some(\{self.de_expr(props[n.0].type_id, "v")})\n",
    )
  }
  buf.write_string("  _ => ()\n}")
  if has_flatten {
    buf.write_string(", flatten=true")
  }
  if deny_unknown_fields && !has_flatten {
    buf.write_string(", deny=true")
  }
  if !allow_seq {
    buf.write_string(", positional=false")
  }
  if external_variant {
    buf.write_string(", external_variant=true")
  }
  buf.write_string(")\n")
  // Absent fields, in declaration order: defaults, `None` for optional
  // `Option`s, or serde's missing-field/invalid-length errors.
  for j, n in named {
    let (i, p) = (n.0, props[n.0])
    let details = entry(self.space, p.type_id).details
    let missing = match (p.state, details) {
      (Optional, Option(_)) => self.de_expr(p.type_id, "r.absent(\{j})")
      (Optional, _) => self.zero_value(p.type_id)
      (Default(v), _) =>
        "\{self.default_fn(out, owner, p.name, p.type_id, v)}()"
      // `deserialize_with = Option::deserialize` reports absence itself.
      (Required, Option(_)) => "raise r.absent_error(\{j})"
      (Required, _) => self.de_expr(p.type_id, "r.absent(\{j})")
    }
    buf.write_string(
      "let v\{i} = if f\{i} is Some(v) { v } else { \{missing} }\n",
    )
  }
  // Flattened fields read the buffered entries, in declaration order.
  for i, p in props {
    if p.rename is Flatten {
      buf.write_string("let v\{i} = \{self.de_expr(p.type_id, "r.flat()")}\n")
    }
  }
  if has_flatten && deny_unknown_fields {
    buf.write_string("r.deny_leftovers()\n")
  }
  buf.write_string(build)
  buf.to_string()
}

///|
fn known_name(p : @typify.StructProperty) -> String {
  match json_name(p) {
    Some(n) => n
    None => p.name
  }
}

///|
/// Serialization of struct fields into an `ObjectBuilder` named `o`;
/// `access(i)` is the expression for property `i`.
fn Gen::struct_encode(
  self : Gen,
  props : Array[@typify.StructProperty],
  access : (Int) -> String,
) -> String {
  let buf = StringBuilder()
  for i, p in props {
    let v = access(i)
    let details = entry(self.space, p.type_id).details
    match json_name(p) {
      None => buf.write_string("o.flatten(\{self.ser_expr(p.type_id, v)})\n")
      Some(name) => {
        let line = "o.field(\{str_lit(name)}, \{self.ser_expr(p.type_id, v)})"
        let guard_expr = match (p.state, details) {
          (Optional, Option(_)) => Some("\{v} is Some(_)")
          (Optional, Vec(_) | Set(_) | Map(_, _)) => Some("!\{v}.is_empty()")
          _ => None
        }
        match guard_expr {
          Some(g) => buf.write_string("if \{g} {\n  \{line}\n}\n")
          None => buf.write_string(line + "\n")
        }
      }
    }
  }
  buf.to_string()
}

///|
fn Gen::api_methods(self : Gen, out : StringBuilder, name : String) -> Unit {
  ignore(self)
  out.write_string(
    (
      $|///|
      $|pub extend \{name} with @typify_rt.Serde::{
      $|  deserialize, serialize, from_json_str, to_json_string, from_json,
      $|}
      $|
      $|///|
      $|pub impl ToJson for \{name} with to_json(self) {
      $|  @typify_rt.json_of(self, \{str_lit(name)})
      $|}
      $|
      $|
    ),
  )
}

///|
fn Gen::type_default(
  self : Gen,
  out : StringBuilder,
  name : String,
  id : @typify.TypeId,
  value : @serde_json.Value?,
) -> Unit {
  guard value is Some(v) else { return }
  out.write_string(
    (
      $|///|
      $|/// The schema's default value.
      $|pub fn \{name}::default() -> \{name} {
      $|  @typify_rt.default_value(\{str_lit(v.to_string())}, \{self.de_fn(id)}) catch {
      $|    e => abort("invalid default for \{name}: \{"\\{e}"}")
      $|  }
      $|}
      $|
      $|
    ),
  )
}

// ---------------------------------------------------------------------------
// Structs

///|
fn Gen::output_struct(
  self : Gen,
  out : StringBuilder,
  id : @typify.TypeId,
  d : @typify.TypeEntryStruct,
) -> Unit {
  let name = self.type_name(id)
  let fields = self.fields.get("\{id.0}/-1").unwrap()
  out.write_string("///|\n")
  out.write_string(doc_comment(Some(d.description.unwrap_or("`\{d.name}`"))))
  out.write_string("pub(all) struct \{name} {\n")
  for i, p in d.properties {
    out.write_string(indent(doc_comment(p.description), 2))
    out.write_string("  \{fields[i]} : \{self.mbt_type(p.type_id)}\n")
  }
  out.write_string("} derive(Debug, Eq)\n\n")
  let build = "{ \{fields.mapi((i, f) => "\{f}: v\{i}").join(", ")} }"
  let build = "\{name}::" + build
  let decode = self.struct_decode(
    out,
    d.name,
    d.properties,
    "struct \{d.name}",
    d.deny_unknown_fields,
    true,
    "d",
    build,
  )
  out.write_string(
    (
      $|///|
      $|pub impl @typify_rt.Serde for \{name} with deserialize(d) {
      $|\{indent(decode, 2)}
      $|}
      $|
      $|///|
      $|pub impl @typify_rt.Serde for \{name} with serialize(self) {
      $|  let o = @typify_rt.ObjectBuilder::new()
      $|\{indent(self.struct_encode(d.properties, i => "self.\{fields[i]}"), 2)}
      $|  o.build()
      $|}
      $|
      $|
    ),
  )
  self.type_default(out, name, id, d.default)
  self.api_methods(out, name)
}

// ---------------------------------------------------------------------------
// Newtypes

///|
fn Gen::output_newtype(
  self : Gen,
  out : StringBuilder,
  id : @typify.TypeId,
  d : @typify.TypeEntryNewtype,
) -> Unit {
  let name = self.type_name(id)
  let inner = self.mbt_type(d.type_id)
  let is_str = entry(self.space, d.type_id).details is String
  let derives = if is_str { "Debug, Eq, Hash" } else { "Debug, Eq" }
  out.write_string("///|\n")
  out.write_string(doc_comment(Some(d.description.unwrap_or("`\{d.name}`"))))
  out.write_string("pub(all) struct \{name}(\{inner}) derive(\{derives})\n\n")
  // Validation for constrained newtypes (upstream `TryFrom`).
  let check = match d.constraints {
    NoConstraints => ""
    EnumValue(values) | DenyValue(values) => {
      let allowed = self.globals.alloc(
        lower_ident(@typify.sanitize("\{d.name}_values", Snake)),
      )
      out.write_string(
        (
          $|///|
          $|let \{allowed} : Array[@typify_rt.Content] = @typify_rt.enum_values(
          $|  \{str_array(values.map(v => v.to_string()))},
          $|  \{self.de_fn(d.type_id)},
          $|  \{self.ser_fn(d.type_id)},
          $|)
          $|
          $|
        ),
      )
      let is_enum = d.constraints is EnumValue(_)
      "let serialized = (\{self.ser_expr(d.type_id, "value")}) catch { _ => @typify_rt.ser_null() }\nif \{if is_enum { "!" } else { "" }}@typify_rt.contains_value(\{allowed}, serialized) {\n  raise @typify_rt.ConversionError(\"invalid value\")\n}\n"
    }
    String(max_length~, min_length~, pattern~) => {
      let buf = StringBuilder()
      if max_length is Some(v) {
        buf.write_string(
          "if @typify_rt.char_count(value) > \{v} {\n  raise @typify_rt.ConversionError(\{str_lit("longer than \{v} characters")})\n}\n",
        )
      }
      if min_length is Some(v) {
        buf.write_string(
          "if @typify_rt.char_count(value) < \{v} {\n  raise @typify_rt.ConversionError(\{str_lit("shorter than \{v} characters")})\n}\n",
        )
      }
      if pattern is Some(p) {
        let re = self.globals.alloc(
          lower_ident(@typify.sanitize("\{d.name}_pattern", Snake)),
        )
        out.write_string(
          "///|\nlet \{re} : @typify_rt.Regex = @typify_rt.regex(\{str_lit(p)})\n\n",
        )
        buf.write_string(
          "if !\{re}.is_match(value) {\n  raise @typify_rt.ConversionError(\{str_lit("doesn't match pattern \"\{p}\"")})\n}\n",
        )
      }
      buf.to_string()
    }
  }
  if check != "" {
    out.write_string(
      (
        $|///|
        $|/// Validate and wrap a value (upstream `TryFrom`).
        $|pub fn \{name}::new(value : \{inner}) -> \{name} raise @typify_rt.ConversionError {
        $|\{indent(check, 2)}
        $|  \{name}(value)
        $|}
        $|
        $|///|
        $|pub impl @typify_rt.Serde for \{name} with deserialize(d) {
        $|  let value = \{self.de_expr(d.type_id, "d")}
        $|  \{name}::new(value) catch {
        $|    @typify_rt.ConversionError(msg) => raise @typify_rt.DeError(msg)
        $|  }
        $|}
        $|
        $|
      ),
    )
  } else {
    out.write_string(
      (
        $|///|
        $|pub impl @typify_rt.Serde for \{name} with deserialize(d) {
        $|  \{name}(\{self.de_expr(d.type_id, "d")})
        $|}
        $|
        $|
      ),
    )
  }
  out.write_string(
    (
      $|///|
      $|pub impl @typify_rt.Serde for \{name} with serialize(self) {
      $|  \{self.ser_expr(d.type_id, "self.0")}
      $|}
      $|
      $|
    ),
  )
  self.type_default(out, name, id, d.default)
  self.api_methods(out, name)
}

// ---------------------------------------------------------------------------
// Enums

///|
fn Gen::variant_decl(
  self : Gen,
  id : @typify.TypeId,
  i : Int,
  v : @typify.Variant,
) -> String {
  let ctor = self.ctors.get(id.0).unwrap()[i]
  match v.details {
    Simple => ctor
    Item(t) => "\{ctor}(\{self.mbt_type(t)})"
    Tuple(ts) => "\{ctor}(\{ts.map(t => self.mbt_type(t)).join(", ")})"
    Struct(props) => {
      let labels = self.fields.get("\{id.0}/\{i}").unwrap()
      "\{ctor}(\{props.mapi((j, p) => "\{labels[j]}~ : \{self.mbt_type(p.type_id)}").join(", ")})"
    }
  }
}

///|
/// Decoding code for a variant payload (external/untagged forms) from `d`.
fn Gen::variant_payload_decode(
  self : Gen,
  out : StringBuilder,
  id : @typify.TypeId,
  enum_name : String,
  i : Int,
  v : @typify.Variant,
  d : String,
  allow_seq : Bool,
  deny : Bool,
  external : Bool,
) -> String {
  let type_name = self.type_name(id)
  let ctor = "\{type_name}::\{self.ctors.get(id.0).unwrap()[i]}"
  match v.details {
    Simple => "{ @typify_rt.de_unit(\{d}); \{ctor} }"
    Item(t) => "\{ctor}(\{self.de_expr(t, d)})"
    Tuple(ts) => {
      let elems = ts.mapi((j, t) => "let t\{j} = \{self.de_fn(t)}(s.next())")
      let expecting = str_lit(
        "tuple variant \{enum_name}::\{v.ident_name.unwrap()}",
      )
      "{ let s = @typify_rt.de_tuple_variant(\{d}, \{expecting}, \{ts.length()}, \{external}); \{elems.join("; ")}; s.finish(); \{ctor}(\{ts.mapi((j, _) => "t\{j}").join(", ")}) }"
    }
    Struct(props) => {
      let labels = self.fields.get("\{id.0}/\{i}").unwrap()
      let build = "\{ctor}(\{labels.mapi((j, l) => "\{l}=v\{j}").join(", ")})"
      let code = self.struct_decode(
        out,
        enum_name + v.ident_name.unwrap(),
        props,
        "struct variant \{enum_name}::\{v.ident_name.unwrap()}",
        deny,
        allow_seq,
        d,
        build,
        external_variant=external,
      )
      "{\n\{indent(code, 2)}\n}"
    }
  }
}

///|
/// Serialization of a variant's payload (`None` for unit variants); the
/// payload fields are bound as `p0`, `p1`, ...
fn Gen::variant_payload_encode(self : Gen, v : @typify.Variant) -> String? {
  match v.details {
    Simple => None
    Item(t) => Some(self.ser_expr(t, "p0"))
    Tuple(ts) =>
      Some(
        "@typify_rt.Content::Array([\{ts.mapi((j, t) => self.ser_expr(t, "p\{j}")).join(", ")}])",
      )
    Struct(props) =>
      Some(
        "{\n  let o = @typify_rt.ObjectBuilder::new()\n\{indent(self.struct_encode(props, j => "p\{j}").trim_end().to_owned(), 2)}\n  o.build()\n}",
      )
  }
}

///|
fn Gen::variant_pattern(
  self : Gen,
  id : @typify.TypeId,
  i : Int,
  v : @typify.Variant,
) -> String {
  let ctor = self.ctors.get(id.0).unwrap()[i]
  match v.details {
    Simple => ctor
    Item(_) => "\{ctor}(p0)"
    Tuple(ts) => "\{ctor}(\{ts.mapi((j, _) => "p\{j}").join(", ")})"
    Struct(props) => {
      let labels = self.fields.get("\{id.0}/\{i}").unwrap()
      "\{ctor}(\{props.mapi((j, _) => "\{labels[j]}=p\{j}").join(", ")})"
    }
  }
}

///|
fn Gen::output_enum(
  self : Gen,
  out : StringBuilder,
  id : @typify.TypeId,
  d : @typify.TypeEntryEnum,
) -> Unit {
  let name = self.type_name(id)
  let all_simple = d.variants.iter().all(v => v.details is Simple)
  let derives = if all_simple { "Debug, Eq, Hash" } else { "Debug, Eq" }
  let raw_names = d.variants.map(v => v.raw_name)
  out.write_string("///|\n")
  out.write_string(doc_comment(Some(d.description.unwrap_or("`\{d.name}`"))))
  out.write_string("pub(all) enum \{name} {\n")
  for i, v in d.variants {
    out.write_string(indent(doc_comment(v.description), 2))
    out.write_string("  \{self.variant_decl(id, i, v)}\n")
  }
  out.write_string("} derive(\{derives})\n\n")
  // Decoding.
  let arms = StringBuilder()
  let body = match d.tag_type {
    External => {
      for i, v in d.variants {
        let payload_kind = match v.details {
          Simple => ""
          Item(_) => "newtype variant"
          Tuple(_) => "tuple variant"
          Struct(_) => "struct variant"
        }
        let code = match v.details {
          Simple =>
            "{ @typify_rt.variant_unit(payload); \{name}::\{self.ctors.get(id.0).unwrap()[i]} }"
          _ =>
            self.variant_payload_decode(
              out,
              id,
              d.name,
              i,
              v,
              "@typify_rt.variant_payload(payload, \{str_lit(payload_kind)})",
              true,
              d.deny_unknown_fields,
              true,
            )
        }
        arms.write_string("  \{i} => \{indent(code, 2).trim_start()}\n")
      }
      (
        $|let (idx, payload) = @typify_rt.de_enum(d, \{str_lit(d.name)}, \{str_array(raw_names)})
        $|let v = match idx {
        $|\{arms.to_string().trim_end()}
        $|  _ => abort("unreachable")
        $|}
        $|@typify_rt.end_enum_map(d)
        $|v
      )
    }
    Internal(tag~) => {
      for i, v in d.variants {
        let code = match v.details {
          Simple =>
            "{ @typify_rt.internal_unit(rest, \{str_lit(d.name)}, \{str_lit(v.raw_name)}); \{name}::\{self.ctors.get(id.0).unwrap()[i]} }"
          _ =>
            self.variant_payload_decode(
              out,
              id,
              d.name,
              i,
              v,
              "rest",
              true,
              d.deny_unknown_fields,
              false,
            )
        }
        arms.write_string("  \{i} => \{indent(code, 2).trim_start()}\n")
      }
      (
        $|let (idx, rest) = @typify_rt.de_internal(d, \{str_lit(d.name)}, \{str_lit(tag)}, \{str_array(raw_names)})
        $|match idx {
        $|\{arms.to_string().trim_end()}
        $|  _ => abort("unreachable")
        $|}
      )
    }
    Adjacent(tag~, content~) => {
      for i, v in d.variants {
        let code = match v.details {
          Simple =>
            "{ @typify_rt.variant_unit(payload); \{name}::\{self.ctors.get(id.0).unwrap()[i]} }"
          _ =>
            self.variant_payload_decode(
              out,
              id,
              d.name,
              i,
              v,
              "@typify_rt.variant_payload(payload, \"variant content\")",
              true,
              d.deny_unknown_fields,
              false,
            )
        }
        arms.write_string("  \{i} => \{indent(code, 2).trim_start()}\n")
      }
      (
        $|let (idx, payload) = @typify_rt.de_adjacent(d, \{str_lit(d.name)}, \{str_lit(tag)}, \{str_lit(content)}, \{str_array(raw_names)}, \{d.deny_unknown_fields})
        $|match idx {
        $|\{arms.to_string().trim_end()}
        $|  _ => abort("unreachable")
        $|}
      )
    }
    Untagged => {
      let tries = StringBuilder()
      for i, v in d.variants {
        let code = self.variant_payload_decode(
          out,
          id,
          d.name,
          i,
          v,
          "c",
          false,
          d.deny_unknown_fields,
          false,
        )
        tries.write_string(
          "try {\n\{indent(code, 2)}\n} catch {\n  @typify_rt.DeError(msg) if !msg.has_prefix(\"panic:\") => ()\n  e => raise e\n} noraise {\n  v => return v\n}\n",
        )
      }
      (
        $|let c = @typify_rt.de_untagged(d)
        $|\{tries.to_string().trim_end()}
        $|raise @typify_rt.untagged_error(\{str_lit(d.name)})
      )
    }
  }
  out.write_string(
    (
      $|///|
      $|pub impl @typify_rt.Serde for \{name} with deserialize(d) {
      $|\{indent(body, 2)}
      $|}
      $|
      $|
    ),
  )
  // Encoding.
  let enc = StringBuilder()
  for i, v in d.variants {
    let payload = self.variant_payload_encode(v)
    let raw = str_lit(v.raw_name)
    let expr = match (d.tag_type, payload) {
      (External, None) => "@typify_rt.ser_string(\{raw})"
      (External, Some(p)) => "@typify_rt.single_entry(\{raw}, \{p})"
      (Internal(tag~), None) =>
        "@typify_rt.single_entry(\{str_lit(tag)}, @typify_rt.ser_string(\{raw}))"
      (Internal(tag~), Some(p)) =>
        "@typify_rt.tagged(\{str_lit(tag)}, \{raw}, \{p})"
      (Adjacent(tag~, ..), None) =>
        "@typify_rt.single_entry(\{str_lit(tag)}, @typify_rt.ser_string(\{raw}))"
      (Adjacent(tag~, content~), Some(p)) =>
        "@typify_rt.adjacent(\{str_lit(tag)}, \{raw}, \{str_lit(content)}, \{p})"
      (Untagged, None) => "@typify_rt.ser_unit()"
      (Untagged, Some(p)) => p
    }
    enc.write_string(
      "  \{self.variant_pattern(id, i, v)} => \{indent(expr, 2).trim_start()}\n",
    )
  }
  let enc_body = if d.variants.is_empty() {
    "  _ => abort(\"uninhabited\")\n"
  } else {
    enc.to_string()
  }
  out.write_string(
    (
      $|///|
      $|pub impl @typify_rt.Serde for \{name} with serialize(self) {
      $|  match self {
      $|\{indent(enc_body.trim_end().to_owned(), 2)}
      $|  }
      $|}
      $|
      $|
    ),
  )
  if all_simple && !d.variants.is_empty() {
    let idx_arms = d.variants
      .mapi((i, _) => "    \{self.ctors.get(id.0).unwrap()[i]} => \{i}")
      .join("\n")
    let str_arms = d.variants
      .mapi((i, v) => {
        "    \{self.ctors.get(id.0).unwrap()[i]} => \{str_lit(v.raw_name)}"
      })
      .join("\n")
    let parse_arms = d.variants
      .mapi((i, v) => {
        "    \{str_lit(v.raw_name)} => \{self.ctors.get(id.0).unwrap()[i]}"
      })
      .join("\n")
    out.write_string(
      (
        $|///|
        $|/// The variant's position in declaration order.
        $|pub fn \{name}::variant_index(self : \{name}) -> Int {
        $|  match self {
        $|\{idx_arms}
        $|  }
        $|}
        $|
        $|///|
        $|/// The serialized name (upstream `Display`).
        $|pub fn \{name}::to_string(self : \{name}) -> String {
        $|  match self {
        $|\{str_arms}
        $|  }
        $|}
        $|
        $|///|
        $|/// Parse a serialized name (upstream `FromStr`).
        $|pub fn \{name}::parse(value : StringView) -> \{name} raise @typify_rt.ConversionError {
        $|  match value {
        $|\{parse_arms}
        $|    _ => raise @typify_rt.ConversionError("invalid value")
        $|  }
        $|}
        $|
        $|
      ),
    )
  }
  self.type_default(out, name, id, d.default)
  self.api_methods(out, name)
}

// ---------------------------------------------------------------------------

///|
let header : String =
  #|// Code generated by typify.mbt (https://github.com/oxidecomputer/typify port); DO NOT EDIT.
  #|//
  #|// Requires in moon.pkg:
  #|//   import { "bobzhang/typify/runtime" @typify_rt }
  #|

///|
/// Generate MoonBit code for all types in the type space.
pub fn generate(space : @typify.TypeSpace) -> String {
  let gen = Gen::new(space)
  let out = StringBuilder()
  out.write_string(header)
  out.write_string("\n")
  for pair in space.entries() {
    let (id, e) = pair
    match e.details {
      Struct(d) => gen.output_struct(out, id, d)
      Enum(d) => gen.output_enum(out, id, d)
      Newtype(d) => gen.output_newtype(out, id, d)
      _ => ()
    }
  }
  out.to_string()
}

///|
/// The MoonBit name generated for a named type.
pub fn type_name_of(space : @typify.TypeSpace, id : @typify.TypeId) -> String {
  Gen::new(space).type_name(id)
}
