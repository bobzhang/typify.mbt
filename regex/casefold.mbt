// Case-insensitive matching support for `(?i:...)` groups.
//
// regress compares literal characters through its uppercase table and
// brackets through Unicode simple case folding. We derive both from Rust's
// `char` case mappings (see internal/unicode): single-character mappings
// only, and ES2015 Canonicalize's rule that non-ASCII characters never map to
// ASCII in non-Unicode mode.

///|
fn single_upper(c : Int) -> Int {
  if c < 0 || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF) {
    return c
  }
  let u = @unicode.to_uppercase(c.unsafe_to_char())
  if u.char_length() == 1 {
    u.get_char(0).unwrap().to_int()
  } else {
    c
  }
}

///|
fn single_lower(c : Int) -> Int {
  if c < 0 || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF) {
    return c
  }
  let l = @unicode.to_lowercase(c.unsafe_to_char())
  if l.char_length() == 1 {
    l.get_char(0).unwrap().to_int()
  } else {
    c
  }
}

///|
/// ES2015 21.2.2.8.2 Canonicalize (non-Unicode mode).
fn canonicalize(c : Int) -> Int {
  let u = single_upper(c)
  if c >= 128 && u < 128 {
    c
  } else {
    u
  }
}

///|
/// Approximation of Unicode simple case folding.
fn simple_fold(c : Int) -> Int {
  single_lower(single_upper(c))
}

///|
/// For each case-fold class with more than one member: fold target -> members.
let fold_classes : Map[Int, Array[Int]] = {
  let classes : Map[Int, Array[Int]] = Map([])
  for c in @unicode.case_mapped_code_points() {
    for x in [c, single_upper(c), single_lower(c)] {
      let f = simple_fold(x)
      match classes.get(f) {
        Some(members) => if !members.contains(x) { members.push(x) }
        None => classes[f] = [x]
      }
    }
  }
  classes
}

///|
/// Whether `c` matches a bracket set under case-insensitive matching.
fn bracket_contains_icase(set : CharSet, c : Int) -> Bool {
  if set.contains(c) {
    return true
  }
  match fold_classes.get(simple_fold(c)) {
    Some(members) => members.iter().any(m => set.contains(m))
    None => false
  }
}

///|
fn chars_equal(a : Int, b : Int, icase : Bool) -> Bool {
  a == b || (icase && canonicalize(a) == canonicalize(b))
}
