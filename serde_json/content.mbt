///|
/// An ordered JSON document: object entries keep their order and duplicates,
/// numbers keep serde_json's classification. This is the input serde's
/// derived deserializers observe.
pub(all) enum Content {
  Null
  Bool(Bool)
  Number(Number)
  String(String)
  Array(Array[Content])
  Object(Array[Entry])
  /// A value whose error serde_json reports only when the value is visited
  /// (produced by lenient parsing; skipped values are accepted).
  Invalid(ParseError)
} derive(Debug, Eq)

///|
/// An object entry; `key_escaped` records whether the key's source text
/// contained escape sequences (it matters for serde_json's numeric map keys).
pub(all) struct Entry {
  key : String
  key_escaped : Bool
  /// A deferred error in the key text (lenient parsing).
  key_error : ParseError?
  value : Content
} derive(Debug, Eq)

///|
/// The serde_json `Value` of a document (duplicate keys: the last wins; keys
/// sorted).
pub fn Content::to_value(self : Content) -> Value raise ParseError {
  match self {
    Invalid(e) => raise e
    Null => Null
    Bool(b) => Bool(b)
    Number(n) => Number(n)
    String(s) => String(s)
    Array(xs) => {
      let out = []
      for x in xs {
        out.push(x.to_value())
      }
      Array(out)
    }
    Object(entries) => {
      let o = @collections.StrMap::new()
      for e in entries {
        if e.key_error is Some(err) {
          raise err
        }
        o.set(e.key, e.value.to_value())
      }
      Object(o)
    }
  }
}

///|
/// The ordered document of a `Value` (keys in sorted order).
pub fn Value::to_content(self : Value) -> Content {
  match self {
    Null => Null
    Bool(b) => Bool(b)
    Number(n) => Number(n)
    String(s) => String(s)
    Array(xs) => Array(xs.map(x => x.to_content()))
    Object(o) => {
      let entries = []
      for k, v in o {
        entries.push({
          key: k,
          key_escaped: false,
          key_error: None,
          value: v.to_content(),
        })
      }
      Object(entries)
    }
  }
}

///|
/// Compact JSON text of a document, identical to serde_json's serializer
/// (entries in order, duplicates preserved).
pub fn Content::to_string(self : Content) -> String {
  let buf = StringBuilder()
  write_content(buf, self)
  buf.to_string()
}

///|
pub impl Show for Content with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
fn write_content(buf : StringBuilder, c : Content) -> Unit {
  match c {
    Null => buf.write_string("null")
    Bool(b) => buf.write_string(if b { "true" } else { "false" })
    Number(n) => buf.write_string(n.to_string())
    String(s) => write_escaped_str(buf, s)
    Array(xs) => {
      buf.write_char('[')
      for i, x in xs {
        if i > 0 {
          buf.write_char(',')
        }
        write_content(buf, x)
      }
      buf.write_char(']')
    }
    Invalid(_) => buf.write_string("null")
    Object(entries) => {
      buf.write_char('{')
      for i, e in entries {
        if i > 0 {
          buf.write_char(',')
        }
        write_escaped_str(buf, e.key)
        buf.write_char(':')
        write_content(buf, e.value)
      }
      buf.write_char('}')
    }
  }
}
