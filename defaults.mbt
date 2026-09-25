// Default-value validation (upstream defaults.rs, minus code emission).

///|
/// How a default value can be produced.
pub(all) enum DefaultKind {
  /// The type's natural default (null, [], {}, false, 0, "").
  Intrinsic
  /// Needs a bespoke function.
  Specific
  /// Covered by a shared generic function.
  Generic(DefaultImpl)
} derive(Debug)

///|
pub let std_num_nonzero_prefix : String = "::std::num::NonZero"

///|
fn TypeEntry::check_defaults(
  self : TypeEntry,
  space : TypeSpace,
) -> Unit raise TypifyError {
  match self.details {
    Enum({ default: Some(d), .. })
    | Struct({ default: Some(d), .. })
    | Newtype({ default: Some(d), .. }) =>
      if self.validate_value(space, d) is Generic(f) {
        space.add_default_impl(f)
      }
    _ => ()
  }
  match self.details {
    Struct({ properties, .. }) =>
      for prop in properties {
        check_property_defaults(prop, space)
      }
    Enum({ variants, .. }) =>
      for variant in variants {
        if variant.details is Struct(props) {
          for prop in props {
            check_property_defaults(prop, space)
          }
        }
      }
    _ => ()
  }
}

///|
fn check_property_defaults(
  prop : StructProperty,
  space : TypeSpace,
) -> Unit raise TypifyError {
  if prop.state is Default(value) {
    let entry = space.entry_unchecked(prop.type_id)
    if entry.validate_value(space, value) is Generic(f) {
      space.add_default_impl(f)
    }
  }
}

///|
/// Check that a value is a valid instance of this type, and classify how a
/// default of that value can be produced.
pub fn TypeEntry::validate_value(
  self : TypeEntry,
  space : TypeSpace,
  value : @serde_json.Value,
) -> DefaultKind raise TypifyError {
  let or_invalid = (k : DefaultKind?) => {
    match k {
      Some(k) => k
      None => raise InvalidValue
    }
  }
  match self.details {
    Enum({ tag_type, variants, .. }) =>
      match tag_type {
        External =>
          or_invalid(validate_default_for_external_enum(space, variants, value))
        Internal(tag~) =>
          or_invalid(
            validate_default_for_internal_enum(space, variants, value, tag),
          )
        Adjacent(tag~, content~) =>
          or_invalid(
            validate_default_for_adjacent_enum(
              space, variants, value, tag, content,
            ),
          )
        Untagged =>
          or_invalid(validate_default_for_untagged_enum(space, variants, value))
      }
    Struct({ properties, .. }) =>
      or_invalid(validate_default_struct_props(properties, space, value))
    Newtype({ type_id, .. }) => {
      ignore(validate_type_id(type_id, space, value))
      Specific
    }
    Option(type_id) =>
      if value is Null {
        Intrinsic
      } else {
        ignore(validate_type_id(type_id, space, value))
        Specific
      }
    Box(type_id) => validate_type_id(type_id, space, value)
    Vec(type_id) =>
      match value {
        Array([]) => Intrinsic
        Array(items) => {
          let entry = space.entry_unchecked(type_id)
          for item in items {
            ignore(entry.validate_value(space, item))
          }
          Specific
        }
        _ => raise InvalidValue
      }
    Map(key_id, value_id) =>
      match value {
        Object(m) if m.is_empty() => Intrinsic
        Object(m) => {
          let key_ty = space.entry_unchecked(key_id)
          let value_ty = space.entry_unchecked(value_id)
          for k, v in m {
            ignore(key_ty.validate_value(space, String(k)))
            ignore(value_ty.validate_value(space, v))
          }
          Specific
        }
        _ => raise InvalidValue
      }
    Set(type_id) =>
      match value {
        Array([]) => Intrinsic
        Array(items) => {
          let entry = space.entry_unchecked(type_id)
          for i, item in items {
            for j in (i + 1)..<items.length() {
              if item == items[j] {
                raise InvalidValue
              }
            }
            ignore(entry.validate_value(space, item))
          }
          Specific
        }
        _ => raise InvalidValue
      }
    Tuple(ids) => or_invalid(validate_default_tuple(ids, space, value))
    Array(type_id, length) => {
      guard value is Array(arr) else { raise InvalidValue }
      if arr.length() != length {
        raise InvalidValue
      }
      let entry = space.entry_unchecked(type_id)
      for item in arr {
        ignore(entry.validate_value(space, item))
      }
      Specific
    }
    Unit => if value is Null { Intrinsic } else { raise InvalidValue }
    Native(_) => Specific
    JsonValue => Specific
    Boolean =>
      match value {
        Bool(false) => Intrinsic
        Bool(true) => Generic(Boolean)
        _ => raise InvalidValue
      }
    Integer(itype) =>
      match (value.as_u64(), value.as_i64()) {
        (None, None) => raise InvalidValue
        (Some(0UL), _) => Intrinsic
        (Some(_), _) =>
          if itype.has_prefix(std_num_nonzero_prefix) {
            Generic(NZU64)
          } else {
            Generic(U64)
          }
        (_, Some(_)) => Generic(I64)
      }
    Float(_) =>
      match value.as_f64() {
        Some(v) => if v == 0.0 { Intrinsic } else { Generic(I64) }
        None => raise InvalidValue
      }
    String => if value is String("") { Intrinsic } else { Specific }
    Reference(_) => raise panic_with("internal error: entered unreachable code")
  }
}

///|
/// `validate_type_id(..).ok()` that still propagates panics.
fn validate_ok(
  type_id : TypeId,
  space : TypeSpace,
  value : @serde_json.Value,
) -> DefaultKind? raise TypifyError {
  ok(() => validate_type_id(type_id, space, value))
}

///|
fn validate_default_for_external_enum(
  space : TypeSpace,
  variants : Array[Variant],
  value : @serde_json.Value,
) -> DefaultKind? raise TypifyError {
  if value.as_str() is Some(simple_name) {
    guard variants.search_by(v => v.raw_name == simple_name) is Some(i) else {
      return None
    }
    return if variants[i].details is Simple { Some(Specific) } else { None }
  }
  guard value.as_object() is Some(map) else { return None }
  if map.length() != 1 {
    return None
  }
  guard map.first() is Some((name, inner)) else { return None }
  guard variants.search_by(v => v.raw_name == name) is Some(i) else {
    return None
  }
  match variants[i].details {
    Simple => None
    Item(type_id) => validate_ok(type_id, space, inner)
    Tuple(tup) => validate_default_tuple(tup, space, inner)
    Struct(props) => validate_default_struct_props(props, space, inner)
  }
}

///|
fn validate_default_for_internal_enum(
  space : TypeSpace,
  variants : Array[Variant],
  value : @serde_json.Value,
  tag : String,
) -> DefaultKind? raise TypifyError {
  guard value.as_object() is Some(map) else { return None }
  guard map.get(tag).bind(v => v.as_str()) is Some(name) else { return None }
  guard variants.search_by(v => v.raw_name == name) is Some(i) else {
    return None
  }
  match variants[i].details {
    Simple => Some(Specific)
    Struct(props) => {
      let inner = map.copy()
      ignore(inner.remove(tag))
      validate_default_struct_props(props, space, Object(inner))
    }
    Item(_) | Tuple(_) =>
      raise panic_with("internal error: entered unreachable code")
  }
}

///|
fn validate_default_for_adjacent_enum(
  space : TypeSpace,
  variants : Array[Variant],
  value : @serde_json.Value,
  tag : String,
  content : String,
) -> DefaultKind? raise TypifyError {
  guard value.as_object() is Some(map) else { return None }
  let tag_value = map.get(tag).bind(v => v.as_str())
  let content_value = map.get(content)
  let (tag_value, content_value) = match
    (map.length(), tag_value, content_value) {
    (1, Some(t), None) => (t, None)
    (2, Some(t), Some(c)) => (t, Some(c))
    _ => return None
  }
  guard variants.search_by(v => v.raw_name == tag_value) is Some(i) else {
    return None
  }
  match (variants[i].details, content_value) {
    (Simple, None) => Some(Specific)
    (Tuple(tup), Some(c)) => validate_default_tuple(tup, space, c)
    (Struct(props), Some(c)) => validate_default_struct_props(props, space, c)
    _ => None
  }
}

///|
fn validate_default_for_untagged_enum(
  space : TypeSpace,
  variants : Array[Variant],
  value : @serde_json.Value,
) -> DefaultKind? raise TypifyError {
  for variant in variants {
    let result = match variant.details {
      Simple => if value is Null { Some(Specific) } else { None }
      Item(type_id) => validate_ok(type_id, space, value)
      Tuple(tup) => validate_default_tuple(tup, space, value)
      Struct(props) => validate_default_struct_props(props, space, value)
    }
    if result is Some(_) {
      return result
    }
  }
  None
}

///|
fn validate_type_id(
  type_id : TypeId,
  space : TypeSpace,
  value : @serde_json.Value,
) -> DefaultKind raise TypifyError {
  space.entry_unchecked(type_id).validate_value(space, value)
}

///|
fn validate_default_tuple(
  types : Array[TypeId],
  space : TypeSpace,
  value : @serde_json.Value,
) -> DefaultKind? raise TypifyError {
  guard value.as_array() is Some(arr) else { return None }
  if arr.length() != types.length() {
    return None
  }
  for i, type_id in types {
    if validate_ok(type_id, space, arr[i]) is None {
      return None
    }
  }
  Some(Specific)
}

///|
fn validate_default_struct_props(
  properties : Array[StructProperty],
  space : TypeSpace,
  value : @serde_json.Value,
) -> DefaultKind? raise TypifyError {
  guard value.as_object() is Some(map) else { return None }
  let named : @collections.StrMap[(TypeId, Bool)] = @collections.StrMap::new()
  let unnamed : Array[TypeId] = []
  for prop in properties {
    for p in all_props(prop, space) {
      match p.0 {
        Some(name) => named.set(name, (p.1, p.2))
        None => unnamed.push(p.1)
      }
    }
  }
  for name, default_value in map {
    match named.get(name) {
      Some((type_id, _)) =>
        if validate_ok(type_id, space, default_value) is None {
          return None
        }
      None => {
        let mut any = false
        for type_id in unnamed {
          if validate_ok(type_id, space, default_value) is Some(_) {
            any = true
            break
          }
        }
        if !any {
          return None
        }
      }
    }
  }
  for name, info in named {
    if info.1 && !map.contains(name) {
      return None
    }
  }
  Some(Specific)
}

///|
/// All (possibly flattened) properties: (name, type, required).
fn all_props(
  prop : StructProperty,
  space : TypeSpace,
) -> Array[(String?, TypeId, Bool)] raise TypifyError {
  let maybe_name = match prop.rename {
    NoRename => Some(prop.name)
    Rename(r) => Some(r)
    Flatten => None
  }
  if maybe_name is Some(name) {
    return [(Some(name), prop.type_id, prop.state is Required)]
  }
  let entry = space.entry_unchecked(prop.type_id)
  let (properties, all_required) = match entry.details {
    Struct({ properties, .. }) => (properties, !(prop.state is Optional))
    Option(inner) =>
      match space.entry_unchecked(inner).details {
        Struct({ properties, .. }) => (properties, false)
        _ => raise panic_with("internal error: entered unreachable code")
      }
    Map(_, value_id) => return [(None, value_id, false)]
    _ => raise panic_with("internal error: entered unreachable code")
  }
  let out = []
  for p in properties {
    for x in all_props(p, space) {
      out.push((x.0, x.1, x.2 && all_required))
    }
  }
  out
}
