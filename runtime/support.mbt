// Helpers used by generated code.

///|
/// A failed conversion (upstream `self::error::ConversionError`).
pub(all) suberror ConversionError {
  ConversionError(String)
} derive(Debug, Eq)

///|
pub impl Show for ConversionError with output(self, logger) {
  let ConversionError(msg) = self
  logger.write_string(msg)
}

///|
pub fn de_nonzero_u8(d : De) -> Byte raise DeError {
  let v = de_u8(d)
  nonzero(v == 0, "a nonzero u8")
  v
}

///|
pub fn de_nonzero_u16(d : De) -> UInt16 raise DeError {
  let v = de_u16(d)
  nonzero(v == 0, "a nonzero u16")
  v
}

///|
pub fn de_nonzero_u32(d : De) -> UInt raise DeError {
  let v = de_u32(d)
  nonzero(v == 0, "a nonzero u32")
  v
}

///|
pub fn de_nonzero_u64(d : De) -> UInt64 raise DeError {
  let v = de_u64(d)
  nonzero(v == 0, "a nonzero u64")
  v
}

///|
/// Start deserializing a builtin `Json` value.
pub fn De::from_json(json : Json) -> De {
  Value(json_to_value(json).to_content(), Direct)
}

///|
/// Convert serialized content to builtin `Json` (duplicate keys: last wins).
pub fn content_to_json(c : Content) -> Json raise SerError {
  let v = c.to_value() catch {
    @serde_json.ParseError(message~, ..) => raise SerError(message)
  }
  value_to_json(v)
}

///|
/// Decode a default value from its JSON text. Upstream constructs defaults
/// with `.expect(..)`/`.unwrap()`, so failures are panics; they are raised
/// as a `DeError` starting with "panic:".
pub fn[T] default_value(text : String, f : (De) -> T raise DeError) -> T raise DeError {
  f(De::from_str(text)) catch {
    DeError(msg) => raise DeError("panic: invalid default provided: \{msg}")
  }
}

///|
/// The serialized forms of a newtype's enumerated values (decoded as the
/// inner type, then re-serialized).
pub fn[T] enum_values(
  texts : Array[String],
  de : (De) -> T raise DeError,
  ser : (T) -> Content raise SerError,
) -> Array[Content] {
  texts.map(t => {
    let v = de(De::from_str(t)) catch { e => abort("invalid enumerated value \{t}: \{e}") }
    ser(v) catch { e => abort("invalid enumerated value \{t}: \{e}") }
  })
}

///|
/// Whether a serialized value equals one of `allowed` (Rust `PartialEq` on
/// the inner type: numbers by value within their class, maps unordered).
pub fn contains_value(allowed : Array[Content], c : Content) -> Bool {
  let target = c.to_value() catch { _ => return false }
  allowed.iter().any(a => (try a.to_value() catch { _ => @serde_json.Value::Null }) == target)
}

///|
/// Number of Unicode scalar values (`str::chars().count()`).
pub fn char_count(s : String) -> Int {
  s.char_length()
}

///|
pub using @regex { type Regex }

///|
/// Compile a pattern that is known to be valid.
pub fn regex(pattern : String) -> Regex {
  @regex.Regex::new(pattern) catch {
    e => abort("invalid pattern \{pattern}: \{e}")
  }
}

///|
/// Rust `String` ordering (code points).
pub fn compare_keys(a : String, b : String) -> Int {
  @collections.compare_str(a, b)
}

///|
/// `{key: value}`.
pub fn single_entry(key : String, value : Content) -> Content {
  Object([{ key, key_escaped: false, key_error: None, value }])
}

///|
/// An internally tagged variant: the tag first, then the payload's entries.
pub fn tagged(tag : String, name : String, payload : Content) -> Content raise SerError {
  let o = ObjectBuilder::new()
  o.field(tag, String(name))
  match payload {
    Object(_) | Null => o.flatten(payload)
    _ => raise SerError("cannot serialize tagged newtype variant containing a non-map value")
  }
  o.build()
}

///|
/// An adjacently tagged variant `{tag: name, content: payload}`.
pub fn adjacent(tag : String, name : String, content : String, payload : Content) -> Content {
  Object([
    { key: tag, key_escaped: false, key_error: None, value: String(name) },
    { key: content, key_escaped: false, key_error: None, value: payload },
  ])
}

///|
/// Adjacently tagged enums (serde's `AdjacentlyTagged` visitor): the variant
/// and how its content is provided.
pub fn de_adjacent(
  d : De,
  name : String,
  tag : String,
  content : String,
  variants : Array[String],
  deny : Bool,
) -> (Int, VariantInput) raise DeError {
  let fields = [tag, content]
  match de_struct(d, "adjacently tagged enum \{name}", fields, false) {
    Entries(entries) => {
      let mut idx : Int? = None
      let mut payload : De? = None
      for e in entries {
        if e.0 == tag {
          if idx is Some(_) {
            raise duplicate_field_error(tag)
          }
          // The tag is decoded like an enum: "V" or {"V": null}.
          let (i, v) = de_enum(e.1, name, variants)
          variant_unit(v)
          idx = Some(i)
        } else if e.0 == content {
          if payload is Some(_) {
            raise duplicate_field_error(content)
          }
          // Content before the tag is buffered and read as owned content.
          payload = Some(
            match (idx, e.1) {
              (None, Value(c, _)) => Value(validated(c), Owned)
              _ => e.1
            },
          )
        } else if deny {
          raise unknown_field_error(e.0, fields)
        }
      }
      guard idx is Some(i) else { raise missing_field_error(tag) }
      match payload {
        Some(p) => (i, Payload(p))
        None => (i, NoPayload)
      }
    }
    Elements(s) => {
      let t = s.next()
      let (i, v) = de_enum(t, name, variants)
      variant_unit(v)
      let c = s.next()
      s.finish()
      (i, Payload(c))
    }
  }
}
