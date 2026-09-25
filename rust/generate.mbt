// Whole-type-space Rust output (upstream lib.rs `to_stream`).

///|
let base_derives : Array[String] = [
  "::serde::Serialize", "::serde::Deserialize", "Debug", "Clone",
]

///|
fn output_entry(
  space : @typify.TypeSpace,
  e : @typify.TypeEntry,
  output : OutputSpace,
) -> Unit raise @typify.TypifyError {
  match e.details {
    Enum(d) => output_enum(space, e, output, d, base_derives)
    Struct(d) => output_struct(space, e, output, d, base_derives)
    Newtype(d) => output_newtype(space, e, output, d, base_derives)
    Reference(_) => abort("internal error: entered unreachable code")
    _ => ()
  }
}

///|
let conversion_error_item : String =
  #|#[doc = r" Error from a `TryFrom` or `FromStr` implementation."]
  #|pub struct ConversionError(::std::borrow::Cow<'static, str>);
  #|impl ::std::error::Error for ConversionError {}
  #|impl ::std::fmt::Display for ConversionError {
  #|    fn fmt(&self, f: &mut ::std::fmt::Formatter<'_>) -> Result<(), ::std::fmt::Error> {
  #|        ::std::fmt::Display::fmt(&self.0, f)
  #|    }
  #|}
  #|impl ::std::fmt::Debug for ConversionError {
  #|    fn fmt(&self, f: &mut ::std::fmt::Formatter<'_>) -> Result<(), ::std::fmt::Error> {
  #|        ::std::fmt::Debug::fmt(&self.0, f)
  #|    }
  #|}
  #|impl From<&'static str> for ConversionError {
  #|    fn from(value: &'static str) -> Self {
  #|        Self(value.into())
  #|    }
  #|}
  #|impl From<String> for ConversionError {
  #|    fn from(value: String) -> Self {
  #|        Self(value.into())
  #|    }
  #|}

///|
/// All Rust code for the type space, as tokens (upstream `to_stream`).
pub fn to_stream(space : @typify.TypeSpace) -> Tokens raise @typify.TypifyError {
  let output = OutputSpace::new()
  for pair in space.entries() {
    output_entry(space, pair.1, output)
  }
  // Shared default functions that some emitted item calls.
  let called = space.defaults.filter(d => output.contains(d.fn_name()))
  for d in called {
    output.add_item(Defaults, "", default_impl_tokens(d))
  }
  // The error type, only when referenced.
  if output.contains("ConversionError") {
    output.add_item(Error, "", quote(conversion_error_item))
  }
  output.into_stream()
}

///|
/// The Rust type expression for a type id (upstream `Type::ident`).
pub fn ident_of(space : @typify.TypeSpace, id : @typify.TypeId) -> Tokens {
  type_ident(space, entry(space, id), space.settings.type_mod)
}

///|
/// The builder type path for a struct type, when builders are enabled
/// (upstream `Type::builder`).
pub fn builder_of(space : @typify.TypeSpace, id : @typify.TypeId) -> Tokens? {
  if !space.settings.struct_builder {
    return None
  }
  match entry(space, id).details {
    Struct({ name, .. }) =>
      match space.settings.type_mod {
        Some(m) =>
          Some(
            quote("#m :: builder :: #n", args={
              "m": ident(m),
              "n": ident(name),
            }),
          )
        None => Some(quote("builder :: #n", args={ "n": ident(name) }))
      }
    _ => None
  }
}
