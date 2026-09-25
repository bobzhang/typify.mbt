// Serialization back to JSON, following schemars' `Serialize` impls (fields
// that are `None`, `false` or empty are skipped as schemars does).

///|
fn put(
  o : @collections.StrMap[@serde_json.Value],
  key : String,
  v : @serde_json.Value?,
) -> Unit {
  if v is Some(v) {
    o.set(key, v)
  }
}

///|
fn str_value(s : String) -> @serde_json.Value {
  String(s)
}

///|
fn arr_value(xs : Array[@serde_json.Value]) -> @serde_json.Value {
  Array(xs)
}

///|
fn bool_value(b : Bool) -> @serde_json.Value {
  Bool(b)
}

///|
fn f64_value(d : Double) -> @serde_json.Value {
  @serde_json.Value::from_f64(d)
}

///|
fn u32_value(n : UInt) -> @serde_json.Value {
  @serde_json.Value::from_u64(n.to_uint64())
}

///|
fn schemas_value(xs : Array[Schema]) -> @serde_json.Value {
  Array(xs.map(x => x.to_value()))
}

///|
fn schema_map_value(m : @collections.StrMap[Schema]) -> @serde_json.Value {
  Object(m.map(x => x.to_value()))
}

///|
/// Serialize to a JSON value.
pub fn Schema::to_value(self : Schema) -> @serde_json.Value {
  match self {
    Bool(b) => Bool(b)
    Object(o) => o.to_value()
  }
}

///|
/// Serialize to a JSON value.
pub fn SchemaObject::to_value(self : SchemaObject) -> @serde_json.Value {
  let o = @collections.StrMap::new()
  if self.metadata is Some(m) {
    put(o, "$id", m.id.map(str_value))
    put(o, "title", m.title.map(str_value))
    put(o, "description", m.description.map(str_value))
    put(o, "default", m.default)
    if m.deprecated {
      o.set("deprecated", Bool(true))
    }
    if m.read_only {
      o.set("readOnly", Bool(true))
    }
    if m.write_only {
      o.set("writeOnly", Bool(true))
    }
    if !m.examples.is_empty() {
      o.set("examples", Array(m.examples))
    }
  }
  put(
    o,
    "type",
    self.instance_type.map(t => {
      match t {
        Single(t) => String(t.name())
        Vec(ts) => Array(ts.map(t => str_value(t.name())))
      }
    }),
  )
  put(o, "format", self.format.map(str_value))
  put(o, "enum", self.enum_values.map(arr_value))
  put(o, "const", self.const_value)
  if self.subschemas is Some(s) {
    put(o, "allOf", s.all_of.map(schemas_value))
    put(o, "anyOf", s.any_of.map(schemas_value))
    put(o, "oneOf", s.one_of.map(schemas_value))
    put(o, "not", s.not.map(x => x.to_value()))
    put(o, "if", s.if_schema.map(x => x.to_value()))
    put(o, "then", s.then_schema.map(x => x.to_value()))
    put(o, "else", s.else_schema.map(x => x.to_value()))
  }
  if self.number is Some(n) {
    put(o, "multipleOf", n.multiple_of.map(f64_value))
    put(o, "maximum", n.maximum.map(f64_value))
    put(o, "exclusiveMaximum", n.exclusive_maximum.map(f64_value))
    put(o, "minimum", n.minimum.map(f64_value))
    put(o, "exclusiveMinimum", n.exclusive_minimum.map(f64_value))
  }
  if self.string is Some(s) {
    put(o, "maxLength", s.max_length.map(u32_value))
    put(o, "minLength", s.min_length.map(u32_value))
    put(o, "pattern", s.pattern.map(str_value))
  }
  if self.array is Some(a) {
    put(
      o,
      "items",
      a.items.map(i => {
        match i {
          Single(s) => s.to_value()
          Vec(xs) => schemas_value(xs)
        }
      }),
    )
    put(o, "additionalItems", a.additional_items.map(x => x.to_value()))
    put(o, "maxItems", a.max_items.map(u32_value))
    put(o, "minItems", a.min_items.map(u32_value))
    put(o, "uniqueItems", a.unique_items.map(bool_value))
    put(o, "contains", a.contains.map(x => x.to_value()))
  }
  if self.object is Some(ov) {
    put(o, "maxProperties", ov.max_properties.map(u32_value))
    put(o, "minProperties", ov.min_properties.map(u32_value))
    if !ov.required.is_empty() {
      o.set("required", Array(ov.required.to_array().map(str_value)))
    }
    if !ov.properties.is_empty() {
      o.set("properties", schema_map_value(ov.properties))
    }
    if !ov.pattern_properties.is_empty() {
      o.set("patternProperties", schema_map_value(ov.pattern_properties))
    }
    put(
      o,
      "additionalProperties",
      ov.additional_properties.map(x => x.to_value()),
    )
    put(o, "propertyNames", ov.property_names.map(x => x.to_value()))
  }
  put(o, "$ref", self.reference.map(str_value))
  for k, v in self.extensions {
    o.set(k, v)
  }
  Object(o)
}

///|
/// Serialize to a JSON value.
pub fn RootSchema::to_value(self : RootSchema) -> @serde_json.Value {
  guard self.schema.to_value() is Object(o) else { abort("unreachable") }
  let o = o.copy()
  put(o, "$schema", self.meta_schema.map(str_value))
  if !self.definitions.is_empty() {
    o.set("definitions", schema_map_value(self.definitions))
  }
  Object(o)
}
