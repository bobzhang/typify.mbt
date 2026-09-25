///|
/// A set of strings ordered by code point (Rust `BTreeSet<String>`).
pub struct StrSet {
  priv map : StrMap[Unit]
}

///|
pub fn StrSet::new() -> StrSet {
  { map: StrMap::new(), }
}

///|
pub fn StrSet::from_array(items : ArrayView[String]) -> StrSet {
  let s = StrSet::new()
  for item in items {
    s.add(item)
  }
  s
}

///|
/// Insert; returns `true` if the item was not present.
pub fn StrSet::insert(self : StrSet, item : String) -> Bool {
  self.map.insert(item, ()) is None
}

///|
/// Insert, ignoring whether the item was already present.
pub fn StrSet::add(self : StrSet, item : String) -> Unit {
  self.map.set(item, ())
}

///|
pub fn StrSet::remove(self : StrSet, item : StringView) -> Bool {
  self.map.remove(item) is Some(_)
}

///|
pub fn StrSet::contains(self : StrSet, item : StringView) -> Bool {
  self.map.contains(item)
}

///|
pub fn StrSet::length(self : StrSet) -> Int {
  self.map.length()
}

///|
pub fn StrSet::is_empty(self : StrSet) -> Bool {
  self.map.is_empty()
}

///|
/// Items in order.
pub fn StrSet::iter(self : StrSet) -> Iter[String] {
  self.map.iter().map(e => e.0)
}

///|
pub fn StrSet::to_array(self : StrSet) -> Array[String] {
  self.map.keys()
}

///|
pub fn StrSet::copy(self : StrSet) -> StrSet {
  { map: self.map.copy(), }
}

///|
pub fn StrSet::union(self : StrSet, other : StrSet) -> StrSet {
  let out = self.copy()
  for item in other.iter() {
    out.add(item)
  }
  out
}

///|
pub fn StrSet::is_subset(self : StrSet, other : StrSet) -> Bool {
  self.iter().all(item => other.contains(item))
}

///|
pub impl Eq for StrSet with fn equal(self, other) {
  self.map == other.map
}

///|
pub impl Debug for StrSet with fn to_repr(self) {
  Repr(self.to_array())
}
