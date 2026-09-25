// Rust expressions for JSON values of a given type (upstream value.rs).

///|
/// Render `value` as a Rust expression of the entry's type; `scope` prefixes
/// generated type names (e.g. `super::`).
pub fn output_value(
  space : @typify.TypeSpace,
  e : @typify.TypeEntry,
  value : @serde_json.Value,
  scope : Tokens,
) -> Tokens? raise @typify.TypifyError {
  let v = match e.details {
    Enum({ name, tag_type, variants, .. }) =>
      match tag_type {
        External => value_for_external_enum(space, name, variants, value, scope)
        Internal(tag~) =>
          value_for_internal_enum(space, name, variants, value, tag, scope)
        Adjacent(tag~, content~) =>
          value_for_adjacent_enum(
            space, name, variants, value, tag, content, scope,
          )
        Untagged => value_for_untagged_enum(space, name, variants, value, scope)
      }
    Struct({ name, properties, .. }) => {
      guard value_for_struct_props(properties, value, space, scope)
        is Some(props) else {
        return None
      }
      Some(
        quote("#scope #ident { #props }", args={
          "scope": scope,
          "ident": ident(name),
          "props": join(props, ','),
        }),
      )
    }
    Newtype({ name, type_id, .. }) => {
      // Upstream interpolates an `Option` here: `None` renders as nothing.
      let inner = output_value(space, entry(space, type_id), value, scope).unwrap_or(
        Tokens::new(),
      )
      Some(
        quote("#scope #ident ( #inner )", args={
          "scope": scope,
          "ident": ident(name),
          "inner": inner,
        }),
      )
    }
    Option(type_id) =>
      if value is Null {
        Some(quote("::std::option::Option::None"))
      } else {
        output_value(space, entry(space, type_id), value, scope).map(inner => {
          quote("::std::option::Option::Some(#inner)", args={ "inner": inner })
        })
      }
    Box(type_id) =>
      output_value(space, entry(space, type_id), value, scope).map(inner => {
        quote("::std::boxed::Box::new(#inner)", args={ "inner": inner })
      })
    Set(type_id) | Vec(type_id) => {
      guard value.as_array() is Some(arr) else { return None }
      guard all_values(space, entry(space, type_id), arr, scope) is Some(values) else {
        return None
      }
      Some(quote("vec![#values]", args={ "values": join(values, ',') }))
    }
    Map(key_id, value_id) => {
      guard value.as_object() is Some(obj) else { return None }
      let key_ty = entry(space, key_id)
      let value_ty = entry(space, value_id)
      let kvs = []
      for k, v in obj {
        guard output_value(space, key_ty, String(k), scope) is Some(kt) else {
          return None
        }
        guard output_value(space, value_ty, v, scope) is Some(vt) else {
          return None
        }
        kvs.push(quote("(#k, #v)", args={ "k": kt, "v": vt }))
      }
      Some(
        quote("[#kvs].into_iter().collect()", args={ "kvs": join(kvs, ',') }),
      )
    }
    Tuple(types) =>
      value_for_tuple(space, value, types, scope).map(tup => {
        Tokens::from_array([Group(Paren, join(tup, ','))])
      })
    Array(type_id, _) => {
      guard value.as_array() is Some(arr) else { return None }
      guard all_values(space, entry(space, type_id), arr, scope) is Some(values) else {
        return None
      }
      Some(Tokens::from_array([Group(Bracket, join(values, ','))]))
    }
    Unit => if value is Null { Some(quote("()")) } else { None }
    Native({ type_name, .. }) =>
      Some(
        quote(
          "::serde_json::from_str::< #path >(#text).expect(\"invalid default provided\")",
          args={
            "path": path_tokens(type_name),
            "text": lit_str(value.to_string()),
          },
        ),
      )
    JsonValue =>
      Some(
        quote(
          "::serde_json::from_str::<::serde_json::Value>(#text).expect(\"invalid default provided\")",
          args={ "text": lit_str(value.to_string()) },
        ),
      )
    Boolean => value.as_bool().map(lit_bool)
    Integer(type_name) | Float(type_name) => {
      if !value.is_number() {
        return None
      }
      if type_name.has_prefix(@typify.std_num_nonzero_prefix) {
        Some(
          quote("#path::new(#num).unwrap()", args={
            "path": path_tokens(type_name),
            "num": lit_raw(value.to_string()),
          }),
        )
      } else {
        // proc_macro2 splits a negative literal into `-` and the number.
        let repr = "\{value}_\{type_name}"
        if repr.has_prefix("-") {
          Some(
            Tokens::from_array([
              Punct('-', joint=false),
              Literal(repr.unsafe_substring(start=1, end=repr.length())),
            ]),
          )
        } else {
          Some(lit_raw(repr))
        }
      }
    }
    String =>
      value.as_str().map(s => quote("#s.to_string()", args={ "s": lit_str(s) }))
    Reference(_) =>
      raise @typify.TypifyError::Panic(
        "internal error: entered unreachable code",
      )
  }
  v
}

///|
fn all_values(
  space : @typify.TypeSpace,
  inner : @typify.TypeEntry,
  arr : Array[@serde_json.Value],
  scope : Tokens,
) -> Array[Tokens]? raise @typify.TypifyError {
  let out = []
  for v in arr {
    guard output_value(space, inner, v, scope) is Some(t) else { return None }
    out.push(t)
  }
  Some(out)
}

///|
fn find_variant(
  variants : Array[@typify.Variant],
  raw : String,
) -> @typify.Variant? {
  variants.search_by(v => v.raw_name == raw).map(i => variants[i])
}

///|
fn variant_path(
  scope : Tokens,
  type_name : String,
  v : @typify.Variant,
) -> Tokens {
  quote("#scope #t::#v", args={
    "scope": scope,
    "t": ident(type_name),
    "v": ident(v.ident_name.unwrap()),
  })
}

///|
fn value_for_external_enum(
  space : @typify.TypeSpace,
  type_name : String,
  variants : Array[@typify.Variant],
  value : @serde_json.Value,
  scope : Tokens,
) -> Tokens? raise @typify.TypifyError {
  if value.as_str() is Some(simple_name) {
    guard find_variant(variants, simple_name) is Some(variant) else {
      return None
    }
    guard variant.details is Simple else { return None }
    return Some(variant_path(scope, type_name, variant))
  }
  guard value.as_object() is Some(map) else { return None }
  if map.length() != 1 {
    return None
  }
  guard map.first() is Some((name, var_value)) else { return None }
  guard find_variant(variants, name) is Some(variant) else { return None }
  let path = variant_path(scope, type_name, variant)
  match variant.details {
    Simple => None
    Item(type_id) => {
      // Upstream interpolates an `Option` here: `None` renders as nothing.
      let item = output_value(space, entry(space, type_id), var_value, scope).unwrap_or(
        Tokens::new(),
      )
      Some(quote("#path ( #item )", args={ "path": path, "item": item }))
    }
    Tuple(types) =>
      value_for_tuple(space, var_value, types, scope).map(tup => {
        quote("#path ( #tup )", args={ "path": path, "tup": join(tup, ',') })
      })
    Struct(props) =>
      value_for_struct_props(props, var_value, space, scope).map(props => {
        quote("#path { #props }", args={
          "path": path,
          "props": join(props, ','),
        })
      })
  }
}

///|
fn value_for_internal_enum(
  space : @typify.TypeSpace,
  type_name : String,
  variants : Array[@typify.Variant],
  value : @serde_json.Value,
  tag : String,
  scope : Tokens,
) -> Tokens? raise @typify.TypifyError {
  guard value.as_object() is Some(map) else { return None }
  guard map.get(tag).bind(v => v.as_str()) is Some(ser_name) else {
    return None
  }
  guard find_variant(variants, ser_name) is Some(variant) else { return None }
  let path = variant_path(scope, type_name, variant)
  match variant.details {
    Simple => Some(path)
    Struct(props) => {
      let inner = map.copy()
      ignore(inner.remove(tag))
      value_for_struct_props(props, Object(inner), space, scope).map(props => {
        quote("#path { #props }", args={
          "path": path,
          "props": join(props, ','),
        })
      })
    }
    Item(_) | Tuple(_) =>
      raise @typify.TypifyError::Panic(
        "internal error: entered unreachable code",
      )
  }
}

///|
fn value_for_adjacent_enum(
  space : @typify.TypeSpace,
  type_name : String,
  variants : Array[@typify.Variant],
  value : @serde_json.Value,
  tag : String,
  content : String,
  scope : Tokens,
) -> Tokens? raise @typify.TypifyError {
  guard value.as_object() is Some(map) else { return None }
  let tag_value = map.get(tag).bind(v => v.as_str())
  let (tag_value, content_value) = match
    (map.length(), tag_value, map.get(content)) {
    (1, Some(t), None) => (t, None)
    (2, Some(t), Some(c)) => (t, Some(c))
    _ => return None
  }
  guard find_variant(variants, tag_value) is Some(variant) else { return None }
  let path = variant_path(scope, type_name, variant)
  match (variant.details, content_value) {
    (Simple, None) => Some(path)
    (Tuple(types), Some(c)) =>
      value_for_tuple(space, c, types, scope).map(tup => {
        quote("#path ( #tup )", args={ "path": path, "tup": join(tup, ',') })
      })
    (Struct(props), Some(c)) =>
      value_for_struct_props(props, c, space, scope).map(props => {
        quote("#path { #props }", args={
          "path": path,
          "props": join(props, ','),
        })
      })
    _ => None
  }
}

///|
fn value_for_untagged_enum(
  space : @typify.TypeSpace,
  type_name : String,
  variants : Array[@typify.Variant],
  value : @serde_json.Value,
  scope : Tokens,
) -> Tokens? raise @typify.TypifyError {
  for variant in variants {
    let path = variant_path(scope, type_name, variant)
    let result = match variant.details {
      Simple => if value is Null { Some(path) } else { None }
      Item(type_id) =>
        output_value(space, entry(space, type_id), value, scope).map(item => {
          quote("#path ( #item )", args={ "path": path, "item": item })
        })
      Tuple(types) =>
        value_for_tuple(space, value, types, scope).map(tup => {
          quote("#path ( #tup )", args={ "path": path, "tup": join(tup, ',') })
        })
      Struct(props) =>
        value_for_struct_props(props, value, space, scope).map(props => {
          quote("#path { #props }", args={
            "path": path,
            "props": join(props, ','),
          })
        })
    }
    if result is Some(_) {
      return result
    }
  }
  None
}

///|
fn value_for_tuple(
  space : @typify.TypeSpace,
  value : @serde_json.Value,
  types : Array[@typify.TypeId],
  scope : Tokens,
) -> Array[Tokens]? raise @typify.TypifyError {
  guard value.as_array() is Some(arr) else { return None }
  if arr.length() != types.length() {
    return None
  }
  let out = []
  for i, type_id in types {
    guard output_value(space, entry(space, type_id), arr[i], scope) is Some(t) else {
      return None
    }
    out.push(t)
  }
  Some(out)
}

///|
fn serialized_name(prop : @typify.StructProperty) -> String? {
  match prop.rename {
    NoRename => Some(prop.name)
    Rename(r) => Some(r)
    Flatten => None
  }
}

///|
fn value_for_struct_props(
  properties : Array[@typify.StructProperty],
  value : @serde_json.Value,
  space : @typify.TypeSpace,
  scope : Tokens,
) -> Array[Tokens]? raise @typify.TypifyError {
  guard value.as_object() is Some(map) else { return None }
  let out = []
  for prop in properties {
    guard serialized_name(prop) is Some(name) else { continue }
    let name_ident = ident(prop.name)
    match map.get(name) {
      // Upstream's `?` inside `filter_map` skips unrenderable properties.
      Some(v) =>
        if output_value(space, entry(space, prop.type_id), v, scope)
          is Some(prop_value) {
          out.push(quote("#n: #v", args={ "n": name_ident, "v": prop_value }))
        }
      None =>
        out.push(quote("#n: Default::default()", args={ "n": name_ident }))
    }
  }
  let direct = @collections.StrSet::new()
  for prop in properties {
    if serialized_name(prop) is Some(name) {
      direct.add(name)
    }
  }
  let extra = @collections.StrMap::new()
  for k, v in map {
    if !direct.contains(k) {
      extra.set(k, v)
    }
  }
  let extra_value : @serde_json.Value = Object(extra)
  for prop in properties {
    guard prop.rename is Flatten else { continue }
    let type_entry = entry(space, prop.type_id)
    match type_entry.details {
      Struct(_) | Option(_) | Map(_, _) => ()
      _ =>
        raise @typify.TypifyError::Panic(
          "internal error: entered unreachable code",
        )
    }
    if output_value(space, type_entry, extra_value, scope) is Some(flat_value) {
      out.push(quote("#n: #v", args={ "n": ident(prop.name), "v": flat_value }))
    }
  }
  Some(out)
}
