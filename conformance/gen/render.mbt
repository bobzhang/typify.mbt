// Text-level perturbations that a `Value` cannot express: key order,
// duplicate keys, escapes, number spellings, whitespace, positional struct
// arrays and deep nesting. These probe serde_json's streaming behaviour.

///|
let edge_numbers : Array[String] = [
  "0", "-0", "-0.0", "0.0", "1.0", "1e0", "1E2", "0.1e1", "10e-1", "255", "256",
  "-1", "-128", "-129", "32767", "32768", "65535", "65536", "2147483647", "2147483648",
  "-2147483649", "4294967295", "4294967296", "9007199254740993", "9223372036854775807",
  "9223372036854775808", "-9223372036854775808", "-9223372036854775809", "18446744073709551615",
  "18446744073709551616", "1e400", "-1e400", "1e-400", "1.5", "3.4028235e38", "3.5e38",
  "123456789012345678901234567890", "0.30000000000000004", "5e-324", "1.7976931348623157e308",
]

///|
/// Whitespace, sometimes.
fn Gen::ws(self : Gen, buf : StringBuilder) -> Unit {
  if self.chance(4) {
    buf.write_string(self.pick([" ", "  ", "\t"]))
  }
}

///|
/// A string literal, with some characters written as `\u` escapes.
fn Gen::render_str(
  self : Gen,
  buf : StringBuilder,
  s : String,
  escape_pct : Int,
) -> Unit {
  if !self.chance(escape_pct) || s.is_empty() {
    @serde_json.write_escaped_str(buf, s)
    return
  }
  buf.write_char('"')
  for c in s {
    let code = c.to_int()
    if code < 0x80 && c != '"' && c != '\\' && code >= 0x20 && !self.chance(40) {
      buf.write_char(c)
    } else if code <= 0xFFFF {
      buf.write_string("\\u")
      let hex = code.to_string(radix=16)
      for _ in hex.length()..<4 {
        buf.write_char('0')
      }
      buf.write_string(if self.chance(50) { hex } else { hex.to_upper() })
    } else {
      // A surrogate pair.
      let v = code - 0x10000
      let hi = 0xD800 + (v >> 10)
      let lo = 0xDC00 + (v & 0x3FF)
      buf.write_string(
        "\\u\{hi.to_string(radix=16)}\\u\{lo.to_string(radix=16)}",
      )
    }
  }
  buf.write_char('"')
}

///|
/// Deeply nested arrays (past serde_json's recursion limit of 128).
fn deep_value(depth : Int) -> String {
  let buf = StringBuilder()
  for _ in 0..<depth {
    buf.write_char('[')
  }
  for _ in 0..<depth {
    buf.write_char(']')
  }
  buf.to_string()
}

///|
fn Gen::render(self : Gen, buf : StringBuilder, v : @serde_json.Value) -> Unit {
  self.ws(buf)
  match v {
    Number(n) =>
      if self.chance(8) {
        buf.write_string(self.pick(edge_numbers))
      } else if n is (PosInt(_) | NegInt(_)) && self.chance(6) {
        buf.write_string(n.to_string() + self.pick([".0", "e0", "E+0", ".00"]))
      } else {
        buf.write_string(n.to_string())
      }
    String(s) => self.render_str(buf, s, 4)
    Array(xs) => {
      buf.write_char('[')
      for i, x in xs {
        if i > 0 {
          buf.write_char(',')
        }
        self.render(buf, x)
      }
      self.ws(buf)
      buf.write_char(']')
    }
    Object(m) => {
      let entries : Array[(String, @serde_json.Value)] = []
      for k, x in m {
        entries.push((k, x))
      }
      if self.chance(3) && !entries.is_empty() {
        // Positional form: the values as an array.
        self.render(buf, Array(entries.map(e => e.1)))
        return
      }
      if self.chance(30) {
        // Shuffle.
        for i = entries.length() - 1; i > 0; i = i - 1 {
          let j = self.below(i + 1)
          let t = entries[i]
          entries[i] = entries[j]
          entries[j] = t
        }
      }
      if self.chance(6) && !entries.is_empty() {
        // A duplicate key, with the same or another value.
        let (k, x) = self.pick(entries)
        let x = if self.chance(50) { x } else { self.any(2) }
        entries.insert(self.below(entries.length() + 1), (k, x))
      }
      buf.write_char('{')
      for i, e in entries {
        if i > 0 {
          buf.write_char(',')
        }
        self.ws(buf)
        self.render_str(buf, e.0, 5)
        self.ws(buf)
        buf.write_char(':')
        self.render(buf, e.1)
      }
      if self.chance(2) {
        // An ignored, too-deep value (accepted when skipped).
        if !entries.is_empty() {
          buf.write_char(',')
        }
        buf.write_string("\"zz_deep\":\{deep_value(130)}")
      }
      self.ws(buf)
      buf.write_char('}')
    }
    _ => buf.write_string(v.to_string())
  }
}

///|
/// The text of an instance, perturbed at the text level.
fn Gen::render_text(self : Gen, v : @serde_json.Value) -> String {
  let buf = StringBuilder()
  self.render(buf, v)
  buf.to_string()
}
