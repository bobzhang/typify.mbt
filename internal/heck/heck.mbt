// A port of the `heck` 0.5 crate's case conversions used by typify. The word
// boundary rules and Unicode behaviour follow heck (and Rust's `char`) exactly,
// because generated identifiers must match upstream output.

///|
priv enum WordMode {
  Boundary
  Lowercase
  Uppercase
} derive(Eq)

///|
/// heck's `transform`: split `s` into words and write each word through
/// `with_word`, separated by `boundary`.
fn transform(
  s : String,
  buf : StringBuilder,
  with_word : (StringBuilder, ArrayView[Char]) -> Unit,
  boundary : (StringBuilder) -> Unit,
) -> Unit {
  let mut first_word = true
  let chars = s.to_array()
  let n = chars.length()
  // Words are the maximal runs of alphanumeric characters.
  for start = 0; start <= n; {
    let end = for j = start; j < n; j = j + 1 {
      if !@unicode.is_alphanumeric(chars[j]) {
        break j
      }
    } nobreak {
      n
    }
    let word = chars[start:end]
    let len = word.length()
    let mut init = 0
    let mut mode = Boundary
    for i in 0..<len {
      let c = word[i]
      if i + 1 < len {
        let next = word[i + 1]
        let next_mode = if @unicode.is_lowercase(c) {
          Lowercase
        } else if @unicode.is_uppercase(c) {
          Uppercase
        } else {
          mode
        }
        if next_mode == Lowercase && @unicode.is_uppercase(next) {
          // Word boundary after the current char, e.g. "camelCase".
          if !first_word {
            boundary(buf)
          }
          with_word(buf, word[init:i + 1])
          first_word = false
          init = i + 1
          mode = Boundary
        } else if mode == Uppercase &&
          @unicode.is_uppercase(c) &&
          @unicode.is_lowercase(next) {
          // Word boundary before the current char, e.g. "XMLHttp".
          if !first_word {
            boundary(buf)
          } else {
            first_word = false
          }
          with_word(buf, word[init:i])
          init = i
          mode = Boundary
        } else {
          mode = next_mode
        }
      } else {
        // Last char of the word.
        if !first_word {
          boundary(buf)
        } else {
          first_word = false
        }
        with_word(buf, word[init:])
      }
    }
    continue end + 1
  }
}

///|
fn lowercase(buf : StringBuilder, word : ArrayView[Char]) -> Unit {
  let len = word.length()
  for i, c in word {
    if c == 'Σ' && i + 1 == len {
      buf.write_char('ς')
    } else {
      buf.write_string(@unicode.to_lowercase(c))
    }
  }
}

///|
fn capitalize(buf : StringBuilder, word : ArrayView[Char]) -> Unit {
  guard word is [first, .. rest] else { return }
  buf.write_string(@unicode.to_uppercase(first))
  lowercase(buf, rest)
}

///|
/// Convert to `UpperCamelCase` (a.k.a. `PascalCase`), like heck's
/// `ToPascalCase`.
pub fn to_pascal_case(s : String) -> String {
  let buf = StringBuilder()
  transform(s, buf, capitalize, _ => ())
  buf.to_string()
}

///|
/// Convert to `snake_case`, like heck's `ToSnakeCase`.
pub fn to_snake_case(s : String) -> String {
  let buf = StringBuilder()
  transform(s, buf, lowercase, b => b.write_char('_'))
  buf.to_string()
}

///|
/// Convert to `kebab-case`, like heck's `ToKebabCase`.
pub fn to_kebab_case(s : String) -> String {
  let buf = StringBuilder()
  transform(s, buf, lowercase, b => b.write_char('-'))
  buf.to_string()
}
