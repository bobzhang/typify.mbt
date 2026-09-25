// Rust type expressions for IR types (upstream `TypeEntry::type_ident`).

///|
fn entry(space : @typify.TypeSpace, id : @typify.TypeId) -> @typify.TypeEntry {
  match space.id_to_entry.get(id) {
    Some(e) => e
    None => abort("unresolved type id \{id}")
  }
}

///|
/// The Rust type for an entry, optionally qualified by a module (`super`).
pub fn type_ident(
  space : @typify.TypeSpace,
  e : @typify.TypeEntry,
  type_mod : String?,
) -> Tokens {
  match e.details {
    Enum({ name, .. }) | Struct({ name, .. }) | Newtype({ name, .. }) =>
      match type_mod {
        Some(m) => quote("#m :: #n", args={ "m": ident(m), "n": ident(name) })
        None => ident(name)
      }
    Option(id) => {
      let inner = entry(space, id)
      let inner_ident = type_ident(space, inner, type_mod)
      // Nested options are flattened.
      match inner.details {
        Option(_) => inner_ident
        _ => quote("::std::option::Option<#t>", args={ "t": inner_ident })
      }
    }
    Box(id) =>
      quote("::std::boxed::Box<#t>", args={
        "t": type_ident(space, entry(space, id), type_mod),
      })
    Vec(id) | Set(id) =>
      quote("::std::vec::Vec<#t>", args={
        "t": type_ident(space, entry(space, id), type_mod),
      })
    Map(key_id, value_id) => {
      let key = entry(space, key_id)
      let value = entry(space, value_id)
      if key.details is String && value.details is JsonValue {
        quote("::serde_json::Map<::std::string::String, ::serde_json::Value>")
      } else {
        quote("#m<#k, #v>", args={
          "m": path_tokens(space.settings.map_type),
          "k": type_ident(space, key, type_mod),
          "v": type_ident(space, value, type_mod),
        })
      }
    }
    Tuple(items) => {
      let idents = items.map(id => type_ident(space, entry(space, id), type_mod))
      let inner = if items.length() != 1 {
        join(idents, ',')
      } else {
        terminated(idents, ',')
      }
      Tokens::from_array([Group(Paren, inner)])
    }
    Array(item_id, length) =>
      Tokens::from_array([
        Group(
          Bracket,
          quote("#t; #n", args={
            "t": type_ident(space, entry(space, item_id), type_mod),
            "n": lit_usize(length),
          }),
        ),
      ])
    Native({ type_name, parameters, .. }) => {
      let path = path_tokens(type_name)
      if parameters.is_empty() {
        path
      } else {
        let idents = parameters.map(id => {
          type_ident(space, entry(space, id), type_mod)
        })
        quote("#p < #ts >", args={ "p": path, "ts": terminated(idents, ',') })
      }
    }
    Unit => quote("()")
    String => quote("::std::string::String")
    Boolean => ident("bool")
    JsonValue => quote("::serde_json::Value")
    Integer(name) | Float(name) => path_tokens(name)
    Reference(_) => abort("references should be resolved by now")
  }
}

///|
/// The type as a function parameter: complex types are borrowed
/// (upstream `type_parameter_ident`).
pub fn type_parameter_ident(
  space : @typify.TypeSpace,
  e : @typify.TypeEntry,
  lifetime? : String,
) -> Tokens {
  let lt = match lifetime {
    Some(s) => Tokens::from_array([Punct('\'', joint=true), Ident(s)])
    None => Tokens::new()
  }
  let type_mod = space.settings.type_mod
  match e.details {
    Enum({ variants, .. }) if variants.iter().all(v => v.details is Simple) =>
      type_ident(space, e, type_mod)
    Enum(_)
    | Struct(_)
    | Newtype(_)
    | Vec(_)
    | Map(_, _)
    | Set(_)
    | Box(_)
    | Native(_)
    | Array(_, _)
    | JsonValue =>
      quote("& #lt #t", args={ "lt": lt, "t": type_ident(space, e, type_mod) })
    Option(id) => {
      let inner = entry(space, id)
      let inner_ident = type_parameter_ident(space, inner, lifetime?)
      match inner.details {
        Option(_) => inner_ident
        _ => quote("Option<#t>", args={ "t": inner_ident })
      }
    }
    Tuple(items) => {
      let streams = items.map(id => {
        type_parameter_ident(space, entry(space, id), lifetime?)
      })
      let inner = if items.length() != 1 {
        join(streams, ',')
      } else {
        terminated(streams, ',')
      }
      Tokens::from_array([Group(Paren, inner)])
    }
    Unit | Boolean | Integer(_) | Float(_) => type_ident(space, e, type_mod)
    String => quote("& #lt str", args={ "lt": lt })
    Reference(_) => abort("references should be resolved by now")
  }
}
