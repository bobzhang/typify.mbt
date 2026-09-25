///|
/// A set of code points as sorted, disjoint, non-adjacent inclusive
/// intervals (regress `CodePointSet`).
priv struct CharSet {
  mut ranges : Array[(Int, Int)]
}

///|
fn CharSet::new() -> CharSet {
  { ranges: [], }
}

///|
fn CharSet::from_ranges(ranges : Array[(Int, Int)]) -> CharSet {
  let s = CharSet::new()
  for r in ranges {
    s.add(r.0, r.1)
  }
  s
}

///|
/// Add the inclusive interval `[lo, hi]`, keeping the representation
/// normalised.
fn CharSet::add(self : CharSet, lo : Int, hi : Int) -> Unit {
  let out = []
  let mut lo = lo
  let mut hi = hi
  let mut placed = false
  for r in self.ranges {
    if r.1 + 1 < lo {
      out.push(r)
    } else if hi + 1 < r.0 {
      if !placed {
        out.push((lo, hi))
        placed = true
      }
      out.push(r)
    } else {
      // Overlapping or adjacent: merge.
      lo = lo.min(r.0)
      hi = hi.max(r.1)
    }
  }
  if !placed {
    out.push((lo, hi))
  }
  self.ranges = out
}

///|
fn CharSet::add_one(self : CharSet, c : Int) -> Unit {
  self.add(c, c)
}

///|
fn CharSet::add_set(self : CharSet, other : CharSet) -> Unit {
  for r in other.ranges {
    self.add(r.0, r.1)
  }
}

///|
fn CharSet::inverted(self : CharSet) -> CharSet {
  let out = []
  let mut next = 0
  for r in self.ranges {
    if r.0 > next {
      out.push((next, r.0 - 1))
    }
    next = r.1 + 1
  }
  if next <= 0x10FFFF {
    out.push((next, 0x10FFFF))
  }
  { ranges: out, }
}

///|
fn CharSet::contains(self : CharSet, c : Int) -> Bool {
  for lo = 0, hi = self.ranges.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let r = self.ranges[mid]
    if c < r.0 {
      continue lo, mid
    } else if c > r.1 {
      continue mid + 1, hi
    } else {
      break true
    }
  } nobreak {
    false
  }
}

///|
/// `charclasses::DIGITS`
fn digits() -> CharSet {
  CharSet::from_ranges([('0'.to_int(), '9'.to_int())])
}

///|
/// `charclasses::WORD_CHARS`
fn word_chars() -> CharSet {
  CharSet::from_ranges([
    ('0'.to_int(), '9'.to_int()),
    ('A'.to_int(), 'Z'.to_int()),
    ('_'.to_int(), '_'.to_int()),
    ('a'.to_int(), 'z'.to_int()),
  ])
}

///|
/// `charclasses::WHITESPACE` plus `LINE_TERMINATOR`.
fn spaces() -> CharSet {
  CharSet::from_ranges([
    (0x09, 0x0D),
    (0x20, 0x20),
    (0xA0, 0xA0),
    (0x1680, 0x1680),
    (0x2000, 0x200A),
    (0x2028, 0x2029),
    (0x202F, 0x202F),
    (0x205F, 0x205F),
    (0x3000, 0x3000),
    (0xFEFF, 0xFEFF),
  ])
}

///|
fn is_line_terminator(c : Int) -> Bool {
  c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029
}

///|
fn is_word_char(c : Int) -> Bool {
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  c == '_'.to_int() ||
  (c >= 'a'.to_int() && c <= 'z'.to_int())
}
