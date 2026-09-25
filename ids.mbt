///|
/// Identifier of a type within a `TypeSpace`.
pub(all) struct TypeId(Int) derive(Eq, Compare, Hash, Debug)

///|
pub impl Show for TypeId with fn output(self, logger) {
  logger.write_string("TypeId(\{self.0})")
}

///|
/// A name for a type being converted.
pub(all) enum Name {
  /// The name must be used (a named definition).
  Required(String)
  /// A hint for a name; the schema title takes precedence.
  Suggested(String)
  Unknown
} derive(Eq, Debug)

///|
pub fn Name::into_option(self : Name) -> String? {
  match self {
    Required(s) | Suggested(s) => Some(s)
    Unknown => None
  }
}

///|
/// Derive a suggested sub-name: `prefix_s`.
pub fn Name::append(self : Name, s : String) -> Name {
  match self {
    Required(prefix) | Suggested(prefix) => Suggested("\{prefix}_\{s}")
    Unknown => Unknown
  }
}

///|
/// A key for referenceable schemas: the root or a named definition.
pub(all) enum RefKey {
  Root
  Def(String)
} derive(Eq, Hash, Debug)
