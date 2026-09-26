// Decoding a `serde_json::Value` into the schema model, reproducing
// `serde_json::from_str::<schemars::schema::RootSchema>`:
//
// - every struct is `#[serde(default)]`: absent keys take default values;
// - `Option<T>` fields read `null` as `None`, except `const` and `default`
//   (`allow_null`), which keep `Some(Null)`;
// - validation groups and metadata are `#[serde(flatten)]`: each consumes the
//   keys it recognises and all remaining keys become `extensions`;
// - a group equal to its default is `None` (`skip_if_default`);
// - `Schema` and `SingleOrVec` are untagged enums.

///|
/// A schema decoding error with serde's message and a JSON pointer to the
/// offending value.
pub(all) suberror SchemaError {
  SchemaError(message~ : String, path~ : String)
} derive(Debug, Eq)

///|
pub impl Show for SchemaError with fn output(self, logger) {
  let SchemaError(message~, path~) = self
  if path == "" {
    logger.write_string(message)
  } else {
    logger.write_string("\{message} at \{path}")
  }
}

///|
fn json_pointer_escape(key : String) -> String {
  key.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
/// serde's `Unexpected` rendering of a value.
fn unexpected(v : @serde_json.Value) -> String {
  match v {
    Null => "null"
    Bool(b) => "boolean `\{b}`"
    Number(PosInt(n)) => "integer `\{n}`"
    Number(NegInt(n)) => "integer `\{n}`"
    Number(Float(_) as n) => "floating point `\{n}`"
    String(s) => {
      let buf = StringBuilder()
      @serde_json.write_escaped_str(buf, s)
      "string \{buf}"
    }
    Array(_) => "sequence"
    Object(_) => "map"
  }
}

///|
fn invalid_type(
  v : @serde_json.Value,
  expected : String,
  path : String,
) -> SchemaError {
  SchemaError(
    message="invalid type: \{unexpected(v)}, expected \{expected}",
    path~,
  )
}

///|
fn child(path : String, key : String) -> String {
  "\{path}/\{json_pointer_escape(key)}"
}

///|
fn decode_string(
  v : @serde_json.Value,
  path : String,
) -> String raise SchemaError {
  match v {
    String(s) => s
    _ => raise invalid_type(v, "a string", path)
  }
}

///|
fn decode_bool(v : @serde_json.Value, path : String) -> Bool raise SchemaError {
  match v {
    Bool(b) => b
    _ => raise invalid_type(v, "a boolean", path)
  }
}

///|
fn decode_f64(v : @serde_json.Value, path : String) -> Double raise SchemaError {
  match v {
    Number(n) => n.as_f64()
    _ => raise invalid_type(v, "f64", path)
  }
}

///|
fn decode_u32(v : @serde_json.Value, path : String) -> UInt raise SchemaError {
  match v {
    Number(PosInt(n)) =>
      if n <= 0xFFFF_FFFFUL {
        n.to_uint()
      } else {
        raise SchemaError(
          message="invalid value: integer `\{n}`, expected u32",
          path~,
        )
      }
    Number(NegInt(n)) =>
      raise SchemaError(
        message="invalid value: integer `\{n}`, expected u32",
        path~,
      )
    _ => raise invalid_type(v, "u32", path)
  }
}

///|
fn decode_array(
  v : @serde_json.Value,
  path : String,
) -> Array[@serde_json.Value] raise SchemaError {
  match v {
    Array(xs) => xs
    _ => raise invalid_type(v, "a sequence", path)
  }
}

///|
fn decode_object(
  v : @serde_json.Value,
  path : String,
) -> @collections.StrMap[@serde_json.Value] raise SchemaError {
  match v {
    Object(o) => o
    _ => raise invalid_type(v, "a map", path)
  }
}

///|
/// Decode `Option<T>`: `null` is `None`.
fn[T] opt(
  v : @serde_json.Value?,
  path : String,
  f : (@serde_json.Value, String) -> T raise SchemaError,
) -> T? raise SchemaError {
  match v {
    None | Some(Null) => None
    Some(x) => Some(f(x, path))
  }
}

///|
/// Decode an untagged `Schema`: a boolean or a schema object.
pub fn decode_schema(
  v : @serde_json.Value,
  path? : String = "",
) -> Schema raise SchemaError {
  match v {
    Bool(b) => Bool(b)
    Object(o) => Object(decode_schema_object(o, path~))
    _ =>
      raise SchemaError(
        message="data did not match any variant of untagged enum Schema",
        path~,
      )
  }
}

///|
fn decode_schema_array(
  v : @serde_json.Value,
  path : String,
) -> Array[Schema] raise SchemaError {
  let xs = decode_array(v, path)
  let out = []
  for i, x in xs {
    out.push(decode_schema(x, path=child(path, i.to_string())))
  }
  out
}

///|
fn decode_schema_map(
  v : @serde_json.Value,
  path : String,
) -> @collections.StrMap[Schema] raise SchemaError {
  let o = decode_object(v, path)
  // Keep the document's key order when the input preserves it.
  let out = o.empty_like()
  for k, x in o {
    out.set(k, decode_schema(x, path=child(path, k)))
  }
  out
}

///|
fn decode_instance_type(
  v : @serde_json.Value,
  path : String,
) -> InstanceType raise SchemaError {
  match v {
    String("null") => Null
    String("boolean") => Boolean
    String("object") => Object
    String("array") => Array
    String("number") => Number
    String("string") => String
    String("integer") => Integer
    _ => raise SchemaError(message="unknown instance type", path~)
  }
}

///|
fn decode_type(
  v : @serde_json.Value,
  path : String,
) -> SingleOrVec[InstanceType] raise SchemaError {
  let fail = SchemaError(
    message="data did not match any variant of untagged enum SingleOrVec",
    path~,
  )
  match v {
    String(_) => Single(decode_instance_type(v, path)) catch { _ => raise fail }
    Array(xs) => {
      let out = []
      for x in xs {
        out.push(decode_instance_type(x, path)) catch {
          _ => raise fail
        }
      }
      Vec(out)
    }
    _ => raise fail
  }
}

///|
fn decode_items(
  v : @serde_json.Value,
  path : String,
) -> SingleOrVec[Schema] raise SchemaError {
  match v {
    Array(_) => Vec(decode_schema_array(v, path))
    _ =>
      Single(decode_schema(v, path~)) catch {
        _ =>
          raise SchemaError(
            message="data did not match any variant of untagged enum SingleOrVec",
            path~,
          )
      }
  }
}

///|
/// Key-consuming view of an object's entries (serde's flatten buffer).
priv struct Entries {
  map : @collections.StrMap[@serde_json.Value]
  path : String
}

///|
fn Entries::take(self : Entries, key : String) -> @serde_json.Value? {
  self.map.remove(key)
}

///|
fn Entries::path_of(self : Entries, key : String) -> String {
  child(self.path, key)
}

///|
fn Entries::metadata(self : Entries) -> Metadata? raise SchemaError {
  let m : Metadata = {
    id: opt(self.take("$id"), self.path_of("$id"), decode_string),
    title: opt(self.take("title"), self.path_of("title"), decode_string),
    description: opt(
      self.take("description"),
      self.path_of("description"),
      decode_string,
    ),
    // allow_null
    default: self.take("default"),
    deprecated: match self.take("deprecated") {
      None => false
      Some(v) => decode_bool(v, self.path_of("deprecated"))
    },
    read_only: match self.take("readOnly") {
      None => false
      Some(v) => decode_bool(v, self.path_of("readOnly"))
    },
    write_only: match self.take("writeOnly") {
      None => false
      Some(v) => decode_bool(v, self.path_of("writeOnly"))
    },
    examples: match self.take("examples") {
      None => []
      Some(v) => decode_array(v, self.path_of("examples"))
    },
  }
  if m == Metadata::default() {
    None
  } else {
    Some(m)
  }
}

///|
fn Entries::subschemas(
  self : Entries,
) -> SubschemaValidation? raise SchemaError {
  let s : SubschemaValidation = {
    all_of: opt(self.take("allOf"), self.path_of("allOf"), decode_schema_array),
    any_of: opt(self.take("anyOf"), self.path_of("anyOf"), decode_schema_array),
    one_of: opt(self.take("oneOf"), self.path_of("oneOf"), decode_schema_array),
    not: opt(self.take("not"), self.path_of("not"), (v, p) => {
      decode_schema(v, path=p)
    }),
    if_schema: opt(self.take("if"), self.path_of("if"), (v, p) => {
      decode_schema(v, path=p)
    }),
    then_schema: opt(self.take("then"), self.path_of("then"), (v, p) => {
      decode_schema(v, path=p)
    }),
    else_schema: opt(self.take("else"), self.path_of("else"), (v, p) => {
      decode_schema(v, path=p)
    }),
  }
  if s == SubschemaValidation::default() {
    None
  } else {
    Some(s)
  }
}

///|
fn Entries::number(self : Entries) -> NumberValidation? raise SchemaError {
  let n : NumberValidation = {
    multiple_of: opt(
      self.take("multipleOf"),
      self.path_of("multipleOf"),
      decode_f64,
    ),
    maximum: opt(self.take("maximum"), self.path_of("maximum"), decode_f64),
    exclusive_maximum: opt(
      self.take("exclusiveMaximum"),
      self.path_of("exclusiveMaximum"),
      decode_f64,
    ),
    minimum: opt(self.take("minimum"), self.path_of("minimum"), decode_f64),
    exclusive_minimum: opt(
      self.take("exclusiveMinimum"),
      self.path_of("exclusiveMinimum"),
      decode_f64,
    ),
  }
  if n == NumberValidation::default() {
    None
  } else {
    Some(n)
  }
}

///|
fn Entries::string(self : Entries) -> StringValidation? raise SchemaError {
  let s : StringValidation = {
    max_length: opt(
      self.take("maxLength"),
      self.path_of("maxLength"),
      decode_u32,
    ),
    min_length: opt(
      self.take("minLength"),
      self.path_of("minLength"),
      decode_u32,
    ),
    pattern: opt(self.take("pattern"), self.path_of("pattern"), decode_string),
  }
  if s == StringValidation::default() {
    None
  } else {
    Some(s)
  }
}

///|
fn Entries::array(self : Entries) -> ArrayValidation? raise SchemaError {
  let a : ArrayValidation = {
    items: opt(self.take("items"), self.path_of("items"), decode_items),
    additional_items: opt(
      self.take("additionalItems"),
      self.path_of("additionalItems"),
      (v, p) => decode_schema(v, path=p),
    ),
    max_items: opt(self.take("maxItems"), self.path_of("maxItems"), decode_u32),
    min_items: opt(self.take("minItems"), self.path_of("minItems"), decode_u32),
    unique_items: opt(
      self.take("uniqueItems"),
      self.path_of("uniqueItems"),
      decode_bool,
    ),
    contains: opt(self.take("contains"), self.path_of("contains"), (v, p) => {
      decode_schema(v, path=p)
    }),
  }
  if a == ArrayValidation::default() {
    None
  } else {
    Some(a)
  }
}

///|
fn Entries::object(self : Entries) -> ObjectValidation? raise SchemaError {
  let required = match self.take("required") {
    None => @collections.StrSet::new()
    Some(v) => {
      let p = self.path_of("required")
      let set = @collections.StrSet::new()
      for i, x in decode_array(v, p) {
        set.add(decode_string(x, child(p, i.to_string())))
      }
      set
    }
  }
  let o : ObjectValidation = {
    max_properties: opt(
      self.take("maxProperties"),
      self.path_of("maxProperties"),
      decode_u32,
    ),
    min_properties: opt(
      self.take("minProperties"),
      self.path_of("minProperties"),
      decode_u32,
    ),
    required,
    properties: match self.take("properties") {
      None => @collections.StrMap::new()
      Some(v) => decode_schema_map(v, self.path_of("properties"))
    },
    pattern_properties: match self.take("patternProperties") {
      None => @collections.StrMap::new()
      Some(v) => decode_schema_map(v, self.path_of("patternProperties"))
    },
    additional_properties: opt(
      self.take("additionalProperties"),
      self.path_of("additionalProperties"),
      (v, p) => decode_schema(v, path=p),
    ),
    property_names: opt(
      self.take("propertyNames"),
      self.path_of("propertyNames"),
      (v, p) => decode_schema(v, path=p),
    ),
  }
  if o == ObjectValidation::default() {
    None
  } else {
    Some(o)
  }
}

///|
fn decode_schema_object_entries(e : Entries) -> SchemaObject raise SchemaError {
  let instance_type = opt(e.take("type"), e.path_of("type"), decode_type)
  let format = opt(e.take("format"), e.path_of("format"), decode_string)
  let enum_values = opt(e.take("enum"), e.path_of("enum"), decode_array)
  // allow_null
  let const_value = e.take("const")
  let reference = opt(e.take("$ref"), e.path_of("$ref"), decode_string)
  let metadata = e.metadata()
  let subschemas = e.subschemas()
  let number = e.number()
  let string = e.string()
  let array = e.array()
  let object = e.object()
  {
    metadata,
    instance_type,
    format,
    enum_values,
    const_value,
    subschemas,
    number,
    string,
    array,
    object,
    reference,
    extensions: e.map,
  }
}

///|
/// Decode a schema object from the entries of a JSON object.
pub fn decode_schema_object(
  o : @collections.StrMap[@serde_json.Value],
  path? : String = "",
) -> SchemaObject raise SchemaError {
  decode_schema_object_entries({ map: o.copy(), path, })
}

///|
/// Decode a root schema document from a JSON value.
pub fn RootSchema::from_value(
  v : @serde_json.Value,
) -> RootSchema raise SchemaError {
  guard v is Object(o) else { raise invalid_type(v, "a map", "") }
  let e : Entries = { map: o.copy(), path: "", }
  let meta_schema = opt(e.take("$schema"), "/$schema", decode_string)
  let definitions = match (e.take("definitions"), e.take("$defs")) {
    (Some(_), Some(_)) =>
      raise SchemaError(message="duplicate field `definitions`", path="")
    (Some(v), None) => decode_schema_map(v, "/definitions")
    (None, Some(v)) => decode_schema_map(v, "/$defs")
    (None, None) => @collections.StrMap::new()
  }
  let schema = decode_schema_object_entries(e)
  { meta_schema, schema, definitions, }
}

///|
/// Parse and decode a root schema document from JSON text.
/// `preserve_order` keeps maps (properties, definitions, ...) in document
/// order, like schemars' `preserve_order` feature (see
/// `TypeSpaceSettings::with_preserve_property_order`).
pub fn RootSchema::from_json_str(
  text : StringView,
  preserve_order? : Bool = false,
) -> RootSchema raise {
  RootSchema::from_value(@serde_json.parse(text, preserve_order~))
}
