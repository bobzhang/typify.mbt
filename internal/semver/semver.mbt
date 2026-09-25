// A port of the parts of the `semver` crate (1.0) that typify uses:
// `Version::parse`, `VersionReq::parse` and `VersionReq::matches`.

///|
pub suberror SemverError {
  SemverError(String)
} derive(Debug)

///|
pub struct Version {
  major : UInt64
  minor : UInt64
  patch : UInt64
  /// Dot-separated pre-release identifiers ("" when absent).
  pre : String
} derive(Debug, Eq)

///|
priv enum Op {
  Exact
  Greater
  GreaterEq
  Less
  LessEq
  Tilde
  Caret
  Wildcard
}

///|
priv struct Comparator {
  op : Op
  major : UInt64
  minor : UInt64?
  patch : UInt64?
  pre : String
}

///|
pub struct VersionReq {
  priv comparators : Array[Comparator]
}

///|
/// Cursor over the ASCII-oriented input.
priv struct Input {
  s : String
  mut pos : Int
}

///|
fn Input::peek(self : Input) -> Int {
  if self.pos < self.s.length() {
    self.s[self.pos].to_int()
  } else {
    -1
  }
}

///|
fn Input::eat(self : Input, c : Char) -> Bool {
  if self.peek() == c.to_int() {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Input::skip_spaces(self : Input) -> Unit {
  while self.peek() == ' '.to_int() {
    self.pos += 1
  }
}

///|
fn Input::at_end(self : Input) -> Bool {
  self.pos >= self.s.length()
}

///|
fn numeric_identifier(input : Input, what : String) -> UInt64 raise SemverError {
  let start = input.pos
  let mut value = 0UL
  while input.peek() >= '0'.to_int() && input.peek() <= '9'.to_int() {
    if value == 0UL && input.pos > start {
      raise SemverError("invalid leading zero in \{what} version number")
    }
    let d = (input.peek() - '0'.to_int()).to_uint64()
    if value > (0xFFFF_FFFF_FFFF_FFFFUL - d) / 10UL {
      raise SemverError("value of \{what} version number exceeds u64::MAX")
    }
    value = value * 10UL + d
    input.pos += 1
  }
  if input.pos == start {
    if input.at_end() {
      raise SemverError(
        "unexpected end of input while parsing \{what} version number",
      )
    }
    raise SemverError(
      "unexpected character while parsing \{what} version number",
    )
  }
  value
}

///|
/// Parse dot-separated identifiers of `[0-9A-Za-z-]`; returns "" when the
/// input does not start with one.
fn identifier(input : Input, is_pre : Bool) -> String raise SemverError {
  let start = input.pos
  for ;; {
    let seg_start = input.pos
    let mut has_nondigit = false
    for ;; {
      let c = input.peek()
      if (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
        (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
        c == '-'.to_int() {
        has_nondigit = true
        input.pos += 1
      } else if c >= '0'.to_int() && c <= '9'.to_int() {
        input.pos += 1
      } else {
        break
      }
    }
    let seg_len = input.pos - seg_start
    if seg_len == 0 {
      if seg_start == start && input.peek() != '.'.to_int() {
        return ""
      }
      raise SemverError("empty identifier segment")
    }
    if is_pre && seg_len > 1 && !has_nondigit && input.s[seg_start] == '0' {
      raise SemverError("invalid leading zero in pre-release identifier")
    }
    if !input.eat('.') {
      break
    }
  }
  input.s.unsafe_substring(start~, end=input.pos)
}

///|
/// `semver::Version::parse`.
pub fn Version::parse(text : String) -> Version raise SemverError {
  if text == "" {
    raise SemverError("empty string, expected a semver version")
  }
  let input = { s: text, pos: 0, }
  let major = numeric_identifier(input, "major")
  if !input.eat('.') {
    raise SemverError("unexpected character after major version number")
  }
  let minor = numeric_identifier(input, "minor")
  if !input.eat('.') {
    raise SemverError("unexpected character after minor version number")
  }
  let patch = numeric_identifier(input, "patch")
  let mut pre = ""
  if input.eat('-') {
    pre = identifier(input, true)
    if pre == "" {
      raise SemverError("empty identifier segment in pre-release identifier")
    }
  }
  if input.eat('+') {
    if identifier(input, false) == "" {
      raise SemverError("empty identifier segment in build metadata")
    }
  }
  if !input.at_end() {
    raise SemverError("unexpected character after version")
  }
  { major, minor, patch, pre, }
}

///|
fn is_wildcard(c : Int) -> Bool {
  c == '*'.to_int() || c == 'x'.to_int() || c == 'X'.to_int()
}

///|
fn comparator(input : Input) -> Comparator raise SemverError {
  let before = input.pos
  let mut op : Op = if input.eat('=') {
    Exact
  } else if input.eat('>') {
    if input.eat('=') {
      GreaterEq
    } else {
      Greater
    }
  } else if input.eat('<') {
    if input.eat('=') {
      LessEq
    } else {
      Less
    }
  } else if input.eat('~') {
    Tilde
  } else if input.eat('^') {
    Caret
  } else {
    Caret
  }
  let default_op = input.pos == before
  input.skip_spaces()
  let major = numeric_identifier(input, "major")
  let mut has_wildcard = false
  let mut minor = None
  if input.eat('.') {
    if is_wildcard(input.peek()) {
      input.pos += 1
      has_wildcard = true
      if default_op {
        op = Wildcard
      }
    } else {
      minor = Some(numeric_identifier(input, "minor"))
    }
  }
  let mut patch = None
  if input.eat('.') {
    if is_wildcard(input.peek()) {
      input.pos += 1
      if default_op {
        op = Wildcard
      }
    } else if has_wildcard {
      raise SemverError("unexpected character after wildcard in version req")
    } else {
      patch = Some(numeric_identifier(input, "patch"))
    }
  }
  let mut pre = ""
  if patch is Some(_) && input.eat('-') {
    pre = identifier(input, true)
    if pre == "" {
      raise SemverError("empty identifier segment in pre-release identifier")
    }
  }
  if patch is Some(_) && input.eat('+') {
    if identifier(input, false) == "" {
      raise SemverError("empty identifier segment in build metadata")
    }
  }
  input.skip_spaces()
  { op, major, minor, patch, pre, }
}

///|
/// `semver::VersionReq::parse`.
pub fn VersionReq::parse(text : String) -> VersionReq raise SemverError {
  let input = { s: text, pos: 0, }
  input.skip_spaces()
  if is_wildcard(input.peek()) {
    let save = input.pos
    input.pos += 1
    input.skip_spaces()
    if input.at_end() {
      return { comparators: [], }
    }
    if input.peek() == ','.to_int() {
      raise SemverError("wildcard req must be the only comparator")
    }
    input.pos = save
    raise SemverError("unexpected character after wildcard in version req")
  }
  let comparators = []
  for ;; {
    comparators.push(comparator(input))
    if input.at_end() {
      break
    }
    if !input.eat(',') {
      raise SemverError("expected comma after version requirement")
    }
    input.skip_spaces()
    if comparators.length() == 32 {
      raise SemverError("excessive number of version comparators")
    }
  }
  { comparators, }
}

///|
/// semver's ordering of pre-release strings ("" is a release, which sorts
/// after any pre-release).
fn compare_pre(a : String, b : String) -> Int {
  if a == b {
    return 0
  }
  if a == "" {
    return 1
  }
  if b == "" {
    return -1
  }
  let xs = a.split(".").map(v => v.to_owned()).collect()
  let ys = b.split(".").map(v => v.to_owned()).collect()
  for i, x in xs {
    guard ys.get(i) is Some(y) else { return 1 }
    let x_num = x.iter().all(c => c.is_ascii_digit())
    let y_num = y.iter().all(c => c.is_ascii_digit())
    let c = match (x_num, y_num) {
      (true, true) => {
        let l = x.length().compare(y.length())
        if l != 0 {
          l
        } else {
          ascii_compare(x, y)
        }
      }
      (true, false) => return -1
      (false, true) => return 1
      (false, false) => ascii_compare(x, y)
    }
    if c != 0 {
      return c
    }
  }
  if ys.length() > xs.length() {
    -1
  } else {
    0
  }
}

///|
fn ascii_compare(x : String, y : String) -> Int {
  for i in 0..<x.length().min(y.length()) {
    let c = x[i].to_int().compare(y[i].to_int())
    if c != 0 {
      return c
    }
  }
  x.length().compare(y.length())
}

///|
fn matches_exact(cmp : Comparator, ver : Version) -> Bool {
  if ver.major != cmp.major {
    return false
  }
  if cmp.minor is Some(minor) && ver.minor != minor {
    return false
  }
  if cmp.patch is Some(patch) && ver.patch != patch {
    return false
  }
  ver.pre == cmp.pre
}

///|
fn matches_greater(cmp : Comparator, ver : Version) -> Bool {
  if ver.major != cmp.major {
    return ver.major > cmp.major
  }
  guard cmp.minor is Some(minor) else { return false }
  if ver.minor != minor {
    return ver.minor > minor
  }
  guard cmp.patch is Some(patch) else { return false }
  if ver.patch != patch {
    return ver.patch > patch
  }
  compare_pre(ver.pre, cmp.pre) > 0
}

///|
fn matches_less(cmp : Comparator, ver : Version) -> Bool {
  if ver.major != cmp.major {
    return ver.major < cmp.major
  }
  guard cmp.minor is Some(minor) else { return false }
  if ver.minor != minor {
    return ver.minor < minor
  }
  guard cmp.patch is Some(patch) else { return false }
  if ver.patch != patch {
    return ver.patch < patch
  }
  compare_pre(ver.pre, cmp.pre) < 0
}

///|
fn matches_tilde(cmp : Comparator, ver : Version) -> Bool {
  if ver.major != cmp.major {
    return false
  }
  if cmp.minor is Some(minor) && ver.minor != minor {
    return false
  }
  if cmp.patch is Some(patch) && ver.patch != patch {
    return ver.patch > patch
  }
  compare_pre(ver.pre, cmp.pre) >= 0
}

///|
fn matches_caret(cmp : Comparator, ver : Version) -> Bool {
  if ver.major != cmp.major {
    return false
  }
  guard cmp.minor is Some(minor) else { return true }
  guard cmp.patch is Some(patch) else {
    return if cmp.major > 0UL { ver.minor >= minor } else { ver.minor == minor }
  }
  if cmp.major > 0UL {
    if ver.minor != minor {
      return ver.minor > minor
    } else if ver.patch != patch {
      return ver.patch > patch
    }
  } else if minor > 0UL {
    if ver.minor != minor {
      return false
    } else if ver.patch != patch {
      return ver.patch > patch
    }
  } else if ver.minor != minor || ver.patch != patch {
    return false
  }
  compare_pre(ver.pre, cmp.pre) >= 0
}

///|
fn matches_impl(cmp : Comparator, ver : Version) -> Bool {
  match cmp.op {
    Exact | Wildcard => matches_exact(cmp, ver)
    Greater => matches_greater(cmp, ver)
    GreaterEq => matches_exact(cmp, ver) || matches_greater(cmp, ver)
    Less => matches_less(cmp, ver)
    LessEq => matches_exact(cmp, ver) || matches_less(cmp, ver)
    Tilde => matches_tilde(cmp, ver)
    Caret => matches_caret(cmp, ver)
  }
}

///|
fn pre_is_compatible(cmp : Comparator, ver : Version) -> Bool {
  cmp.major == ver.major &&
  cmp.minor == Some(ver.minor) &&
  cmp.patch == Some(ver.patch) &&
  cmp.pre != ""
}

///|
/// `semver::VersionReq::matches`.
pub fn VersionReq::matches(self : VersionReq, ver : Version) -> Bool {
  for cmp in self.comparators {
    if !matches_impl(cmp, ver) {
      return false
    }
  }
  if ver.pre == "" {
    return true
  }
  self.comparators.iter().any(cmp => pre_is_compatible(cmp, ver))
}
