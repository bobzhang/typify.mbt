///|
/// A map from `String` keys ordered by code point (Rust `BTreeMap<String, V>`
/// semantics). Backed by a sorted array; intended for schema-sized data.
pub struct StrMap[V] {
  priv entries : Array[(String, V)]
}

///|
pub fn[V] StrMap::new() -> StrMap[V] {
  { entries: [], }
}

///|
/// Build a map from pairs; later duplicates overwrite earlier ones.
pub fn[V] StrMap::from_array(pairs : ArrayView[(String, V)]) -> StrMap[V] {
  let m = StrMap::new()
  for pair in pairs {
    m.set(pair.0, pair.1)
  }
  m
}

///|
/// Binary search: `Ok(index)` if found, `Err(insertion_point)` otherwise.
fn[V] StrMap::search(self : StrMap[V], key : StringView) -> Result[Int, Int] {
  for lo = 0, hi = self.entries.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    let c = compare_str(self.entries[mid].0, key)
    if c < 0 {
      continue mid + 1, hi
    } else if c > 0 {
      continue lo, mid
    } else {
      break Ok(mid)
    }
  } nobreak {
    Err(lo)
  }
}

///|
pub fn[V] StrMap::length(self : StrMap[V]) -> Int {
  self.entries.length()
}

///|
pub fn[V] StrMap::is_empty(self : StrMap[V]) -> Bool {
  self.entries.is_empty()
}

///|
pub fn[V] StrMap::get(self : StrMap[V], key : StringView) -> V? {
  match self.search(key) {
    Ok(i) => Some(self.entries[i].1)
    Err(_) => None
  }
}

///|
pub fn[V] StrMap::contains(self : StrMap[V], key : StringView) -> Bool {
  self.search(key) is Ok(_)
}

///|
/// Insert or replace; returns the previous value.
pub fn[V] StrMap::insert(self : StrMap[V], key : String, value : V) -> V? {
  match self.search(key) {
    Ok(i) => {
      let old = self.entries[i].1
      self.entries[i] = (key, value)
      Some(old)
    }
    Err(i) => {
      self.entries.insert(i, (key, value))
      None
    }
  }
}

///|
pub fn[V] StrMap::set(self : StrMap[V], key : String, value : V) -> Unit {
  ignore(self.insert(key, value))
}

///|
pub fn[V] StrMap::remove(self : StrMap[V], key : StringView) -> V? {
  match self.search(key) {
    Ok(i) => Some(self.entries.remove(i).1)
    Err(_) => None
  }
}

///|
/// Entries in key order.
pub fn[V] StrMap::iter(self : StrMap[V]) -> Iter[(String, V)] {
  self.entries.iter()
}

///|
/// Entries in key order.
pub fn[V] StrMap::iter2(self : StrMap[V]) -> Iter2[String, V] {
  let it = self.entries.iter()
  Iter2::new(() => it.next())
}

///|
pub fn[V] StrMap::keys(self : StrMap[V]) -> Array[String] {
  self.entries.map(e => e.0)
}

///|
pub fn[V] StrMap::values(self : StrMap[V]) -> Array[V] {
  self.entries.map(e => e.1)
}

///|
pub fn[V] StrMap::to_array(self : StrMap[V]) -> Array[(String, V)] {
  self.entries.copy()
}

///|
pub fn[V] StrMap::copy(self : StrMap[V]) -> StrMap[V] {
  { entries: self.entries.copy(), }
}

///|
pub fn[V] StrMap::first(self : StrMap[V]) -> (String, V)? {
  self.entries.get(0)
}

///|
pub fn[V, W] StrMap::map(self : StrMap[V], f : (V) -> W) -> StrMap[W] {
  { entries: self.entries.map(e => (e.0, f(e.1))), }
}

///|
pub impl[V : Eq] Eq for StrMap[V] with fn equal(self, other) {
  self.entries == other.entries
}

///|
pub impl[V : Debug] Debug for StrMap[V] with fn to_repr(self) {
  Repr(Map::from_array(self.entries))
}
