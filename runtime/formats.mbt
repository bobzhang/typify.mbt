// String-formatted types with the serde behaviour of the Rust types typify
// uses: `uuid::Uuid`, `chrono::NaiveDate`, `chrono::DateTime<Utc>` and
// `std::net::{IpAddr, Ipv4Addr, Ipv6Addr}`.

///|
fn is_hex(c : Char) -> Bool {
  c.is_ascii_digit() || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn hex_val(c : Char) -> Int {
  if c.is_ascii_digit() {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else {
    c.to_int() - 'A'.to_int() + 10
  }
}

// ---------------------------------------------------------------------------
// UUID

///|
/// A UUID (serialized as lowercase hyphenated text).
pub struct Uuid {
  priv bytes : FixedArray[Int]
} derive(Eq, Hash)

///|
pub impl Debug for Uuid with to_repr(self) {
  Repr(self.to_string())
}

///|
/// `Uuid::parse_str`: hyphenated, simple, `urn:uuid:` or braced forms.
pub fn Uuid::parse(s : String) -> Uuid raise ConversionError {
  let err = ConversionError("UUID parsing failed")
  let body = if s.length() == 45 && s.has_prefix("urn:uuid:") {
    s.unsafe_substring(start=9, end=45)
  } else if s.length() == 38 && s.has_prefix("{") && s.has_suffix("}") {
    s.unsafe_substring(start=1, end=37)
  } else {
    s
  }
  let chars = body.to_array()
  let hex = if chars.length() == 36 {
    for i, c in chars {
      if i is (8 | 13 | 18 | 23) {
        if c != '-' {
          raise err
        }
      } else if !is_hex(c) {
        raise err
      }
    }
    chars.filter(c => c != '-')
  } else if chars.length() == 32 && body == s {
    if !chars.iter().all(is_hex) {
      raise err
    }
    chars
  } else {
    raise err
  }
  { bytes: FixedArray::makei(16, i => hex_val(hex[2 * i]) * 16 + hex_val(hex[2 * i + 1])) }
}

///|
pub fn Uuid::to_string(self : Uuid) -> String {
  let digits = "0123456789abcdef"
  let buf = StringBuilder()
  for i, b in self.bytes {
    if i is (4 | 6 | 8 | 10) {
      buf.write_char('-')
    }
    buf.write_char(digits.get_char(b >> 4).unwrap())
    buf.write_char(digits.get_char(b & 15).unwrap())
  }
  buf.to_string()
}

///|
pub fn Uuid::deserialize(d : De) -> Uuid raise DeError {
  let s = de_string(d)
  Uuid::parse(s) catch {
    ConversionError(msg) => raise DeError(msg)
  }
}

///|
pub fn Uuid::serialize(self : Uuid) -> Content raise SerError {
  String(self.to_string())
}

// ---------------------------------------------------------------------------
// Dates

///|
fn is_leap(y : Int) -> Bool {
  (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

///|
fn days_in_month(y : Int, m : Int) -> Int {
  match m {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap(y) { 29 } else { 28 }
    _ => 0
  }
}

///|
/// A calendar date (`chrono::NaiveDate`, serialized as `%Y-%m-%d`).
pub struct NaiveDate {
  year : Int
  month : Int
  day : Int
} derive(Eq, Hash, Debug)

///|
priv struct Cursor {
  s : Array[Char]
  mut pos : Int
}

///|
fn Cursor::digits(self : Cursor, min : Int, max : Int) -> Int? {
  let start = self.pos
  let mut v = 0
  while self.pos < self.s.length() && self.pos - start < max && self.s[self.pos].is_ascii_digit() {
    v = v * 10 + (self.s[self.pos].to_int() - '0'.to_int())
    self.pos += 1
  }
  if self.pos - start < min {
    None
  } else {
    Some(v)
  }
}

///|
fn Cursor::eat(self : Cursor, c : Char) -> Bool {
  if self.pos < self.s.length() && self.s[self.pos] == c {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn Cursor::parse_date(self : Cursor) -> NaiveDate? {
  // chrono: optional sign for years beyond four digits.
  let sign = if self.eat('+') { 1 } else if self.eat('-') { -1 } else { 0 }
  guard self.digits(if sign == 0 { 4 } else { 5 }, if sign == 0 { 4 } else { 9 }) is Some(y) else {
    return None
  }
  let year = if sign < 0 { -y } else { y }
  guard self.eat('-') else { return None }
  guard self.digits(2, 2) is Some(m) else { return None }
  guard self.eat('-') else { return None }
  guard self.digits(2, 2) is Some(day) else { return None }
  if m < 1 || m > 12 || day < 1 || day > days_in_month(year, m) {
    return None
  }
  Some({ year, month: m, day })
}

///|
pub fn NaiveDate::parse(s : String) -> NaiveDate raise ConversionError {
  let c = Cursor::{ s: s.to_array(), pos: 0 }
  match c.parse_date() {
    Some(d) if c.pos == c.s.length() => d
    _ => raise ConversionError("input contains invalid characters")
  }
}

///|
fn pad(n : Int, width : Int) -> String {
  let s = n.abs().to_string()
  "0".repeat((width - s.length()).max(0)) + s
}

///|
pub fn NaiveDate::to_string(self : NaiveDate) -> String {
  let year = if self.year >= 0 && self.year <= 9999 {
    pad(self.year, 4)
  } else if self.year < 0 {
    "-" + pad(self.year, 4)
  } else {
    "+" + pad(self.year, 4)
  }
  "\{year}-\{pad(self.month, 2)}-\{pad(self.day, 2)}"
}

///|
pub fn NaiveDate::deserialize(d : De) -> NaiveDate raise DeError {
  let s = de_string(d)
  NaiveDate::parse(s) catch {
    ConversionError(msg) => raise DeError(msg)
  }
}

///|
pub fn NaiveDate::serialize(self : NaiveDate) -> Content raise SerError {
  String(self.to_string())
}

///|
/// Days since 1970-01-01 (proleptic Gregorian).
fn days_from_civil(y : Int, m : Int, d : Int) -> Int64 {
  let y = if m <= 2 { y - 1 } else { y }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = (m + 9) % 12
  let doy = (153 * mp + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era.to_int64() * 146097L + doe.to_int64() - 719468L
}

///|
fn civil_from_days(z : Int64) -> (Int, Int, Int) {
  let z = z + 719468L
  let era = (if z >= 0L { z } else { z - 146096L }) / 146097L
  let doe = (z - era * 146097L).to_int()
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era.to_int() * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  (if m <= 2 { y + 1 } else { y }, m, d)
}

///|
/// A UTC timestamp (`chrono::DateTime<Utc>`, RFC 3339).
pub struct DateTimeUtc {
  /// Seconds since the Unix epoch.
  seconds : Int64
  /// Nanoseconds (may exceed 10^9 - 1 for a leap second).
  nanos : Int
} derive(Eq, Hash, Debug)

///|
pub fn DateTimeUtc::parse(s : String) -> DateTimeUtc raise ConversionError {
  let err = ConversionError("input contains invalid characters")
  let c = Cursor::{ s: s.to_array(), pos: 0 }
  guard c.parse_date() is Some(date) else { raise err }
  if !(c.eat('T') || c.eat('t') || c.eat(' ')) {
    raise err
  }
  guard c.digits(2, 2) is Some(h) else { raise err }
  guard c.eat(':') else { raise err }
  guard c.digits(2, 2) is Some(mi) else { raise err }
  guard c.eat(':') else { raise err }
  guard c.digits(2, 2) is Some(sec) else { raise err }
  let mut nanos = 0
  if c.eat('.') {
    let start = c.pos
    let mut scale = 100000000
    while c.pos < c.s.length() && c.s[c.pos].is_ascii_digit() {
      nanos += (c.s[c.pos].to_int() - '0'.to_int()) * scale
      scale /= 10
      c.pos += 1
    }
    if c.pos == start {
      raise err
    }
  }
  let offset = if c.eat('Z') || c.eat('z') {
    0
  } else {
    let sign = if c.eat('+') { 1 } else if c.eat('-') { -1 } else { raise err }
    guard c.digits(2, 2) is Some(oh) else { raise err }
    guard c.eat(':') else { raise err }
    guard c.digits(2, 2) is Some(om) else { raise err }
    sign * (oh * 3600 + om * 60)
  }
  if c.pos != c.s.length() || h > 23 || mi > 59 || sec > 60 {
    raise err
  }
  // A leap second is represented as second 59 with extra nanoseconds.
  let (sec, nanos) = if sec == 60 { (59, nanos + 1000000000) } else { (sec, nanos) }
  let days = days_from_civil(date.year, date.month, date.day)
  let seconds = days * 86400L + (h * 3600 + mi * 60 + sec).to_int64() - offset.to_int64()
  { seconds, nanos }
}

///|
/// chrono's `to_rfc3339_opts(SecondsFormat::AutoSi, true)`.
pub fn DateTimeUtc::to_string(self : DateTimeUtc) -> String {
  let days = if self.seconds >= 0L { self.seconds / 86400L } else { (self.seconds - 86399L) / 86400L }
  let secs = (self.seconds - days * 86400L).to_int()
  let (y, m, d) = civil_from_days(days)
  let date : NaiveDate = { year: y, month: m, day: d }
  let (sec, nanos) = if self.nanos >= 1000000000 {
    (secs % 60 + 1, self.nanos - 1000000000)
  } else {
    (secs % 60, self.nanos)
  }
  let frac = if nanos == 0 {
    ""
  } else if nanos % 1000000 == 0 {
    "." + pad(nanos / 1000000, 3)
  } else if nanos % 1000 == 0 {
    "." + pad(nanos / 1000, 6)
  } else {
    "." + pad(nanos, 9)
  }
  "\{date.to_string()}T\{pad(secs / 3600, 2)}:\{pad(secs / 60 % 60, 2)}:\{pad(sec, 2)}\{frac}Z"
}

///|
pub fn DateTimeUtc::deserialize(d : De) -> DateTimeUtc raise DeError {
  let s = de_string(d)
  DateTimeUtc::parse(s) catch {
    ConversionError(msg) => raise DeError(msg)
  }
}

///|
pub fn DateTimeUtc::serialize(self : DateTimeUtc) -> Content raise SerError {
  String(self.to_string())
}

// ---------------------------------------------------------------------------
// IP addresses

///|
/// An IPv4 address (`std::net::Ipv4Addr`).
pub struct Ipv4Addr {
  octets : FixedArray[Int]
} derive(Eq, Hash, Debug)

///|
fn parse_ipv4_chars(chars : ArrayView[Char]) -> FixedArray[Int]? {
  let octets = FixedArray::make(4, 0)
  let mut i = 0
  for k in 0..<4 {
    if k > 0 {
      if i >= chars.length() || chars[i] != '.' {
        return None
      }
      i += 1
    }
    let start = i
    let mut v = 0
    while i < chars.length() && chars[i].is_ascii_digit() && i - start < 3 {
      v = v * 10 + (chars[i].to_int() - '0'.to_int())
      i += 1
    }
    let len = i - start
    // Rust rejects leading zeros and values above 255.
    if len == 0 || v > 255 || (len > 1 && chars[start] == '0') {
      return None
    }
    octets[k] = v
  }
  if i != chars.length() {
    None
  } else {
    Some(octets)
  }
}

///|
pub fn Ipv4Addr::parse(s : String) -> Ipv4Addr raise ConversionError {
  match parse_ipv4_chars(s.to_array()[:]) {
    Some(octets) => { octets, }
    None => raise ConversionError("invalid IPv4 address syntax")
  }
}

///|
pub fn Ipv4Addr::to_string(self : Ipv4Addr) -> String {
  self.octets.iter().map(o => o.to_string()).collect().join(".")
}

///|
pub fn Ipv4Addr::deserialize(d : De) -> Ipv4Addr raise DeError {
  let s = de_string(d)
  Ipv4Addr::parse(s) catch {
    ConversionError(msg) => raise DeError(msg)
  }
}

///|
pub fn Ipv4Addr::serialize(self : Ipv4Addr) -> Content raise SerError {
  String(self.to_string())
}

///|
/// An IPv6 address (`std::net::Ipv6Addr`).
pub struct Ipv6Addr {
  segments : FixedArray[Int]
} derive(Eq, Hash, Debug)

///|
fn parse_ipv6_chars(chars : Array[Char]) -> FixedArray[Int]? {
  // Split around "::".
  let n = chars.length()
  let mut dbl = -1
  for i in 0..<(n - 1) {
    if chars[i] == ':' && chars[i + 1] == ':' {
      if dbl >= 0 {
        return None
      }
      dbl = i
    }
  }
  fn groups(part : ArrayView[Char]) -> Array[Int]? {
    let out = []
    if part.length() == 0 {
      return Some(out)
    }
    let mut i = 0
    for ;; {
      // An embedded IPv4 address may end the address.
      let rest = part[i:]
      if rest.iter().any(c => c == '.') && !rest.iter().any(c => c == ':') {
        guard parse_ipv4_chars(rest) is Some(o) else { return None }
        out.push(o[0] * 256 + o[1])
        out.push(o[2] * 256 + o[3])
        return Some(out)
      }
      let start = i
      let mut v = 0
      while i < part.length() && is_hex(part[i]) && i - start < 4 {
        v = v * 16 + hex_val(part[i])
        i += 1
      }
      if i == start {
        return None
      }
      out.push(v)
      if i == part.length() {
        return Some(out)
      }
      if part[i] != ':' {
        return None
      }
      i += 1
      if i == part.length() {
        return None
      }
    }
  }
  let segs = FixedArray::make(8, 0)
  if dbl < 0 {
    guard groups(chars[:]) is Some(g) else { return None }
    if g.length() != 8 {
      return None
    }
    for i, v in g {
      segs[i] = v
    }
  } else {
    guard groups(chars[:dbl]) is Some(head) else { return None }
    guard groups(chars[dbl + 2:]) is Some(tail) else { return None }
    if head.length() + tail.length() > 7 {
      return None
    }
    for i, v in head {
      segs[i] = v
    }
    for i, v in tail {
      segs[8 - tail.length() + i] = v
    }
  }
  Some(segs)
}

///|
pub fn Ipv6Addr::parse(s : String) -> Ipv6Addr raise ConversionError {
  match parse_ipv6_chars(s.to_array()) {
    Some(segments) => { segments, }
    None => raise ConversionError("invalid IPv6 address syntax")
  }
}

///|
/// Rust's `Ipv6Addr` display (RFC 5952, IPv4-mapped addresses dotted).
pub fn Ipv6Addr::to_string(self : Ipv6Addr) -> String {
  let s = self.segments
  if s[0] == 0 && s[1] == 0 && s[2] == 0 && s[3] == 0 && s[4] == 0 && s[5] == 0xFFFF {
    return "::ffff:\{s[6] >> 8}.\{s[6] & 255}.\{s[7] >> 8}.\{s[7] & 255}"
  }
  // Longest run (length >= 2) of zero segments; the first one wins.
  let mut best_start = -1
  let mut best_len = 0
  let mut i = 0
  while i < 8 {
    if s[i] == 0 {
      let start = i
      while i < 8 && s[i] == 0 {
        i += 1
      }
      if i - start > best_len {
        best_start = start
        best_len = i - start
      }
    } else {
      i += 1
    }
  }
  let hex = (v : Int) => v.to_string(radix=16)
  if best_len < 2 {
    return s.iter().map(hex).collect().join(":")
  }
  let head = s[0:best_start].iter().map(hex).collect().join(":")
  let tail = s[best_start + best_len:].iter().map(hex).collect().join(":")
  "\{head}::\{tail}"
}

///|
pub fn Ipv6Addr::deserialize(d : De) -> Ipv6Addr raise DeError {
  let s = de_string(d)
  Ipv6Addr::parse(s) catch {
    ConversionError(msg) => raise DeError(msg)
  }
}

///|
pub fn Ipv6Addr::serialize(self : Ipv6Addr) -> Content raise SerError {
  String(self.to_string())
}

///|
/// An IP address (`std::net::IpAddr`).
pub(all) enum IpAddr {
  V4(Ipv4Addr)
  V6(Ipv6Addr)
} derive(Eq, Hash, Debug)

///|
pub fn IpAddr::parse(s : String) -> IpAddr raise ConversionError {
  match parse_ipv4_chars(s.to_array()[:]) {
    Some(octets) => V4({ octets, })
    None =>
      match parse_ipv6_chars(s.to_array()) {
        Some(segments) => V6({ segments, })
        None => raise ConversionError("invalid IP address syntax")
      }
  }
}

///|
pub fn IpAddr::to_string(self : IpAddr) -> String {
  match self {
    V4(a) => a.to_string()
    V6(a) => a.to_string()
  }
}

///|
pub fn IpAddr::deserialize(d : De) -> IpAddr raise DeError {
  let s = de_string(d)
  IpAddr::parse(s) catch {
    ConversionError(msg) => raise DeError(msg)
  }
}

///|
pub fn IpAddr::serialize(self : IpAddr) -> Content raise SerError {
  String(self.to_string())
}
