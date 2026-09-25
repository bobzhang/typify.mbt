// Primitive decoders with serde / serde_json acceptance rules and messages.

///|
/// serde_json's rendering of an unexpected value in error messages.
pub fn unexpected(j : Json) -> String {
  match j {
    Null => "null"
    True => "boolean `true`"
    False => "boolean `false`"
    Number(d, repr~) =>
      match classify_number(d, repr) {
        Float(_) as n => "floating point `\{n}`"
        n => "integer `\{n}`"
      }
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
pub fn error(path : @json.JsonPath, message : String) -> @json.JsonDecodeError {
  @json.JsonDecodeError((path, message))
}

///|
pub fn invalid_type(
  j : Json,
  expected : String,
  path : @json.JsonPath,
) -> @json.JsonDecodeError {
  error(path, "invalid type: \{unexpected(j)}, expected \{expected}")
}

///|
pub fn invalid_value(
  what : String,
  expected : String,
  path : @json.JsonPath,
) -> @json.JsonDecodeError {
  error(path, "invalid value: \{what}, expected \{expected}")
}

///|
pub fn missing_field(
  name : String,
  path : @json.JsonPath,
) -> @json.JsonDecodeError {
  error(path, "missing field `\{name}`")
}

///|
/// serde's `unknown field` message listing the expected fields.
pub fn unknown_field(
  name : String,
  expected : ArrayView[String],
  path : @json.JsonPath,
) -> @json.JsonDecodeError {
  error(path, "unknown field `\{name}`, \{one_of(expected)}")
}

///|
/// serde's `unknown variant` message.
pub fn unknown_variant(
  name : String,
  expected : ArrayView[String],
  path : @json.JsonPath,
) -> @json.JsonDecodeError {
  error(path, "unknown variant `\{name}`, \{one_of(expected)}")
}

///|
/// serde's `OneOf` rendering.
fn one_of(names : ArrayView[String]) -> String {
  match names {
    [] => "there are no fields"
    [a] => "expected `\{a}`"
    [a, b] => "expected `\{a}` or `\{b}`"
    _ =>
      "expected one of \{names.iter().map(n => "`\{n}`").collect().join(", ")}"
  }
}

///|
pub fn decode_bool(
  j : Json,
  path : @json.JsonPath,
) -> Bool raise @json.JsonDecodeError {
  match j {
    True => true
    False => false
    _ => raise invalid_type(j, "a boolean", path)
  }
}

///|
pub fn decode_string(
  j : Json,
  path : @json.JsonPath,
) -> String raise @json.JsonDecodeError {
  match j {
    String(s) => s
    _ => raise invalid_type(j, "a string", path)
  }
}

///|
pub fn decode_unit(
  j : Json,
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  match j {
    Null => ()
    _ => raise invalid_type(j, "unit", path)
  }
}

///|
/// The serde_json number class of a JSON value, or an invalid-type error.
fn number_of(
  j : Json,
  expected : String,
  path : @json.JsonPath,
) -> @serde_json.Number raise @json.JsonDecodeError {
  match j {
    Number(d, repr~) => classify_number(d, repr)
    _ => raise invalid_type(j, expected, path)
  }
}

///|
/// Decode an integer within `[min, max]` (serde's primitive visitors).
fn decode_int_in(
  j : Json,
  expected : String,
  min : Int64,
  max : UInt64,
  path : @json.JsonPath,
) -> @serde_json.Number raise @json.JsonDecodeError {
  let n = number_of(j, expected, path)
  match n {
    PosInt(u) =>
      if u <= max {
        n
      } else {
        raise invalid_value("integer `\{u}`", expected, path)
      }
    NegInt(i) =>
      if i >= min {
        n
      } else {
        raise invalid_value("integer `\{i}`", expected, path)
      }
    Float(_) => raise invalid_type(j, expected, path)
  }
}

///|
fn number_to_int64(n : @serde_json.Number) -> Int64 {
  match n {
    PosInt(u) => u.reinterpret_as_int64()
    NegInt(i) => i
    Float(d) => d.to_int64()
  }
}

///|
pub fn decode_i8(
  j : Json,
  path : @json.JsonPath,
) -> Int raise @json.JsonDecodeError {
  number_to_int64(decode_int_in(j, "i8", -128L, 127UL, path)).to_int()
}

///|
pub fn decode_u8(
  j : Json,
  path : @json.JsonPath,
) -> Byte raise @json.JsonDecodeError {
  number_to_int64(decode_int_in(j, "u8", 0L, 255UL, path)).to_byte()
}

///|
pub fn decode_i16(
  j : Json,
  path : @json.JsonPath,
) -> Int16 raise @json.JsonDecodeError {
  number_to_int64(decode_int_in(j, "i16", -32768L, 32767UL, path)).to_int16()
}

///|
pub fn decode_u16(
  j : Json,
  path : @json.JsonPath,
) -> UInt16 raise @json.JsonDecodeError {
  number_to_int64(decode_int_in(j, "u16", 0L, 65535UL, path)).to_uint16()
}

///|
pub fn decode_i32(
  j : Json,
  path : @json.JsonPath,
) -> Int raise @json.JsonDecodeError {
  number_to_int64(decode_int_in(j, "i32", -2147483648L, 2147483647UL, path)).to_int()
}

///|
pub fn decode_u32(
  j : Json,
  path : @json.JsonPath,
) -> UInt raise @json.JsonDecodeError {
  number_to_int64(decode_int_in(j, "u32", 0L, 4294967295UL, path))
  .reinterpret_as_uint64()
  .to_uint()
}

///|
pub fn decode_i64(
  j : Json,
  path : @json.JsonPath,
) -> Int64 raise @json.JsonDecodeError {
  number_to_int64(
    decode_int_in(
      j,
      "i64",
      -0x7FFF_FFFF_FFFF_FFFFL - 1L,
      0x7FFF_FFFF_FFFF_FFFFUL,
      path,
    ),
  )
}

///|
pub fn decode_u64(
  j : Json,
  path : @json.JsonPath,
) -> UInt64 raise @json.JsonDecodeError {
  match decode_int_in(j, "u64", 0L, 0xFFFF_FFFF_FFFF_FFFFUL, path) {
    PosInt(u) => u
    _ => 0
  }
}

///|
/// `NonZero*` types: like the unsigned type, but zero is rejected.
pub fn check_nonzero(
  is_zero : Bool,
  expected : String,
  path : @json.JsonPath,
) -> Unit raise @json.JsonDecodeError {
  if is_zero {
    raise invalid_value("integer `0`", expected, path)
  }
}

///|
pub fn decode_f64(
  j : Json,
  path : @json.JsonPath,
) -> Double raise @json.JsonDecodeError {
  number_of(j, "f64", path).as_f64()
}

///|
pub fn decode_f32(
  j : Json,
  path : @json.JsonPath,
) -> Float raise @json.JsonDecodeError {
  number_of(j, "f32", path).as_f64().to_float()
}

///|
/// Decode `Option<T>`: `null` is `None`.
pub fn[T] decode_option(
  j : Json,
  path : @json.JsonPath,
  f : (Json, @json.JsonPath) -> T raise @json.JsonDecodeError,
) -> T? raise @json.JsonDecodeError {
  match j {
    Null => None
    _ => Some(f(j, path))
  }
}

///|
pub fn[T] decode_array(
  j : Json,
  path : @json.JsonPath,
  f : (Json, @json.JsonPath) -> T raise @json.JsonDecodeError,
) -> Array[T] raise @json.JsonDecodeError {
  guard j is Array(xs) else { raise invalid_type(j, "a sequence", path) }
  let out = []
  for i, x in xs {
    out.push(f(x, path.add_index(i)))
  }
  out
}

///|
/// A fixed-size array `[T; N]`.
pub fn[T] decode_fixed_array(
  j : Json,
  n : Int,
  path : @json.JsonPath,
  f : (Json, @json.JsonPath) -> T raise @json.JsonDecodeError,
) -> FixedArray[T] raise @json.JsonDecodeError {
  let expected = "an array of length \{n}"
  guard j is Array(xs) else { raise invalid_type(j, expected, path) }
  if xs.length() != n {
    raise error(path, "invalid length \{xs.length()}, expected \{expected}")
  }
  let out = []
  for i, x in xs {
    out.push(f(x, path.add_index(i)))
  }
  FixedArray::from_array(out)
}

///|
/// The elements of a JSON array of exactly `n` elements (tuples).
pub fn tuple_elements(
  j : Json,
  n : Int,
  path : @json.JsonPath,
) -> Array[Json] raise @json.JsonDecodeError {
  let expected = "a tuple of size \{n}"
  guard j is Array(xs) else { raise invalid_type(j, expected, path) }
  if xs.length() != n {
    raise error(path, "invalid length \{xs.length()}, expected \{expected}")
  }
  xs
}

///|
/// Decode a map; `key` decodes a key from its string form (serde_json
/// `MapKey`).
pub fn[K : Hash + Eq, V] decode_map(
  j : Json,
  path : @json.JsonPath,
  key : (String, @json.JsonPath) -> K raise @json.JsonDecodeError,
  value : (Json, @json.JsonPath) -> V raise @json.JsonDecodeError,
) -> Map[K, V] raise @json.JsonDecodeError {
  guard j is Object(m) else { raise invalid_type(j, "a map", path) }
  let out : Map[K, V] = Map([])
  for k, v in m {
    let p = path.add_key(k)
    out[key(k, p)] = value(v, p)
  }
  out
}

///|
/// serde_json map keys are strings; integer keys are parsed from them.
pub fn key_as_json_number(
  k : String,
  path : @json.JsonPath,
) -> Json raise @json.JsonDecodeError {
  try parse(k) catch {
    _ => raise error(path, "invalid type: string \"\{k}\", expected a number")
  } noraise {
    Number(_, ..) as n => n
    _ => raise error(path, "invalid type: string \"\{k}\", expected a number")
  }
}
