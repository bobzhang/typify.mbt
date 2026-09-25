///|
test "number classification follows serde_json" {
  let v = @serde_json.parse(
    "[1, 1.0, -1, -0, 18446744073709551615, 18446744073709551616, 1e2]",
  )
  inspect(
    v,
    content="[1,1.0,-1,-0.0,18446744073709551615,1.8446744073709552e+19,100.0]",
  )
  guard v is Array(xs) else { fail("expected array") }
  debug_inspect(
    xs.map(x => (x.is_u64(), x.is_i64(), x.is_f64())),
    content=(
      #|[
      #|  (true, true, false),
      #|  (false, false, true),
      #|  (false, true, false),
      #|  (false, false, true),
      #|  (true, false, false),
      #|  (false, false, true),
      #|  (false, false, true),
      #|]
    ),
  )
  // 1 and 1.0 are different values.
  assert_true(xs[0] != xs[1])
}

///|
test "objects iterate in code point order; duplicates keep the last" {
  let v = @serde_json.parse(
    (
      #|{"b": 1, "aa": 2, "\u00e9": 3, "a": 4, "b": 5}
    ),
  )
  inspect(v, content="{\"a\":4,\"aa\":2,\"b\":5,\"é\":3}")
}

///|
test "string escapes" {
  let v = @serde_json.parse(
    (
      #|"a\"b\\c\/d\b\f\n\r\t\u0001\u00e9\ud83d\ude00"
    ),
  )
  inspect(v, content="\"a\\\"b\\\\c/d\\b\\f\\n\\r\\t\\u0001é😀\"")
}

///|
test "pretty printing" {
  let v = @serde_json.parse("{\"a\":[1,{\"b\":null}],\"c\":{},\"d\":[]}")
  inspect(
    v.to_string_pretty(),
    content=(
      #|{
      #|  "a": [
      #|    1,
      #|    {
      #|      "b": null
      #|    }
      #|  ],
      #|  "c": {},
      #|  "d": []
      #|}
    ),
  )
}

///|
test "errors" {
  let cases = [
    "", "[1,]", "{\"a\" 1}", "01", "1.", "\"\\ud800\"", "[1] x", "1e999",
  ]
  let out = cases.map(c => {
    try @serde_json.parse(c) catch {
      e => e.to_string()
    } noraise {
      v => "ok: \{v}"
    }
  })
  debug_inspect(
    out,
    content=(
      #|[
      #|  "EOF while parsing a value at line 1 column 0",
      #|  "trailing comma at line 1 column 4",
      #|  "expected `:` at line 1 column 6",
      #|  "invalid number at line 1 column 2",
      #|  "EOF while parsing a value at line 1 column 2",
      #|  "unexpected end of hex escape at line 1 column 8",
      #|  "trailing characters at line 1 column 5",
      #|  "number out of range at line 1 column 5",
      #|]
    ),
  )
}

///|
test "conversion to and from builtin Json" {
  let v = @serde_json.parse(
    "{\"big\":18446744073709551615,\"f\":1.5,\"n\":[null,true]}",
  )
  let j = v.to_json()
  let back = @serde_json.Value::from_json(j)
  assert_eq(back, v)
}

///|
/// A generator of JSON values with bounded depth.
fn gen_value(depth : Int) -> @quickcheck.Generator[@serde_json.Value] {
  let leaves : Array[@quickcheck.Generator[@serde_json.Value]] = [
    @quickcheck.pure(@serde_json.Value::Null),
    @quickcheck.spawn().map((b : Bool) => @serde_json.Value::Bool(b)),
    @quickcheck.spawn().map((n : UInt64) => @serde_json.Value::from_u64(n)),
    @quickcheck.spawn().map((n : Int64) => @serde_json.Value::from_i64(n)),
    @quickcheck.spawn().map((s : String) => @serde_json.Value::String(s)),
  ]
  if depth <= 0 {
    return @quickcheck.one_of(leaves)
  }
  let inner = gen_value(depth - 1)
  let arrays = @quickcheck.int_range(0, 4).flat_map(n => {
    inner.array_with_size(n).map(xs => @serde_json.Value::Array(xs))
  })
  let objects = @quickcheck.int_range(0, 4).flat_map(n => {
    @quickcheck.spawn()
    .array_with_size(n)
    .zip(inner.array_with_size(n))
    .map(p => {
      let (keys, vals) : (Array[String], Array[@serde_json.Value]) = p
      @serde_json.Value::object(keys.mapi((i, k) => (k, vals[i])))
    })
  })
  @quickcheck.one_of(leaves + [arrays, objects])
}

///|
/// Floats are excluded: serde_json's default float parser is not correctly
/// rounded (e.g. it reads `0.9604567029227533` as `0.9604567029227532`), and
/// this port reproduces that; exact float behaviour is covered by the
/// differential oracle instead.
test "print then parse is the identity (non-float values)" {
  let values = gen_value(3).samples(count=400, seed=0x7479706966UL)
  for v in values {
    assert_eq(@serde_json.parse(v.to_string()), v)
    assert_eq(@serde_json.parse(v.to_string_pretty()), v)
  }
}

///|
test "format_f64 output is shortest round-trip text" {
  @quickcheck.check((d : Double) => {
    d.is_nan() ||
    d.is_inf() ||
    (try @string.parse_double(@serde_json.format_f64(d)) catch {
      _ => false
    } noraise {
      back => back == d
    })
  })
}
