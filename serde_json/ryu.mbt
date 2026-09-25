///|
/// Decompose a finite, non-zero `abs` value into its shortest round-trip
/// decimal digits and exponent: `abs == digits * 10^exp`.
///
/// MoonBit's `Double::to_string` already produces the shortest round-trip
/// digits (as ryu does); only the layout differs, so we re-parse it.
fn shortest_digits(abs : Double) -> (String, Int) {
  let chars = abs.to_string().to_array()
  // Split off an optional exponent: "1.5e+300" / "1e-7".
  let mut exp = 0
  let mut mantissa_end = chars.length()
  for i, c in chars {
    if c == 'e' || c == 'E' {
      mantissa_end = i
      let mut negative = false
      let mut e = 0
      for j in (i + 1)..<chars.length() {
        match chars[j] {
          '-' => negative = true
          '+' => ()
          d => e = e * 10 + (d.to_int() - '0'.to_int())
        }
      }
      exp = if negative { -e } else { e }
      break
    }
  }
  // Collect the mantissa digits, adjusting the exponent for fraction digits.
  let digits = StringBuilder()
  let mut seen_point = false
  let mut seen_nonzero = false
  for i in 0..<mantissa_end {
    let c = chars[i]
    if c == '.' {
      seen_point = true
      continue
    }
    if seen_point {
      exp -= 1
    }
    if c != '0' || seen_nonzero {
      seen_nonzero = true
      digits.write_char(c)
    }
  }
  // Strip trailing zeros into the exponent.
  let digits = digits.to_string()
  let mut end = digits.length()
  while end > 1 && digits[end - 1] == '0' {
    end -= 1
    exp += 1
  }
  (digits.unsafe_substring(start=0, end~), exp)
}

///|
/// serde_json writes an explicit `+` on positive exponents (`1e+16`).
fn write_exponent(buf : StringBuilder, e : Int) -> Unit {
  buf.write_char('e')
  if e >= 0 {
    buf.write_char('+')
  }
  buf.write_string(e.to_string())
}

///|
/// Format a finite `f64` exactly like serde_json 1.0.151's float writer
/// (ryu's shortest digits and layout, with `e+` for positive exponents).
pub fn format_f64(d : Double) -> String {
  let buf = StringBuilder()
  if d < 0.0 || (d == 0.0 && 1.0 / d < 0.0) {
    buf.write_char('-')
  }
  let abs = d.abs()
  if abs == 0.0 {
    buf.write_string("0.0")
    return buf.to_string()
  }
  let (digits, k) = shortest_digits(abs)
  let length = digits.length()
  let kk = length + k // 10^(kk-1) <= abs < 10^kk
  if 0 <= k && kk <= 16 {
    // 1234e7 -> 12340000000.0
    buf.write_string(digits)
    for _ in 0..<k {
      buf.write_char('0')
    }
    buf.write_string(".0")
  } else if 0 < kk && kk <= 16 {
    // 1234e-2 -> 12.34
    buf.write_string(digits.unsafe_substring(start=0, end=kk))
    buf.write_char('.')
    buf.write_string(digits.unsafe_substring(start=kk, end=length))
  } else if -5 < kk && kk <= 0 {
    // 1234e-6 -> 0.001234
    buf.write_string("0.")
    for _ in 0..<-kk {
      buf.write_char('0')
    }
    buf.write_string(digits)
  } else if length == 1 {
    // 1e30
    buf.write_string(digits)
    write_exponent(buf, kk - 1)
  } else {
    // 1234e30 -> 1.234e33
    buf.write_string(digits.unsafe_substring(start=0, end=1))
    buf.write_char('.')
    buf.write_string(digits.unsafe_substring(start=1, end=length))
    write_exponent(buf, kk - 1)
  }
  buf.to_string()
}
