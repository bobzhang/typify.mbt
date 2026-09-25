///|
/// Compare two strings by Unicode code points.
///
/// This is the ordering of Rust's `str` (UTF-8 byte order), which upstream
/// typify relies on through `BTreeMap<String, _>` iteration. MoonBit's own
/// `String::compare` orders by length first, so it must not be used where
/// iteration order is observable.
pub fn compare_str(a : StringView, b : StringView) -> Int {
  let la = a.length()
  let lb = b.length()
  for i = 0, j = 0; i < la && j < lb; {
    let ca = a.code_unit_at(i).to_int()
    let cb = b.code_unit_at(j).to_int()
    if ca == cb {
      continue i + 1, j + 1
    }
    // Code units differ. Surrogates (0xD800..0xDFFF) encode code points above
    // 0xFFFF, which sort after every BMP code point in UTF-8 order.
    let ka = if ca >= 0xD800 && ca <= 0xDFFF { ca + 0x10000 } else { ca }
    let kb = if cb >= 0xD800 && cb <= 0xDFFF { cb + 0x10000 } else { cb }
    break if ka < kb { -1 } else { 1 }
  } nobreak {
    // One string is a prefix of the other.
    (la - i).compare(lb - j)
  }
}
