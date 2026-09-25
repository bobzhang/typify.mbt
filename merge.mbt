// Schema merging for `allOf` (upstream merge.rs). A merge that is
// unsatisfiable returns `None` (upstream `Err(())`); upstream panics
// (`unimplemented!`, failed assertions) raise `Panic`.

///|
/// Merge all schemas; an unsatisfiable result is `false`.
fn merge_all(
  schemas : Array[@schema.Schema],
  defs : Defs,
) -> @schema.Schema raise TypifyError {
  match try_merge_all(schemas, defs) {
    Some(s) => s
    None => Bool(false)
  }
}

///|
fn try_merge_all(
  schemas : Array[@schema.Schema],
  defs : Defs,
) -> @schema.Schema? raise TypifyError {
  match schemas {
    [] =>
      raise panic_with(
        "we should not be trying to merge an empty array of schemas",
      )
    [only] => Some(only)
    [first, second, .. rest] => {
      guard try_merge_schema(first, second, defs) is Some(out) else {
        return None
      }
      let mut out = out
      for schema in rest {
        guard try_merge_schema(out, schema, defs) is Some(next) else {
          return None
        }
        out = next
      }
      Some(out)
    }
  }
}

///|
fn merge_additional_items(
  a : @schema.Schema?,
  b : @schema.Schema?,
  defs : Defs,
) -> @schema.Schema? raise TypifyError {
  match (a, b) {
    (None, None) => Some(Bool(true))
    _ => merge_additional_properties(a, b, defs)
  }
}

///|
fn merge_additional_properties(
  a : @schema.Schema?,
  b : @schema.Schema?,
  defs : Defs,
) -> @schema.Schema? raise TypifyError {
  match (a, b) {
    (None, other) | (other, None) => other
    (Some(aa), Some(bb)) => Some(merge_schema(aa, bb, defs))
  }
}

///|
fn merge_schema(
  a : @schema.Schema,
  b : @schema.Schema,
  defs : Defs,
) -> @schema.Schema raise TypifyError {
  match try_merge_schema(a, b, defs) {
    Some(s) => s
    None => Bool(false)
  }
}

///|
fn try_merge_schema(
  a : @schema.Schema,
  b : @schema.Schema,
  defs : Defs,
) -> @schema.Schema? raise TypifyError {
  match (a, b) {
    (Bool(false), _) | (_, Bool(false)) => return None
    (Bool(true), other) | (other, Bool(true)) => return Some(other)
    (Object({ reference: Some(ar), .. }), Object({ reference: Some(br), .. })) if ar ==
      br => return Some(Object(@schema.SchemaObject::new_ref(ar)))
    _ => ()
  }
  // Resolve a reference before merging (left alternative first).
  let ref_case = match a {
    Object({ reference: Some(r), .. }) => Some((a, r, b))
    _ =>
      match b {
        Object({ reference: Some(r), .. }) => Some((b, r, a))
        _ => None
      }
  }
  if ref_case is Some((ref_schema, ref_name, other)) {
    guard defs.get(ref_key(ref_name)) is Some(resolved) else {
      raise panic_with("unresolved reference: \{ref_name}")
    }
    guard try_merge_schema(resolved, other, defs) is Some(merged) else {
      return None
    }
    return if roughly(merged, resolved) {
      Some(ref_schema)
    } else {
      Some(merged)
    }
  }
  guard (a, b) is (Object(aa), Object(bb)) else { abort("unreachable") }
  merge_schema_object(aa, bb, defs).map(o => @schema.Schema::Object(o))
}

///|
fn merge_schema_object(
  a : @schema.SchemaObject,
  b : @schema.SchemaObject,
  defs : Defs,
) -> @schema.SchemaObject? raise TypifyError {
  if a.reference is Some(_) || b.reference is Some(_) {
    raise panic_with("assertion failed: reference.is_none()")
  }
  guard merge_so_instance_type(a.instance_type, b.instance_type)
    is Some(instance_type) else {
    return None
  }
  guard merge_so_format(a.format, b.format) is Some(format) else { return None }
  guard merge_so_number(a.number, b.number) is Some(number) else { return None }
  guard merge_so_string(a.string, b.string) is Some(string) else { return None }
  guard merge_so_array(a.array, b.array, defs) is Some(array) else {
    return None
  }
  guard merge_so_object(a.object, b.object, defs) is Some(object) else {
    return None
  }
  guard merge_so_enum_values(
      a.enum_values,
      a.const_value,
      b.enum_values,
      b.const_value,
    )
    is Some(enum_values) else {
    return None
  }
  let merged : @schema.SchemaObject = {
    ..@schema.SchemaObject::default(),
    instance_type,
    format,
    enum_values,
    number,
    string,
    array,
    object,
  }
  guard try_merge_with_subschemas(merged, a.subschemas, defs) is Some(merged) else {
    return None
  }
  guard try_merge_with_subschemas(merged, b.subschemas, defs) is Some(merged) else {
    return None
  }
  if merged == @schema.Schema::Bool(false).into_object() {
    raise panic_with("assertion failed: merged schema is false")
  }
  // Weed out enumerated values that no longer validate.
  match merged.enum_values {
    Some(values) => {
      let wrapped : @schema.Schema = Object({ ..merged, enum_values: None, })
      let kept = values.filter(v => schema_value_validate(wrapped, v) is None)
      Some({ ..merged, enum_values: Some(kept), })
    }
    None => Some(merged)
  }
}

///|
/// Returns `None` when unsatisfiable, `Some(result)` otherwise.
fn merge_so_enum_values(
  a_enum : Array[@serde_json.Value]?,
  a_const : @serde_json.Value?,
  b_enum : Array[@serde_json.Value]?,
  b_const : @serde_json.Value?,
) -> Array[@serde_json.Value]?? raise TypifyError {
  let side = (e : Array[@serde_json.Value]?, c : @serde_json.Value?) => {
    match (e, c) {
      (None, None) => None
      (Some(values), None) => Some(values)
      (None, Some(v)) => Some([v])
      (Some(_), Some(_)) => raise panic_with("not implemented")
    }
  }
  match (side(a_enum, a_const), side(b_enum, b_const)) {
    (None, None) => Some(None)
    (None, Some(values)) | (Some(values), None) => Some(Some(values))
    (Some(aa), Some(bb)) => {
      let values = aa.filter(v => bb.contains(v))
      if values.is_empty() {
        None
      } else {
        Some(Some(values))
      }
    }
  }
}

///|
/// Merge a schema with subschema validation; `None` if unsatisfiable.
fn try_merge_with_subschemas(
  schema_object : @schema.SchemaObject,
  maybe_subschemas : @schema.SubschemaValidation?,
  defs : Defs,
) -> @schema.SchemaObject? raise TypifyError {
  guard maybe_subschemas is Some(s) else { return Some(schema_object) }
  if s.if_schema is Some(_) ||
    s.then_schema is Some(_) ||
    s.else_schema is Some(_) {
    raise panic_with("not implemented: if/then/else schemas are not supported")
  }
  let mut schema_object = schema_object
  if s.all_of is Some(all_of) {
    let mut merged : @schema.Schema = Object(schema_object)
    for other in all_of {
      guard try_merge_schema(merged, other, defs) is Some(m) else {
        return None
      }
      merged = m
    }
    if merged is Bool(false) {
      raise panic_with("assertion failed: merged_schema != false")
    }
    schema_object = merged.into_object()
  }
  if s.not is Some(not) {
    guard try_merge_schema_not(schema_object, not, defs) is Some(o) else {
      return None
    }
    schema_object = o
  }
  if s.any_of is Some(_) && s.one_of is Some(_) {
    raise panic_with("assertion failed: any_of.is_none() || one_of.is_none()")
  }
  if s.any_of is Some(any_of) {
    let merged = try_merge_with_each_subschema(schema_object, any_of, defs)
    match merged {
      [] => return None
      [only] => schema_object = only.into_object()
      _ =>
        schema_object = {
          ..@schema.SchemaObject::default(),
          metadata: schema_object.metadata,
          subschemas: Some({
            ..@schema.SubschemaValidation::default(),
            any_of: Some(merged),
          }),
        }
    }
  }
  if s.one_of is Some(one_of) {
    let merged = try_merge_with_each_subschema(schema_object, one_of, defs)
    match merged {
      [] => return None
      [only] => schema_object = only.into_object()
      _ =>
        schema_object = {
          ..@schema.SchemaObject::default(),
          metadata: schema_object.metadata,
          subschemas: Some({
            ..@schema.SubschemaValidation::default(),
            one_of: Some(merged),
          }),
        }
    }
  }
  Some(schema_object)
}

///|
fn try_merge_with_each_subschema(
  schema_object : @schema.SchemaObject,
  subschemas : Array[@schema.Schema],
  defs : Defs,
) -> Array[@schema.Schema] raise TypifyError {
  let schema : @schema.Schema = Object(schema_object)
  let out = []
  for ii, other in subschemas {
    guard try_merge_schema(schema, other, defs) is Some(merged) else {
      continue
    }
    if roughly(merged, schema) {
      out.push(schema)
    } else if roughly(merged, other) {
      out.push(other)
    } else {
      let joined = [schema, other]
      for jj, not_schema_item in subschemas {
        if jj != ii {
          joined.push(not_schema(not_schema_item))
        }
      }
      out.push(all_of_schema(joined))
    }
  }
  out
}

///|
fn merge_schema_not(
  schema : @schema.Schema,
  not_schema : @schema.Schema,
  defs : Defs,
) -> @schema.Schema raise TypifyError {
  match (schema, not_schema) {
    (_, Bool(true)) | (Bool(false), _) => Bool(false)
    (any, Bool(false)) => any
    (Bool(true), Object(_)) => raise panic_with("not yet implemented")
    (Object(o), any_not) =>
      match try_merge_schema_not(o, any_not, defs) {
        Some(o) => Object(o)
        None => Bool(false)
      }
  }
}

///|
/// "Subtract" the `not` schema from the schema object.
fn try_merge_schema_not(
  schema_object : @schema.SchemaObject,
  not_schema : @schema.Schema,
  defs : Defs,
) -> @schema.SchemaObject? raise TypifyError {
  match not_schema {
    Bool(true) => None
    Bool(false) => Some(schema_object)
    Object(not_object) =>
      try_merge_schema_object_not(schema_object, not_object, defs)
  }
}

///|
fn try_merge_with_subschemas_not(
  schema_object : @schema.SchemaObject,
  not_subschemas : @schema.SubschemaValidation,
  defs : Defs,
) -> @schema.SchemaObject? raise TypifyError {
  let m = sub_present(not_subschemas)
  if m == S_ANY {
    // not(anyOf) == allOf(not)
    let all_of = not_subschemas.any_of.unwrap().map(not_schema)
    let new_other = only_subschemas({
      ..@schema.SubschemaValidation::default(),
      all_of: Some(all_of),
    })
    merge_schema_object(schema_object, new_other, defs)
  } else if m == S_NOT {
    try_merge_schema(Object(schema_object), not_subschemas.not.unwrap(), defs).map(s => {
        s.into_object()
      },
    )
  } else if m == S_ONE || m == 0 {
    Some(schema_object)
  } else if m == S_ALL {
    match try_merge_all(not_subschemas.all_of.unwrap(), defs) {
      Some(merged_not) => try_merge_schema_not(schema_object, merged_not, defs)
      None => Some(schema_object)
    }
  } else {
    raise panic_with("not yet implemented: not subschemas")
  }
}

///|
fn try_merge_schema_object_not(
  schema_object : @schema.SchemaObject,
  not_object : @schema.SchemaObject,
  defs : Defs,
) -> @schema.SchemaObject? raise TypifyError {
  let mut schema_object = schema_object
  match (schema_object.enum_values, not_object.enum_values) {
    (Some(values), Some(not_values)) => {
      let kept = values.filter(v => !not_values.contains(v))
      if kept.is_empty() {
        return None
      }
      schema_object = { ..schema_object, enum_values: Some(kept), }
    }
    _ => ()
  }
  match (schema_object.object, not_object.object) {
    (Some(obj), Some(not_obj)) => {
      let properties = @collections.StrMap::new()
      for name, prop_schema in obj.properties {
        match not_obj.properties.get(name) {
          Some(not_prop) =>
            properties.set(name, merge_schema_not(prop_schema, not_prop, defs))
          None => properties.set(name, prop_schema)
        }
      }
      for name in not_obj.properties.keys() {
        if !obj.properties.contains(name) {
          properties.set(name, @schema.Schema::Bool(false))
        }
      }
      for not_required in not_obj.required.iter() {
        if !not_obj.properties.contains(not_required) {
          properties.set(not_required, @schema.Schema::Bool(false))
        }
      }
      for required in obj.required.iter() {
        if properties.get(required) is Some(Bool(false)) {
          return None
        }
      }
      schema_object = { ..schema_object, object: Some({ ..obj, properties, }), }
    }
    _ => ()
  }
  match not_object.subschemas {
    Some(not_subschemas) =>
      try_merge_with_subschemas_not(schema_object, not_subschemas, defs)
    None => Some(schema_object)
  }
}

///|
fn merge_so_instance_type(
  a : @schema.SingleOrVec[@schema.InstanceType]?,
  b : @schema.SingleOrVec[@schema.InstanceType]?,
) -> @schema.SingleOrVec[@schema.InstanceType]?? {
  match (a, b) {
    (None, None) => Some(None)
    (None, Some(_) as other) | (Some(_) as other, None) => Some(other)
    (Some(Single(aa)), Some(Single(bb))) =>
      if aa == bb {
        Some(Some(Single(aa)))
      } else {
        None
      }
    (Some(Vec(types)), Some(Single(it)))
    | (Some(Single(it)), Some(Vec(types))) =>
      if types.contains(it) {
        Some(Some(Single(it)))
      } else {
        None
      }
    (Some(Vec(aa)), Some(Vec(bb))) => {
      let types = aa.filter(t => bb.contains(t))
      types.sort()
      types.dedup()
      match types {
        [] => None
        [t] => Some(Some(Single(t)))
        _ => Some(Some(Vec(types)))
      }
    }
  }
}

///|
fn merge_so_format(a : String?, b : String?) -> String?? {
  match (a, b) {
    (None, other) | (other, None) => Some(other)
    (Some("ip"), Some("ipv4" | "ipv6" as r))
    | (Some("ipv4" | "ipv6" as r), Some("ip")) => Some(Some(r))
    (Some(aa), Some(bb)) if aa == bb => Some(Some(aa))
    _ => None
  }
}

///|
fn[T] choose_value(a : T?, b : T?, prefer : (T, T) -> T) -> T? {
  match (a, b) {
    (None, other) | (other, None) => other
    (Some(aa), Some(bb)) => Some(prefer(aa, bb))
  }
}

///|
/// Rust `f64 % f64` (truncated remainder).
fn frem(x : Double, y : Double) -> Double {
  x - (x / y).trunc() * y
}

///|
fn merge_so_number(
  a : @schema.NumberValidation?,
  b : @schema.NumberValidation?,
) -> @schema.NumberValidation?? raise TypifyError {
  match (a, b) {
    (None, other) | (other, None) => return Some(other)
    (Some(a), Some(b)) if a == b => return Some(Some(a))
    _ => ()
  }
  guard (a, b) is (Some(a), Some(b)) else { abort("unreachable") }
  let maximum = choose_value(a.maximum, b.maximum, fmin)
  let exclusive_maximum = choose_value(
    a.exclusive_maximum,
    b.exclusive_maximum,
    fmin,
  )
  let minimum = choose_value(a.minimum, b.minimum, fmax)
  let exclusive_minimum = choose_value(
    a.exclusive_minimum,
    b.exclusive_minimum,
    fmax,
  )
  let multiple_of = choose_value(a.multiple_of, b.multiple_of, (a, b) => {
    let mut x = a
    let mut y = b
    while y != 0.0 {
      let t = frem(x, y)
      x = y
      y = t
    }
    a / x * b
  })
  let (minimum, exclusive_minimum) = match (minimum, exclusive_minimum) {
    (Some(inc), Some(exc)) if exc >= inc => (None, Some(exc))
    (Some(inc), Some(_)) => (Some(inc), None)
    pair => pair
  }
  let (maximum, exclusive_maximum) = match (maximum, exclusive_maximum) {
    (Some(inc), Some(exc)) if exc <= inc => (None, Some(exc))
    (Some(inc), Some(_)) => (Some(inc), None)
    pair => pair
  }
  match (minimum, exclusive_minimum, maximum, exclusive_maximum) {
    (Some(min), None, Some(max), None) if min > max => return None
    (Some(min), None, None, Some(xmax)) if min >= xmax => return None
    (None, Some(xmin), Some(max), None) if xmin >= max => return None
    (None, Some(xmin), None, Some(xmax)) if xmin >= xmax => return None
    (Some(_), Some(_), _, _) | (_, _, Some(_), Some(_)) =>
      raise panic_with("internal error: entered unreachable code")
    _ => ()
  }
  Some(
    Some({
      multiple_of,
      maximum,
      exclusive_maximum,
      minimum,
      exclusive_minimum,
    }),
  )
}

///|
fn merge_so_string(
  a : @schema.StringValidation?,
  b : @schema.StringValidation?,
) -> @schema.StringValidation?? {
  match (a, b) {
    (None, other) | (other, None) => return Some(other)
    (Some(a), Some(b)) if a == b => return Some(Some(a))
    _ => ()
  }
  guard (a, b) is (Some(a), Some(b)) else { abort("unreachable") }
  let max_length = choose_value(a.max_length, b.max_length, (x, y) => {
    if x <= y {
      x
    } else {
      y
    }
  })
  let min_length = choose_value(a.min_length, b.min_length, (x, y) => {
    if x >= y {
      x
    } else {
      y
    }
  })
  let pattern = match (a.pattern, b.pattern) {
    (None, v) | (v, None) => v
    (Some(x), Some(y)) if x == y => Some(x)
    // Combine distinct patterns with lookaheads.
    (Some(x), Some(y)) if x.has_prefix("(?=") => Some("\{x}(?=\{y})")
    (Some(x), Some(y)) => Some("(?=\{x})(?=\{y})")
  }
  if (min_length, max_length) is (Some(min), Some(max)) && min > max {
    return None
  }
  Some(Some({ max_length, min_length, pattern, }))
}

///|
fn umin(x : UInt, y : UInt) -> UInt {
  if x <= y {
    x
  } else {
    y
  }
}

///|
fn umax(x : UInt, y : UInt) -> UInt {
  if x >= y {
    x
  } else {
    y
  }
}

///|
fn merge_so_array(
  a : @schema.ArrayValidation?,
  b : @schema.ArrayValidation?,
  defs : Defs,
) -> @schema.ArrayValidation?? raise TypifyError {
  match (a, b) {
    (None, other) | (other, None) => return Some(other)
    _ => ()
  }
  guard (a, b) is (Some(aa), Some(bb)) else { abort("unreachable") }
  let max_items = choose_value(aa.max_items, bb.max_items, umin)
  let min_items = choose_value(aa.min_items, bb.min_items, umax)
  let unique_items = choose_value(aa.unique_items, bb.unique_items, (x, y) => {
    x || y
  })
  let contains = match (aa.contains, bb.contains) {
    (None, other) | (other, None) => other
    (Some(x), Some(y)) if x == y => Some(x)
    _ => return None
  }
  if (min_items, max_items) is (Some(min), Some(max)) && min > max {
    return None
  }
  let (items, additional_items, max_items) : (
    @schema.SingleOrVec[@schema.Schema]?,
    @schema.Schema?,
    UInt?,
  ) = match ((aa.items, aa.additional_items), (bb.items, bb.additional_items)) {
    ((None, _), (None, _)) => (None, None, max_items)
    ((None, _), (Some(Single(item)), _))
    | ((Some(Single(item)), _), (None, _)) =>
      (Some(Single(item)), None, max_items)
    ((None, _), (Some(Vec(items)), additional))
    | ((Some(Vec(items)), additional), (None, _)) =>
      match max_items {
        Some(max) if items.length() >= max.reinterpret_as_int() =>
          (
            Some(Vec(items[:max.reinterpret_as_int()].to_owned())),
            None,
            max_items,
          )
        _ => (Some(Vec(items)), additional, max_items)
      }
    ((Some(Single(a_single)), _), (Some(Single(b_single)), _)) => {
      guard try_merge_schema(a_single, b_single, defs) is Some(merged) else {
        return None
      }
      (Some(Single(merged)), None, max_items)
    }
    ((Some(Single(single)), _), (Some(Vec(items)), additional))
    | ((Some(Vec(items)), additional), (Some(Single(single)), _)) => {
      guard merge_items_array(
          items.map(i => (i, single)),
          min_items,
          max_items,
          defs,
        )
        is Some((items, allow_additional)) else {
        return None
      }
      if allow_additional {
        let additional = match additional {
          None => single
          Some(additional_schema) =>
            match try_merge_schema(additional_schema, single, defs) {
              Some(s) => s
              None => return None
            }
        }
        (Some(Vec(items)), Some(additional), max_items)
      } else {
        (Some(Vec(items)), None, Some(items.length().reinterpret_as_uint()))
      }
    }
    ((Some(Vec(a_items)), a_additional), (Some(Vec(b_items)), b_additional)) => {
      let items_len = a_items.length().max(b_items.length())
      let pairs = []
      for i in 0..<items_len {
        let x = match a_items.get(i) {
          Some(s) => s
          None => a_additional.unwrap_or(Bool(true))
        }
        let y = match b_items.get(i) {
          Some(s) => s
          None => b_additional.unwrap_or(Bool(true))
        }
        pairs.push((x, y))
      }
      guard merge_items_array(pairs, min_items, max_items, defs)
        is Some((items, allow_additional)) else {
        return None
      }
      if allow_additional {
        let additional = merge_additional_items(
          a_additional, b_additional, defs,
        )
        (Some(Vec(items)), additional, max_items)
      } else {
        (Some(Vec(items)), None, Some(items.length().reinterpret_as_uint()))
      }
    }
  }
  Some(
    Some({
      items,
      additional_items,
      max_items,
      min_items,
      unique_items,
      contains,
    }),
  )
}

///|
/// Merge item pairs; stops at `max_items` or at the first unsatisfiable
/// item. Returns the items and whether additional items remain possible.
fn merge_items_array(
  pairs : Array[(@schema.Schema, @schema.Schema)],
  min_items : UInt?,
  max_items : UInt?,
  defs : Defs,
) -> (Array[@schema.Schema], Bool)? raise TypifyError {
  let items = []
  for pair in pairs {
    match try_merge_schema(pair.0, pair.1, defs) {
      Some(schema) => {
        items.push(schema)
        if max_items is Some(max) && items.length() == max.reinterpret_as_int() {
          return Some((items, false))
        }
      }
      None => {
        if items.length().reinterpret_as_uint() < min_items.unwrap_or(1) {
          return None
        }
        return Some((items, false))
      }
    }
  }
  Some((items, true))
}

///|
fn merge_so_object(
  a : @schema.ObjectValidation?,
  b : @schema.ObjectValidation?,
  defs : Defs,
) -> @schema.ObjectValidation?? raise TypifyError {
  match (a, b) {
    (None, other) | (other, None) => return Some(other)
    _ => ()
  }
  guard (a, b) is (Some(aa), Some(bb)) else { abort("unreachable") }
  let required = aa.required.union(bb.required)
  let additional_properties = merge_additional_properties(
    aa.additional_properties,
    bb.additional_properties,
    defs,
  )
  // Properties of a, then those only in b, resolved and checked in order
  // (upstream short-circuits on the first unsatisfiable required property).
  let properties = @collections.StrMap::new()
  let add = (name : String, resolved : @schema.Schema) => {
    match resolved {
      Bool(false) if required.contains(name) => false
      Bool(false) => {
        if !(additional_properties is Some(Bool(false))) {
          properties.set(name, resolved)
        }
        true
      }
      schema => {
        properties.set(name, schema)
        true
      }
    }
  }
  for name, a_schema in aa.properties {
    let resolved = match bb.properties.get(name) {
      Some(b_schema) => merge_schema(a_schema, b_schema, defs)
      None => filter_prop(name, a_schema, bb, defs)
    }
    if !add(name, resolved) {
      return None
    }
  }
  for name, b_schema in bb.properties {
    if !aa.properties.contains(name) {
      if !add(name, filter_prop(name, b_schema, aa, defs)) {
        return None
      }
    }
  }
  let max_properties = choose_value(aa.max_properties, bb.max_properties, umin)
  let min_properties = choose_value(aa.min_properties, bb.min_properties, umax)
  if (min_properties, max_properties) is (Some(min), Some(max)) && min > max {
    return None
  }
  Some(
    Some({
      required,
      properties,
      additional_properties,
      max_properties,
      min_properties,
      pattern_properties: @collections.StrMap::new(),
      property_names: None,
    }),
  )
}

///|
fn filter_prop(
  name : String,
  prop_schema : @schema.Schema,
  object_schema : @schema.ObjectValidation,
  _defs : Defs,
) -> @schema.Schema raise TypifyError {
  if object_schema.properties.contains(name) {
    raise panic_with(
      "assertion failed: !object_schema.properties.contains_key(name)",
    )
  }
  if object_schema.property_names is Some(_) {
    raise panic_with("assertion failed: object_schema.property_names.is_none()")
  }
  if !object_schema.pattern_properties.is_empty() {
    raise panic_with(
      "assertion failed: object_schema.pattern_properties.is_empty()",
    )
  }
  match object_schema.additional_properties {
    Some(Bool(true)) | None => prop_schema
    Some(Bool(false)) => Bool(false)
    Some(additional) => all_of_schema([additional, prop_schema])
  }
}
