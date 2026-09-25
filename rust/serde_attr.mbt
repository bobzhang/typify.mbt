// Serde attributes for struct properties and default-value functions
// (upstream structs.rs `generate_serde_attr`, defaults.rs `default_fn`).

///|
priv enum DefaultFunction {
  NoDefault
  DefaultDefault
  Custom(String)
}

///|
fn generate_serde_attr(
  type_name : String,
  prop_name : String,
  naming : @typify.StructPropertyRename,
  state : @typify.StructPropertyState,
  prop_type : @typify.TypeEntry,
  space : @typify.TypeSpace,
  output : OutputSpace,
) -> (Tokens, DefaultFunction) {
  let options : Array[Tokens] = []
  match naming {
    Rename(s) => options.push(quote("rename = #s", args={ "s": lit_str(s) }))
    Flatten => options.push(quote("flatten"))
    NoRename => ()
  }
  let default_fn : DefaultFunction = match (state, prop_type.details) {
    (Optional, Option(_)) => {
      options.push(
        quote("skip_serializing_if = \"::std::option::Option::is_none\""),
      )
      DefaultDefault
    }
    (Optional, Vec(_)) => {
      options.push(quote("default"))
      options.push(quote("skip_serializing_if = \"::std::vec::Vec::is_empty\""))
      DefaultDefault
    }
    (Optional, Map(key_id, value_id)) => {
      options.push(quote("default"))
      let key_ty = entry(space, key_id)
      let value_ty = entry(space, value_id)
      if key_ty.details is String && value_ty.details is JsonValue {
        options.push(
          quote("skip_serializing_if = \"::serde_json::Map::is_empty\""),
        )
      } else {
        let is_empty = "\{path_tokens(space.settings.map_type)}::is_empty"
        options.push(
          quote("skip_serializing_if = #s", args={ "s": lit_str(is_empty) }),
        )
      }
      DefaultDefault
    }
    (Optional, _) => {
      options.push(quote("default"))
      DefaultDefault
    }
    (Default(value), _) => {
      let (fn_name, def) = default_fn(
        prop_type, value, space, type_name, prop_name,
      )
      options.push(quote("default = #s", args={ "s": lit_str(fn_name) }))
      if def is Some(def) {
        output.add_item(Defaults, type_name, def)
      }
      Custom(fn_name)
    }
    (Required, Option(_)) => {
      options.push(
        quote("deserialize_with = \"::std::option::Option::deserialize\""),
      )
      NoDefault
    }
    (Required, _) => NoDefault
  }
  let serde = if options.is_empty() {
    Tokens::new()
  } else {
    quote("#[serde( #opts )]", args={ "opts": join(options, ',') })
  }
  (serde, default_fn)
}

///|
/// The function producing a default value: a shared generic one where
/// possible, otherwise a generated `defaults::<type>_<prop>` function.
fn default_fn(
  e : @typify.TypeEntry,
  value : @serde_json.Value,
  space : @typify.TypeSpace,
  type_name : String,
  prop_name : String,
) -> (String, Tokens?) {
  let builtin = match e.details {
    Unit => abort("internal error: entered unreachable code")
    Boolean => Some("defaults::default_bool::<true>")
    Integer(name) =>
      match (value.as_u64(), value.as_i64()) {
        (Some(v), _) =>
          if name.has_prefix(@typify.std_num_nonzero_prefix) {
            Some("defaults::default_nzu64::<\{name}, \{v}>")
          } else {
            Some("defaults::default_u64::<\{name}, \{v}>")
          }
        (None, Some(v)) => Some("defaults::default_i64::<\{name}, \{v}>")
        _ => abort("explicit panic")
      }
    _ => None
  }
  if builtin is Some(name) {
    return (name, None)
  }
  let n = type_ident(space, e, Some("super"))
  guard output_value(space, e, value, quote("super::")) is Some(v) else {
    abort(
      "The default value could not be rendered for this type\nvalue: \{value.to_string_pretty()}",
    )
  }
  let fn_name = @typify.sanitize("\{type_name}_\{prop_name}", Snake)
  let def = quote("pub(super) fn #f() -> #n { #v }", args={
    "f": ident(fn_name),
    "n": n,
    "v": v,
  })
  ("defaults::\{fn_name}", Some(def))
}

///|
/// The shared default functions (`defaults::default_*`).
fn default_impl_tokens(d : @typify.DefaultImpl) -> Tokens {
  match d {
    Boolean =>
      quote("pub(super) fn default_bool<const V: bool>() -> bool { V }")
    I64 =>
      quote(
        "pub(super) fn default_i64<T, const V: i64>() -> T where T: ::std::convert::TryFrom<i64>, <T as ::std::convert::TryFrom<i64>>::Error: ::std::fmt::Debug, { T::try_from(V).unwrap() }",
      )
    U64 =>
      quote(
        "pub(super) fn default_u64<T, const V: u64>() -> T where T: ::std::convert::TryFrom<u64>, <T as ::std::convert::TryFrom<u64>>::Error: ::std::fmt::Debug, { T::try_from(V).unwrap() }",
      )
    NZU64 =>
      quote(
        "pub(super) fn default_nzu64<T, const V: u64>() -> T where T: ::std::convert::TryFrom<::std::num::NonZeroU64>, <T as ::std::convert::TryFrom<::std::num::NonZeroU64>>::Error: ::std::fmt::Debug, { T::try_from(::std::num::NonZeroU64::try_from(V).unwrap()).unwrap() }",
      )
  }
}

///|
/// A doc attribute: the description, or the type name in backticks.
fn make_doc(name : String, description : String?) -> Tokens {
  let desc = match description {
    Some(d) => d
    None => "`\{name}`"
  }
  quote("#[doc = #d]", args={ "d": lit_str(desc) })
}

///|
/// Derive paths: the base set plus extra and per-type derives, sorted and
/// deduplicated (a `BTreeSet<&str>` upstream).
fn strings_to_derives(
  derive_set : Array[String],
  type_derives : @collections.StrSet,
  extra_derives : Array[String],
) -> Array[Tokens] {
  let combined = @collections.StrSet::from_array(derive_set)
  for d in extra_derives {
    combined.add(d)
  }
  for d in type_derives.iter() {
    combined.add(d)
  }
  combined.to_array().map(path_tokens)
}

///|
fn strings_to_attrs(
  type_attrs : @collections.StrSet,
  extra_attrs : Array[String],
) -> Array[Tokens] {
  let combined = @collections.StrSet::from_array(extra_attrs)
  for a in type_attrs.iter() {
    combined.add(a)
  }
  combined.to_array().map(parse_tokens)
}
