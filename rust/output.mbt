// Collected output items (upstream output.rs).

///|
pub(all) enum OutputSpaceMod {
  Crate
  Builder
  Defaults
  Error
} derive(Eq, Debug)

///|
fn OutputSpaceMod::index(self : OutputSpaceMod) -> Int {
  match self {
    Crate => 0
    Builder => 1
    Defaults => 2
    Error => 3
  }
}

///|
/// Items keyed by module, then by an order hint (the type name).
pub struct OutputSpace {
  priv items : Array[@collections.StrMap[Tokens]]
}

///|
pub fn OutputSpace::new() -> OutputSpace {
  { items: Array::makei(4, _ => @collections.StrMap::new()), }
}

///|
pub fn OutputSpace::add_item(
  self : OutputSpace,
  location : OutputSpaceMod,
  order_hint : String,
  stream : Tokens,
) -> Unit {
  let m = self.items[location.index()]
  match m.get(order_hint) {
    Some(existing) => existing.append(stream)
    None => {
      let t = Tokens::new()
      t.append(stream)
      m.set(order_hint, t)
    }
  }
}

///|
/// Whether any item's rendered tokens contain `needle`.
pub fn OutputSpace::contains(self : OutputSpace, needle : String) -> Bool {
  for m in self.items {
    for _, stream in m {
      if stream.to_string().contains(needle) {
        return true
      }
    }
  }
  false
}

///|
pub fn OutputSpace::into_stream(self : OutputSpace) -> Tokens {
  let out = Tokens::new()
  for i, m in self.items {
    if m.is_empty() {
      continue
    }
    let items = concat(m.values())
    match i {
      0 => out.append(items)
      1 =>
        out.append(
          quote(
            "#[doc = \" Types for composing complex structures.\"] pub mod builder { #items }",
            args={ "items": items },
          ),
        )
      2 =>
        out.append(
          quote(
            "#[doc = \" Generation of default values for serde.\"] pub mod defaults { #items }",
            args={ "items": items },
          ),
        )
      _ =>
        out.append(
          quote("#[doc = \" Error types.\"] pub mod error { #items }", args={
            "items": items,
          }),
        )
    }
  }
  out
}
