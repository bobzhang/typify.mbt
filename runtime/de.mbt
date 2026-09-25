// A port of the serde deserialization semantics that typify-generated types
// observe with `serde_json::from_str`. Input is the ordered, leniently parsed
// `Content` document; a `De` says which serde deserializer is reading it:
//
// - `Direct`: `serde_json::Deserializer` over the text.
// - `Owned`: serde's `ContentDeserializer` (internal tags, flattened struct
//   fields, adjacent content given before the tag).
// - `Borrowed`: serde's `ContentRefDeserializer` (untagged trials, flattened
//   maps).
// - `MapKey`: serde_json's `MapKey` for object keys read directly.
// - `Flat`: `FlatMapDeserializer` over a struct's leftover entries.
// - `Missing`: `MissingFieldDeserializer` for an absent field.

///|
pub(all) enum Mode {
  Direct
  Owned
  Borrowed
} derive(Eq, Debug)

///|
/// Leftover entries of a struct with flattened fields.
pub struct FlatBuf {
  priv entries : Array[FlatEntry]
}

///|
priv struct FlatEntry {
  key : String
  value : @serde_json.Content
  mut taken : Bool
}

///|
pub(all) enum De {
  Value(@serde_json.Content, Mode)
  MapKey(String, Bool)
  Flat(FlatBuf)
  Missing(String)
}

///|
/// A deserialization error with serde's message.
pub(all) suberror DeError {
  DeError(String)
} derive(Debug, Eq)

///|
pub impl Show for DeError with fn output(self, logger) {
  let DeError(msg) = self
  logger.write_string(msg)
}

///|
/// Start deserializing JSON text (`serde_json::from_str`).
pub fn De::from_str(text : StringView) -> De raise DeError {
  let c = @serde_json.parse_content(text, lenient=true) catch {
    @serde_json.ParseError(message~, ..) => raise DeError(message)
  }
  Value(c, Direct)
}

///|
fn parse_error_message(e : @serde_json.ParseError) -> String {
  let ParseError(message~, ..) = e
  message
}

///|
fn content_unexpected(c : @serde_json.Content) -> String {
  match c {
    Null => "null"
    Bool(b) => "boolean `\{b}`"
    Number(Float(_) as n) => "floating point `\{n}`"
    Number(n) => "integer `\{n}`"
    Float32(f) => "floating point `\{@serde_json.format_f64(f.to_double())}`"
    String(s) => {
      let buf = StringBuilder()
      @serde_json.write_escaped_str(buf, s)
      "string \{buf}"
    }
    Array(_) => "sequence"
    Object(_) => "map"
    Invalid(_) => "invalid value"
  }
}

///|
pub fn invalid_type_error(
  c : @serde_json.Content,
  expected : String,
) -> DeError {
  DeError("invalid type: \{content_unexpected(c)}, expected \{expected}")
}

///|
fn flatten_error() -> DeError {
  DeError("can only flatten structs and maps")
}

///|
fn missing_error(name : String) -> DeError {
  DeError("missing field `\{name}`")
}

///|
/// Raise the deferred error of an invalid node.
fn check_valid(c : @serde_json.Content) -> Unit raise DeError {
  if c is Invalid(e) {
    raise DeError(parse_error_message(e))
  }
}

///|
/// A fully validated copy of a subtree (visiting it as `Content`, like
/// serde's `ContentVisitor` does).
pub fn validated(c : @serde_json.Content) -> @serde_json.Content raise DeError {
  match c {
    Invalid(e) => raise DeError(parse_error_message(e))
    Array(xs) => {
      let out = []
      for x in xs {
        out.push(validated(x))
      }
      Array(out)
    }
    Object(entries) => {
      let out = []
      for e in entries {
        if e.key_error is Some(err) {
          raise DeError(parse_error_message(err))
        }
        out.push({ ..e, value: validated(e.value), })
      }
      Object(out)
    }
    _ => c
  }
}

// ---------------------------------------------------------------------------
// Primitives

///|
pub fn de_bool(d : De) -> Bool raise DeError {
  match d {
    Value(Bool(b), _) => b
    Value(c, _) => {
      check_valid(c)
      raise invalid_type_error(c, "a boolean")
    }
    MapKey("true", false) => true
    MapKey("false", false) => false
    MapKey(k, _) => raise invalid_type_error(String(k), "a boolean")
    Flat(_) => raise flatten_error()
    Missing(n) => raise missing_error(n)
  }
}

///|
pub fn de_string(d : De) -> String raise DeError {
  de_string_expecting(d, "a string")
}

///|
/// `std::path::PathBuf`.
pub fn de_path(d : De) -> String raise DeError {
  de_string_expecting(d, "path string")
}

///|
/// A string (`deserialize_str`); `expecting` is the visitor's description
/// used in invalid-type errors.
pub fn de_string_expecting(d : De, expecting : String) -> String raise DeError {
  match d {
    Value(String(s), _) => s
    Value(c, _) => {
      check_valid(c)
      raise invalid_type_error(c, expecting)
    }
    MapKey(k, _) => k
    Flat(_) => raise flatten_error()
    Missing(n) => raise missing_error(n)
  }
}

///|
/// A serde_json map key parsed as a number (`MapKey::deserialize_number`):
/// the whole raw key text must be a JSON number.
fn key_number(
  k : String,
  escaped : Bool,
  expected : String,
) -> @serde_json.Number raise DeError {
  if escaped {
    raise DeError("invalid type: string \"\{k}\", expected \{expected}")
  }
  let first = k.get_char(0)
  if !(first is Some('-' | '0'..='9')) {
    raise DeError("invalid type: string \"\{k}\", expected \{expected}")
  }
  try @serde_json.parse(k) catch {
    @serde_json.ParseError(message~, ..) => raise DeError(message)
  } noraise {
    Number(n) => n
    _ => raise DeError("invalid type: string \"\{k}\", expected \{expected}")
  }
}

///|
fn de_number(
  d : De,
  expected : String,
) -> (@serde_json.Number, @serde_json.Content) raise DeError {
  match d {
    Value(Number(n) as c, _) => (n, c)
    Value(c, _) => {
      check_valid(c)
      raise invalid_type_error(c, expected)
    }
    MapKey(k, escaped) => {
      let n = key_number(k, escaped, expected)
      (n, Number(n))
    }
    Flat(_) => raise flatten_error()
    Missing(n) => raise missing_error(n)
  }
}

///|
/// An integer within `[min, max]` (serde's primitive integer visitors).
fn de_int_in(
  d : De,
  expected : String,
  min : Int64,
  max : UInt64,
) -> Int64 raise DeError {
  let (n, c) = de_number(d, expected)
  match n {
    PosInt(u) =>
      if u <= max {
        u.reinterpret_as_int64()
      } else {
        raise DeError("invalid value: integer `\{u}`, expected \{expected}")
      }
    NegInt(i) =>
      if i >= min {
        i
      } else {
        raise DeError("invalid value: integer `\{i}`, expected \{expected}")
      }
    Float(_) => raise invalid_type_error(c, expected)
  }
}

///|
pub fn de_i8(d : De) -> Int raise DeError {
  de_int_in(d, "i8", -128L, 127UL).to_int()
}

///|
pub fn de_u8(d : De) -> Byte raise DeError {
  de_u8_expecting(d, "u8")
}

///|
/// `de_u8` with the visitor description `expecting` (e.g. `NonZero`).
pub fn de_u8_expecting(d : De, expecting : String) -> Byte raise DeError {
  de_int_in(d, expecting, 0L, 255UL).to_byte()
}

///|
pub fn de_i16(d : De) -> Int16 raise DeError {
  Int16::from_int64(de_int_in(d, "i16", -32768L, 32767UL))
}

///|
pub fn de_u16(d : De) -> UInt16 raise DeError {
  de_u16_expecting(d, "u16")
}

///|
/// `de_u16` with the visitor description `expecting` (e.g. `NonZero`).
pub fn de_u16_expecting(d : De, expecting : String) -> UInt16 raise DeError {
  de_int_in(d, expecting, 0L, 65535UL).to_int().to_uint16()
}

///|
pub fn de_i32(d : De) -> Int raise DeError {
  de_int_in(d, "i32", -2147483648L, 2147483647UL).to_int()
}

///|
pub fn de_u32(d : De) -> UInt raise DeError {
  de_u32_expecting(d, "u32")
}

///|
/// `de_u32` with the visitor description `expecting` (e.g. `NonZero`).
pub fn de_u32_expecting(d : De, expecting : String) -> UInt raise DeError {
  de_int_in(d, expecting, 0L, 4294967295UL).reinterpret_as_uint64().to_uint()
}

///|
pub fn de_i64(d : De) -> Int64 raise DeError {
  de_int_in(d, "i64", -0x7FFF_FFFF_FFFF_FFFFL - 1L, 0x7FFF_FFFF_FFFF_FFFFUL)
}

///|
pub fn de_u64(d : De) -> UInt64 raise DeError {
  de_u64_expecting(d, "u64")
}

///|
/// `de_u64` with the visitor description `expecting` (e.g. `NonZero`).
pub fn de_u64_expecting(d : De, expecting : String) -> UInt64 raise DeError {
  let (n, c) = de_number(d, expecting)
  match n {
    PosInt(u) => u
    NegInt(i) =>
      raise DeError("invalid value: integer `\{i}`, expected \{expecting}")
    Float(_) => raise invalid_type_error(c, expecting)
  }
}

///|
/// `NonZero*`: the unsigned value must not be zero.
pub fn nonzero(is_zero : Bool, expected : String) -> Unit raise DeError {
  if is_zero {
    raise DeError("invalid value: integer `0`, expected \{expected}")
  }
}

///|
pub fn de_f64(d : De) -> Double raise DeError {
  de_number(d, "f64").0.as_f64()
}

///|
pub fn de_f32(d : De) -> Float raise DeError {
  Float::from_double(de_number(d, "f32").0.as_f64())
}

///|
pub fn de_unit(d : De) -> Unit raise DeError {
  match d {
    Value(Null, _) => ()
    Value(Object([]), Owned) => ()
    Value(c, _) => {
      check_valid(c)
      raise invalid_type_error(c, "unit")
    }
    MapKey(k, _) => raise invalid_type_error(String(k), "unit")
    Flat(_) => ()
    Missing(n) => raise missing_error(n)
  }
}

///|
pub fn[T] de_option(d : De, f : (De) -> T raise DeError) -> T? raise DeError {
  match d {
    Value(Null, _) => None
    Value(_, _) | MapKey(_, _) => Some(f(d))
    // A flattened option swallows the inner error (claims are not undone).
    Flat(_) =>
      try f(d) catch {
        _ => None
      } noraise {
        v => Some(v)
      }
    Missing(_) => None
  }
}

///|
/// Elements of an array; also used for tuples/fixed arrays.
fn seq_elements(
  d : De,
  expected : String,
) -> (Array[@serde_json.Content], Mode) raise DeError {
  match d {
    Value(Array(xs), mode) => (xs, mode)
    Value(c, _) => {
      check_valid(c)
      raise invalid_type_error(c, expected)
    }
    MapKey(k, _) => raise invalid_type_error(String(k), expected)
    Flat(_) => raise flatten_error()
    Missing(n) => raise missing_error(n)
  }
}

///|
pub fn[T] de_vec(d : De, f : (De) -> T raise DeError) -> Array[T] raise DeError {
  let (xs, mode) = seq_elements(d, "a sequence")
  let out = []
  for x in xs {
    out.push(f(Value(x, mode)))
  }
  out
}

///|
/// The element deserializers of a fixed-length sequence (tuple or array):
/// elements are decoded by the caller in order; `finish` checks surplus.
pub struct SeqReader {
  priv items : Array[@serde_json.Content]
  priv mode : Mode
  priv mut pos : Int
  priv expected : String
}

///|
/// serde_derive's sequence visitor description: `<expecting> with N elements`.
fn with_elements(expecting : String, n : Int) -> String {
  if n == 1 {
    "\{expecting} with 1 element"
  } else {
    "\{expecting} with \{n} elements"
  }
}

///|
/// The payload of a tuple variant (`expecting` is `tuple variant E::V`);
/// `external`: an externally tagged variant, whose buffered form reports
/// serde's generic `tuple variant`.
pub fn de_tuple_variant(
  d : De,
  expecting : String,
  n : Int,
  external : Bool,
) -> SeqReader raise DeError {
  match d {
    Value(Array(xs), mode) =>
      { items: xs, mode, pos: 0, expected: with_elements(expecting, n) }
    Value(c, mode) => {
      check_valid(c)
      raise invalid_type_error(
        c,
        if external && !(mode is Direct) {
          "tuple variant"
        } else {
          expecting
        },
      )
    }
    MapKey(k, _) => raise invalid_type_error(String(k), expecting)
    Flat(_) => raise flatten_error()
    Missing(n) => raise missing_error(n)
  }
}

///|
pub fn de_tuple(d : De, n : Int) -> SeqReader raise DeError {
  let expected = "a tuple of size \{n}"
  let (xs, mode) = seq_elements(d, expected)
  { items: xs, mode, pos: 0, expected, }
}

///|
pub fn de_fixed(d : De, n : Int) -> SeqReader raise DeError {
  let expected = "an array of length \{n}"
  let (xs, mode) = seq_elements(d, expected)
  { items: xs, mode, pos: 0, expected, }
}

///|
/// The next element, or an `invalid length` error.
pub fn SeqReader::next(self : SeqReader) -> De raise DeError {
  guard self.items.get(self.pos) is Some(x) else {
    raise DeError("invalid length \{self.pos}, expected \{self.expected}")
  }
  self.pos += 1
  Value(x, self.mode)
}

///|
/// Surplus elements: serde_json reports trailing characters, buffered
/// deserializers an invalid length.
pub fn SeqReader::finish(self : SeqReader) -> Unit raise DeError {
  if self.pos < self.items.length() {
    match self.mode {
      Direct => raise DeError("trailing characters")
      _ =>
        raise DeError(
          "invalid length \{self.items.length()}, expected \{self.pos} element\{if self.pos == 1 { "" } else { "s" }} in sequence",
        )
    }
  }
}

///|
/// Key/value deserializers of an object, in order.
pub fn de_map_entries(d : De) -> Array[(De, De)] raise DeError {
  match d {
    Value(Object(entries), mode) => {
      let out = []
      for e in entries {
        if e.key_error is Some(err) {
          raise DeError(parse_error_message(err))
        }
        let key : De = match mode {
          Direct => MapKey(e.key, e.key_escaped)
          _ => Value(String(e.key), mode)
        }
        out.push((key, Value(e.value, mode)))
      }
      out
    }
    Value(c, _) => {
      check_valid(c)
      raise invalid_type_error(c, "a map")
    }
    MapKey(k, _) => raise invalid_type_error(String(k), "a map")
    // FlatMapAccess: all remaining entries, not claimed, borrowed.
    Flat(buf) =>
      buf.entries
      .filter(e => !e.taken)
      .map(e => (Value(String(e.key), Borrowed), Value(e.value, Borrowed)))
    Missing(n) => raise missing_error(n)
  }
}

///|
pub fn[K : Hash + Eq, V] de_map(
  d : De,
  k : (De) -> K raise DeError,
  v : (De) -> V raise DeError,
) -> Map[K, V] raise DeError {
  let out : Map[K, V] = Map([])
  for e in de_map_entries(d) {
    let key = k(e.0)
    out[key] = v(e.1)
  }
  out
}

///|
/// `serde_json::Value` (`deserialize_any` into a Value), as builtin `Json`
/// with number classes in `repr` and keys in serde_json order.
pub fn de_json(d : De) -> Json raise DeError {
  match d {
    Value(c, _) => {
      let c = validated(c)
      let v = c.to_value() catch {
        @serde_json.ParseError(message~, ..) => raise DeError(message)
      }
      value_to_json(v)
    }
    MapKey(k, _) => Json::string(k)
    Flat(_) => {
      let m : Map[String, Json] = Map([])
      let o = @collections.StrMap::new()
      for e in de_map_entries(d) {
        guard e.0 is Value(String(key), _) else { continue }
        o.set(key, e.1)
      }
      for key, v in o {
        m[key] = de_json(v)
      }
      Json::object(m)
    }
    Missing(n) => raise missing_error(n)
  }
}

// ---------------------------------------------------------------------------
// Structs

///|
/// The input of a derived struct visitor: map entries or positional
/// elements.
pub(all) enum StructInput {
  /// Keys (already decoded strings) and value deserializers, in order.
  Entries(Array[(String, De)])
  Elements(SeqReader)
}

///|
/// `deserialize_struct` (or `deserialize_map` for structs with flattened
/// fields, which also reject positional arrays).
///
/// `external_variant`: the payload of an externally tagged struct variant,
/// whose buffered form reports serde's generic `struct variant`.
pub fn de_struct(
  d : De,
  expecting : String,
  fields : Array[String],
  has_flatten : Bool,
  external_variant? : Bool = false,
) -> StructInput raise DeError {
  match d {
    Value(Object(entries), mode) => {
      let out = []
      for e in entries {
        if e.key_error is Some(err) {
          raise DeError(parse_error_message(err))
        }
        out.push((e.key, De::Value(e.value, mode)))
      }
      Entries(out)
    }
    Value(Array(xs), mode) if !has_flatten =>
      Elements({
        items: xs,
        mode,
        pos: 0,
        expected: with_elements(expecting, fields.length()),
      })
    // A struct with flatten fields is read as a map: its visitor has no
    // sequence form.
    Value(Array(_) as c, _) => raise invalid_type_error(c, expecting)
    Value(c, mode) => {
      check_valid(c)
      raise invalid_type_error(
        c,
        if external_variant && !(mode is Direct) {
          "struct variant"
        } else {
          expecting
        },
      )
    }
    MapKey(k, _) => raise invalid_type_error(String(k), expecting)
    Flat(buf) =>
      if has_flatten {
        // deserialize_map: all remaining entries, not claimed.
        Entries(
          buf.entries
          .filter(e => !e.taken)
          .map(e => (e.key, De::Value(e.value, Borrowed))),
        )
      } else {
        // FlatStructAccess: claim recognised fields before decoding.
        let out = []
        for e in buf.entries {
          if !e.taken && fields.contains(e.key) {
            e.taken = true
            out.push((e.key, De::Value(e.value, Owned)))
          }
        }
        Entries(out)
      }
    Missing(n) => raise missing_error(n)
  }
}

///|
/// serde's `unknown field` error, listing the expected fields.
pub fn unknown_field_error(name : String, expected : Array[String]) -> DeError {
  DeError("unknown field `\{name}`, \{one_of_fields(expected)}")
}

///|
fn one_of_fields(names : Array[String]) -> String {
  match names {
    [] => "there are no fields"
    [a] => "expected `\{a}`"
    [a, b] => "expected `\{a}` or `\{b}`"
    _ => "expected one of \{names.map(n => "`\{n}`").join(", ")}"
  }
}

///|
pub fn duplicate_field_error(name : String) -> DeError {
  DeError("duplicate field `\{name}`")
}

///|
pub fn missing_field_error(name : String) -> DeError {
  missing_error(name)
}

///|
/// A buffer of unrecognised entries for flattened fields.
pub fn FlatBuf::new() -> FlatBuf {
  { entries: [], }
}

///|
/// Buffer an unrecognised entry (serde collects it as `Content`, which
/// validates the value).
pub fn FlatBuf::push(
  self : FlatBuf,
  key : String,
  value : De,
) -> Unit raise DeError {
  guard value is Value(c, _) else { return }
  self.entries.push({ key, value: validated(c), taken: false, })
}

///|
/// Under `deny_unknown_fields`: the first unclaimed leftover is an error.
pub fn FlatBuf::deny_leftovers(self : FlatBuf) -> Unit raise DeError {
  for e in self.entries {
    if !e.taken {
      raise DeError("unknown field `\{e.key}`")
    }
  }
}

///|
/// Positional struct fields: the next element, or `None` when exhausted.
pub fn SeqReader::next_opt(self : SeqReader) -> De? {
  match self.items.get(self.pos) {
    Some(x) => {
      self.pos += 1
      Some(Value(x, self.mode))
    }
    None => None
  }
}

///|
/// Positional struct: `invalid length` for the first missing element.
pub fn SeqReader::invalid_length(self : SeqReader) -> DeError {
  DeError("invalid length \{self.pos}, expected \{self.expected}")
}

// ---------------------------------------------------------------------------
// Enums

///|
/// How a variant's payload is provided.
pub(all) enum VariantInput {
  /// The string form (`"V"`): only unit variants are valid.
  UnitOnly
  /// The payload of the map form.
  Payload(De)
  /// A buffered map form with no payload (`None`).
  NoPayload
}

///|
fn variant_index(name : String, variants : Array[String]) -> Int raise DeError {
  match variants.search(name) {
    Some(i) => i
    None =>
      raise DeError("unknown variant `\{name}`, \{one_of_variants(variants)}")
  }
}

///|
fn one_of_variants(names : Array[String]) -> String {
  match names {
    [] => "there are no variants"
    [a] => "expected `\{a}`"
    [a, b] => "expected `\{a}` or `\{b}`"
    _ => "expected one of \{names.map(n => "`\{n}`").join(", ")}"
  }
}

///|
/// `deserialize_enum` for externally tagged enums: the variant index and its
/// payload.
pub fn de_enum(
  d : De,
  name : String,
  variants : Array[String],
) -> (Int, VariantInput) raise DeError {
  match d {
    Value(String(s), _) => (variant_index(s, variants), UnitOnly)
    Value(Object(entries), Direct) => {
      // `{}`: the variant identifier peeks `}`.
      guard entries is [first, .. rest] else { raise DeError("expected value") }
      if first.key_error is Some(err) {
        raise DeError(parse_error_message(err))
      }
      let idx = variant_index(first.key, variants)
      // serde_json reads the payload before rejecting extra entries; the
      // caller decodes the payload, then calls `end_enum_map`.
      (
        idx,
        Payload(
          if rest.is_empty() {
            Value(first.value, Direct)
          } else {
            Value(first.value, Direct)
          },
        ),
      )
    }
    Value(Object(entries), mode) =>
      match entries {
        [e] => {
          if e.key_error is Some(err) {
            raise DeError(parse_error_message(err))
          }
          (variant_index(e.key, variants), Payload(Value(e.value, mode)))
        }
        _ => raise DeError("invalid value: map, expected map with a single key")
      }
    // serde_json's `deserialize_enum` peeks: anything but a string or an
    // object is `expected value`, without parsing the value. (A too-deep
    // array would also be `expected value`; only objects are recursion errors
    // there, which a deferred `Invalid` node cannot tell apart.)
    Value(Invalid(ParseError(message="number out of range", ..)), Direct) =>
      raise DeError("expected value")
    Value(Invalid(e), Direct) => raise DeError(parse_error_message(e))
    Value(_, Direct) => raise DeError("expected value")
    Value(c, _) => {
      check_valid(c)
      raise invalid_type_error(c, "string or map")
    }
    MapKey(k, _) => (variant_index(k, variants), UnitOnly)
    Flat(buf) => {
      for e in buf.entries {
        if !e.taken && variants.contains(e.key) {
          e.taken = true
          return (
            variant_index(e.key, variants),
            Payload(Value(e.value, Owned)),
          )
        }
      }
      raise DeError("no variant of enum \{name} found in flattened data")
    }
    Missing(n) => raise missing_error(n)
  }
}

///|
/// serde_json rejects a map form with more than one entry after the payload
/// has been read.
pub fn end_enum_map(d : De) -> Unit raise DeError {
  if d is Value(Object(entries), Direct) && entries.length() > 1 {
    // serde_json expects the closing brace after the payload.
    raise DeError("expected value")
  }
}

///|
pub fn variant_unit(v : VariantInput) -> Unit raise DeError {
  match v {
    UnitOnly | NoPayload => ()
    Payload(d) => de_unit(d)
  }
}

///|
/// The payload deserializer of a newtype/tuple/struct variant.
pub fn variant_payload(v : VariantInput, kind : String) -> De raise DeError {
  match v {
    Payload(d) => d
    UnitOnly | NoPayload =>
      raise DeError("invalid type: unit variant, expected \{kind}")
  }
}

///|
/// Capture a value as `Content` for untagged enums (then tried with the
/// borrowed deserializer).
pub fn de_untagged(d : De) -> De raise DeError {
  match d {
    Value(c, _) => Value(validated(c), Borrowed)
    MapKey(k, _) => Value(String(k), Borrowed)
    Flat(buf) =>
      Value(
        Object(
          buf.entries
          .filter(e => !e.taken)
          .map(e => {
            key: e.key,
            key_escaped: false,
            key_error: None,
            value: e.value,
          }),
        ),
        Borrowed,
      )
    Missing(n) => raise missing_error(n)
  }
}

///|
pub fn untagged_error(name : String) -> DeError {
  DeError("data did not match any variant of untagged enum \{name}")
}

///|
/// A variant identifier from buffered content: a name or a variant index.
fn tag_identifier(
  c : @serde_json.Content,
  variants : Array[String],
  buffered : Bool,
) -> Int raise DeError {
  match c {
    String(s) => variant_index(s, variants)
    Number(PosInt(i)) if buffered =>
      if i < variants.length().to_uint64() {
        i.to_int()
      } else {
        raise DeError(
          "invalid value: integer `\{i}`, expected variant index 0 <= i < \{variants.length()}",
        )
      }
    _ => {
      check_valid(c)
      raise invalid_type_error(c, "variant identifier")
    }
  }
}

///|
/// Internally tagged enums (`TaggedContentVisitor`): the variant and the
/// remaining content, read with the owned deserializer.
pub fn de_internal(
  d : De,
  name : String,
  tag : String,
  variants : Array[String],
) -> (Int, De) raise DeError {
  let (c, mode) = match d {
    Value(c, mode) => (c, mode)
    Flat(_) => {
      guard de_untagged(d) is Value(c, _) else { abort("unreachable") }
      (c, Borrowed)
    }
    MapKey(k, _) =>
      raise invalid_type_error(String(k), "internally tagged enum \{name}")
    Missing(n) => raise missing_error(n)
  }
  let buffered = mode != Direct
  match c {
    Object(entries) => {
      let mut found : Int? = None
      let rest = []
      for e in entries {
        if e.key_error is Some(err) {
          raise DeError(parse_error_message(err))
        }
        if e.key == tag {
          if found is Some(_) {
            raise duplicate_field_error(tag)
          }
          found = Some(tag_identifier(e.value, variants, buffered))
        } else {
          rest.push({ ..e, value: validated(e.value), })
        }
      }
      match found {
        Some(i) => (i, Value(Object(rest), Owned))
        None => raise missing_error(tag)
      }
    }
    Array(xs) =>
      match xs {
        [t, .. rest] => {
          let i = tag_identifier(t, variants, buffered)
          let remaining = []
          for x in rest {
            remaining.push(validated(x))
          }
          (i, Value(Array(remaining), Owned))
        }
        [] => raise DeError("invalid length 0, expected tag")
      }
    _ => {
      check_valid(c)
      raise invalid_type_error(c, "internally tagged enum \{name}")
    }
  }
}

///|
/// A unit variant of an internally tagged enum: a map (contents ignored),
/// unit, or an empty sequence.
pub fn internal_unit(
  d : De,
  name : String,
  variant : String,
) -> Unit raise DeError {
  match d {
    Value(Object(_), _) | Value(Null, _) => ()
    Value(Array([]), _) => ()
    Value(Array(xs), _) =>
      raise DeError(
        "invalid length \{xs.length()}, expected 0 elements in sequence",
      )
    Value(c, _) =>
      raise invalid_type_error(c, "unit variant \{name}::\{variant}")
    _ => ()
  }
}
