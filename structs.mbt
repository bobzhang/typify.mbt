// Struct conversion (upstream structs.rs, minus code emission).

///|
/// A stable sort (Rust `sort_by` is stable; ties keep their order).
fn[T] stable_sort_by(xs : Array[T], cmp : (T, T) -> Int) -> Array[T] {
  if xs.length() <= 1 {
    return xs.copy()
  }
  let mid = xs.length() / 2
  let left = stable_sort_by(xs[:mid].to_owned(), cmp)
  let right = stable_sort_by(xs[mid:].to_owned(), cmp)
  let out = []
  for i = 0, j = 0; i < left.length() || j < right.length(); {
    if j >= right.length() || (i < left.length() && cmp(left[i], right[j]) <= 0) {
      out.push(left[i])
      continue i + 1, j
    } else {
      out.push(right[j])
      continue i, j + 1
    }
  }
  out
}

///|
fn TypeSpace::struct_members(
  self : TypeSpace,
  type_name : String?,
  validation : @schema.ObjectValidation,
) -> (Array[StructProperty], Bool) raise TypifyError {
  // Required properties without a schema accept any value.
  let props : Array[(String, @schema.Schema)] = validation.properties.to_array()
  for prop_name in validation.required.iter() {
    if !validation.properties.contains(prop_name) {
      props.push((prop_name, Bool(true)))
    }
  }
  let properties = []
  for p in props {
    let (prop_name, schema) = p
    // Unsatisfiable properties are ignored.
    if schema is Bool(false) {
      continue
    }
    let sub_type_name = type_name.map(base => {
      "\{base}_\{@heck.to_snake_case(prop_name)}"
    })
    properties.push(
      self.struct_property(
        sub_type_name,
        validation.required,
        prop_name,
        schema,
      ),
    )
  }
  let properties = stable_sort_by(properties, (a, b) => {
    @collections.compare_str(a.name, b.name)
  })
  let deny_unknown_fields = match validation.additional_properties {
    Some(Bool(false)) => true
    Some(Bool(true)) | None => false
    Some(_) as additional => {
      let sub_type_name = type_name.map(base => "\{base}_extra")
      let map_type = self.make_map(
        sub_type_name,
        validation.property_names,
        additional,
      )
      let map_type_id = self.assign_type(map_type)
      properties.push({
        name: "extra",
        rename: Flatten,
        state: Required,
        description: None,
        type_id: map_type_id,
      })
      false
    }
  }
  (properties, deny_unknown_fields)
}

///|
fn TypeSpace::struct_property(
  self : TypeSpace,
  type_name : String?,
  required : @collections.StrSet,
  prop_name : String,
  schema : @schema.Schema,
) -> StructProperty raise TypifyError {
  let sub_type_name = match type_name {
    Some(name) => Name::Suggested(name)
    None => Unknown
  }
  let (type_id, metadata) = self.id_for_schema(sub_type_name, schema)
  let mut type_id = type_id
  let state = if required.contains(prop_name) {
    StructPropertyState::Required
  } else {
    match has_default(self, type_id, metadata_default(metadata)) {
      Required => {
        type_id = self.id_to_option(type_id)
        Optional
      }
      other => other
    }
  }
  let (name, rename) = recase(prop_name, Snake)
  {
    name,
    rename: match rename {
      Some(old) => Rename(old)
      None => NoRename
    },
    state,
    description: metadata_description(metadata),
    type_id,
  }
}

///|
fn TypeSpace::make_map(
  self : TypeSpace,
  type_name : String?,
  property_names : @schema.Schema?,
  additional_properties : @schema.Schema?,
) -> TypeEntry raise TypifyError {
  let key_id = match property_names {
    Some(Bool(true)) | None => self.assign_type(TypeEntry::from_details(String))
    Some(Bool(false)) => raise panic_with("not yet implemented")
    Some(Object(obj)) => {
      let key_type_name = match type_name {
        Some(name) => Name::Suggested("\{name}Key")
        None => Unknown
      }
      self.id_for_schema_string(key_type_name, obj)
    }
  }
  let (value_id, _) = match additional_properties {
    Some(value_schema) => {
      let value_type_name = match type_name {
        Some(name) => Name::Suggested("\{name}Value")
        None => Unknown
      }
      self.id_for_schema(value_type_name, value_schema)
    }
    None => self.id_for_schema(Unknown, Bool(true))
  }
  TypeEntry::from_details(Map(key_id, value_id))
}

///|
/// Convert a schema that must be string-like (map keys).
fn TypeSpace::id_for_schema_string(
  self : TypeSpace,
  type_name : Name,
  schema_obj : @schema.SchemaObject,
) -> TypeId raise TypifyError {
  match schema_obj {
    { instance_type: None, subschemas: None, reference: None, .. } => {
      let schema : @schema.Schema = Object({
        ..schema_obj,
        instance_type: Some(Single(String)),
      })
      self.id_for_schema(type_name, schema).0
    }
    _ => self.id_for_schema(type_name, Object(schema_obj)).0
  }
}

///|
/// A struct whose members are the (flattened) subschemas; members are
/// optional for `anyOf`.
fn TypeSpace::flattened_union_struct(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  subschemas : Array[@schema.Schema],
  optional : Bool,
) -> Converted raise TypifyError {
  let properties = []
  for idx, schema in subschemas {
    let sub_name = match get_type_name(type_name, metadata) {
      Some(name) => Name::Suggested("\{name}Subtype\{idx}")
      None => Unknown
    }
    let (type_id, _) = self.id_for_schema(sub_name, schema)
    let type_id = if optional { self.id_to_option(type_id) } else { type_id }
    properties.push({
      name: "subtype_\{idx}",
      rename: Flatten,
      state: if optional {
        Optional
      } else {
        Required
      },
      description: None,
      type_id,
    })
  }
  (
    TypeEntryStruct::from_metadata(
      self, type_name, metadata, properties, false, original_schema,
    ),
    metadata,
  )
}

///|
/// Whether a non-required property can use an implicit default.
fn has_default(
  space : TypeSpace,
  type_id : TypeId,
  default : @serde_json.Value?,
) -> StructPropertyState {
  let details = space.id_to_entry.get(type_id).map(e => e.details)
  match (details, default) {
    (Some(Option(_)), None) => Optional
    (Some(Vec(_)), None) => Optional
    (Some(Map(_, _)), None) => Optional
    (Some(Unit), None) => Optional
    (_, None) => Required
    (Some(Option(_)), Some(Null)) => Optional
    (Some(Vec(_)), Some(Array([]))) => Optional
    (Some(Map(_, _)), Some(Object(m))) if m.is_empty() => Optional
    (Some(Boolean), Some(Bool(false))) => Optional
    (Some(Integer(_)), Some(Number(n))) if n.as_u64() == Some(0UL) => Optional
    (Some(Integer(_)), Some(Number(n))) if n.as_f64() == 0.0 => Optional
    (Some(String), Some(String(""))) => Optional
    (_, Some(d)) => Default(d)
  }
}
