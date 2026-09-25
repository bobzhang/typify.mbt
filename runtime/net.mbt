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
  let s = de_string_expecting(d, "IPv4 address")
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
  if s[0] == 0 &&
    s[1] == 0 &&
    s[2] == 0 &&
    s[3] == 0 &&
    s[4] == 0 &&
    s[5] == 0xFFFF {
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
  let s = de_string_expecting(d, "IPv6 address")
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
  let s = de_string_expecting(d, "IP address")
  IpAddr::parse(s) catch {
    ConversionError(msg) => raise DeError(msg)
  }
}

///|
pub fn IpAddr::serialize(self : IpAddr) -> Content raise SerError {
  String(self.to_string())
}
