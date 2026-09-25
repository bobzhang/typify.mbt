// Leaf and structural converters (upstream convert.rs).

///|
fn TypeSpace::convert_string(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  format : String?,
  validation : @schema.StringValidation?,
) -> Converted raise TypifyError {
  let display_from_str : Array[TypeSpaceImpl] = [Display, FromStr]
  match format {
    Some("uuid") => {
      self.uses_uuid = true
      (TypeEntry::new_native("::uuid::Uuid", display_from_str), metadata)
    }
    Some("date") => {
      self.uses_chrono = true
      (
        TypeEntry::new_native("::chrono::naive::NaiveDate", display_from_str),
        metadata,
      )
    }
    Some("date-time") => {
      self.uses_chrono = true
      (
        TypeEntry::new_native(
          "::chrono::DateTime<::chrono::offset::Utc>", display_from_str,
        ),
        metadata,
      )
    }
    Some("ip") =>
      (TypeEntry::new_native("::std::net::IpAddr", display_from_str), metadata)
    Some("ipv4") =>
      (
        TypeEntry::new_native("::std::net::Ipv4Addr", display_from_str),
        metadata,
      )
    Some("ipv6") =>
      (
        TypeEntry::new_native("::std::net::Ipv6Addr", display_from_str),
        metadata,
      )
    _ =>
      match validation {
        None | Some({ max_length: None, min_length: None, pattern: None, }) =>
          (TypeEntry::from_details(String), metadata)
        Some(v) => {
          if v.pattern is Some(pattern) {
            ignore(
              @regex.Regex::new(pattern) catch {
                e =>
                  raise InvalidSchema(
                    type_name=type_name.into_option(),
                    reason="invalid pattern '\{pattern}' \{e}",
                  )
              },
            )
            self.uses_regress = true
          }
          let type_id = self.assign_type(TypeEntry::from_details(String))
          (
            TypeEntryNewtype::from_metadata_with_string_validation(
              self, type_name, metadata, type_id, v, original_schema,
            ),
            metadata,
          )
        }
      }
  }
}

///|
fn TypeSpace::convert_enum_string(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  enum_values : Array[@serde_json.Value],
  validation : @schema.StringValidation?,
) -> Converted raise TypifyError {
  let mut has_null = false
  let validator = StringValidator::new(type_name, validation)
  let variants = []
  for value in enum_values {
    match value {
      Null => has_null = true
      String(variant_name) =>
        if validator.is_valid(variant_name) {
          variants.push(Variant::new(variant_name, None, Simple))
        }
      _ => raise BadValue("string", value)
    }
  }
  if variants.is_empty() {
    if has_null {
      self.convert_null(metadata)
    } else {
      self.convert_never(type_name, original_schema)
    }
  } else {
    let mut ty = TypeEntryEnum::from_metadata(
      self,
      type_name,
      metadata,
      External,
      variants,
      false,
      original_schema,
    )
    if has_null {
      ty = self.type_to_option(ty)
    }
    (ty, metadata)
  }
}

///|
priv struct IntFormat {
  format : String
  ty : String
  nz_ty : String
  min : Double
  max : Double
}

///|
/// Integer formats, from most to least restrictive. Bounds are the Rust
/// `T::MIN as f64` / `T::MAX as f64` values.
let int_formats : Array[IntFormat] = [
  {
    format: "int8",
    ty: "i8",
    nz_ty: "::std::num::NonZeroU8",
    min: -128.0,
    max: 127.0,
  },
  {
    format: "uint8",
    ty: "u8",
    nz_ty: "::std::num::NonZeroU8",
    min: 0.0,
    max: 255.0,
  },
  {
    format: "int16",
    ty: "i16",
    nz_ty: "::std::num::NonZeroU16",
    min: -32768.0,
    max: 32767.0,
  },
  {
    format: "uint16",
    ty: "u16",
    nz_ty: "::std::num::NonZeroU16",
    min: 0.0,
    max: 65535.0,
  },
  {
    format: "int",
    ty: "i32",
    nz_ty: "::std::num::NonZeroU32",
    min: -2147483648.0,
    max: 2147483647.0,
  },
  {
    format: "int32",
    ty: "i32",
    nz_ty: "::std::num::NonZeroU32",
    min: -2147483648.0,
    max: 2147483647.0,
  },
  {
    format: "uint",
    ty: "u32",
    nz_ty: "::std::num::NonZeroU32",
    min: 0.0,
    max: 4294967295.0,
  },
  {
    format: "uint32",
    ty: "u32",
    nz_ty: "::std::num::NonZeroU32",
    min: 0.0,
    max: 4294967295.0,
  },
  {
    format: "int64",
    ty: "i64",
    nz_ty: "::std::num::NonZeroU64",
    min: (-0x7FFF_FFFF_FFFF_FFFFL - 1L).to_double(),
    max: 0x7FFF_FFFF_FFFF_FFFFL.to_double(),
  },
  {
    format: "uint64",
    ty: "u64",
    nz_ty: "::std::num::NonZeroU64",
    min: 0.0,
    max: 0xFFFF_FFFF_FFFF_FFFFUL.to_double(),
  },
]

///|
/// `f64::EPSILON`
const F64_EPSILON : Double = 2.220446049250313e-16

///|
fn fmax(a : Double, b : Double) -> Double {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if a >= b {
    a
  } else {
    b
  }
}

///|
fn fmin(a : Double, b : Double) -> Double {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if a <= b {
    a
  } else {
    b
  }
}

///|
fn TypeSpace::convert_integer(
  _self : TypeSpace,
  metadata : @schema.Metadata?,
  validation : @schema.NumberValidation?,
  format : String?,
) -> Converted raise TypifyError {
  let (min0, max0, multiple) = match validation {
    None => (None, None, None)
    Some(v) => {
      let min = match (v.minimum, v.exclusive_minimum) {
        (None, None) => None
        (None, Some(e)) => Some(e + 1.0)
        (Some(m), None) => Some(m)
        (Some(m), Some(e)) => Some(fmax(m, e + 1.0))
      }
      let max = match (v.maximum, v.exclusive_maximum) {
        (None, None) => None
        (None, Some(e)) => Some(e - 1.0)
        (Some(m), None) => Some(m)
        (Some(m), Some(e)) => Some(fmin(m, e - 1.0))
      }
      (min, max, v.multiple_of)
    }
  }
  let mut min = min0
  let mut max = max0
  let default = metadata_default(metadata)
  if format is Some(format) {
    match int_formats.search_by(f => f.format == format) {
      Some(i) => {
        let f = int_formats[i]
        let valid_min = match min {
          None => true
          Some(fmin) => fmin >= f.min
        }
        let valid_max = match max {
          None => true
          Some(fmax) => fmax <= f.max
        }
        if multiple is None && valid_min && valid_max {
          if default.bind(v => v.as_f64()) is Some(d) &&
            (d < f.min || d > f.max) {
            raise InvalidValue
          }
          return if min == Some(1.0) {
            (TypeEntry::new_integer(f.nz_ty), metadata)
          } else {
            (TypeEntry::new_integer(f.ty), metadata)
          }
        }
        if min is None {
          min = Some(f.min)
        }
        if max is None {
          max = Some(f.max)
        }
      }
      None => ()
    }
  }
  // Check the default against the bounds.
  if default is Some(d) {
    let ok = match (d.as_f64(), min, max) {
      (Some(_), None, None) => true
      (Some(v), None, Some(fmax)) => v <= fmax
      (Some(v), Some(fmin), None) => v >= fmin
      (Some(v), Some(fmin), Some(fmax)) => v >= fmin && v <= fmax
      _ => false
    }
    if !ok {
      raise InvalidValue
    }
  }
  let rev = int_formats.rev()
  let maybe_type = match (min, max) {
    (None, Some(max)) =>
      rev.search_by(f => (f.max - max).abs() <= F64_EPSILON).map(i => rev[i].ty)
    (Some(min), None) => {
      let mut found = None
      for f in rev {
        if min == 1.0 {
          found = Some(f.nz_ty)
          break
        } else if (f.min - min).abs() <= F64_EPSILON {
          found = Some(f.ty)
          break
        }
      }
      found
    }
    (Some(min), Some(max)) => {
      let mut found = None
      for f in rev {
        if min == 1.0 {
          found = Some(f.nz_ty)
          break
        } else if (f.max - max).abs() <= F64_EPSILON &&
          (f.min - min).abs() <= F64_EPSILON {
          found = Some(f.ty)
          break
        }
      }
      found
    }
    (None, None) => None
  }
  match maybe_type {
    Some(ty) => (TypeEntry::new_integer(ty), metadata)
    None => (TypeEntry::new_integer("i64"), metadata)
  }
}

///|
fn TypeSpace::convert_number(
  _self : TypeSpace,
  metadata : @schema.Metadata?,
  format : String?,
) -> Converted {
  match format {
    Some("float") => (TypeEntry::new_float("f32"), metadata)
    _ => (TypeEntry::new_float("f64"), metadata)
  }
}

///|
fn TypeSpace::convert_null(
  _self : TypeSpace,
  metadata : @schema.Metadata?,
) -> Converted {
  (TypeEntry::from_details(Unit), metadata)
}

///|
fn can_handle_pattern_properties(v : @schema.ObjectValidation) -> Bool {
  if !v.required.is_empty() || !v.properties.is_empty() {
    return false
  }
  guard v.pattern_properties.first() is Some((_, first)) else { return false }
  if !v.pattern_properties.values().iter().all(s => s == first) {
    return false
  }
  if v.additional_properties is (Some(Bool(true)) | Some(Object(_))) {
    return false
  }
  v.property_names is None
}

///|
fn TypeSpace::convert_object(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  validation : @schema.ObjectValidation?,
) -> Converted raise TypifyError {
  match validation {
    // Maps: no properties and non-false additionalProperties.
    Some(v) if v.required.is_empty() &&
      v.properties.is_empty() &&
      v.pattern_properties.is_empty() &&
      !(v.additional_properties is Some(Bool(false))) => {
      let entry = self.make_map(
        type_name.into_option(),
        v.property_names,
        v.additional_properties,
      )
      (entry, metadata)
    }
    Some(v) if can_handle_pattern_properties(v) => {
      let pattern = v.pattern_properties.keys().join("|")
      let property_names : @schema.Schema? = Some(
        Object({
          ..@schema.SchemaObject::default(),
          string: Some({
            max_length: None,
            min_length: None,
            pattern: Some(pattern),
          }),
        }),
      )
      let additional = v.pattern_properties.first().map(p => p.1)
      let entry = self.make_map(
        type_name.into_option(),
        property_names,
        additional,
      )
      (entry, metadata)
    }
    None => (self.make_map(type_name.into_option(), None, None), metadata)
    Some(v) => {
      let tmp_type_name = get_type_name(type_name, metadata)
      let (properties, deny_unknown_fields) = self.struct_members(
        tmp_type_name, v,
      )
      (
        TypeEntryStruct::from_metadata(
          self, type_name, metadata, properties, deny_unknown_fields, original_schema,
        ),
        None,
      )
    }
  }
}

///|
fn TypeSpace::convert_reference(
  self : TypeSpace,
  metadata : @schema.Metadata?,
  ref_name : String,
) -> Converted raise TypifyError {
  if !ref_name.has_prefix("#") {
    raise panic_with("external references are not supported: \{ref_name}")
  }
  match self.ref_to_id.get(ref_key(ref_name)) {
    Some(type_id) => (TypeEntry::from_details(Reference(type_id)), metadata)
    None => raise panic_with("$ref \{ref_name} is missing")
  }
}

///|
fn TypeSpace::convert_all_of(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  subschemas : Array[@schema.Schema],
) -> Converted raise TypifyError {
  if self.maybe_singleton_subschema(type_name, subschemas) is Some(ty) {
    return (ty, metadata)
  }
  let merged = merge_all(subschemas, self.definitions)
  if merged is Bool(false) {
    return self.convert_never(type_name, original_schema)
  }
  let merged = merged.into_object()
  if merged.metadata is Some(_) {
    raise panic_with("assertion failed: merged_schema.metadata.is_none()")
  }
  let (type_entry, _) = self.convert_schema_object(type_name, original_schema, {
    ..merged,
    metadata,
  })
  (type_entry, None)
}

///|
fn TypeSpace::convert_any_of(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  subschemas : Array[@schema.Schema],
) -> Converted raise TypifyError {
  if subschemas.is_empty() {
    let type_name = match get_type_name(type_name, metadata) {
      Some(name) => Name::Required(name)
      None => type_name
    }
    return self.convert_never(type_name, original_schema)
  }
  if self.maybe_option(type_name, metadata, subschemas) is Some(ty) {
    return (ty, metadata)
  }
  if all_mutually_exclusive(subschemas, self.definitions) {
    self.convert_one_of(type_name, original_schema, metadata, subschemas)
  } else {
    self.flattened_union_struct(
      type_name, original_schema, metadata, subschemas, true,
    )
  }
}

///|
fn TypeSpace::convert_one_of(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  subschemas : Array[@schema.Schema],
) -> Converted raise TypifyError {
  let ty = match self.maybe_option(type_name, metadata, subschemas) {
    Some(ty) => ty
    None =>
      match
        self.maybe_externally_tagged_enum(
          type_name, original_schema, metadata, subschemas,
        ) {
        Some(ty) => ty
        None =>
          match
            self.maybe_adjacently_tagged_enum(
              type_name, original_schema, metadata, subschemas,
            ) {
            Some(ty) => ty
            None =>
              match
                self.maybe_internally_tagged_enum(
                  type_name, original_schema, metadata, subschemas,
                ) {
                Some(ty) => ty
                None =>
                  match self.maybe_singleton_subschema(type_name, subschemas) {
                    Some(ty) => ty
                    None =>
                      self.untagged_enum(
                        type_name, original_schema, metadata, subschemas,
                      )
                  }
              }
          }
      }
  }
  (ty, metadata)
}

///|
/// Infer an instance type from a JSON value (for `not`/untyped enums).
fn value_instance_type(v : @serde_json.Value) -> @schema.InstanceType {
  match v {
    Null => Null
    Bool(_) => Boolean
    Number(_) => Number
    String(_) => String
    Array(_) => Array
    Object(_) => Object
  }
}

///|
fn TypeSpace::convert_not(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  subschema : @schema.Schema,
) -> Converted raise TypifyError {
  match subschema {
    Bool(b) => {
      let (entry, _) = self.convert_schema(type_name, Bool(!b))
      (entry, metadata)
    }
    Object(o) if shape(o, any=F_META) => {
      let (entry, _) = self.convert_schema(type_name, Bool(false))
      (entry, metadata)
    }
    Object(
      { instance_type: Some(Single(_)), enum_values: Some(enum_values), .. } as o
    ) => {
      let type_schema = { ..o, enum_values: None, }
      let (entry, _) = self.convert_schema_object(
        Unknown,
        original_schema,
        type_schema,
      )
      for value in enum_values {
        ignore(entry.validate_value(self, value))
      }
      let type_id = self.assign_type(entry)
      (
        TypeEntryNewtype::from_metadata_with_deny_values(
          self, type_name, metadata, type_id, enum_values, original_schema,
        ),
        metadata,
      )
    }
    Object(o) if shape(o, some=F_ENUM, any=F_META) => {
      let enum_values = o.enum_values.unwrap()
      let inner_metadata = o.metadata
      let types : Array[@schema.InstanceType] = []
      for v in enum_values {
        let t = match v {
          Bool(_) => @schema.InstanceType::Boolean
          Number(_) => Number
          String(_) => String
          _ => raise panic_with("unhandled type for `not` construction: \{v}")
        }
        if !types.contains(t) {
          types.push(t)
        }
      }
      guard types is [instance_type] else {
        raise panic_with("multiple implied types for an un-typed enum")
      }
      let typed_schema = {
        ..@schema.SchemaObject::default(),
        instance_type: Some(Single(instance_type)),
      }
      let (entry, _) = self.convert_schema_object(
        Unknown,
        original_schema,
        typed_schema,
      )
      for value in enum_values {
        ignore(entry.validate_value(self, value))
      }
      let type_id = self.assign_type(entry)
      (
        TypeEntryNewtype::from_metadata_with_deny_values(
          self, type_name, inner_metadata, type_id, enum_values, original_schema,
        ),
        inner_metadata,
      )
    }
    _ => raise panic_with("not yet implemented: unhandled not schema")
  }
}

///|
fn TypeSpace::convert_array(
  self : TypeSpace,
  type_name : Name,
  metadata : @schema.Metadata?,
  validation : @schema.ArrayValidation,
) -> Converted raise TypifyError {
  match validation {
    // Tuples and fixed-length arrays.
    {
      items,
      additional_items,
      max_items: Some(max_items),
      min_items: Some(min_items),
      unique_items: None,
      contains: None,
    } if max_items == min_items && max_items > 0 => {
      let max = max_items.reinterpret_as_int()
      match items {
        Some(Vec(items)) if items.length() < max => {
          let rest_name = type_name.append("additional")
          let rest_id = match additional_items {
            Some(rest_schema) => self.id_for_schema(rest_name, rest_schema).0
            None => self.id_for_schema(rest_name, Bool(true)).0
          }
          let types = []
          for ii, item_schema in items {
            types.push(
              self.id_for_schema(type_name.append("item\{ii}"), item_schema).0,
            )
          }
          for _ in items.length()..<max {
            types.push(rest_id)
          }
          (TypeEntry::from_details(Tuple(types)), metadata)
        }
        Some(Vec(items)) => {
          let types = []
          for ii, item_schema in items {
            if ii >= max {
              break
            }
            types.push(
              self.id_for_schema(type_name.append("item\{ii}"), item_schema).0,
            )
          }
          (TypeEntry::from_details(Tuple(types)), metadata)
        }
        Some(Single(item_schema)) => {
          let item_id = self.id_for_schema(
              type_name.append("item"),
              item_schema,
            ).0
          (TypeEntry::from_details(Array(item_id, max)), metadata)
        }
        None => {
          let any_id = self.id_for_schema(type_name.append("item"), Bool(true)).0
          (TypeEntry::from_details(Array(any_id, max)), metadata)
        }
      }
    }
    // Arrays and sets.
    { items: Some(Single(item)), unique_items, contains: None, .. } => {
      let item_type_name = match get_type_name(type_name, metadata) {
        Some(s) => Name::Suggested("\{s}Item")
        None => Unknown
      }
      let (type_id, _) = self.id_for_schema(item_type_name, item)
      match unique_items {
        Some(true) => (TypeEntry::from_details(Set(type_id)), metadata)
        _ => (TypeEntry::from_details(Vec(type_id)), metadata)
      }
    }
    // Arrays and sets with no specified items.
    { items: None, unique_items, contains: None, .. } => {
      self.uses_serde_json = true
      let type_id = self.assign_type(TypeEntry::from_details(JsonValue))
      match unique_items {
        Some(true) => (TypeEntry::from_details(Set(type_id)), metadata)
        _ => (TypeEntry::from_details(Vec(type_id)), metadata)
      }
    }
    _ =>
      raise InvalidSchema(
        type_name=type_name.into_option(),
        reason="unhandled array validation \{Repr(validation)}",
      )
  }
}

///|
fn TypeSpace::convert_array_of_any(
  self : TypeSpace,
  metadata : @schema.Metadata?,
) -> Converted {
  self.uses_serde_json = true
  let type_id = self.assign_type(TypeEntry::from_details(JsonValue))
  (TypeEntry::from_details(Vec(type_id)), metadata)
}

///|
fn TypeSpace::convert_bool(
  _self : TypeSpace,
  metadata : @schema.Metadata?,
) -> Converted {
  (TypeEntry::from_details(Boolean), metadata)
}

///|
fn TypeSpace::convert_permissive(
  self : TypeSpace,
  metadata : @schema.Metadata?,
) -> Converted {
  self.uses_serde_json = true
  (TypeEntry::from_details(JsonValue), metadata)
}

///|
/// The "never" type: an enum with no variants.
fn TypeSpace::convert_never(
  self : TypeSpace,
  type_name : Name,
  schema : @schema.Schema,
) -> Converted raise TypifyError {
  let ty = TypeEntryEnum::from_metadata(
    self,
    type_name,
    None,
    External,
    [],
    true,
    schema,
  )
  (ty, None)
}

///|
fn TypeSpace::convert_typed_enum(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  schema : @schema.SchemaObject,
  enum_values : Array[@serde_json.Value],
) -> Converted raise TypifyError {
  let type_schema = { ..schema, enum_values: None, }
  let inner_type_name = match get_type_name(type_name, schema.metadata) {
    Some(s) => Name::Suggested("\{s}Inner")
    None => Unknown
  }
  let (entry, metadata) = self.convert_schema_object(
    inner_type_name, original_schema, type_schema,
  )
  for value in enum_values {
    ignore(entry.validate_value(self, value))
  }
  let type_id = self.assign_type(entry)
  let newtype = TypeEntryNewtype::from_metadata_with_enum_values(
    self, type_name, metadata, type_id, enum_values, original_schema,
  )
  (newtype, if metadata is Some(_) { schema.metadata } else { None })
}

///|
fn TypeSpace::convert_unknown_enum(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  metadata : @schema.Metadata?,
  enum_values : Array[@serde_json.Value],
) -> Converted raise TypifyError {
  if enum_values.is_empty() {
    return self.convert_never(type_name, original_schema)
  }
  let types : Array[@schema.InstanceType] = []
  for v in enum_values {
    let t = value_instance_type(v)
    if !types.contains(t) {
      types.push(t)
    }
  }
  let has_null = types.contains(Null)
  if has_null {
    let non_null = enum_values.filter(v => !v.is_null())
    if non_null.is_empty() {
      return self.convert_null(metadata)
    }
    let (entry, metadata) = self.convert_unknown_enum(
      type_name, original_schema, metadata, non_null,
    )
    return (self.type_to_option(entry), metadata)
  }
  match types {
    [String] =>
      self.convert_enum_string(
        type_name,
        original_schema,
        metadata,
        enum_values,
        None,
      )
    [Boolean] => self.convert_bool(metadata)
    [instance_type] => {
      let typed_schema = {
        ..@schema.SchemaObject::default(),
        instance_type: Some(Single(instance_type)),
      }
      let (entry, new_metadata) = self.convert_typed_enum(
        type_name, original_schema, typed_schema, enum_values,
      )
      (entry, if new_metadata is Some(_) { metadata } else { None })
    }
    _ => raise panic_with("multiple implied types for an un-typed enum")
  }
}

///|
fn TypeSpace::convert_option(
  self : TypeSpace,
  type_name : Name,
  metadata : @schema.Metadata?,
  schema : @schema.Schema,
) -> Converted raise TypifyError {
  let (ty, _) = self.convert_schema(type_name, schema)
  (self.type_to_option(ty), metadata)
}

///|
/// A single subschema is just an annotation layer.
fn TypeSpace::maybe_singleton_subschema(
  self : TypeSpace,
  type_name : Name,
  subschemas : Array[@schema.Schema],
) -> TypeEntry? raise TypifyError {
  match subschemas {
    [subschema] => ok(() => self.convert_schema(type_name, subschema).0)
    _ => None
  }
}
