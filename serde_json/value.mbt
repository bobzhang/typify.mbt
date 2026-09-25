///|
/// A JSON value with serde_json semantics: numbers keep their integer/float
/// classification and objects iterate in key order (serde_json without the
/// `preserve_order` feature, as used by typify).
pub(all) enum Value {
  Null
  Bool(Bool)
  Number(Number)
  String(String)
  Array(Array[Value])
  Object(@collections.StrMap[Value])
} derive(Debug, Eq)

///|
pub fn Value::is_null(self : Value) -> Bool {
  self is Null
}

///|
pub fn Value::is_boolean(self : Value) -> Bool {
  self is Bool(_)
}

///|
pub fn Value::is_number(self : Value) -> Bool {
  self is Number(_)
}

///|
pub fn Value::is_string(self : Value) -> Bool {
  self is String(_)
}

///|
pub fn Value::is_array(self : Value) -> Bool {
  self is Array(_)
}

///|
pub fn Value::is_object(self : Value) -> Bool {
  self is Object(_)
}

///|
pub fn Value::is_u64(self : Value) -> Bool {
  self is Number(n) && n.is_u64()
}

///|
pub fn Value::is_i64(self : Value) -> Bool {
  self is Number(n) && n.is_i64()
}

///|
pub fn Value::is_f64(self : Value) -> Bool {
  self is Number(n) && n.is_f64()
}

///|
pub fn Value::as_bool(self : Value) -> Bool? {
  match self {
    Bool(b) => Some(b)
    _ => None
  }
}

///|
pub fn Value::as_str(self : Value) -> String? {
  match self {
    String(s) => Some(s)
    _ => None
  }
}

///|
pub fn Value::as_array(self : Value) -> Array[Value]? {
  match self {
    Array(a) => Some(a)
    _ => None
  }
}

///|
pub fn Value::as_object(self : Value) -> @collections.StrMap[Value]? {
  match self {
    Object(o) => Some(o)
    _ => None
  }
}

///|
pub fn Value::as_u64(self : Value) -> UInt64? {
  match self {
    Number(n) => n.as_u64()
    _ => None
  }
}

///|
pub fn Value::as_i64(self : Value) -> Int64? {
  match self {
    Number(n) => n.as_i64()
    _ => None
  }
}

///|
/// Like serde_json's `as_f64`: any number converts, other values do not.
pub fn Value::as_f64(self : Value) -> Double? {
  match self {
    Number(n) => Some(n.as_f64())
    _ => None
  }
}

///|
/// Look up a key of an object value.
pub fn Value::get(self : Value, key : StringView) -> Value? {
  match self {
    Object(o) => o.get(key)
    _ => None
  }
}

///|
/// Build an object value from pairs (later duplicates win).
pub fn Value::object(pairs : ArrayView[(String, Value)]) -> Value {
  Object(@collections.StrMap::from_array(pairs))
}

///|
pub fn Value::from_u64(n : UInt64) -> Value {
  Number(PosInt(n))
}

///|
pub fn Value::from_i64(n : Int64) -> Value {
  Number(Number::from_i64(n))
}

///|
/// Non-finite floats become `Null`, like serde_json's `From<f64>`.
pub fn Value::from_f64(d : Double) -> Value {
  match Number::from_f64(d) {
    Some(n) => Number(n)
    None => Null
  }
}

///|
/// Compact JSON text, identical to serde_json's `Display` / `to_string`.
pub impl Show for Value with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn Value::to_string(self : Value) -> String {
  let buf = StringBuilder()
  write_compact(buf, self)
  buf.to_string()
}

///|
/// Pretty JSON text, identical to serde_json's `to_string_pretty`.
pub fn Value::to_string_pretty(self : Value) -> String {
  let buf = StringBuilder()
  write_pretty(buf, self, 0)
  buf.to_string()
}

///|
/// Convert to MoonBit's builtin `Json`. Integers outside the exactly
/// representable range keep their text in `repr`.
pub fn Value::to_json(self : Value) -> Json {
  match self {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Number(n) => {
      let d = n.as_f64()
      match n {
        Float(_) => Json::number(d)
        _ => {
          let text = n.to_string()
          if d.to_string() == text {
            Json::number(d)
          } else {
            Json::number(d, repr=text)
          }
        }
      }
    }
    String(s) => Json::string(s)
    Array(xs) => Json::array(xs.map(x => x.to_json()))
    Object(o) => {
      let m : Map[String, Json] = Map([])
      for k, v in o {
        m[k] = v.to_json()
      }
      Json::object(m)
    }
  }
}

///|
/// Convert from MoonBit's builtin `Json`. Numbers with a preserved lexeme are
/// re-classified from it; otherwise integral values within 2^53 become
/// integers and everything else a float.
pub fn Value::from_json(json : Json) -> Value {
  match json {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(d, repr~) => {
      if repr is Some(text) {
        try parse(text) catch {
          _ => ()
        } noraise {
          Number(n) => return Number(n)
          _ => ()
        }
      }
      let limit = 9007199254740992.0
      if d == d.floor() && d.abs() <= limit {
        if d >= 0.0 {
          Number(PosInt(d.to_uint64()))
        } else {
          Number(NegInt(d.to_int64()))
        }
      } else {
        Value::from_f64(d)
      }
    }
    String(s) => String(s)
    Array(xs) => Array(xs.map(Value::from_json))
    Object(m) => {
      let o = @collections.StrMap::new()
      for k, v in m {
        o.set(k, Value::from_json(v))
      }
      Object(o)
    }
  }
}
