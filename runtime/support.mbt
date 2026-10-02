// Helpers used by generated code.

///|
/// A failed conversion (upstream `self::error::ConversionError`).
pub(all) suberror ConversionError {
  ConversionError(String)
} derive(Debug, Eq)

///|
pub impl Show for ConversionError with fn output(self, logger) {
  let ConversionError(msg) = self
  logger.write_string(msg)
}

///|
pub fn de_nonzero_u8(d : De) -> Byte raise DeError {
  let v = de_u8_expecting(d, "a nonzero u8")
  nonzero(v == 0, "a nonzero u8")
  v
}

///|
pub fn de_nonzero_u16(d : De) -> UInt16 raise DeError {
  let v = de_u16_expecting(d, "a nonzero u16")
  nonzero(v == 0, "a nonzero u16")
  v
}

///|
pub fn de_nonzero_u32(d : De) -> UInt raise DeError {
  let v = de_u32_expecting(d, "a nonzero u32")
  nonzero(v == 0, "a nonzero u32")
  v
}

///|
pub fn de_nonzero_u64(d : De) -> UInt64 raise DeError {
  let v = de_u64_expecting(d, "a nonzero u64")
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
///
/// `preserve_order` keeps object keys in document order (serde_json's
/// `preserve_order`), as `--preserve-order` output expects.
pub fn content_to_json(
  c : Content,
  preserve_order? : Bool = false,
) -> Json raise SerError {
  let v = c.to_value(preserve_order~) catch {
    @serde_json.ParseError(message~, ..) => raise SerError(message)
  }
  value_to_json(v)
}

///|
/// Decode a default value from its JSON text. Upstream constructs defaults
/// with `.expect(..)`/`.unwrap()`, so failures are panics; they are raised
/// as a `DeError` starting with "panic:".
pub fn[T] default_value(
  text : String,
  f : (De) -> T raise DeError,
) -> T raise DeError {
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
    let v = de(De::from_str(t)) catch {
      e => abort("invalid enumerated value \{t}: \{e}")
    }
    ser(v) catch {
      e => abort("invalid enumerated value \{t}: \{e}")
    }
  })
}

///|
/// Whether a serialized value equals one of `allowed` (Rust `PartialEq` on
/// the inner type: numbers by value within their class, maps unordered).
pub fn contains_value(allowed : Array[Content], c : Content) -> Bool {
  let target = c.to_value() catch { _ => return false }
  allowed
  .iter()
  .any(a => (a.to_value() catch { _ => @serde_json.Value::Null }) == target)
}

///|
/// Number of Unicode scalar values (`str::chars().count()`).
pub fn char_count(s : String) -> Int {
  s.char_length()
}

///|
pub using @regex {type Regex}

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
  Object([{ key, key_escaped: false, key_error: None, value, }])
}

///|
/// An internally tagged variant: the tag first, then the payload's entries.
pub fn tagged(
  tag : String,
  name : String,
  payload : Content,
) -> Content raise SerError {
  let o = ObjectBuilder::new()
  o.field(tag, String(name))
  match payload {
    Object(_) | Null => o.flatten(payload)
    _ =>
      raise SerError(
        "cannot serialize tagged newtype variant containing a non-map value",
      )
  }
  o.build()
}

///|
/// An adjacently tagged variant `{tag: name, content: payload}`.
pub fn adjacent(
  tag : String,
  name : String,
  content : String,
  payload : Content,
) -> Content {
  Object([
    { key: tag, key_escaped: false, key_error: None, value: String(name), },
    { key: content, key_escaped: false, key_error: None, value: payload, },
  ])
}

///|
/// Adjacently tagged enums (serde's `AdjacentlyTagged` visitor): finds the
/// variant and calls `decode(variant, content)` as serde's visitor does:
/// content after the tag is decoded as soon as it is read (in the current
/// mode), content before the tag is buffered and decoded once the tag is
/// known; entries after that are still checked for duplicates.
pub fn[T] de_adjacent(
  d : De,
  name : String,
  tag : String,
  content : String,
  variants : Array[String],
  deny : Bool,
  decode : (Int, VariantInput) -> T raise DeError,
  paths? : Bool = false,
) -> T raise DeError {
  // With `paths`, errors in the content say so (`error_at`).
  let decode = if paths {
    (i : Int, v : VariantInput) => {
      decode(i, v) catch {
        e => raise if v is Payload(_) { error_at(e, content) } else { e }
      }
    }
  } else {
    decode
  }
  let fields = [tag, content]
  let expecting = "adjacently tagged enum \{name}"
  let entries : Array[() -> (String, De)] = match
    de_struct(d, expecting, fields, false) {
    Entries(es) => es.map(e => () => e)
    // Flattened: only the tag and content entries, claimed as they are read.
    Claiming(es) => es.map(e => () => claim_entry(e))
    Elements(s) => {
      // `[tag, content]`: the tag is a variant identifier.
      let t = match s.next_opt() {
        Some(t) => t
        None => raise DeError("invalid length 0, expected \{expecting}")
      }
      let i = match t {
        Value(c, mode) => tag_identifier(c, variants, !(mode is Direct))
        _ => raise DeError("invalid type, expected variant identifier")
      }
      let c = match s.next_opt() {
        Some(c) => c
        None => raise DeError("invalid length 1, expected \{expecting}")
      }
      let r = decode(i, Payload(c))
      s.finish()
      return r
    }
  }
  let mut idx : Int? = None
  let mut buffered : De? = None
  let mut result : T? = None
  let mut seen_content = false
  for get in entries {
    let (key, value) = get()
    if key == tag {
      if idx is Some(_) {
        raise duplicate_field_error(tag)
      }
      // The tag is decoded like an enum: "V" or {"V": null}.
      let (i, v) = de_enum(value, name, variants)
      variant_unit(v)
      idx = Some(i)
      if buffered is Some(c) {
        result = Some(decode(i, Payload(c)))
      }
    } else if key == content {
      if seen_content {
        raise duplicate_field_error(content)
      }
      seen_content = true
      match idx {
        Some(i) => result = Some(decode(i, Payload(value)))
        // Content before the tag is buffered and read as owned content.
        None =>
          buffered = Some(
            match value {
              Value(c, _) => Value(validated(c), Owned)
              other => other
            },
          )
      }
    } else if deny {
      raise unknown_field_error(key, fields)
    }
  }
  guard idx is Some(i) else { raise missing_field_error(tag) }
  match result {
    Some(r) => r
    None => decode(i, NoPayload)
  }
}

///|
/// The content of an adjacently tagged variant: absent content is decoded
/// from serde's `MissingFieldDeserializer` (`Option` payloads become
/// `None`, anything else is `missing field <content>`).
pub fn adjacent_content(v : VariantInput, content : String) -> De {
  match v {
    Payload(d) => d
    UnitOnly | NoPayload => Missing(content)
  }
}

///|
/// The content of an adjacently tagged unit variant: serde reads it with
/// `deserialize_any` and its `UntaggedUnitVisitor`, so only `null` (or no
/// content) is accepted; `expecting` is `unit variant Enum::Variant`.
pub fn adjacent_unit(
  v : VariantInput,
  expecting : String,
) -> Unit raise DeError {
  match v {
    Payload(Value(Null, _)) | Payload(Missing(_)) | UnitOnly | NoPayload => ()
    Payload(Value(c, _)) => {
      check_valid(c)
      raise invalid_type_error(c, expecting)
    }
    Payload(MapKey(k, _)) => raise invalid_type_error(String(k), expecting)
    Payload(Flat(_)) => raise flatten_error()
  }
}

///|
/// Decode a type through its core `FromJson` (a replacement type with the
/// `json` codec). The value is read as `serde_json::Value` with its keys in
/// document order; duplicate keys are resolved (last wins) before the type
/// sees them.
pub fn[T : @json.FromJson] de_from_json(d : De) -> T raise DeError {
  let json = de_json_ordered(d)
  @json.from_json(json) catch {
    @json.JsonDecodeError((path, message)) => {
      let at = path.to_string().trim().to_owned()
      let message = message.trim().to_owned()
      raise DeError(
        if at == "" || at == "$" {
          message
        } else {
          "\{message} at \{at}"
        },
      )
    }
  }
}

///|
/// Encode a type through its core `ToJson` (a replacement type with the
/// `json` codec), keeping its object keys in the order it builds them.
pub fn[T : ToJson] ser_to_json(value : T) -> Content {
  ser_json_ordered(value.to_json())
}
