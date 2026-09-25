///|
pub(all) enum Case {
  Pascal
  Snake
}

///|
/// Whether `ident` may be used as a Rust identifier as-is (upstream
/// `accept_as_ident`): false for keywords, which get a trailing `_`.
pub fn accept_as_ident(ident : String) -> Bool {
  !(ident
  is ("_"
  | "abstract"
  | "as"
  | "async"
  | "await"
  | "become"
  | "box"
  | "break"
  | "const"
  | "continue"
  | "crate"
  | "do"
  | "dyn"
  | "else"
  | "enum"
  | "extern"
  | "false"
  | "final"
  | "fn"
  | "for"
  | "gen"
  | "if"
  | "impl"
  | "in"
  | "let"
  | "loop"
  | "macro"
  | "match"
  | "mod"
  | "move"
  | "mut"
  | "override"
  | "priv"
  | "pub"
  | "ref"
  | "return"
  | "Self"
  | "self"
  | "static"
  | "struct"
  | "super"
  | "trait"
  | "true"
  | "try"
  | "type"
  | "typeof"
  | "unsafe"
  | "unsized"
  | "use"
  | "virtual"
  | "where"
  | "while"
  | "yield"))
}

///|
fn to_case(s : String, case : Case) -> String {
  match case {
    Pascal => @heck.to_pascal_case(s)
    Snake => @heck.to_snake_case(s)
  }
}

///|
/// Turn arbitrary text into a Rust identifier in the given case (upstream
/// `sanitize`).
pub fn sanitize(input : String, case : Case) -> String {
  let out = match input {
    "+1" => "plus1"
    "-1" => "minus1"
    _ => {
      let buf = StringBuilder()
      for c in input {
        if c == '\'' {
          continue
        }
        buf.write_char(if @unicode.is_xid_continue(c) { c } else { '-' })
      }
      to_case(buf.to_string(), case)
    }
  }
  let prefix = to_case("x", case)
  let out = match out.get_char(0) {
    None => prefix
    Some(c) if @unicode.is_xid_start(c) => out
    Some(_) => prefix + out
  }
  if accept_as_ident(out) {
    out
  } else {
    out + "_"
  }
}

///|
/// Sanitize and report the original name if it changed.
pub fn recase(input : String, case : Case) -> (String, String?) {
  let new = sanitize(input, case)
  (new, if new == input { None } else { Some(input) })
}

///|
fn metadata_description(metadata : @schema.Metadata?) -> String? {
  metadata.bind(m => m.description)
}

///|
fn metadata_title(metadata : @schema.Metadata?) -> String? {
  metadata.bind(m => m.title)
}

///|
fn metadata_default(metadata : @schema.Metadata?) -> @serde_json.Value? {
  metadata.bind(m => m.default)
}

///|
fn metadata_title_and_description(metadata : @schema.Metadata?) -> String? {
  match metadata {
    None => None
    Some(m) =>
      match (m.title, m.description) {
        (Some(t), Some(d)) => Some("\{t}\n\n\{d}")
        (Some(t), None) => Some(t)
        (None, Some(d)) => Some(d)
        (None, None) => None
      }
  }
}

///|
/// The type name to use: a required name wins, then the title, then a
/// suggestion.
fn get_type_name(type_name : Name, metadata : @schema.Metadata?) -> String? {
  let name = match (type_name, metadata_title(metadata)) {
    (Required(name), _) => name
    (Suggested(name), None) => name
    (_, Some(name)) => name
    (Unknown, None) => return None
  }
  Some(sanitize(name, Pascal))
}

///|
priv struct TypePatch {
  name : String
  derives : @collections.StrSet
  attrs : @collections.StrSet
}

///|
fn TypePatch::new(
  settings : TypeSpaceSettings,
  type_name : String,
) -> TypePatch {
  match settings.patch.get(type_name) {
    None =>
      {
        name: type_name,
        derives: @collections.StrSet::new(),
        attrs: @collections.StrSet::new(),
      }
    Some(patch) =>
      {
        name: patch.rename.unwrap_or(type_name),
        derives: @collections.StrSet::from_array(patch.derives),
        attrs: @collections.StrSet::from_array(patch.attrs),
      }
  }
}

///|
/// Whether all items are distinct.
fn[T : Hash + Eq] unique(items : Array[T]) -> Bool {
  let seen : Map[T, Unit] = Map([])
  for item in items {
    if seen.contains(item) {
      return false
    }
    seen[item] = ()
  }
  true
}

///|
/// UTF-8 byte length (Rust `str::len`).
fn utf8_len(s : String) -> Int {
  let mut n = 0
  for c in s {
    let cp = c.to_int()
    n += if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
  }
  n
}

///|
/// Rust `&s[byte_offset..]`; aborts (like Rust panics) on a non-boundary.
fn slice_from_byte(s : String, byte_offset : Int) -> String raise TypifyError {
  let mut n = 0
  let mut i = 0
  for c in s {
    if n == byte_offset {
      return s.unsafe_substring(start=i, end=s.length())
    }
    if n > byte_offset {
      break
    }
    let cp = c.to_int()
    n += if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
    i += c.utf16_len()
  }
  if n == byte_offset {
    return ""
  }
  raise panic_with("byte index \{byte_offset} is not a char boundary of \{s}")
}
