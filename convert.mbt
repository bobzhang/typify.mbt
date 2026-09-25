// Schema -> type conversion dispatch (upstream convert.rs). The arms of
// `convert_schema_object` are tried in upstream's order; each comment names
// the upstream arm.

///|
/// The conversion result: a type entry and the metadata that applies to it.
type Converted = (TypeEntry, @schema.Metadata?)

///|
fn TypeSpace::convert_schema(
  self : TypeSpace,
  type_name : Name,
  schema : @schema.Schema,
) -> Converted raise TypifyError {
  match schema {
    Object(obj) =>
      match self.cache_lookup(obj) {
        Some(entry) => (entry, obj.metadata)
        None => self.convert_schema_object(type_name, schema, obj)
      }
    Bool(true) => self.convert_permissive(None)
    Bool(false) => self.convert_never(type_name, schema)
  }
}

///|
/// Re-convert a modified schema, keeping the outer metadata as upstream's
/// `.map(|(te, m)| ...)` does.
fn TypeSpace::reconvert_keep_metadata(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  new_schema : @schema.SchemaObject,
  metadata : @schema.Metadata?,
) -> Converted raise TypifyError {
  let (te, m) = self.convert_schema_object(
    type_name, original_schema, new_schema,
  )
  match m {
    Some(_) if m == metadata => (te, metadata)
    Some(_) => raise panic_with("unexpected metadata value")
    None => (te, None)
  }
}

///|
fn TypeSpace::convert_schema_object(
  self : TypeSpace,
  type_name : Name,
  original_schema : @schema.Schema,
  schema : @schema.SchemaObject,
) -> Converted raise TypifyError {
  if self.convert_rust_extension(schema) is Some(entry) {
    return (entry, schema.metadata)
  }
  let metadata = schema.metadata
  let any_validation = F_META | F_FORMAT | F_NUM | F_STR | F_ARR | F_OBJ
  let single = single_type(schema)
  // Option: exactly two instance types, one of them null.
  if schema.instance_type is Some(Vec(multiple)) &&
    multiple.length() == 2 &&
    multiple.contains(Null) {
    let only_null = schema.enum_values is Some(values) &&
      values.iter().all(v => v.is_null())
    if only_null {
      return self.convert_null(metadata)
    }
    match multiple.search_by(t => t != Null) {
      Some(i) => {
        let other_type = multiple[i]
        let enum_values = schema.enum_values.map(values => {
          values.filter(v => !v.is_null())
        })
        let ss : @schema.Schema = Object({
          ..schema,
          instance_type: Some(Single(other_type)),
          enum_values,
        })
        let inner_type_name = match type_name {
          Required(name) => Name::Suggested("\{name}Inner")
          _ => type_name
        }
        return self.convert_option(inner_type_name, metadata, ss)
      }
      None => {
        let new_schema = { ..schema, instance_type: Some(Single(Null)), }
        return self.reconvert_keep_metadata(
          type_name, original_schema, new_schema, metadata,
        )
      }
    }
  }
  // Strings
  if single is Some(String) && shape(schema, some=F_TYPE, any=any_validation) {
    return self.convert_string(
      type_name,
      original_schema,
      metadata,
      schema.format,
      schema.string,
    )
  }
  // Strings with the type omitted, but validation present
  if shape(schema, some=F_STR, any=F_META | F_FORMAT) {
    return self.convert_string(
      type_name,
      original_schema,
      metadata,
      schema.format,
      schema.string,
    )
  }
  // Enumerated string type
  if single is Some(String) &&
    shape(schema, some=F_TYPE | F_ENUM, any=any_validation) {
    return self.convert_enum_string(
      type_name,
      original_schema,
      metadata,
      schema.enum_values.unwrap(),
      schema.string,
    )
  }
  // Integers
  if single is Some(Integer) && shape(schema, some=F_TYPE, any=any_validation) {
    return self.convert_integer(metadata, schema.number, schema.format)
  }
  // Numbers
  if single is Some(Number) && shape(schema, some=F_TYPE, any=any_validation) {
    return self.convert_number(metadata, schema.format)
  }
  // Boolean
  if single is Some(Boolean) &&
    shape(
      schema,
      some=F_TYPE,
      any=F_META | F_ENUM | F_NUM | F_STR | F_ARR | F_OBJ,
    ) {
    return self.convert_bool(metadata)
  }
  // Object
  if single is Some(Object) &&
    shape(schema, some=F_TYPE, any=F_META | F_NUM | F_STR | F_ARR | F_OBJ) {
    return self.convert_object(
      type_name,
      original_schema,
      metadata,
      schema.object,
    )
  }
  // Object with the type omitted, but validation present
  if shape(schema, some=F_OBJ, any=F_META) {
    return self.convert_object(
      type_name,
      original_schema,
      metadata,
      schema.object,
    )
  }
  // Array
  if single is Some(Array) &&
    shape(schema, some=F_TYPE | F_ARR, any=F_META | F_NUM | F_STR | F_OBJ) {
    return self.convert_array(type_name, metadata, schema.array.unwrap())
  }
  // Array with the type omitted, but validation present
  if shape(schema, some=F_ARR, any=F_META) {
    return self.convert_array(type_name, metadata, schema.array.unwrap())
  }
  // Arrays of anything
  if single is Some(Array) &&
    shape(schema, some=F_TYPE, any=F_META | F_NUM | F_STR | F_OBJ) {
    return self.convert_array_of_any(metadata)
  }
  // The permissive schema
  if shape(schema, any=F_META) {
    return self.convert_permissive(metadata)
  }
  // Null
  if single is Some(Null) && shape(schema, some=F_TYPE, any=any_validation) {
    return self.convert_null(metadata)
  }
  // Reference
  if shape(schema, some=F_REF, any=F_META) {
    return self.convert_reference(metadata, schema.reference.unwrap())
  }
  // References that also include the type.
  if shape(schema, some=F_REF, any=F_META | F_TYPE) {
    let reference = schema.reference.unwrap()
    let ref_schema = self.definition(reference)
    guard ref_schema is Object(r) && r.instance_type == schema.instance_type else {
      raise panic_with("assertion failed: $ref type mismatch for \{reference}")
    }
    return self.convert_reference(metadata, reference)
  }
  // References with other constraints: merge with the referenced chain.
  if schema.reference is Some(reference) {
    let mut def = self.definition(reference)
    let mut new_schema : @schema.Schema = Object({ ..schema, reference: None, })
    while def is Object({ reference: r, .. }) {
      let schema_only_ref : @schema.Schema = Object({
        ..@schema.SchemaObject::default(),
        reference: r,
      })
      let schema_without_ref : @schema.Schema = Object({
        ..def.into_object(),
        reference: None,
      })
      new_schema = merge_all(
        [schema_without_ref, schema_only_ref, new_schema],
        self.definitions,
      )
      match r {
        Some(r) => def = self.definition(r)
        None => break
      }
    }
    let (type_entry, _) = self.convert_schema(type_name, new_schema) catch {
      e => raise panic_with("called `Result::unwrap()` on an `Err` value: \{e}")
    }
    return (type_entry, metadata)
  }
  // Enum of a single, known, non-String type (strings above).
  if single is Some(_) && schema.enum_values is Some(enum_values) {
    return self.convert_typed_enum(
      type_name, original_schema, schema, enum_values,
    )
  }
  // Enum of unknown type
  if shape(schema, some=F_ENUM, any=F_META) {
    return self.convert_unknown_enum(
      type_name,
      original_schema,
      metadata,
      schema.enum_values.unwrap(),
    )
  }
  // Subschemas
  if shape(schema, some=F_SUB, any=F_META | F_TYPE) {
    let subschemas = schema.subschemas.unwrap()
    let m = sub_present(subschemas)
    if m == S_ALL {
      return self.convert_all_of(
        type_name,
        original_schema,
        metadata,
        subschemas.all_of.unwrap(),
      )
    } else if m == S_ANY {
      return self.convert_any_of(
        type_name,
        original_schema,
        metadata,
        subschemas.any_of.unwrap(),
      )
    } else if m == S_ONE {
      return self.convert_one_of(
        type_name,
        original_schema,
        metadata,
        subschemas.one_of.unwrap(),
      )
    } else if m == S_NOT {
      return self.convert_not(
        type_name,
        original_schema,
        metadata,
        subschemas.not.unwrap(),
      )
    }
    // Multiple subschemas: merge, then convert.
    let schema_object = { ..schema, subschemas: None, }
    return match
      try_merge_with_subschemas(
        schema_object,
        Some(subschemas),
        self.definitions,
      ) {
      Some(s) => {
        let (type_entry, _) = self.convert_schema_object(
          type_name, original_schema, s,
        )
        (type_entry, None)
      }
      None => self.convert_never(type_name, original_schema)
    }
  }
  // Subschemas with other stuff.
  if schema.subschemas is Some(subschemas) {
    let without_subschemas = { ..schema, subschemas: None, metadata: None, }
    return match
      try_merge_with_subschemas(
        without_subschemas,
        Some(subschemas),
        self.definitions,
      ) {
      Some(merged) => {
        let merged = { ..merged, metadata, }
        let (type_entry, _) = self.convert_schema_object(
          type_name, original_schema, merged,
        )
        (type_entry, None)
      }
      None => self.convert_never(type_name, original_schema)
    }
  }
  // Constant values are ignored.
  if schema.const_value is Some(_) {
    return self.reconvert_keep_metadata(
      type_name,
      original_schema,
      { ..schema, const_value: None, },
      metadata,
    )
  }
  if schema.instance_type is Some(Vec(instance_types)) {
    // All seven instance types: strip them and try again.
    let all : Array[@schema.InstanceType] = [
      Null,
      Boolean,
      Object,
      Array,
      Number,
      String,
      Integer,
    ]
    if all.iter().all(t => instance_types.contains(t)) {
      let (type_entry, _) = self.convert_schema_object(
        type_name,
        original_schema,
        { ..schema, instance_type: None, },
      )
      return (type_entry, metadata)
    }
    // A singleton type array is a singleton type.
    if instance_types is [it] {
      let (type_entry, _) = self.convert_schema_object(
        type_name,
        original_schema,
        { ..schema, instance_type: Some(Single(it)), },
      )
      return (type_entry, metadata)
    }
    // Several types: an untagged enum labeled by type.
    if shape(schema, some=F_TYPE, any=any_validation) {
      let unique_types : Array[@schema.InstanceType] = []
      for t in instance_types {
        if !unique_types.contains(t) {
          unique_types.push(t)
        }
      }
      unique_types.sort_by((a, b) => {
        reordered_rank(a).compare(reordered_rank(b))
      })
      let subschemas = unique_types.map(it => {
        let base = {
          ..@schema.SchemaObject::default(),
          instance_type: Some(Single(it)),
        }
        let (label, inner) : (String, @schema.SchemaObject) = match it {
          Null => ("null", base)
          Boolean => ("boolean", base)
          Object => ("object", { ..base, object: schema.object, })
          Array => ("array", { ..base, array: schema.array, })
          Number =>
            (
              "number",
              { ..base, format: schema.format, number: schema.number, },
            )
          String =>
            (
              "string",
              { ..base, format: schema.format, string: schema.string, },
            )
          Integer =>
            (
              "integer",
              { ..base, format: schema.format, number: schema.number, },
            )
        }
        @schema.Schema::Object({
          ..@schema.SchemaObject::default(),
          metadata: Some({ ..@schema.Metadata::default(), title: Some(label), }),
          subschemas: Some({
            ..@schema.SubschemaValidation::default(),
            all_of: Some([Object(inner)]),
          }),
        })
      })
      let type_entry = self.untagged_enum(
        type_name, original_schema, metadata, subschemas,
      )
      return (type_entry, metadata)
    }
  }
  raise panic_with(
    "not yet implemented: invalid (or unexpected) schema:\n\{@schema.Schema::Object(schema).to_value().to_string_pretty()}",
  )
}

///|
/// Look up the definition for a `$ref` (upstream `.get(..).unwrap()`).
fn TypeSpace::definition(
  self : TypeSpace,
  reference : String,
) -> @schema.Schema raise TypifyError {
  match self.definitions.get(ref_key(reference)) {
    Some(s) => s
    None =>
      raise panic_with(
        "called `Option::unwrap()` on a `None` value ($ref \{reference})",
      )
  }
}
