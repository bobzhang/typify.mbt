// Enum conversion (upstream enums.rs, minus code emission).

///|
/// `oneOf`/`anyOf` with exactly one non-null subschema is an `Option`.
fn TypeSpace::maybe_option(
  self : TypeSpace,
  type_name : Name,
  metadata : @schema.Metadata?,
  subschemas : Array[@schema.Schema],
) -> TypeEntry? raise TypifyError {
  if subschemas.length() == 1 {
    return None
  }
  let non_nulls = subschemas.filter(s => !is_null_schema(s))
  guard non_nulls is [non_null] else { return None }
  ok(() => self.convert_option(type_name, metadata, non_null).0)
}

///|
priv enum ProtoVariant {
  Simple(String, String?)
  Typed(String, @schema.Schema, String?)
}

///|
fn ProtoVariant::name(self : ProtoVariant) -> String {
  match self {
    Simple(n, _) | Typed(n, _, _) => n
  }
}

///|
/// The string or null instance type restriction for simple variants.
fn string_or_untyped(o : @schema.SchemaObject) -> Bool {
  match o.instance_type {
    Some(Single(String)) | None => true
    _ => false
  }
}

///|
fn TypeSpace::maybe_externally_tagged_enum(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  enum_metadata : @schema.Metadata?,
  subschemas : Array[@schema.Schema],
) -> TypeEntry? raise TypifyError {
  let loose = F_META | F_TYPE | F_NUM | F_STR | F_ARR | F_OBJ
  let protos : Array[ProtoVariant] = []
  for schema in subschemas {
    match schema {
      Bool(true) => raise panic_with("internal error: entered unreachable code")
      Bool(false) => raise panic_with("not yet implemented")
      Object(o) if shape(o, some=F_ENUM, any=loose) => {
        if !string_or_untyped(o) {
          return None
        }
        for value in o.enum_values.unwrap() {
          guard value.as_str() is Some(name) else { return None }
          protos.push(Simple(name, metadata_description(o.metadata)))
        }
      }
      Object(o) if shape(o, some=F_CONST, any=loose) => {
        if !string_or_untyped(o) {
          return None
        }
        guard o.const_value.unwrap().as_str() is Some(name) else { return None }
        protos.push(Simple(name, metadata_description(o.metadata)))
      }
      other =>
        match get_object(other) {
          Some((metadata, v)) if v.max_properties is None &&
            v.min_properties is None &&
            v.required.length() == 1 &&
            v.properties.length() == 1 &&
            v.pattern_properties.is_empty() &&
            v.property_names is None => {
            let (prop_name, prop_type) = v.properties.first().unwrap()
            if !v.required.contains(prop_name) {
              raise panic_with("assertion failed: required.contains(prop_name)")
            }
            protos.push(
              Typed(prop_name, prop_type, metadata_description(metadata)),
            )
          }
          _ => return None
        }
    }
  }
  if !unique(protos.map(p => p.name())) {
    return None
  }
  let mut deny_unknown_fields = false
  let variants = []
  for proto in protos {
    match proto {
      Simple(name, description) =>
        variants.push(Variant::new(name, description, Simple))
      Typed(name, schema, description) => {
        guard ok(() => self.external_variant(type_name.append(name), schema))
          is Some((details, deny)) else {
          return None
        }
        deny_unknown_fields = deny_unknown_fields || deny
        variants.push(Variant::new(name, description, details))
      }
    }
  }
  Some(
    TypeEntryEnum::from_metadata(
      self,
      type_name,
      enum_metadata,
      External,
      variants,
      deny_unknown_fields,
      original_schema,
    ),
  )
}

///|
/// Variant details for a variant's payload schema, and whether it denies
/// unknown fields.
fn TypeSpace::external_variant(
  self : TypeSpace,
  prop_type_name : Name,
  variant_schema : @schema.Schema,
) -> (VariantDetails, Bool) raise TypifyError {
  let (ty, _) = self.convert_schema(prop_type_name, variant_schema)
  match ty.details {
    Tuple(types) => (Tuple(types), false)
    Unit => (Simple, false)
    Struct({ properties, deny_unknown_fields, .. }) =>
      (Struct(properties), deny_unknown_fields)
    _ => (Item(self.assign_type(ty)), false)
  }
}

///|
fn TypeSpace::maybe_internally_tagged_enum(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  subschemas : Array[@schema.Schema],
) -> TypeEntry? raise TypifyError {
  // Required, constant-string properties of each subschema.
  let sets : Array[@collections.StrMap[@collections.StrSet]] = subschemas.map(schema => {
    let m = @collections.StrMap::new()
    if get_object(schema) is Some((_, v)) {
      for prop_name, prop_type in v.properties {
        if v.required.contains(prop_name) &&
          constant_string_value(prop_type) is Some(value) {
          m.set(prop_name, @collections.StrSet::from_array([value]))
        }
      }
    }
    m
  })
  guard sets is [first, .. rest] else { return None }
  let mut acc = first
  for b in rest {
    let next = @collections.StrMap::new()
    for prop, a_values in acc {
      match b.get(prop) {
        Some(b_values) if !a_values.iter().any(x => b_values.contains(x)) =>
          next.set(prop, a_values.union(b_values))
        _ => ()
      }
    }
    acc = next
  }
  guard acc.first() is Some((tag, _)) else { return None }
  let mut deny_unknown_fields = false
  let result = ok(() => {
    let variants = []
    for schema in subschemas {
      guard get_object(schema) is Some((variant_metadata, v)) else {
        raise panic_with("internal error: entered unreachable code")
      }
      match v.additional_properties {
        Some(Bool(false)) => deny_unknown_fields = true
        None => ()
        _ => raise panic_with("internal error: entered unreachable code")
      }
      variants.push(
        self.internal_variant(
          get_type_name(type_name, variant_metadata),
          variant_metadata,
          v,
          tag,
        ),
      )
    }
    variants
  })
  guard result is Some(variants) else { return None }
  Some(
    TypeEntryEnum::from_metadata(
      self,
      type_name,
      metadata,
      Internal(tag~),
      variants,
      deny_unknown_fields,
      original_schema,
    ),
  )
}

///|
fn TypeSpace::internal_variant(
  self : TypeSpace,
  enum_type_name : String?,
  metadata : @schema.Metadata?,
  validation : @schema.ObjectValidation,
  tag : String,
) -> Variant raise TypifyError {
  if validation.properties.length() == 1 {
    let (tag_name, schema) = validation.properties.first().unwrap()
    guard constant_string_value(schema) is Some(variant_name) else {
      raise panic_with("called `Option::unwrap()` on a `None` value")
    }
    if tag_name != tag || validation.required.length() != 1 {
      raise panic_with("assertion failed: internal tag shape")
    }
    Variant::new(variant_name, None, Simple)
  } else {
    guard validation.properties.get(tag).bind(constant_string_value)
      is Some(variant_name) else {
      raise panic_with("called `Option::unwrap()` on a `None` value")
    }
    let properties = validation.properties.copy()
    ignore(properties.remove(tag))
    let required = validation.required.copy()
    ignore(required.remove(tag))
    let new_validation = { ..validation, properties, required, }
    let (props, _) = self.struct_members(enum_type_name, new_validation)
    Variant::new(
      variant_name,
      metadata_title_and_description(metadata),
      Struct(props),
    )
  }
}

///|
fn TypeSpace::maybe_adjacently_tagged_enum(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  subschemas : Array[@schema.Schema],
) -> TypeEntry? raise TypifyError {
  let prop_sets : Array[(@collections.StrSet, @collections.StrSet)] = []
  for schema in subschemas {
    match get_object(schema) {
      Some((_, v)) if v.properties.length() == v.required.length() => {
        let constants = @collections.StrSet::new()
        for name, t in v.properties {
          if constant_string_value(t) is Some(_) {
            constants.add(name)
          }
        }
        prop_sets.push(
          (constants, @collections.StrSet::from_array(v.properties.keys())),
        )
      }
      _ => return None
    }
  }
  guard prop_sets is [first, .. rest] else { return None }
  let mut tag_props = first.0
  let mut content_props = first.1
  for p in rest {
    tag_props = @collections.StrSet::from_array(
      tag_props.to_array().filter(x => p.0.contains(x)),
    )
    content_props = content_props.union(p.1)
  }
  if tag_props.length() != 1 || content_props.length() != 2 {
    return None
  }
  let tag = tag_props.to_array()[0]
  guard content_props.to_array().filter(x => !tag_props.contains(x))
    is [content, ..] else {
    return None
  }
  let mut deny_unknown_fields = false
  let result = ok(() => {
    let variants = []
    for schema in subschemas {
      guard get_object(schema) is Some((variant_metadata, v)) else {
        raise panic_with("internal error: entered unreachable code")
      }
      let (variant, deny) = self.adjacent_variant(
        type_name, variant_metadata, v, tag, content,
      )
      deny_unknown_fields = deny_unknown_fields || deny
      variants.push(variant)
    }
    variants
  })
  guard result is Some(variants) else { return None }
  Some(
    TypeEntryEnum::from_metadata(
      self,
      type_name,
      metadata,
      Adjacent(tag~, content~),
      variants,
      deny_unknown_fields,
      original_schema,
    ),
  )
}

///|
fn TypeSpace::adjacent_variant(
  self : TypeSpace,
  enum_type_name : Name,
  metadata : @schema.Metadata?,
  validation : @schema.ObjectValidation,
  tag : String,
  content : String,
) -> (Variant, Bool) raise TypifyError {
  if validation.properties.length() == 1 {
    let (tag_name, schema) = validation.properties.first().unwrap()
    guard constant_string_value(schema) is Some(variant_name) else {
      raise panic_with("called `Option::unwrap()` on a `None` value")
    }
    if tag_name != tag || validation.required.length() != 1 {
      raise panic_with("assertion failed: adjacent tag shape")
    }
    (Variant::new(variant_name, None, Simple), false)
  } else {
    guard validation.properties.get(tag).bind(constant_string_value)
      is Some(variant_name) else {
      raise panic_with("called `Option::unwrap()` on a `None` value")
    }
    let sub_type_name = match enum_type_name {
      Required(_) => enum_type_name.append(content)
      _ => enum_type_name.append(variant_name)
    }
    guard validation.properties.get(content) is Some(content_schema) else {
      raise panic_with("called `Option::unwrap()` on a `None` value")
    }
    let (details, deny) = self.external_variant(sub_type_name, content_schema)
    (
      Variant::new(
        variant_name,
        metadata_title_and_description(metadata),
        details,
      ),
      deny,
    )
  }
}

///|
/// An enum with one variant per subschema; variant names are inferred where
/// possible (common prefixes removed), otherwise `VariantN`.
fn TypeSpace::untagged_enum(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  subschemas : Array[@schema.Schema],
) -> TypeEntry raise TypifyError {
  let tmp_type_name = get_type_name(type_name, metadata)
  let fallback = () => Array::makei(subschemas.length(), i => "Variant\{i}")
  let variant_names = {
    let names = []
    let mut all_named = true
    for s in subschemas {
      match schema_is_named(s) {
        Some(n) => names.push(n)
        None => {
          all_named = false
          break
        }
      }
    }
    if !all_named || !unique(names) {
      fallback()
    } else {
      let mut prefix = names[0]
      for i in 1..<names.length() {
        prefix = get_common_prefix(prefix, names[i])
      }
      let prefix_len = utf8_len(prefix)
      let stripped = []
      for n in names {
        let rest = slice_from_byte(n, prefix_len)
        if rest == "" {
          break
        }
        stripped.push(rest)
      }
      if stripped.length() == names.length() {
        stripped
      } else {
        fallback()
      }
    }
  }
  let mut deny_unknown_fields = false
  let variants = []
  for i, schema in subschemas {
    let variant_name = variant_names[i]
    let base : Name = match tmp_type_name {
      Some(name) => Suggested(name)
      None => Unknown
    }
    let (details, deny) = self.external_variant(
      base.append(variant_name),
      schema,
    )
    deny_unknown_fields = deny_unknown_fields || deny
    variants.push(Variant::new(variant_name, None, details))
  }
  TypeEntryEnum::from_metadata(
    self,
    type_name,
    metadata,
    Untagged,
    variants,
    deny_unknown_fields,
    original_schema,
  )
}

///|
/// Whether the schema can only be satisfied by null.
fn is_null_schema(schema : @schema.Schema) -> Bool {
  match schema {
    Object({ instance_type: Some(Single(t)), .. }) => t == Null
    Object({ instance_type: Some(Vec(types)), .. }) =>
      types.iter().all(t => t == Null)
    Object({ const_value: Some(v), .. }) => v.is_null()
    Object({ enum_values: Some(values), .. }) =>
      values.iter().all(v => v.is_null())
    _ => false
  }
}

///|
/// The common prefix of two names at word boundaries, in PascalCase.
fn get_common_prefix(name : String, prefix : String) -> String {
  let a = @heck.to_kebab_case(name).split("-").collect()
  let b = @heck.to_kebab_case(prefix).split("-").collect()
  let common = []
  for i in 0..<a.length().min(b.length()) {
    if a[i] != b[i] {
      break
    }
    common.push(a[i].to_owned())
  }
  @heck.to_pascal_case(common.join("-"))
}
