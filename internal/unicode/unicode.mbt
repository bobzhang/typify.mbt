///|
/// Binary search in a flattened, sorted `[lo, hi]` range table.
fn in_table(table : FixedArray[Int], c : Char) -> Bool {
  let cp = c.to_int()
  let n = table.length() / 2
  for lo = 0, hi = n; lo < hi; {
    let mid = lo + (hi - lo) / 2
    if cp < table[2 * mid] {
      continue lo, mid
    } else if cp > table[2 * mid + 1] {
      continue mid + 1, hi
    } else {
      break true
    }
  } nobreak {
    false
  }
}

///|
/// Binary search in a sorted key table; returns the index of `c` if present.
fn find_key(keys : FixedArray[Int], c : Char) -> Int? {
  let cp = c.to_int()
  for lo = 0, hi = keys.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if cp < keys[mid] {
      continue lo, mid
    } else if cp > keys[mid] {
      continue mid + 1, hi
    } else {
      break Some(mid)
    }
  } nobreak {
    None
  }
}

///|
/// Unicode `XID_Start`, as defined by the `unicode-ident` crate.
pub fn is_xid_start(c : Char) -> Bool {
  if c.is_ascii() {
    c.is_ascii_alphabetic()
  } else {
    in_table(xid_start_table, c)
  }
}

///|
/// Unicode `XID_Continue`, as defined by the `unicode-ident` crate.
pub fn is_xid_continue(c : Char) -> Bool {
  if c.is_ascii() {
    c.is_ascii_alphabetic() || c.is_ascii_digit() || c == '_'
  } else {
    in_table(xid_continue_table, c)
  }
}

///|
/// Equivalent of Rust's `char::is_alphanumeric`.
pub fn is_alphanumeric(c : Char) -> Bool {
  if c.is_ascii() {
    c.is_ascii_alphabetic() || c.is_ascii_digit()
  } else {
    in_table(alphanumeric_table, c)
  }
}

///|
/// Equivalent of Rust's `char::is_lowercase`.
pub fn is_lowercase(c : Char) -> Bool {
  if c.is_ascii() {
    c.is_ascii_lowercase()
  } else {
    in_table(lowercase_table, c)
  }
}

///|
/// Equivalent of Rust's `char::is_uppercase`.
pub fn is_uppercase(c : Char) -> Bool {
  if c.is_ascii() {
    c.is_ascii_uppercase()
  } else {
    in_table(uppercase_table, c)
  }
}

///|
/// Equivalent of Rust's `char::to_lowercase` (full, possibly multi-char mapping).
pub fn to_lowercase(c : Char) -> String {
  if c.is_ascii() {
    return c.to_ascii_lowercase().to_string()
  }
  match find_key(lower_map_keys, c) {
    Some(i) => lower_map_values[i]
    None => c.to_string()
  }
}

///|
/// Equivalent of Rust's `char::to_uppercase` (full, possibly multi-char mapping).
pub fn to_uppercase(c : Char) -> String {
  if c.is_ascii() {
    return c.to_ascii_uppercase().to_string()
  }
  match find_key(upper_map_keys, c) {
    Some(i) => upper_map_values[i]
    None => c.to_string()
  }
}
