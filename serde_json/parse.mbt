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
  /// Whether the last string parsed contained an escape sequence.
  mut last_escaped : Bool
  /// Lenient mode defers errors that serde_json only reports when a value is
  /// actually visited (not skipped as an ignored field).
  lenient : Bool
  /// The first deferred error within the value being parsed.
  mut pending : ParseError?
  /// Nesting levels past the recursion limit being parsed leniently.
  mut unlimited : Int
}

///|
/// Record a deferrable error: raise in strict mode, remember in lenient mode.
fn Parser::postpone(self : Parser, e : ParseError) -> Unit raise ParseError {
  if !self.lenient {
    raise e
  }
  if self.pending is None {
    self.pending = Some(e)
  }
}

///|
fn Parser::take_pending(self : Parser) -> ParseError? {
  let p = self.pending
  self.pending = None
  p
}

///|
/// serde_json's `POW10` table (exactly rounded powers of ten).
let pow10 : ReadOnlyArray[Double] = [
  1.0e0, 1.0e1, 1.0e2, 1.0e3, 1.0e4, 1.0e5, 1.0e6, 1.0e7, 1.0e8, 1.0e9, 1.0e10, 1.0e11,
  1.0e12, 1.0e13, 1.0e14, 1.0e15, 1.0e16, 1.0e17, 1.0e18, 1.0e19, 1.0e20, 1.0e21,
  1.0e22, 1.0e23, 1.0e24, 1.0e25, 1.0e26, 1.0e27, 1.0e28, 1.0e29, 1.0e30, 1.0e31,
  1.0e32, 1.0e33, 1.0e34, 1.0e35, 1.0e36, 1.0e37, 1.0e38, 1.0e39, 1.0e40, 1.0e41,
  1.0e42, 1.0e43, 1.0e44, 1.0e45, 1.0e46, 1.0e47, 1.0e48, 1.0e49, 1.0e50, 1.0e51,
  1.0e52, 1.0e53, 1.0e54, 1.0e55, 1.0e56, 1.0e57, 1.0e58, 1.0e59, 1.0e60, 1.0e61,
  1.0e62, 1.0e63, 1.0e64, 1.0e65, 1.0e66, 1.0e67, 1.0e68, 1.0e69, 1.0e70, 1.0e71,
  1.0e72, 1.0e73, 1.0e74, 1.0e75, 1.0e76, 1.0e77, 1.0e78, 1.0e79, 1.0e80, 1.0e81,
  1.0e82, 1.0e83, 1.0e84, 1.0e85, 1.0e86, 1.0e87, 1.0e88, 1.0e89, 1.0e90, 1.0e91,
  1.0e92, 1.0e93, 1.0e94, 1.0e95, 1.0e96, 1.0e97, 1.0e98, 1.0e99, 1.0e100, 1.0e101,
  1.0e102, 1.0e103, 1.0e104, 1.0e105, 1.0e106, 1.0e107, 1.0e108, 1.0e109, 1.0e110,
  1.0e111, 1.0e112, 1.0e113, 1.0e114, 1.0e115, 1.0e116, 1.0e117, 1.0e118, 1.0e119,
  1.0e120, 1.0e121, 1.0e122, 1.0e123, 1.0e124, 1.0e125, 1.0e126, 1.0e127, 1.0e128,
  1.0e129, 1.0e130, 1.0e131, 1.0e132, 1.0e133, 1.0e134, 1.0e135, 1.0e136, 1.0e137,
  1.0e138, 1.0e139, 1.0e140, 1.0e141, 1.0e142, 1.0e143, 1.0e144, 1.0e145, 1.0e146,
  1.0e147, 1.0e148, 1.0e149, 1.0e150, 1.0e151, 1.0e152, 1.0e153, 1.0e154, 1.0e155,
  1.0e156, 1.0e157, 1.0e158, 1.0e159, 1.0e160, 1.0e161, 1.0e162, 1.0e163, 1.0e164,
  1.0e165, 1.0e166, 1.0e167, 1.0e168, 1.0e169, 1.0e170, 1.0e171, 1.0e172, 1.0e173,
  1.0e174, 1.0e175, 1.0e176, 1.0e177, 1.0e178, 1.0e179, 1.0e180, 1.0e181, 1.0e182,
  1.0e183, 1.0e184, 1.0e185, 1.0e186, 1.0e187, 1.0e188, 1.0e189, 1.0e190, 1.0e191,
  1.0e192, 1.0e193, 1.0e194, 1.0e195, 1.0e196, 1.0e197, 1.0e198, 1.0e199, 1.0e200,
  1.0e201, 1.0e202, 1.0e203, 1.0e204, 1.0e205, 1.0e206, 1.0e207, 1.0e208, 1.0e209,
  1.0e210, 1.0e211, 1.0e212, 1.0e213, 1.0e214, 1.0e215, 1.0e216, 1.0e217, 1.0e218,
  1.0e219, 1.0e220, 1.0e221, 1.0e222, 1.0e223, 1.0e224, 1.0e225, 1.0e226, 1.0e227,
  1.0e228, 1.0e229, 1.0e230, 1.0e231, 1.0e232, 1.0e233, 1.0e234, 1.0e235, 1.0e236,
  1.0e237, 1.0e238, 1.0e239, 1.0e240, 1.0e241, 1.0e242, 1.0e243, 1.0e244, 1.0e245,
  1.0e246, 1.0e247, 1.0e248, 1.0e249, 1.0e250, 1.0e251, 1.0e252, 1.0e253, 1.0e254,
  1.0e255, 1.0e256, 1.0e257, 1.0e258, 1.0e259, 1.0e260, 1.0e261, 1.0e262, 1.0e263,
  1.0e264, 1.0e265, 1.0e266, 1.0e267, 1.0e268, 1.0e269, 1.0e270, 1.0e271, 1.0e272,
  1.0e273, 1.0e274, 1.0e275, 1.0e276, 1.0e277, 1.0e278, 1.0e279, 1.0e280, 1.0e281,
  1.0e282, 1.0e283, 1.0e284, 1.0e285, 1.0e286, 1.0e287, 1.0e288, 1.0e289, 1.0e290,
  1.0e291, 1.0e292, 1.0e293, 1.0e294, 1.0e295, 1.0e296, 1.0e297, 1.0e298, 1.0e299,
  1.0e300, 1.0e301, 1.0e302, 1.0e303, 1.0e304, 1.0e305, 1.0e306, 1.0e307, 1.0e308,
]

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
/// `deserialize_any` building an ordered `Content`.
fn Parser::parse_value(self : Parser) -> Content raise ParseError {
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
      self.number_or_deferred(false)
    }
    '0'..='9' => self.number_or_deferred(true)
    '"' => {
      self.index += 1
      let s = self.parse_str()
      match self.take_pending() {
        Some(e) => Invalid(e)
        None => String(s)
      }
    }
    '[' => {
      let too_deep = self.check_recursion()
      self.index += 1
      let items = self.parse_seq()
      self.leave()
      // end_seq: the visitor only returns after peeking `]`.
      self.index += 1
      match too_deep {
        Some(e) => Invalid(e)
        None => Array(items)
      }
    }
    '{' => {
      let too_deep = self.check_recursion()
      self.index += 1
      let obj = self.parse_map()
      self.leave()
      self.index += 1
      match too_deep {
        Some(e) => Invalid(e)
        None => Object(obj)
      }
    }
    _ => raise self.peek_error("expected value")
  }
}

///|
/// Enter a nested array/object. Returns a deferred error when the recursion
/// limit is exceeded in lenient mode (the subtree is then parsed without
/// limit, as serde_json skips ignored values).
fn Parser::check_recursion(self : Parser) -> ParseError? raise ParseError {
  if self.unlimited > 0 {
    self.unlimited += 1
    return None
  }
  self.remaining_depth -= 1
  if self.remaining_depth == 0 {
    let e = self.peek_error("recursion limit exceeded")
    if !self.lenient {
      raise e
    }
    self.remaining_depth += 1
    self.unlimited = 1
    return Some(e)
  }
  None
}

///|
fn Parser::leave(self : Parser) -> Unit {
  if self.unlimited > 0 {
    self.unlimited -= 1
  } else {
    self.remaining_depth += 1
  }
}

///|
/// `SeqAccess::next_element_seed` driven to completion. Leaves the closing
/// `]` unconsumed.
fn Parser::parse_seq(self : Parser) -> Array[Content] raise ParseError {
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
fn Parser::parse_map(self : Parser) -> Array[Entry] raise ParseError {
  let obj = []
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
    let key_escaped = self.last_escaped
    let key_error = self.take_pending()
    // parse_object_colon
    match self.parse_whitespace() {
      ':' => self.index += 1
      -1 => raise self.peek_error("EOF while parsing an object")
      _ => raise self.peek_error("expected `:`")
    }
    // Entries keep their order and duplicates.
    obj.push({ key, key_escaped, key_error, value: self.parse_value(), })
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
        self.postpone(self.error("lone leading surrogate in hex escape"))
        return
      }
      if n < 0xD800 || n > 0xDBFF {
        push_utf8(buf, n)
        return
      }
      // A leading surrogate must be followed by `\u` + trailing surrogate.
      // (When skipping, serde_json does not pair surrogates at all.)
      match self.peek() {
        -1 => raise self.error("EOF while parsing a string")
        '\\' => self.index += 1
        _ => {
          self.index += 1
          let e = self.error("unexpected end of hex escape")
          self.index -= 1
          self.postpone(e)
          return
        }
      }
      match self.peek() {
        -1 => raise self.error("EOF while parsing a string")
        'u' => self.index += 1
        _ => {
          self.index += 1
          let e = self.error("unexpected end of hex escape")
          // Resume at the backslash: it starts an ordinary escape.
          self.index -= 2
          self.postpone(e)
          return
        }
      }
      let n2 = self.decode_hex_escape()
      if n2 < 0xDC00 || n2 > 0xDFFF {
        self.postpone(self.error("lone leading surrogate in hex escape"))
        return
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
  self.last_escaped = false
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
        self.last_escaped = true
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
/// Parse a number; in lenient mode an out-of-range number becomes a deferred
/// error after validating its syntax like serde_json's `ignore_number`.
fn Parser::number_or_deferred(
  self : Parser,
  positive : Bool,
) -> Content raise ParseError {
  let start = self.index
  try self.parse_integer(positive) catch {
    ParseError(message="number out of range", ..) as e if self.lenient => {
      self.index = start
      self.ignore_number()
      Invalid(e)
    }
    e => raise e
  } noraise {
    n => Number(n)
  }
}

///|
/// serde_json's `ignore_integer` / `ignore_decimal` / `ignore_exponent`:
/// syntax only.
fn Parser::ignore_number(self : Parser) -> Unit raise ParseError {
  match self.next_char() {
    '0' =>
      if self.peek() is ('0'..='9') {
        raise self.peek_error("invalid number")
      }
    '1'..='9' =>
      while self.peek() is ('0'..='9') {
        self.index += 1
      }
    -1 => raise self.error("EOF while parsing a value")
    _ => raise self.error("invalid number")
  }
  if self.peek() == '.' {
    self.index += 1
    let mut digits = 0
    while self.peek() is ('0'..='9') {
      self.index += 1
      digits += 1
    }
    if digits == 0 {
      if self.peek() < 0 {
        raise self.peek_error("EOF while parsing a value")
      }
      raise self.peek_error("invalid number")
    }
  }
  if self.peek() is ('e' | 'E') {
    self.index += 1
    if self.peek() is ('+' | '-') {
      self.index += 1
    }
    match self.next_char() {
      '0'..='9' => ()
      -1 => raise self.error("EOF while parsing a value")
      _ => raise self.error("invalid number")
    }
    while self.peek() is ('0'..='9') {
      self.index += 1
    }
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
  parse_content(text).to_value()
}

///|
/// Parse JSON text into an ordered document that keeps duplicate keys,
/// number classes and key-escape information (serde's `Content` view of the
/// input).
pub fn parse_content(
  text : StringView,
  lenient? : Bool = false,
) -> Content raise ParseError {
  let p = Parser::{
    src: @utf8.encode(text),
    index: 0,
    remaining_depth: recursion_limit,
    last_escaped: false,
    lenient,
    pending: None,
    unlimited: 0,
  }
  let v = p.parse_value()
  // Deserializer::end
  if p.parse_whitespace() >= 0 {
    raise p.peek_error("trailing characters")
  }
  v
}
