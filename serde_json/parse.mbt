///|
/// A JSON syntax or range error, mirroring serde_json's error codes and
/// positions (1-based line, column in UTF-8 bytes).
pub(all) suberror ParseError {
  ParseError(message~ : String, line~ : Int, column~ : Int)
} derive(Debug, Eq)

///|
pub impl Show for ParseError with fn output(self, logger) {
  let ParseError(message~, line~, column~) = self
  logger.write_string("\{message} at line \{line} column \{column}")
}

///|
/// serde_json's default recursion limit.
let recursion_limit : Int = 128

///|
/// A byte-level port of serde_json's `Deserializer<SliceRead>` restricted to
/// what `from_str::<Value>` exercises.
priv struct Parser {
  src : Bytes
  mut index : Int
  mut remaining_depth : Int
}

///|
/// serde_json's `POW10` table (exactly rounded powers of ten).
let pow10 : FixedArray[Double] = FixedArray::makei(309, i => {
  @string.parse_double("1e\{i}") catch {
    _ => abort("unreachable")
  }
})

///|
/// `SliceRead::position_of_index`.
fn Parser::error_at(self : Parser, i : Int, message : String) -> ParseError {
  let mut line = 1
  let mut start_of_line = 0
  for j in 0..<i {
    if self.src[j] == b'\n' {
      line += 1
      start_of_line = j + 1
    }
  }
  ParseError(message~, line~, column=i - start_of_line)
}

///|
/// serde_json `error`: position of the next unread byte.
fn Parser::error(self : Parser, message : String) -> ParseError {
  self.error_at(self.index, message)
}

///|
/// serde_json `peek_error`: position just after the peeked byte.
fn Parser::peek_error(self : Parser, message : String) -> ParseError {
  self.error_at((self.index + 1).min(self.src.length()), message)
}

///|
fn Parser::peek(self : Parser) -> Int {
  if self.index < self.src.length() {
    self.src[self.index].to_int()
  } else {
    -1
  }
}

///|
fn Parser::next_char(self : Parser) -> Int {
  let c = self.peek()
  if c >= 0 {
    self.index += 1
  }
  c
}

///|
/// `parse_whitespace`: skip whitespace and peek.
fn Parser::parse_whitespace(self : Parser) -> Int {
  while self.peek() is (0x20 | 0x0A | 0x0D | 0x09) {
    self.index += 1
  }
  self.peek()
}

///|
fn Parser::parse_ident(self : Parser, ident : String) -> Unit raise ParseError {
  for c in ident {
    let next = self.next_char()
    if next < 0 {
      raise self.error("EOF while parsing a value")
    } else if next != c.to_int() {
      raise self.error("expected ident")
    }
  }
}

///|
/// `deserialize_any` specialised to `Value`.
fn Parser::parse_value(self : Parser) -> Value raise ParseError {
  let peek = self.parse_whitespace()
  match peek {
    -1 => raise self.peek_error("EOF while parsing a value")
    'n' => {
      self.index += 1
      self.parse_ident("ull")
      Null
    }
    't' => {
      self.index += 1
      self.parse_ident("rue")
      Bool(true)
    }
    'f' => {
      self.index += 1
      self.parse_ident("alse")
      Bool(false)
    }
    '-' => {
      self.index += 1
      Number(self.parse_integer(false))
    }
    '0'..='9' => Number(self.parse_integer(true))
    '"' => {
      self.index += 1
      String(self.parse_str())
    }
    '[' => {
      self.check_recursion()
      self.index += 1
      let items = self.parse_seq()
      self.remaining_depth += 1
      // end_seq: the visitor only returns after peeking `]`.
      self.index += 1
      Array(items)
    }
    '{' => {
      self.check_recursion()
      self.index += 1
      let obj = self.parse_map()
      self.remaining_depth += 1
      self.index += 1
      Object(obj)
    }
    _ => raise self.peek_error("expected value")
  }
}

///|
fn Parser::check_recursion(self : Parser) -> Unit raise ParseError {
  self.remaining_depth -= 1
  if self.remaining_depth == 0 {
    raise self.peek_error("recursion limit exceeded")
  }
}

///|
/// `SeqAccess::next_element_seed` driven to completion. Leaves the closing
/// `]` unconsumed.
fn Parser::parse_seq(self : Parser) -> Array[Value] raise ParseError {
  let items = []
  for first = true {
    let peek = self.parse_whitespace()
    if peek < 0 {
      raise self.peek_error("EOF while parsing a list")
    }
    if peek == ']' {
      break
    } else if first {
      ()
    } else if peek == ',' {
      self.index += 1
      match self.parse_whitespace() {
        ']' => raise self.peek_error("trailing comma")
        -1 => raise self.peek_error("EOF while parsing a value")
        _ => ()
      }
    } else {
      raise self.peek_error("expected `,` or `]`")
    }
    items.push(self.parse_value())
    continue false
  }
  items
}

///|
/// `MapAccess` driven to completion. Leaves the closing `}` unconsumed.
fn Parser::parse_map(
  self : Parser,
) -> @collections.StrMap[Value] raise ParseError {
  let obj = @collections.StrMap::new()
  for first = true {
    let peek = self.parse_whitespace()
    if peek < 0 {
      raise self.peek_error("EOF while parsing an object")
    }
    if peek == '}' {
      break
    } else if first {
      if peek != '"' {
        raise self.peek_error("key must be a string")
      }
    } else if peek == ',' {
      self.index += 1
      match self.parse_whitespace() {
        '"' => ()
        '}' => raise self.peek_error("trailing comma")
        -1 => raise self.peek_error("EOF while parsing a value")
        _ => raise self.peek_error("key must be a string")
      }
    } else {
      raise self.peek_error("expected `,` or `}`")
    }
    // MapKey: eat the quote and parse the string.
    self.index += 1
    let key = self.parse_str()
    // parse_object_colon
    match self.parse_whitespace() {
      ':' => self.index += 1
      -1 => raise self.peek_error("EOF while parsing an object")
      _ => raise self.peek_error("expected `:`")
    }
    // Duplicate keys: the last occurrence wins (BTreeMap::insert).
    obj.set(key, self.parse_value())
    continue false
  }
  obj
}

///|
fn push_utf8(buf : Buffer, cp : Int) -> Unit {
  if cp < 0x80 {
    buf.write_byte(cp.to_byte())
  } else if cp < 0x800 {
    buf.write_byte((0xC0 | (cp >> 6)).to_byte())
    buf.write_byte((0x80 | (cp & 0x3F)).to_byte())
  } else if cp < 0x10000 {
    buf.write_byte((0xE0 | (cp >> 12)).to_byte())
    buf.write_byte((0x80 | ((cp >> 6) & 0x3F)).to_byte())
    buf.write_byte((0x80 | (cp & 0x3F)).to_byte())
  } else {
    buf.write_byte((0xF0 | (cp >> 18)).to_byte())
    buf.write_byte((0x80 | ((cp >> 12) & 0x3F)).to_byte())
    buf.write_byte((0x80 | ((cp >> 6) & 0x3F)).to_byte())
    buf.write_byte((0x80 | (cp & 0x3F)).to_byte())
  }
}

///|
/// `SliceRead::decode_hex_escape`.
fn Parser::decode_hex_escape(self : Parser) -> Int raise ParseError {
  if self.index + 4 > self.src.length() {
    self.index = self.src.length()
    raise self.error("EOF while parsing a string")
  }
  let mut n = 0
  let mut ok = true
  for k in 0..<4 {
    let c = self.src[self.index + k].to_int()
    let d = match c {
      '0'..='9' => c - '0'
      'a'..='f' => c - 'a' + 10
      'A'..='F' => c - 'A' + 10
      _ => {
        ok = false
        0
      }
    }
    n = n * 16 + d
  }
  self.index += 4
  if !ok {
    raise self.error("invalid escape")
  }
  n
}

///|
/// `parse_escape` + `parse_unicode_escape` with `validate = true`.
fn Parser::parse_escape(self : Parser, buf : Buffer) -> Unit raise ParseError {
  let ch = self.next_char()
  match ch {
    -1 => raise self.error("EOF while parsing a string")
    '"' => buf.write_byte(b'"')
    '\\' => buf.write_byte(b'\\')
    '/' => buf.write_byte(b'/')
    'b' => buf.write_byte(b'\x08')
    'f' => buf.write_byte(b'\x0c')
    'n' => buf.write_byte(b'\n')
    'r' => buf.write_byte(b'\r')
    't' => buf.write_byte(b'\t')
    'u' => {
      let n = self.decode_hex_escape()
      if n >= 0xDC00 && n <= 0xDFFF {
        raise self.error("lone leading surrogate in hex escape")
      }
      if n < 0xD800 || n > 0xDBFF {
        push_utf8(buf, n)
        return
      }
      // A leading surrogate must be followed by `\u` + trailing surrogate.
      match self.peek() {
        -1 => raise self.error("EOF while parsing a string")
        '\\' => self.index += 1
        _ => {
          self.index += 1
          raise self.error("unexpected end of hex escape")
        }
      }
      match self.peek() {
        -1 => raise self.error("EOF while parsing a string")
        'u' => self.index += 1
        _ => {
          self.index += 1
          raise self.error("unexpected end of hex escape")
        }
      }
      let n2 = self.decode_hex_escape()
      if n2 < 0xDC00 || n2 > 0xDFFF {
        raise self.error("lone leading surrogate in hex escape")
      }
      push_utf8(buf, 0x10000 + ((n - 0xD800) << 10) + (n2 - 0xDC00))
    }
    _ => raise self.error("invalid escape")
  }
}

///|
/// `SliceRead::parse_str_bytes`; the opening quote has been consumed.
fn Parser::parse_str(self : Parser) -> String raise ParseError {
  let buf = Buffer()
  for ;; {
    let c = self.peek()
    match c {
      -1 => raise self.error("EOF while parsing a string")
      '"' => {
        self.index += 1
        break
      }
      '\\' => {
        self.index += 1
        self.parse_escape(buf)
      }
      _ if c < 0x20 => {
        self.index += 1
        raise self.error(
          "control character (\\u0000-\\u001F) found while parsing a string",
        )
      }
      _ => {
        buf.write_byte(c.to_byte())
        self.index += 1
      }
    }
  }
  @utf8.decode(buf.to_bytes()) catch {
    _ => abort("unreachable: input and escapes are valid UTF-8")
  }
}

///|
fn overflows_u64(significand : UInt64, digit : UInt64) -> Bool {
  let max = 0xFFFF_FFFF_FFFF_FFFFUL
  significand >= max / 10 && (significand > max / 10 || digit > max % 10)
}

///|
fn Parser::parse_integer(
  self : Parser,
  positive : Bool,
) -> Number raise ParseError {
  let next = self.next_char()
  match next {
    -1 => raise self.error("EOF while parsing a value")
    '0' => {
      // There can be only one leading '0'.
      if self.peek() is ('0'..='9') {
        raise self.peek_error("invalid number")
      }
      self.parse_number(positive, 0)
    }
    '1'..='9' => {
      let mut significand = (next - '0').to_uint64()
      for ;; {
        let c = self.peek()
        if !(c is ('0'..='9')) {
          break self.parse_number(positive, significand)
        }
        let digit = (c - '0').to_uint64()
        if overflows_u64(significand, digit) {
          break Float(self.parse_long_integer(positive, significand))
        }
        self.index += 1
        significand = significand * 10 + digit
      }
    }
    _ => raise self.error("invalid number")
  }
}

///|
fn Parser::parse_number(
  self : Parser,
  positive : Bool,
  significand : UInt64,
) -> Number raise ParseError {
  match self.peek() {
    '.' => Float(self.parse_decimal(positive, significand, 0))
    'e' | 'E' => Float(self.parse_exponent(positive, significand, 0))
    _ =>
      if positive {
        PosInt(significand)
      } else {
        let neg = -significand.reinterpret_as_int64()
        // Convert into a float if we underflow, or on `-0`.
        if neg >= 0L {
          Float(-significand.to_double())
        } else {
          NegInt(neg)
        }
      }
  }
}

///|
fn Parser::parse_decimal(
  self : Parser,
  positive : Bool,
  significand : UInt64,
  exponent_before_decimal_point : Int,
) -> Double raise ParseError {
  self.index += 1 // '.'
  let mut significand = significand
  let mut exponent_after_decimal_point = 0
  while self.peek() is ('0'..='9') {
    let digit = (self.peek() - '0').to_uint64()
    if overflows_u64(significand, digit) {
      let exponent = exponent_before_decimal_point +
        exponent_after_decimal_point
      // parse_decimal_overflow: ignore all further digits.
      while self.peek() is ('0'..='9') {
        self.index += 1
      }
      return match self.peek() {
        'e' | 'E' => self.parse_exponent(positive, significand, exponent)
        _ => self.f64_from_parts(positive, significand, exponent)
      }
    }
    self.index += 1
    significand = significand * 10 + digit
    exponent_after_decimal_point -= 1
  }
  // Error if there is not at least one digit after the decimal point.
  if exponent_after_decimal_point == 0 {
    if self.peek() < 0 {
      raise self.peek_error("EOF while parsing a value")
    }
    raise self.peek_error("invalid number")
  }
  let exponent = exponent_before_decimal_point + exponent_after_decimal_point
  match self.peek() {
    'e' | 'E' => self.parse_exponent(positive, significand, exponent)
    _ => self.f64_from_parts(positive, significand, exponent)
  }
}

///|
fn Parser::parse_exponent(
  self : Parser,
  positive : Bool,
  significand : UInt64,
  starting_exp : Int,
) -> Double raise ParseError {
  self.index += 1 // 'e' | 'E'
  let positive_exp = match self.peek() {
    '+' => {
      self.index += 1
      true
    }
    '-' => {
      self.index += 1
      false
    }
    _ => true
  }
  let next = self.next_char()
  if next < 0 {
    raise self.error("EOF while parsing a value")
  }
  // Make sure a digit follows the exponent place.
  if !(next is ('0'..='9')) {
    raise self.error("invalid number")
  }
  let mut exp = next - '0'
  let int_max = 2147483647
  while self.peek() is ('0'..='9') {
    let digit = self.peek() - '0'
    self.index += 1
    if exp >= int_max / 10 && (exp > int_max / 10 || digit > int_max % 10) {
      // parse_exponent_overflow: error instead of +/- infinity.
      if significand != 0UL && positive_exp {
        raise self.error("number out of range")
      }
      while self.peek() is ('0'..='9') {
        self.index += 1
      }
      return if positive { 0.0 } else { -0.0 }
    }
    exp = exp * 10 + digit
  }
  let final_exp = if positive_exp {
    saturating_add(starting_exp, exp)
  } else {
    saturating_add(starting_exp, -exp)
  }
  self.f64_from_parts(positive, significand, final_exp)
}

///|
fn saturating_add(a : Int, b : Int) -> Int {
  let r = a.to_int64() + b.to_int64()
  if r > 2147483647L {
    2147483647
  } else if r < -2147483648L {
    -2147483648
  } else {
    r.to_int()
  }
}

///|
/// serde_json's non-`float_roundtrip` float assembly (de.rs `f64_from_parts`).
/// Note: this is not always correctly rounded, exactly like serde_json.
fn Parser::f64_from_parts(
  self : Parser,
  positive : Bool,
  significand : UInt64,
  exponent : Int,
) -> Double raise ParseError {
  let mut f = significand.to_double()
  let mut exponent = exponent
  for ;; {
    // `exponent.wrapping_abs() as usize`
    let idx = if exponent == -2147483648 { -1 } else { exponent.abs() }
    if idx >= 0 && idx < pow10.length() {
      if exponent >= 0 {
        f = f * pow10[idx]
        if f.is_inf() {
          raise self.error("number out of range")
        }
      } else {
        f = f / pow10[idx]
      }
      break
    }
    if f == 0.0 {
      break
    }
    if exponent >= 0 {
      raise self.error("number out of range")
    }
    f = f / 1.0e308
    exponent += 308
  }
  if positive {
    f
  } else {
    -f
  }
}

///|
fn Parser::parse_long_integer(
  self : Parser,
  positive : Bool,
  significand : UInt64,
) -> Double raise ParseError {
  let mut exponent = 0
  for ;; {
    match self.peek() {
      '0'..='9' => {
        self.index += 1
        exponent += 1
      }
      '.' => break self.parse_decimal(positive, significand, exponent)
      'e' | 'E' => break self.parse_exponent(positive, significand, exponent)
      _ => break self.f64_from_parts(positive, significand, exponent)
    }
  }
}

///|
/// Parse JSON text exactly like `serde_json::from_str::<Value>`, including
/// its error messages and positions.
pub fn parse(text : StringView) -> Value raise ParseError {
  let p = Parser::{
    src: @utf8.encode(text),
    index: 0,
    remaining_depth: recursion_limit,
  }
  let v = p.parse_value()
  // Deserializer::end
  if p.parse_whitespace() >= 0 {
    raise p.peek_error("trailing characters")
  }
  v
}
