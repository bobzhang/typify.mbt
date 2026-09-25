// Encoders producing `Json` that `stringify` renders exactly like serde_json.

///|
pub fn encode_f64(d : Double) -> Json {
  if d.is_nan() || d.is_inf() {
    Json::null()
  } else {
    Json::number(d, repr=@serde_json.format_f64(d))
  }
}

///|
pub fn encode_f32(f : Float) -> Json {
  if f.is_nan() || f.is_inf() {
    Json::null()
  } else {
    Json::number(f.to_double(), repr=format_f32(f))
  }
}

///|
/// serde_json's formatting of an `f32` (ryu's shortest `f32` digits).
fn format_f32(f : Float) -> String {
  // Shortest digits of the f32 value, laid out like ryu.
  let s = f.to_string()
  let d = @serde_json.parse(s) catch {
    _ => return @serde_json.format_f64(f.to_double())
  }
  match d {
    Number(n) => @serde_json.format_f64(n.as_f64())
    _ => @serde_json.format_f64(f.to_double())
  }
}

///|
pub fn encode_i64(n : Int64) -> Json {
  let d = n.to_double()
  if exact_integer_double(d) {
    Json::number(d)
  } else {
    Json::number(d, repr=n.to_string())
  }
}

///|
pub fn encode_u64(n : UInt64) -> Json {
  let d = n.to_double()
  if exact_integer_double(d) {
    Json::number(d)
  } else {
    Json::number(d, repr=n.to_string())
  }
}

///|
pub fn encode_int(n : Int) -> Json {
  Json::number(n.to_double())
}

///|
pub fn encode_uint(n : UInt) -> Json {
  Json::number(n.to_double())
}

///|
pub fn[T] encode_array(xs : ArrayView[T], f : (T) -> Json) -> Json {
  Json::array(xs.iter().map(f).collect())
}

///|
pub fn[K, V] encode_map(
  m : Map[K, V],
  key : (K) -> String,
  value : (V) -> Json,
) -> Json {
  let out : Map[String, Json] = Map([])
  for k, v in m {
    out[key(k)] = value(v)
  }
  Json::object(out)
}
