///|
let hex_digits : String = "0123456789abcdef"

///|
/// Write a JSON string literal with serde_json's escaping rules: only `"`,
/// `\` and control characters are escaped; everything else is emitted as-is.
pub fn write_escaped_str(buf : StringBuilder, s : StringView) -> Unit {
  buf.write_char('"')
  // Copy runs of characters that need no escape in one step.
  let n = s.length()
  let mut start = 0
  for i in 0..<n {
    let u = s.unsafe_get(i).to_int()
    if u >= 0x20 && u != 0x22 && u != 0x5C {
      continue
    }
    if start < i {
      buf.write_view(s[start:i])
    }
    start = i + 1
    match u {
      0x22 => buf.write_string("\\\"")
      0x5C => buf.write_string("\\\\")
      0x08 => buf.write_string("\\b")
      0x09 => buf.write_string("\\t")
      0x0A => buf.write_string("\\n")
      0x0C => buf.write_string("\\f")
      0x0D => buf.write_string("\\r")
      _ => {
        buf.write_string("\\u00")
        buf.write_char(hex_digits.get_char(u >> 4).unwrap())
        buf.write_char(hex_digits.get_char(u & 0xF).unwrap())
      }
    }
  }
  if start < n {
    buf.write_view(s[start:n])
  }
  buf.write_char('"')
}

///|
fn write_compact(buf : StringBuilder, v : Value) -> Unit {
  match v {
    Null => buf.write_string("null")
    Bool(true) => buf.write_string("true")
    Bool(false) => buf.write_string("false")
    Number(n) => buf.write_string(n.to_string())
    String(s) => write_escaped_str(buf, s)
    Array(xs) => {
      buf.write_char('[')
      for i, x in xs {
        if i > 0 {
          buf.write_char(',')
        }
        write_compact(buf, x)
      }
      buf.write_char(']')
    }
    Object(o) => {
      buf.write_char('{')
      let mut first = true
      for k, x in o {
        if !first {
          buf.write_char(',')
        }
        first = false
        write_escaped_str(buf, k)
        buf.write_char(':')
        write_compact(buf, x)
      }
      buf.write_char('}')
    }
  }
}

///|
fn write_indent(buf : StringBuilder, level : Int) -> Unit {
  for _ in 0..<level {
    buf.write_string("  ")
  }
}

///|
fn write_pretty(buf : StringBuilder, v : Value, level : Int) -> Unit {
  match v {
    Array(xs) => {
      if xs.is_empty() {
        buf.write_string("[]")
        return
      }
      buf.write_char('[')
      for i, x in xs {
        buf.write_string(if i > 0 { ",\n" } else { "\n" })
        write_indent(buf, level + 1)
        write_pretty(buf, x, level + 1)
      }
      buf.write_char('\n')
      write_indent(buf, level)
      buf.write_char(']')
    }
    Object(o) => {
      if o.is_empty() {
        buf.write_string("{}")
        return
      }
      buf.write_char('{')
      let mut first = true
      for k, x in o {
        buf.write_string(if first { "\n" } else { ",\n" })
        first = false
        write_indent(buf, level + 1)
        write_escaped_str(buf, k)
        buf.write_string(": ")
        write_pretty(buf, x, level + 1)
      }
      buf.write_char('\n')
      write_indent(buf, level)
      buf.write_char('}')
    }
    _ => write_compact(buf, v)
  }
}
