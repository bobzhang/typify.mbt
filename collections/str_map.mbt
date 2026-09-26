///|
/// A map from `String` keys ordered by code point (Rust `BTreeMap<String, V>`
/// semantics), or, when created with `new_ordered`, by insertion (serde_json's
/// `preserve_order` map, an `IndexMap`). Backed by an array; intended for
/// schema-sized data.
pub struct StrMap[V] {
  priv entries : Array[(String, V)]
  /// Insertion order instead of key order.
  priv ordered : Bool
}

///|
pub fn[V] StrMap::new() -> StrMap[V] {
  { entries: [], ordered: false, }
}

///|
/// An empty map that keeps keys in insertion order. Replacing a value keeps
/// its key's position; removing a key keeps the order of the others.
pub fn[V] StrMap::new_ordered() -> StrMap[V] {
  { entries: [], ordered: true, }
}

///|
/// An empty map with the same ordering as `self`.
pub fn[V, W] StrMap::empty_like(self : StrMap[V]) -> StrMap[W] {
  { entries: [], ordered: self.ordered, }
}

///|
/// Whether the map keeps insertion order.
pub fn[V] StrMap::is_ordered(self : StrMap[V]) -> Bool {
  self.ordered
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
  if self.ordered {
    // Insertion order: a linear scan, new keys go last.
    for i, e in self.entries {
      if e.0[:] == key {
        return Ok(i)
      }
    }
    return Err(self.entries.length())
  }
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
/// Entries in key order (insertion order for ordered maps).
pub fn[V] StrMap::iter(self : StrMap[V]) -> Iter[(String, V)] {
  self.entries.iter()
}

///|
/// Entries in key order (insertion order for ordered maps).
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
  { entries: self.entries.copy(), ordered: self.ordered, }
}

///|
pub fn[V] StrMap::first(self : StrMap[V]) -> (String, V)? {
  self.entries.get(0)
}

///|
pub fn[V, W] StrMap::map(self : StrMap[V], f : (V) -> W) -> StrMap[W] {
  { entries: self.entries.map(e => (e.0, f(e.1))), ordered: self.ordered, }
}

///|
/// Equal entries, in any order (as for `IndexMap` and `BTreeMap`).
pub impl[V : Eq] Eq for StrMap[V] with fn equal(self, other) {
  if !self.ordered && !other.ordered {
    return self.entries == other.entries
  }
  self.entries.length() == other.entries.length() &&
  self.entries.iter().all(e => other.get(e.0) is Some(v) && v == e.1)
}

///|
pub impl[V : Debug] Debug for StrMap[V] with fn to_repr(self) {
  Repr(Map::from_array(self.entries))
}
