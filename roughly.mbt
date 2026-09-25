///|
/// Structural equality ignoring metadata and extensions (upstream `Roughly`).
fn roughly(a : @schema.Schema, b : @schema.Schema) -> Bool {
  match (a, b) {
    (Bool(x), Bool(y)) => x == y
    (Bool(false), _) | (_, Bool(false)) => false
    (Bool(true), Object(o)) | (Object(o), Bool(true)) => shape(o, any=F_META)
    (Object(a), Object(b)) =>
      a.instance_type == b.instance_type &&
      a.format == b.format &&
      a.enum_values == b.enum_values &&
      a.const_value == b.const_value &&
      roughly_subschemas(a.subschemas, b.subschemas) &&
      a.number == b.number &&
      a.string == b.string &&
      roughly_array(a.array, b.array) &&
      roughly_object(a.object, b.object) &&
      a.reference == b.reference
  }
}

///|
fn roughly_option(a : @schema.Schema?, b : @schema.Schema?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => roughly(x, y)
    _ => false
  }
}

///|
fn roughly_schema_array(
  a : Array[@schema.Schema]?,
  b : Array[@schema.Schema]?,
) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) =>
      x.length() == y.length() &&
      x.iter().zip(y.iter()).all(p => roughly(p.0, p.1))
    _ => false
  }
}

///|
fn roughly_subschemas(
  a : @schema.SubschemaValidation?,
  b : @schema.SubschemaValidation?,
) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) =>
      roughly_schema_array(x.all_of, y.all_of) &&
      roughly_schema_array(x.any_of, y.any_of) &&
      roughly_schema_array(x.one_of, y.one_of) &&
      roughly_option(x.not, y.not) &&
      roughly_option(x.if_schema, y.if_schema) &&
      roughly_option(x.then_schema, y.then_schema) &&
      roughly_option(x.else_schema, y.else_schema)
    _ => false
  }
}

///|
fn roughly_array(
  a : @schema.ArrayValidation?,
  b : @schema.ArrayValidation?,
) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) =>
      match (x.items, y.items) {
        (None, None) => true
        (Some(Single(p)), Some(Single(q))) => roughly(p, q)
        (Some(Vec(p)), Some(Vec(q))) => roughly_schema_array(Some(p), Some(q))
        _ => false
      }
    _ => false
  }
}

///|
fn roughly_properties(
  a : @collections.StrMap[@schema.Schema],
  b : @collections.StrMap[@schema.Schema],
) -> Bool {
  let xs = a.to_array()
  let ys = b.to_array()
  xs.length() == ys.length() &&
  xs.iter().zip(ys.iter()).all(p => p.0.0 == p.1.0 && roughly(p.0.1, p.1.1))
}

///|
fn roughly_object(
  a : @schema.ObjectValidation?,
  b : @schema.ObjectValidation?,
) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) =>
      x.max_properties == y.max_properties &&
      x.min_properties == y.min_properties &&
      x.required == y.required &&
      roughly_properties(x.properties, y.properties) &&
      roughly_properties(x.pattern_properties, y.pattern_properties) &&
      roughly_option(x.additional_properties, y.additional_properties) &&
      roughly_option(x.property_names, y.property_names)
    _ => false
  }
}
