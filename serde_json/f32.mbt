///|
/// `10^n` as a `BigInt` (`n >= 0`).
fn big_pow10(n : Int) -> @bigint.BigInt {
  let mut r = @bigint.BigInt::from_int(1)
  let ten = @bigint.BigInt::from_int(10)
  for _ in 0..<n {
    r = r * ten
  }
  r
}

///|
/// Floor division of non-negative `a` by positive `b`, and whether it was exact.
fn big_divmod(a : @bigint.BigInt, b : @bigint.BigInt) -> (@bigint.BigInt, Bool) {
  let q = a / b
  (q, (q * b).equal(a))
}

///|
/// The shortest decimal `digits * 10^k` inside the round-to-nearest-even
/// interval of the positive, finite f32 with significand `m` and binary
/// exponent `e` (value `m * 2^e`), choosing the candidate closest to the
/// exact value (ties to even), as Ryu, Schubfach and zmij do.
///
/// Computed exactly with big integers: f32 has few enough bits that this is
/// cheap, and it is only used for serialization of `f32` fields.
fn shortest_f32_digits(m : Int, e : Int, lower_closer : Bool) -> (String, Int) {
  // Scale the value and its interval bounds by 4 so that they are integers
  // times 2^(e-2).
  let v = m * 4
  let hi = v + 2
  let lo = if lower_closer { v - 1 } else { v - 2 }
  let inclusive = m % 2 == 0
  let be = e - 2
  // value(x) = x * 2^be = num(x) / den
  let den = if be < 0 { @bigint.BigInt::from_int(1) << -be } else { 1N }
  let num = (x : Int) => {
    if be < 0 {
      @bigint.BigInt::from_int(x)
    } else {
      @bigint.BigInt::from_int(x) << be
    }
  }
  let (nv, nlo, nhi) = (num(v), num(lo), num(hi))
  // kk: 10^(kk-1) <= value < 10^kk.
  let mut kk = @math.floor(
      @math.log10(m.to_double() * @math.pow(2.0, e.to_double())),
    ).to_int() +
    1
  let scaled = (k : Int) => {
    if k >= 0 {
      (nv, den * big_pow10(k))
    } else {
      (nv * big_pow10(-k), den)
    }
  }
  // Correct the floating-point estimate of kk.
  while true {
    let (a, b) = scaled(kk)
    if a >= b {
      kk += 1
      continue
    }
    let (a, b) = scaled(kk - 1)
    if a < b {
      kk -= 1
      continue
    }
    break
  }
  for p in 1..<=9 {
    let k = kk - p
    let (mul, d) = if k >= 0 {
      (1N, den * big_pow10(k))
    } else {
      (big_pow10(-k), den)
    }
    // Candidates c with lo <= c * 10^k <= hi (strict when not inclusive).
    let (qlo, exact_lo) = big_divmod(nlo * mul, d)
    let cand_lo = if exact_lo && inclusive { qlo } else { qlo + 1N }
    let (qhi, exact_hi) = big_divmod(nhi * mul, d)
    let cand_hi = if exact_hi && !inclusive { qhi - 1N } else { qhi }
    if cand_lo > cand_hi {
      continue
    }
    // Round the exact value to the nearest candidate, ties to even.
    let (q, _) = big_divmod(nv * mul, d)
    let rem2 = (nv * mul - q * d) * 2N
    let rounded = if rem2 > d || (rem2 == d && q % 2N != 0N) {
      q + 1N
    } else {
      q
    }
    let c = if rounded < cand_lo {
      cand_lo
    } else if rounded > cand_hi {
      cand_hi
    } else {
      rounded
    }
    // Strip trailing zeros into the exponent.
    let digits = c.to_string()
    let mut end = digits.length()
    let mut exp = k
    while end > 1 && digits[end - 1] == '0' {
      end -= 1
      exp += 1
    }
    return (digits.unsafe_substring(start=0, end~), exp)
  }
  abort("unreachable: 9 digits always round-trip an f32")
}

///|
/// Format a finite `f32` exactly like serde_json 1.0.151's float writer
/// (zmij: shortest round-trip digits for `f32`, plain notation for decimal
/// exponents in -6..=12, otherwise `d.ddde±x`).
pub fn format_f32(f : Float) -> String {
  let bits = f.reinterpret_as_uint()
  let buf = StringBuilder()
  if bits >> 31 != 0 {
    buf.write_char('-')
  }
  let biased = ((bits >> 23) & 0xFF).reinterpret_as_int()
  let frac = (bits & 0x7FFFFF).reinterpret_as_int()
  if biased == 0 && frac == 0 {
    buf.write_string("0.0")
    return buf.to_string()
  }
  let (m, e) = if biased == 0 {
    (frac, -149)
  } else {
    (frac | 0x800000, biased - 150)
  }
  let (digits, k) = shortest_f32_digits(m, e, frac == 0 && biased > 1)
  write_layout(buf, digits, k, min_kk=-5, max_kk=13)
  buf.to_string()
}
