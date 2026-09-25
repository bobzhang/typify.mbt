// A port of regress 0.12's parser (src/parse.rs) for the default flags:
// non-Unicode ("Annex B") syntax, with `(?ims-ims:...)` modifier groups.
// Error texts match regress exactly.

///|
let max_capture_groups : Int = 65535

///|
let max_loops : Int = 65535

///|
let max_nesting_depth : Int = 256

///|
priv struct Flags {
  icase : Bool
  multiline : Bool
  dot_all : Bool
}

///|
priv struct Parser {
  input : Array[Int]
  mut pos : Int
  mut flags : Flags
  mut loop_count : Int
  mut group_count : Int
  mut group_count_max : Int
  /// Group name -> 0-based group indices, in order.
  named_group_indices : Map[String, Array[Int]]
  mut depth : Int
}

///|
fn syntax_error(text : String) -> RegexError {
  RegexError(text)
}

///|
fn Parser::peek(self : Parser) -> Int? {
  self.input.get(self.pos)
}

///|
fn Parser::next(self : Parser) -> Int? {
  let c = self.input.get(self.pos)
  if c is Some(_) {
    self.pos += 1
  }
  c
}

///|
fn Parser::try_consume(self : Parser, c : Char) -> Bool {
  if self.peek() == Some(c.to_int()) {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Parser::try_consume_str(self : Parser, s : String) -> Bool {
  let save = self.pos
  for c in s {
    if self.next() != Some(c.to_int()) {
      self.pos = save
      return false
    }
  }
  true
}

///|
fn Parser::char_node(self : Parser, c : Int) -> Node {
  Char(c, icase=self.flags.icase)
}

///|
fn is_ascii_digit(c : Int) -> Bool {
  c >= '0'.to_int() && c <= '9'.to_int()
}

///|
fn is_ascii_alpha(c : Int) -> Bool {
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int())
}

///|
fn hex_value(c : Int) -> Int? {
  if c >= '0'.to_int() && c <= '9'.to_int() {
    Some(c - '0'.to_int())
  } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
    Some(c - 'a'.to_int() + 10)
  } else if c >= 'A'.to_int() && c <= 'F'.to_int() {
    Some(c - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Rust's `u32::from_str_radix(s, 16)`: an optional leading `+`, then at
/// least one hex digit. Returns `None` on overflow of `limit`.
fn parse_hex(digits : Array[Int], limit : Int64) -> Int64? {
  let mut i = 0
  if digits.length() > 0 && digits[0] == '+'.to_int() {
    i = 1
  }
  if i >= digits.length() {
    return None
  }
  let mut v = 0L
  for j in i..<digits.length() {
    guard hex_value(digits[j]) is Some(d) else { return None }
    v = v * 16L + d.to_int64()
    if v > limit {
      return None
    }
  }
  Some(v)
}

///|
fn Parser::try_parse(self : Parser) -> Node raise RegexError {
  self.parse_capture_groups()
  let body = self.consume_disjunction()
  match self.peek() {
    Some(c) if c == ')'.to_int() => raise syntax_error("Unbalanced parenthesis")
    Some(c) => {
      let s = if c >= 0xD800 && c <= 0xDFFF {
        let hex = c.to_string(radix=16).to_upper()
        "\\u\{hex}"
      } else {
        c.unsafe_to_char().to_string()
      }
      raise syntax_error("Unexpected char: \{s}")
    }
    None => body
  }
}

///|
/// ES6 21.2.2.3 Disjunction.
fn Parser::consume_disjunction(self : Parser) -> Node raise RegexError {
  self.depth += 1
  if self.depth > max_nesting_depth {
    raise syntax_error("Regular expression is too deeply nested")
  }
  let terms = [self.consume_term()]
  while self.try_consume('|') {
    terms.push(self.consume_term())
  }
  self.depth -= 1
  make_alt(terms)
}

///|
/// ES6 21.2.2.5 Term (a sequence of atoms with optional quantifiers).
fn Parser::consume_term(self : Parser) -> Node raise RegexError {
  let result : Array[Node] = []
  for ;; {
    let start_group = self.group_count
    let mut start_offset = result.length()
    let mut quantifier_allowed = true
    guard self.peek() is Some(c) else { break }
    match c.unsafe_to_char() {
      ')' | '|' => break
      '^' => {
        self.pos += 1
        result.push(StartAnchor(multiline=self.flags.multiline))
        quantifier_allowed = false
      }
      '$' => {
        self.pos += 1
        result.push(EndAnchor(multiline=self.flags.multiline))
        quantifier_allowed = false
      }
      '\\' => {
        self.pos += 1
        guard self.peek() is Some(e) else {
          raise syntax_error("Incomplete escape")
        }
        if e == 'b'.to_int() {
          self.pos += 1
          result.push(WordBoundary(invert=false))
        } else if e == 'B'.to_int() {
          self.pos += 1
          result.push(WordBoundary(invert=true))
        } else if e == 'c'.to_int() {
          self.pos += 1
          match self.peek() {
            Some(l) if is_ascii_alpha(l) => {
              self.pos += 1
              result.push(self.char_node(l % 32))
            }
            _ => {
              start_offset += 1
              result.push(self.char_node('\\'.to_int()))
              result.push(self.char_node('c'.to_int()))
            }
          }
        } else {
          result.push(self.consume_atom_escape())
        }
      }
      '.' => {
        self.pos += 1
        result.push(AnyChar(dot_all=self.flags.dot_all))
      }
      '(' => {
        if self.try_consume_str("(?=") {
          result.push(self.consume_lookaround(negate=false, backwards=false))
        } else if self.try_consume_str("(?!") {
          result.push(self.consume_lookaround(negate=true, backwards=false))
        } else if self.try_consume_str("(?<=") {
          quantifier_allowed = false
          result.push(self.consume_lookaround(negate=false, backwards=true))
        } else if self.try_consume_str("(?<!") {
          quantifier_allowed = false
          result.push(self.consume_lookaround(negate=true, backwards=true))
        } else if self.try_consume_str("(?:") {
          result.push(self.consume_disjunction())
        } else if self.try_consume_modifier_group() is Some(group) {
          result.push(group)
        } else {
          // Capturing group.
          self.pos += 1
          let group = self.group_count
          if self.group_count >= max_capture_groups {
            raise syntax_error("Capture group count limit exceeded")
          }
          self.group_count += 1
          if self.try_consume('?') {
            if self.try_consume_named_capture_group_name() is None {
              raise syntax_error(
                "Invalid token at named capture group identifier",
              )
            }
          }
          let contents = self.consume_disjunction()
          result.push(Group(group, contents))
        }
        if !self.try_consume(')') {
          raise syntax_error("Unbalanced parenthesis")
        }
      }
      '[' => result.push(self.consume_bracket())
      '{' => {
        let save = self.pos
        if self.try_consume_braced_quantifier() is Some(_) {
          raise syntax_error("Invalid braced quantifier")
        }
        self.pos = save + 1
        result.push(self.char_node(c))
      }
      '*' | '+' | '?' => raise syntax_error("Invalid atom character")
      _ => {
        self.pos += 1
        result.push(self.char_node(c))
      }
    }
    // We just parsed a term; try parsing a quantifier.
    if self.try_consume_quantifier() is Some((min, max, greedy)) {
      if !quantifier_allowed {
        raise syntax_error("Quantifier not allowed here")
      }
      if max is Some(max) && min > max {
        raise syntax_error("Invalid quantifier")
      }
      let quantifee = result[start_offset:].to_owned()
      while result.length() > start_offset {
        ignore(result.pop())
      }
      if self.loop_count >= max_loops {
        raise syntax_error("Loop count limit exceeded")
      }
      self.loop_count += 1
      result.push(
        Loop(
          make_cat(quantifee),
          min~,
          max~,
          greedy~,
          first_group=start_group,
          end_group=self.group_count,
        ),
      )
    }
  }
  make_cat(result)
}

///|
fn Parser::consume_lookaround(
  self : Parser,
  negate~ : Bool,
  backwards~ : Bool,
) -> Node raise RegexError {
  let contents = self.consume_disjunction()
  Look(contents, negate~, backwards~)
}

///|
/// `(?ims-ims:...)`. Returns `None` (consuming nothing) if the input does not
/// start a modifier group.
fn Parser::try_consume_modifier_group(self : Parser) -> Node? raise RegexError {
  let mut cursor = self.pos
  if self.input.get(cursor) != Some('('.to_int()) {
    return None
  }
  cursor += 1
  if self.input.get(cursor) != Some('?'.to_int()) {
    return None
  }
  cursor += 1
  guard self.input.get(cursor) is Some(first) else { return None }
  cursor += 1
  if first == '<'.to_int() {
    return None
  }
  let mut current = first
  let mut seen_hyphen = false
  let mut saw_flag = false
  let mut icase : Bool? = None
  let mut multiline : Bool? = None
  let mut dot_all : Bool? = None
  for ;; {
    match current.unsafe_to_char() {
      'i' => {
        if icase is Some(_) {
          raise syntax_error("Invalid group modifier")
        }
        icase = Some(!seen_hyphen)
        saw_flag = true
      }
      'm' => {
        if multiline is Some(_) {
          raise syntax_error("Invalid group modifier")
        }
        multiline = Some(!seen_hyphen)
        saw_flag = true
      }
      's' => {
        if dot_all is Some(_) {
          raise syntax_error("Invalid group modifier")
        }
        dot_all = Some(!seen_hyphen)
        saw_flag = true
      }
      '-' => {
        if seen_hyphen {
          raise syntax_error("Invalid group modifier")
        }
        seen_hyphen = true
      }
      ':' => {
        if !saw_flag {
          raise syntax_error("Invalid group modifier")
        }
        self.pos = cursor
        let flags = {
          icase: icase.unwrap_or(self.flags.icase),
          multiline: multiline.unwrap_or(self.flags.multiline),
          dot_all: dot_all.unwrap_or(self.flags.dot_all),
        }
        return Some(self.consume_disjunction_with(flags))
      }
      _ => raise syntax_error("Invalid group modifier")
    }
    guard self.input.get(cursor) is Some(next) else {
      raise syntax_error("Invalid group modifier")
    }
    cursor += 1
    current = next
  }
}

///|
/// Parse a disjunction with `flags` in effect, restoring the outer flags.
fn Parser::consume_disjunction_with(
  self : Parser,
  flags : Flags,
) -> Node raise RegexError {
  let saved = self.flags
  self.flags = flags
  defer {
    self.flags = saved
  }
  self.consume_disjunction()
}

///|
priv enum ClassAtom {
  CodePoint(Int)
  Class(ClassType, positive~ : Bool)
}

///|
fn add_class_atom(set : CharSet, atom : ClassAtom) -> Unit {
  match atom {
    CodePoint(c) => set.add_one(c)
    Class(ct, positive~) => set.add_set(ct.codepoints(positive))
  }
}

///|
/// ES6 21.2.2.13 CharacterClass.
fn Parser::consume_bracket(self : Parser) -> Node raise RegexError {
  self.pos += 1 // '['
  let invert = self.try_consume('^')
  let set = CharSet::new()
  for ;; {
    match self.peek() {
      None => raise syntax_error("Unbalanced bracket")
      Some(c) if c == ']'.to_int() => {
        self.pos += 1
        return Bracket(set, invert~, icase=self.flags.icase)
      }
      _ => ()
    }
    guard self.try_consume_bracket_class_atom() is Some(first) else { continue }
    if !self.try_consume('-') {
      add_class_atom(set, first)
      continue
    }
    guard self.try_consume_bracket_class_atom() is Some(second) else {
      // No second atom, e.g. [a-].
      add_class_atom(set, first)
      set.add_one('-'.to_int())
      continue
    }
    if (first, second) is (CodePoint(c1), CodePoint(c2)) {
      if c1 > c2 {
        raise syntax_error(
          "Range values reversed, start char code is greater than end char code.",
        )
      }
      set.add(c1, c2)
      continue
    }
    // Not a range: treat as individual atoms.
    add_class_atom(set, first)
    set.add_one('-'.to_int())
    add_class_atom(set, second)
  }
}

///|
fn Parser::try_consume_bracket_class_atom(
  self : Parser,
) -> ClassAtom? raise RegexError {
  guard self.peek() is Some(c) else { return None }
  if c == ']'.to_int() {
    return None
  }
  if c != '\\'.to_int() {
    self.pos += 1
    return Some(CodePoint(c))
  }
  self.pos += 1
  guard self.peek() is Some(ec) else {
    raise syntax_error("Unterminated escape")
  }
  match ec.unsafe_to_char() {
    'b' => {
      self.pos += 1
      Some(CodePoint(0x08))
    }
    'c' => {
      let save = self.pos
      self.pos += 1
      match self.peek() {
        Some(n) if is_ascii_digit(n) || n == '_'.to_int() => {
          self.pos += 1
          Some(CodePoint(n & 0x1F))
        }
        Some(n) if is_ascii_alpha(n) => {
          self.pos += 1
          Some(CodePoint(n % 32))
        }
        _ => {
          self.pos = save
          Some(CodePoint('\\'.to_int()))
        }
      }
    }
    'd' => {
      self.pos += 1
      Some(Class(Digits, positive=true))
    }
    'D' => {
      self.pos += 1
      Some(Class(Digits, positive=false))
    }
    's' => {
      self.pos += 1
      Some(Class(Spaces, positive=true))
    }
    'S' => {
      self.pos += 1
      Some(Class(Spaces, positive=false))
    }
    'w' => {
      self.pos += 1
      Some(Class(Words, positive=true))
    }
    'W' => {
      self.pos += 1
      Some(Class(Words, positive=false))
    }
    _ => Some(CodePoint(self.consume_character_escape()))
  }
}

///|
fn Parser::try_consume_quantifier(self : Parser) -> (Int, Int?, Bool)? {
  guard self.peek() is Some(c) else { return None }
  let quant = match c.unsafe_to_char() {
    '+' => {
      self.pos += 1
      Some((1, None))
    }
    '*' => {
      self.pos += 1
      Some((0, None))
    }
    '?' => {
      self.pos += 1
      Some((0, Some(1)))
    }
    '{' => self.try_consume_braced_quantifier()
    _ => None
  }
  guard quant is Some((min, max)) else { return None }
  let greedy = !self.try_consume('?')
  Some((min, max, greedy))
}

///|
fn Parser::try_consume_braced_quantifier(self : Parser) -> (Int, Int?)? {
  let save = self.pos
  self.pos += 1 // '{'
  guard self.try_consume_decimal_integer_literal() is Some(min) else {
    self.pos = save
    return None
  }
  let mut max = Some(min)
  if self.try_consume(',') {
    max = self.try_consume_decimal_integer_literal()
  }
  if !self.try_consume('}') {
    self.pos = save
    return None
  }
  Some((min, max))
}

///|
/// Saturating decimal literal (all digits are consumed).
fn Parser::try_consume_decimal_integer_literal(self : Parser) -> Int? {
  let limit = 2147483647
  let mut result = 0
  let mut count = 0
  while self.peek() is Some(c) && is_ascii_digit(c) {
    self.pos += 1
    count += 1
    let d = c - '0'.to_int()
    result = if result > (limit - d) / 10 { limit } else { result * 10 + d }
  }
  if count > 0 {
    Some(result)
  } else {
    None
  }
}

///|
fn Parser::consume_character_escape(self : Parser) -> Int raise RegexError {
  guard self.next() is Some(c) else { raise syntax_error("Incomplete escape") }
  match c.unsafe_to_char() {
    'f' => 0x0C
    'n' => 0x0A
    'r' => 0x0D
    't' => 0x09
    'v' => 0x0B
    'c' =>
      match self.next() {
        Some(n) if is_ascii_alpha(n) => n % 32
        _ => raise syntax_error("Invalid character escape")
      }
    '0' if !(self.peek() is Some(n) && is_ascii_digit(n)) => 0
    'x' => {
      let save = self.pos
      let x1 = self.next().bind(hex_value)
      let x2 = self.next().bind(hex_value)
      match (x1, x2) {
        (Some(a), Some(b)) => a * 16 + b
        _ => {
          self.pos = save
          c
        }
      }
    }
    'u' =>
      match self.try_escape_unicode_sequence() {
        Some(u) => u
        None => c
      }
    '0'..='7' => {
      let d = c - '0'.to_int()
      guard self.peek() is Some(c1) else { return d }
      let d1 = c1 - '0'.to_int()
      if c == '0'.to_int() && (c1 == '8'.to_int() || c1 == '9'.to_int()) {
        0
      } else if !(d1 >= 0 && d1 <= 7) {
        d
      } else if d >= 4 {
        self.pos += 1
        d * 8 + d1
      } else {
        self.pos += 1
        match self.peek() {
          Some(c2) if c2 >= '0'.to_int() && c2 <= '7'.to_int() => {
            self.pos += 1
            d * 64 + d1 * 8 + (c2 - '0'.to_int())
          }
          _ => d * 8 + d1
        }
      }
    }
    // IdentityEscape (syntax characters and, in Annex B, anything else).
    _ => c
  }
}

///|
fn Parser::consume_atom_escape(self : Parser) -> Node raise RegexError {
  guard self.peek() is Some(c) else { raise syntax_error("Incomplete escape") }
  match c.unsafe_to_char() {
    'd' | 'D' => {
      self.pos += 1
      Bracket(
        Digits.codepoints(c == 'd'.to_int()),
        invert=false,
        icase=self.flags.icase,
      )
    }
    's' | 'S' => {
      self.pos += 1
      Bracket(
        Spaces.codepoints(c == 's'.to_int()),
        invert=false,
        icase=self.flags.icase,
      )
    }
    'w' | 'W' => {
      self.pos += 1
      Bracket(
        Words.codepoints(c == 'w'.to_int()),
        invert=false,
        icase=self.flags.icase,
      )
    }
    '1'..='9' => {
      // A backreference if the group exists, else a legacy octal or
      // identity escape.
      let save = self.pos
      let group = self.try_consume_decimal_integer_literal().unwrap()
      if group <= self.group_count_max {
        BackRef(group, icase=self.flags.icase)
      } else {
        self.pos = save
        self.char_node(self.consume_character_escape())
      }
    }
    'k' if !self.named_group_indices.is_empty() => {
      self.pos += 1
      guard self.try_consume_named_capture_group_name() is Some(name) else {
        raise syntax_error("Invalid named backreference syntax")
      }
      guard self.named_group_indices.get(name) is Some(indices) else {
        raise syntax_error(
          "Backreference to invalid named capture group: \{name}",
        )
      }
      make_alt(indices.map(i => BackRef(i + 1, icase=self.flags.icase)))
    }
    'k' => {
      self.pos += 1
      self.char_node(c)
    }
    _ => self.char_node(self.consume_character_escape())
  }
}

///|
/// `\u{X...}` or `\uXXXX` (with surrogate-pair joining). On failure the input
/// is restored and `None` returned.
fn Parser::try_escape_unicode_sequence(self : Parser) -> Int? {
  let orig = self.pos
  if self.try_consume('{') {
    let digits = []
    for ;; {
      match self.next() {
        Some(c) if c == '}'.to_int() => break
        Some(c) if c >= 0xD800 && c <= 0xDFFF => {
          self.pos = orig
          return None
        }
        Some(c) => digits.push(c)
        None => {
          self.pos = orig
          return None
        }
      }
    }
    match parse_hex(digits, 0xFFFF_FFFFL) {
      Some(u) if u <= 0x10FFFFL => Some(u.to_int())
      _ => {
        self.pos = orig
        None
      }
    }
  } else {
    let digits = []
    for _ in 0..<4 {
      match self.next() {
        Some(c) if !(c >= 0xD800 && c <= 0xDFFF) => digits.push(c)
        _ => {
          self.pos = orig
          return None
        }
      }
    }
    guard parse_hex(digits, 0xFFFFL) is Some(u) else {
      self.pos = orig
      return None
    }
    let u = u.to_int()
    if u >= 0xD800 && u <= 0xDBFF {
      // A high surrogate: try to join with a following `\uXXXX` low surrogate.
      if !self.try_consume_str("\\u") {
        return Some(u)
      }
      let after = self.pos
      let low = []
      for _ in 0..<4 {
        match self.next() {
          Some(c) if !(c >= 0xD800 && c <= 0xDFFF) => low.push(c)
          _ => {
            self.pos = after
            return Some(u)
          }
        }
      }
      match parse_hex(low, 0xFFFFL) {
        Some(uu) if uu >= 0xDC00L && uu <= 0xDFFFL =>
          Some(0x10000 + ((u - 0xD800) << 10) + (uu.to_int() - 0xDC00))
        _ => {
          self.pos = after
          Some(u)
        }
      }
    } else {
      Some(u)
    }
  }
}

///|
fn is_group_name_start(c : Int) -> Bool {
  c == '$'.to_int() ||
  c == '_'.to_int() ||
  (c >= 0 && c <= 0x10FFFF && @unicode.is_xid_start(c.unsafe_to_char()))
}

///|
fn is_group_name_continue(c : Int) -> Bool {
  c == '$'.to_int() ||
  c == '_'.to_int() ||
  c == 0x200C ||
  c == 0x200D ||
  (c >= 0 && c <= 0x10FFFF && @unicode.is_xid_continue(c.unsafe_to_char()))
}

///|
/// `<name>`; restores the input (after `<`) and returns `None` on failure.
fn Parser::try_consume_named_capture_group_name(self : Parser) -> String? {
  if !self.try_consume('<') {
    return None
  }
  let orig = self.pos
  let name = StringBuilder()
  let mut first = true
  for ;; {
    guard self.next() is Some(c0) else {
      self.pos = orig
      return None
    }
    let mut c = c0
    if c == '\\'.to_int() && self.try_consume('u') {
      match self.try_escape_unicode_sequence() {
        Some(e) if !(e >= 0xD800 && e <= 0xDFFF) => c = e
        _ => {
          self.pos = orig
          return None
        }
      }
    }
    if first {
      if !is_group_name_start(c) {
        self.pos = orig
        return None
      }
      first = false
    } else {
      if c == '>'.to_int() {
        break
      }
      if !is_group_name_continue(c) {
        self.pos = orig
        return None
      }
    }
    name.write_char(c.unsafe_to_char())
  }
  Some(name.to_string())
}

///|
/// Pre-pass counting capture groups and collecting group names, rejecting
/// duplicate names within the same alternative.
fn Parser::parse_capture_groups(self : Parser) -> Unit raise RegexError {
  let orig = self.pos
  let mut paren_depth = 0
  let alt_indices : Map[Int, Int] = { 0: 0 }
  let locations : Map[String, Array[Array[(Int, Int)]]] = Map([])
  for ;; {
    guard self.next() is Some(c) else { break }
    match c.unsafe_to_char() {
      '\\' => ignore(self.next())
      '[' =>
        for ;; {
          match self.next() {
            Some(d) if d == '\\'.to_int() => ignore(self.next())
            Some(d) if d == ']'.to_int() => break
            Some(_) => continue
            None => break
          }
        }
      '(' => {
        let (is_capturing, group_name) = if self.try_consume('?') {
          let name = self.try_consume_named_capture_group_name()
          (name is Some(_), name)
        } else {
          (true, None)
        }
        if group_name is Some(name) {
          let segments = []
          for d in 0..<=paren_depth {
            segments.push((d, alt_indices.get(d).unwrap_or(0)))
          }
          match locations.get(name) {
            Some(paths) => paths.push(segments)
            None => locations[name] = [segments]
          }
          match self.named_group_indices.get(name) {
            Some(indices) => indices.push(self.group_count_max)
            None => self.named_group_indices[name] = [self.group_count_max]
          }
        }
        if is_capturing {
          self.group_count_max = (self.group_count_max + 1).min(
            max_capture_groups,
          )
        }
        paren_depth += 1
        alt_indices[paren_depth] = 0
      }
      ')' =>
        if paren_depth > 0 {
          alt_indices.remove(paren_depth)
          paren_depth -= 1
        }
      '|' =>
        alt_indices[paren_depth] = alt_indices.get(paren_depth).unwrap_or(0) + 1
      _ => ()
    }
  }
  // Two uses of a name conflict if one path is a prefix of the other.
  for _, paths in locations {
    for i in 0..<paths.length() {
      for j in (i + 1)..<paths.length() {
        let a = paths[i]
        let b = paths[j]
        let n = a.length().min(b.length())
        let conflict = for k in 0..<n {
          if a[k] != b[k] {
            break false
          }
        } nobreak {
          true
        }
        if conflict {
          raise syntax_error("Duplicate capture group name")
        }
      }
    }
  }
  self.pos = orig
}
