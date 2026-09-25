///|
/// A JSON number with serde_json's internal classification.
///
/// serde_json (without `arbitrary_precision`) keeps non-negative integers
/// that fit in `u64` as `PosInt`, negative integers that fit in `i64` as
/// `NegInt`, and everything else as a finite `Float`. The classification is
/// observable: `1` and `1.0` are different values and only the former is an
/// integer.
pub(all) enum Number {
  PosInt(UInt64)
  NegInt(Int64)
  Float(Double)
} derive(Debug)

///|
/// Equality follows serde_json: numbers of different classes are never equal.
pub impl Eq for Number with fn equal(self, other) {
  match (self, other) {
    (PosInt(a), PosInt(b)) => a == b
    (NegInt(a), NegInt(b)) => a == b
    (Float(a), Float(b)) => a == b
    _ => false
  }
}

///|
/// Build a number from a `u64`.
pub fn Number::from_u64(n : UInt64) -> Number {
  PosInt(n)
}

///|
/// Build a number from an `i64`, normalising non-negative values to
/// `PosInt` like serde_json's `From<i64>`.
pub fn Number::from_i64(n : Int64) -> Number {
  if n >= 0 {
    PosInt(n.reinterpret_as_uint64())
  } else {
    NegInt(n)
  }
}

///|
/// Build a number from a finite `f64`; returns `None` for NaN or infinities.
pub fn Number::from_f64(d : Double) -> Number? {
  if d.is_nan() || d.is_inf() {
    None
  } else {
    Some(Float(d))
  }
}

///|
pub fn Number::is_u64(self : Number) -> Bool {
  self is PosInt(_)
}

///|
pub fn Number::is_i64(self : Number) -> Bool {
  match self {
    PosInt(n) => n <= 0x7FFF_FFFF_FFFF_FFFFUL
    NegInt(_) => true
    Float(_) => false
  }
}

///|
pub fn Number::is_f64(self : Number) -> Bool {
  self is Float(_)
}

///|
pub fn Number::as_u64(self : Number) -> UInt64? {
  match self {
    PosInt(n) => Some(n)
    _ => None
  }
}

///|
pub fn Number::as_i64(self : Number) -> Int64? {
  match self {
    PosInt(n) =>
      if n <= 0x7FFF_FFFF_FFFF_FFFFUL {
        Some(n.reinterpret_as_int64())
      } else {
        None
      }
    NegInt(n) => Some(n)
    Float(_) => None
  }
}

///|
/// Any number converts to `f64` (possibly losing precision), like serde_json.
pub fn Number::as_f64(self : Number) -> Double {
  match self {
    PosInt(n) => n.to_double()
    NegInt(n) => n.to_double()
    Float(d) => d
  }
}

///|
/// Render like serde_json's `Display` for `Number` (itoa / ryu).
pub fn Number::to_string(self : Number) -> String {
  match self {
    PosInt(n) => n.to_string()
    NegInt(n) => n.to_string()
    Float(d) => format_f64(d)
  }
}

///|
pub impl Show for Number with fn output(self, logger) {
  logger.write_string(self.to_string())
}
