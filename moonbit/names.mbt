// MoonBit identifiers for generated items.

///|
/// MoonBit keywords and reserved words (a trailing `_` is appended).
let moonbit_keywords : Array[String] = [
  "as", "else", "extern", "fn", "if", "let", "const", "match", "using", "mut", "type",
  "struct", "enum", "trait", "derive", "while", "break", "continue", "import", "return",
  "throw", "raise", "try", "catch", "pub", "priv", "readonly", "true", "false", "test",
  "loop", "for", "in", "impl", "with", "guard", "async", "is", "suberror", "and",
  "letrec", "noraise", "defer", "lexmatch", "where", "nobreak", "declare", "extenum",
  "module", "move", "ref", "static", "super", "unsafe", "use", "await", "dyn", "abstract",
  "do", "final", "macro", "override", "typeof", "virtual", "yield", "local", "method",
  "alias", "assert", "package", "recur", "extend", "lazy", "constructor", "self",
  "Self", "enumview", "var",
]

///|
/// Prelude types a generated type must not shadow.
let reserved_type_names : Array[String] = [
  "Array", "ArrayView", "BigInt", "Bool", "Buffer", "Byte", "Bytes", "BytesView",
  "Char", "Compare", "Debug", "Default", "Double", "Eq", "Error", "Failure", "FixedArray",
  "Float", "FromJson", "Hash", "Hasher", "Int", "Int16", "Int64", "Iter", "Iter2",
  "Json", "Logger", "Map", "Option", "ReadOnlyArray", "Ref", "Repr", "Result", "Set",
  "Show", "SourceLoc", "String", "StringBuilder", "StringView", "ToJson", "UInt",
  "UInt16", "UInt64", "Unit",
]

///|
/// Constructors a generated enum must not shadow (generated code uses them).
let reserved_ctor_names : Array[String] = ["Some", "None", "Ok", "Err"]

///|
/// Allocates unique names within a scope.
priv struct Scope {
  used : Map[String, Unit]
}

///|
fn Scope::new() -> Scope {
  { used: Map([]), }
}

///|
fn Scope::alloc(self : Scope, base : String) -> String {
  let mut name = base
  let mut n = 2
  while self.used.contains(name) {
    name = "\{base}\{n}"
    n += 1
  }
  self.used[name] = ()
  name
}

///|
/// A type or constructor name: ASCII uppercase start, no keywords.
fn upper_ident(s : String, reserved : Array[String]) -> String {
  let s = match s.get_char(0) {
    Some(c) if c.is_ascii_uppercase() => s
    Some(c) if c.is_ascii_lowercase() => {
      let rest = s.unsafe_substring(start=1, end=s.length())
      c.to_ascii_uppercase().to_string() + rest
    }
    _ => "X" + s
  }
  if reserved.contains(s) || moonbit_keywords.contains(s) {
    s + "_"
  } else {
    s
  }
}

///|
/// A field or label name: not starting with an uppercase letter, no
/// keywords.
fn lower_ident(s : String) -> String {
  let s = match s.get_char(0) {
    Some(c) if c.is_ascii_uppercase() => {
      let rest = s.unsafe_substring(start=1, end=s.length())
      c.to_ascii_lowercase().to_string() + rest
    }
    Some(c) if c.is_ascii_digit() => "x" + s
    Some(_) => s
    None => "x"
  }
  if moonbit_keywords.contains(s) {
    s + "_"
  } else {
    s
  }
}
