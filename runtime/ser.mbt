// Serialization to an ordered `Content` document with serde's semantics,
// rendered to text by the serde_json-exact writer.

///|
pub using @serde_json {type Content, type Entry}

///|
/// A serialization error (serde_json's `to_string` fails).
pub(all) suberror SerError {
  SerError(String)
} derive(Debug, Eq)

///|
pub impl Show for SerError with fn output(self, logger) {
  let SerError(msg) = self
  logger.write_string(msg)
}

///|
pub fn ser_null() -> Content {
  Null
}

///|
pub fn ser_bool(b : Bool) -> Content {
  Bool(b)
}

///|
pub fn ser_string(s : String) -> Content {
  String(s)
}

///|
pub fn ser_int(n : Int) -> Content {
  Number(@serde_json.Number::from_i64(n.to_int64()))
}

///|
pub fn ser_uint(n : UInt) -> Content {
  Number(@serde_json.Number::PosInt(n.to_uint64()))
}

///|
pub fn ser_byte(n : Byte) -> Content {
  Number(@serde_json.Number::PosInt(n.to_uint64()))
}

///|
pub fn ser_i16(n : Int16) -> Content {
  Number(@serde_json.Number::from_i64(n.to_int64()))
}

///|
pub fn ser_u16(n : UInt16) -> Content {
  Number(@serde_json.Number::PosInt(n.to_int().to_uint64()))
}

///|
pub fn ser_i64(n : Int64) -> Content {
  Number(@serde_json.Number::from_i64(n))
}

///|
pub fn ser_u64(n : UInt64) -> Content {
  Number(@serde_json.Number::PosInt(n))
}

///|
/// Non-finite floats serialize as `null` (serde_json).
pub fn ser_f64(d : Double) -> Content {
  match @serde_json.Number::from_f64(d) {
    Some(n) => Number(n)
    None => Null
  }
}

///|
/// `f32` values are printed with the shortest `f32` digits (ryu `f32`).
pub fn ser_f32(f : Float) -> Content {
  let d = f.to_double()
  if d.is_nan() || d.is_inf() {
    return Null
  }
  // The shortest decimal that round-trips as an f32, as a Double.
  let text = f.to_string()
  let shortest = @serde_json.parse(text) catch {
    _ => return Number(@serde_json.Number::Float(d))
  }
  match shortest {
    Number(n) => Number(@serde_json.Number::Float(n.as_f64()))
    _ => Number(@serde_json.Number::Float(d))
  }
}

///|
pub fn ser_unit() -> Content {
  Null
}

///|
pub fn[T] ser_vec(
  xs : ArrayView[T],
  f : (T) -> Content raise SerError,
) -> Content raise SerError {
  let out = []
  for x in xs {
    out.push(f(x))
  }
  Array(out)
}

///|
pub fn[T] ser_option(
  v : T?,
  f : (T) -> Content raise SerError,
) -> Content raise SerError {
  match v {
    Some(x) => f(x)
    None => Null
  }
}

///|
/// A map with string keys; `key` renders a key (serde_json `MapKeySerializer`).
pub fn[K, V] ser_map(
  m : Map[K, V],
  key : (K) -> String raise SerError,
  value : (V) -> Content raise SerError,
) -> Content raise SerError {
  let out = []
  for k, v in m {
    out.push(Entry::{
      key: key(k),
      key_escaped: false,
      key_error: None,
      value: value(v),
    })
  }
  Object(out)
}

///|
/// A map serialized in key order (`BTreeMap`): `cmp` is the key type's `Ord`.
pub fn[K, V] ser_sorted_map(
  m : Map[K, V],
  cmp : (K, K) -> Int,
  key : (K) -> String raise SerError,
  value : (V) -> Content raise SerError,
) -> Content raise SerError {
  let pairs = m.to_array()
  pairs.sort_by((a, b) => cmp(a.0, b.0))
  let out = []
  for p in pairs {
    out.push(Entry::{
      key: key(p.0),
      key_escaped: false,
      key_error: None,
      value: value(p.1),
    })
  }
  Object(out)
}

///|
/// A map key from a serialized key value (`MapKeySerializer`): strings are
/// used as-is, integers are quoted; anything else is an error.
pub fn map_key(c : Content) -> String raise SerError {
  match c {
    String(s) => s
    Number(@serde_json.Number::PosInt(_) as n) | Number(NegInt(_) as n) =>
      n.to_string()
    Bool(b) => if b { "true" } else { "false" }
    _ => raise SerError("key must be a string")
  }
}

///|
/// An object being serialized (a struct or a map with flattened entries).
pub struct ObjectBuilder {
  priv entries : Array[@serde_json.Entry]
}

///|
pub fn ObjectBuilder::new() -> ObjectBuilder {
  { entries: [], }
}

///|
pub fn ObjectBuilder::field(
  self : ObjectBuilder,
  key : String,
  value : Content,
) -> Unit {
  self.entries.push({ key, key_escaped: false, key_error: None, value, })
}

///|
/// Merge a flattened value (`FlatMapSerializer`): maps/structs contribute
/// their entries, `None`/unit nothing; anything else is an error.
pub fn ObjectBuilder::flatten(
  self : ObjectBuilder,
  value : Content,
) -> Unit raise SerError {
  match value {
    Object(entries) => self.entries.append(entries)
    Null => ()
    Bool(_) =>
      raise SerError("can only flatten structs and maps (got a boolean)")
    Number(Float(_)) =>
      raise SerError("can only flatten structs and maps (got a float)")
    Number(_) =>
      raise SerError("can only flatten structs and maps (got an integer)")
    String(_) =>
      raise SerError("can only flatten structs and maps (got a string)")
    Array(_) =>
      raise SerError("can only flatten structs and maps (got a sequence)")
    Invalid(_) => raise SerError("invalid value")
  }
}

///|
pub fn ObjectBuilder::build(self : ObjectBuilder) -> Content {
  Object(self.entries)
}

///|
/// `serde_json::Value` payloads (builtin `Json`): keys in serde_json order,
/// numbers by their class.
pub fn ser_json(j : Json) -> Content {
  json_to_value(j).to_content()
}

///|
/// Render a document as compact JSON text (`serde_json::to_string`).
pub fn to_json_string(c : Content) -> String {
  c.to_string()
}
