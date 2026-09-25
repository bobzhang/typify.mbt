// JSON text <-> builtin `Json` with serde_json's exact behaviour.
//
// Numbers carry serde_json's classification in `repr`: floats always get
// their serde_json text (so `1.0` is distinguishable from `1`), integers get
// a repr only when they cannot be represented exactly as a Double.

///|
/// Parse JSON text exactly like `serde_json::from_str::<Value>` (errors,
/// number classification, key order), producing a builtin `Json`.
pub fn parse(text : StringView) -> Json raise @serde_json.ParseError {
  value_to_json(@serde_json.parse(text))
}

///|
/// Convert a serde_json value to `Json`, recording number classes in `repr`.
pub fn value_to_json(v : @serde_json.Value) -> Json {
  match v {
    Null => Json::null()
    Bool(b) => Json::boolean(b)
    Number(n) => number_to_json(n)
    String(s) => Json::string(s)
    Array(xs) => Json::array(xs.map(value_to_json))
    Object(o) => {
      let m : Map[String, Json] = Map([])
      for k, x in o {
        m[k] = value_to_json(x)
      }
      Json::object(m)
    }
  }
}

///|
fn number_to_json(n : @serde_json.Number) -> Json {
  match n {
    Float(d) => Json::number(d, repr=@serde_json.format_f64(d))
    _ => {
      let d = n.as_f64()
      let text = n.to_string()
      if exact_integer_double(d) && d.to_string() == text {
        Json::number(d)
      } else {
        Json::number(d, repr=text)
      }
    }
  }
}

///|
/// Whether `d` is an integer with |d| <= 2^53 (exactly representable).
fn exact_integer_double(d : Double) -> Bool {
  d == d.floor() && d.abs() <= 9007199254740992.0
}

///|
/// The serde_json classification of a `Json` number.
///
/// A `repr` is authoritative (it is either our own or from `@json.parse`
/// for numbers that are not exactly representable). Without one, integral
/// values are integers.
pub fn classify_number(d : Double, repr : String?) -> @serde_json.Number {
  match repr {
    Some(text) =>
      try @serde_json.parse(text) catch {
        _ => Float(d)
      } noraise {
        Number(n) => n
        _ => Float(d)
      }
    None =>
      if d == d.floor() && d.abs() < 18446744073709551616.0 && !d.is_nan() {
        if d >= 0.0 {
          PosInt(d.to_uint64())
        } else if d >= -9223372036854775808.0 {
          if d == 0.0 {
            PosInt(0)
          } else {
            NegInt(d.to_int64())
          }
        } else {
          Float(d)
        }
      } else {
        Float(d)
      }
  }
}

///|
/// Convert `Json` to a serde_json value. Objects are key-sorted (serde_json
/// `Map` order).
pub fn json_to_value(j : Json) -> @serde_json.Value {
  match j {
    Null => Null
    True => Bool(true)
    False => Bool(false)
    Number(d, repr~) =>
      if d.is_nan() || d.is_inf() {
        Null
      } else {
        Number(classify_number(d, repr))
      }
    String(s) => String(s)
    Array(xs) => Array(xs.map(json_to_value))
    Object(m) => {
      let o = @collections.StrMap::new()
      for k, v in m {
        o.set(k, json_to_value(v))
      }
      Object(o)
    }
  }
}

///|
/// Compact JSON text identical to serde_json's serializer: object entries in
/// insertion order, serde_json escaping and number formatting.
pub fn stringify(j : Json) -> String {
  let buf = StringBuilder()
  write_json(buf, j)
  buf.to_string()
}

///|
fn write_json(buf : StringBuilder, j : Json) -> Unit {
  match j {
    Null => buf.write_string("null")
    True => buf.write_string("true")
    False => buf.write_string("false")
    Number(d, repr~) =>
      if d.is_nan() || d.is_inf() {
        buf.write_string("null")
      } else {
        buf.write_string(classify_number(d, repr).to_string())
      }
    String(s) => @serde_json.write_escaped_str(buf, s)
    Array(xs) => {
      buf.write_char('[')
      for i, x in xs {
        if i > 0 {
          buf.write_char(',')
        }
        write_json(buf, x)
      }
      buf.write_char(']')
    }
    Object(m) => {
      buf.write_char('{')
      let mut first = true
      for k, v in m {
        if !first {
          buf.write_char(',')
        }
        first = false
        @serde_json.write_escaped_str(buf, k)
        buf.write_char(':')
        write_json(buf, v)
      }
      buf.write_char('}')
    }
  }
}

///|
/// Re-sort object keys recursively (serde_json `Value` order), used when
/// encoding `serde_json::Value`/`Map` payloads.
pub fn sort_keys(j : Json) -> Json {
  value_to_json(json_to_value(j))
}
