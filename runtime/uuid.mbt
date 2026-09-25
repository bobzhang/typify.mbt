// `uuid::Uuid` (uuid 1.16): `Uuid::parse_str` with uuid's error messages,
// and lowercase hyphenated output.

///|
/// A UUID, serialized as lowercase hyphenated text.
pub struct Uuid {
  priv bytes : FixedArray[Byte]
} derive(Eq, Compare, Hash)

///|
pub impl Debug for Uuid with fn to_repr(self) {
  Repr(self.to_string())
}

///|
pub impl Show for Uuid with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// The UUID with the given 16 bytes (`Uuid::from_bytes`).
pub fn Uuid::from_bytes(bytes : FixedArray[Byte]) -> Uuid {
  guard bytes.length() == 16 else {
    abort("Uuid::from_bytes: expected 16 bytes")
  }
  { bytes: bytes.copy(), }
}

///|
/// The 16 bytes of the UUID.
pub fn Uuid::to_bytes(self : Uuid) -> FixedArray[Byte] {
  self.bytes.copy()
}

///|
/// The value of an ASCII hex digit byte, or -1.
fn hex_digit(b : Int) -> Int {
  if b >= 0x30 && b <= 0x39 {
    b - 0x30
  } else if b >= 0x61 && b <= 0x66 {
    b - 0x61 + 10
  } else if b >= 0x41 && b <= 0x46 {
    b - 0x41 + 10
  } else {
    -1
  }
}

///|
/// `parse_simple` / `parse_hyphenated` on `input[start:end]`.
fn uuid_digits(input : Bytes, start : Int, end : Int) -> FixedArray[Byte]? {
  let n = end - start
  let digit = (i : Int) => hex_digit(input[start + i].to_int())
  let buf = FixedArray::make(16, b'\x00')
  if n == 32 {
    for i in 0..<16 {
      let (h1, h2) = (digit(2 * i), digit(2 * i + 1))
      if h1 < 0 || h2 < 0 {
        return None
      }
      buf[i] = (h1 * 16 + h2).to_byte()
    }
    return Some(buf)
  }
  if n != 36 {
    return None
  }
  for p in [8, 13, 18, 23] {
    if input[start + p] != b'-' {
      return None
    }
  }
  let positions = [0, 4, 9, 14, 19, 24, 28, 32]
  for j, i in positions {
    let (h1, h2, h3, h4) = (digit(i), digit(i + 1), digit(i + 2), digit(i + 3))
    if h1 < 0 || h2 < 0 || h3 < 0 || h4 < 0 {
      return None
    }
    buf[j * 2] = (h1 * 16 + h2).to_byte()
    buf[j * 2 + 1] = (h3 * 16 + h4).to_byte()
  }
  Some(buf)
}

///|
/// `InvalidUuid::into_err`: explain why `s` (the slice the parser rejected)
/// is not a UUID.
fn uuid_error(s : String) -> String {
  let chars = s.to_array()
  let (body, offset, simple) = if chars.length() >= 2 &&
    chars[0] == '{' &&
    chars[chars.length() - 1] == '}' {
    (chars[1:chars.length() - 1], 1, false)
  } else if s.has_prefix("urn:uuid:") {
    (chars[9:], 9, false)
  } else {
    (chars[:], 0, true)
  }
  let mut hyphens = 0
  let bounds = [0, 0, 0, 0]
  let mut index = 0 // byte index into `body`
  for c in body {
    if c == '-' {
      if hyphens < 4 {
        bounds[hyphens] = index
      }
      hyphens += 1
    } else if hex_digit(c.to_int()) < 0 {
      return "invalid character: expected an optional prefix of `urn:uuid:` followed by [0-9a-fA-F-], found `\{c}` at \{index + offset + 1}"
    }
    index += 1
  }
  let byte_len = s.length() // all characters are ASCII here
  if hyphens == 0 && simple {
    return "invalid length: expected length 32 for simple format, found \{byte_len}"
  }
  if hyphens != 4 {
    return "invalid group count: expected 5, found \{hyphens + 1}"
  }
  let starts = [0, 9, 14, 19, 24]
  let expected = [8, 4, 4, 4, 12]
  for i in 0..<4 {
    if bounds[i] != starts[i + 1] - 1 {
      return "invalid group length in group \{i}: expected \{expected[i]}, found \{bounds[i] - starts[i]}"
    }
  }
  "invalid group length in group 4: expected 12, found \{byte_len - starts[4]}"
}

///|
/// `Uuid::parse_str`: the simple (32 hex digits), hyphenated, braced
/// (`{...}`) and URN (`urn:uuid:...`) forms, with uuid's error messages.
fn parse_uuid(s : String) -> Uuid raise ConversionError {
  let input = @utf8.encode(s)
  let n = input.length()
  let (start, end) = if n == 38 && input[0] == b'{' && input[37] == b'}' {
    (1, 37)
  } else if n == 45 && s.has_prefix("urn:uuid:") {
    (9, 45)
  } else {
    (0, n)
  }
  let parsed = if n == 32 || end - start == 36 {
    uuid_digits(input, start, end)
  } else {
    None
  }
  match parsed {
    Some(bytes) => { bytes, }
    None => {
      // The parser reports the inner slice of braced and URN input.
      let rejected = @utf8.decode_lossy(input[start:end])
      raise ConversionError(uuid_error(rejected))
    }
  }
}

///|
/// `Uuid::parse_str` (errors carry uuid's message).
pub fn Uuid::parse(s : String) -> Uuid raise ConversionError {
  parse_uuid(s)
}

///|
/// Lowercase hyphenated form.
pub fn Uuid::to_string(self : Uuid) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder()
  for i, b in self.bytes {
    if i is (4 | 6 | 8 | 10) {
      buf.write_char('-')
    }
    let b = b.to_int()
    buf.write_char(digits.get_char(b >> 4).unwrap())
    buf.write_char(digits.get_char(b & 15).unwrap())
  }
  buf.to_string()
}

///|
pub fn Uuid::deserialize(d : De) -> Uuid raise DeError {
  let s = de_string_expecting(d, "a UUID string")
  parse_uuid(s) catch {
    ConversionError(msg) => raise DeError("UUID parsing failed: \{msg}")
  }
}

///|
pub fn Uuid::serialize(self : Uuid) -> Content raise SerError {
  String(self.to_string())
}
