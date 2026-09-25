///|
/// Validate a value against the instance type, `const` and `enum` of a schema
/// (upstream validate.rs). Returns an error message on failure.
fn schema_value_validate(
  schema : @schema.Schema,
  value : @serde_json.Value,
) -> String? {
  match schema {
    Bool(false) => Some("never schema")
    Bool(true) => None
    Object(object) => {
      if object.const_value is Some(c) && value != c {
        return Some("\{value} does not match the const value \{c}")
      }
      if object.enum_values is Some(values) && !values.contains(value) {
        return Some(
          "\{value} does not match the enum values \{@serde_json.Value::Array(values)}",
        )
      }
      match object.instance_type {
        None => None
        Some(Single(it)) => check_instance(it, value)
        Some(Vec(its)) =>
          if its.iter().any(it => check_instance(it, value) is None) {
            None
          } else {
            Some("no valid instance type")
          }
      }
    }
  }
}

///|
fn check_instance(
  it : @schema.InstanceType,
  value : @serde_json.Value,
) -> String? {
  let ok = match it {
    Null => value.is_null()
    Boolean => value.is_boolean()
    Object => value.is_object()
    Array => value.is_array()
    Number => value.is_number()
    String => value.is_string()
    Integer => value.is_i64() || value.is_u64()
  }
  if ok {
    None
  } else {
    Some("not \{it.name()}")
  }
}
