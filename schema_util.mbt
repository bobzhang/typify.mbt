// Schema inspection helpers (upstream typify-impl/src/util.rs).

///|
type Defs = Map[RefKey, @schema.Schema]

///|
/// Whether all subschemas are pairwise mutually exclusive (conservatively).
fn all_mutually_exclusive(
  subschemas : Array[@schema.Schema],
  defs : Defs,
) -> Bool raise TypifyError {
  let len = subschemas.length()
  if len < 2 {
    return true
  }
  for ii in 0..<(len - 1) {
    for jj in (ii + 1)..<len {
      let a = resolve(subschemas[ii], defs)
      let b = resolve(subschemas[jj], defs)
      if !schemas_mutually_exclusive(a, b, defs) {
        return false
      }
    }
  }
  true
}

///|
/// A schema object consisting only of subschemas (metadata may not be set).
fn pure_subschemas(schema : @schema.Schema) -> @schema.SubschemaValidation? {
  match schema {
    Object(o) if shape(o, some=F_SUB) => o.subschemas
    _ => None
  }
}

///|
fn schemas_mutually_exclusive(
  a : @schema.Schema,
  b : @schema.Schema,
  defs : Defs,
) -> Bool raise TypifyError {
  match (a, b) {
    (Bool(false), _) | (_, Bool(false)) => return true
    (Bool(true), _) | (_, Bool(true)) => return false
    _ => ()
  }
  // (other, subschemas) | (subschemas, other): the left alternative first.
  let sub_case = match pure_subschemas(b) {
    Some(s) => Some((a, s))
    None =>
      match pure_subschemas(a) {
        Some(s) => Some((b, s))
        None => None
      }
  }
  if sub_case is Some((other, subschemas)) {
    let m = sub_present(subschemas)
    return if m == S_ALL {
      let mut any = false
      for sub in subschemas.all_of.unwrap() {
        if schemas_mutually_exclusive(sub, other, defs) {
          any = true
          break
        }
      }
      any
    } else if m == S_ANY || m == S_ONE {
      let list = if m == S_ANY {
        subschemas.any_of.unwrap()
      } else {
        subschemas.one_of.unwrap()
      }
      let mut all = true
      for sub in list {
        if !schemas_mutually_exclusive(sub, other, defs) {
          all = false
          break
        }
      }
      all
    } else if m == S_NOT {
      !schemas_mutually_exclusive(subschemas.not.unwrap(), other, defs)
    } else {
      false
    }
  }
  // Enumerated values without a type.
  let enum_case = match b {
    Object({ instance_type: None, enum_values: Some(values), .. }) =>
      Some((a, values))
    _ =>
      match a {
        Object({ instance_type: None, enum_values: Some(values), .. }) =>
          Some((b, values))
        _ => None
      }
  }
  if enum_case is Some((schema, values)) {
    return values.iter().all(v => schema_value_validate(schema, v) is Some(_))
  }
  // Constant values.
  let const_case = match b {
    Object({ const_value: Some(value), .. }) => Some((a, value))
    _ =>
      match a {
        Object({ const_value: Some(value), .. }) => Some((b, value))
        _ => None
      }
  }
  if const_case is Some((schema, value)) {
    return schema_value_validate(schema, value) is Some(_)
  }
  guard (a, b) is (Object(a), Object(b)) else { abort("unreachable") }
  match (a.instance_type, b.instance_type) {
    (None, _) | (_, None) => false
    (Some(Single(x)), Some(Single(y))) if x != y => true
    (Some(Single(Object)), Some(Single(Object))) =>
      if shape(a, some=F_OBJ, any=F_META | F_TYPE) &&
        shape(b, some=F_OBJ, any=F_META | F_TYPE) {
        object_schemas_mutually_exclusive(a.object.unwrap(), b.object.unwrap())
      } else {
        false
      }
    (Some(Single(Array)), Some(Single(Array))) =>
      if shape(a, some=F_ARR, any=F_META | F_TYPE) &&
        shape(b, some=F_ARR, any=F_META | F_TYPE) {
        array_schemas_mutually_exclusive(
          a.array.unwrap(),
          b.array.unwrap(),
          defs,
        )
      } else {
        false
      }
    (Some(Single(x)), Some(Single(y))) => x != y
    (Some(Vec(xs)), Some(Vec(ys))) => xs.iter().all(t => !ys.contains(t))
    (Some(Single(single)), Some(Vec(vec)))
    | (Some(Vec(vec)), Some(Single(single))) => !vec.contains(single)
  }
}

///|
fn object_schemas_mutually_exclusive(
  a : @schema.ObjectValidation,
  b : @schema.ObjectValidation,
) -> Bool {
  if a.properties.is_empty() || b.properties.is_empty() {
    return false
  }
  let a_props = @collections.StrSet::from_array(a.properties.keys())
  let b_props = @collections.StrSet::from_array(b.properties.keys())
  if !a.required.is_subset(b_props) || !b.required.is_subset(a_props) {
    return true
  }
  // Fixed-value required properties (e.g. enum tags) may still differ.
  let fixed = (v : @schema.ObjectValidation) => {
    let out : Array[(String, String)] = []
    for name in v.required.iter() {
      let t = v.properties.get(name).unwrap()
      if constant_string_value(t) is Some(s) && !out.contains((name, s)) {
        out.push((name, s))
      }
    }
    out
  }
  let aa = fixed(a)
  let bb = fixed(b)
  let subset = (x : Array[(String, String)], y : Array[(String, String)]) => {
    x.iter().all(e => y.contains(e))
  }
  !subset(aa, bb) && !subset(bb, aa)
}

///|
fn array_schemas_mutually_exclusive(
  a : @schema.ArrayValidation,
  b : @schema.ArrayValidation,
  defs : Defs,
) -> Bool raise TypifyError {
  let tuple_vs_single = (
    single : @schema.ArrayValidation,
    tuple : @schema.ArrayValidation,
  ) => {
    match (single, tuple) {
      (
        { items: Some(Single(s)), additional_items: None, .. },
        {
          items: Some(Vec(vec)),
          additional_items: None,
          max_items: Some(max_items),
          min_items: Some(min_items),
          unique_items: None,
          contains: None,
        },
      ) if max_items == min_items &&
        max_items.reinterpret_as_int() == vec.length() => Some((s, vec))
      _ => None
    }
  }
  let pair = match tuple_vs_single(a, b) {
    Some(p) => Some(p)
    None => tuple_vs_single(b, a)
  }
  if pair is Some((single, vec)) {
    for schema in vec {
      if schemas_mutually_exclusive(schema, single, defs) {
        return true
      }
    }
    return false
  }
  if (a.max_items, b.min_items) is (Some(max), Some(min)) && min > max {
    return true
  }
  if (b.max_items, a.min_items) is (Some(max), Some(min)) && min > max {
    return true
  }
  if (a.items, b.items) is (Some(Single(ai)), Some(Single(bi))) &&
    schemas_mutually_exclusive(ai, bi, defs) {
    return true
  }
  false
}

///|
/// If the schema is a constant string (a singleton `enum` or a `const`),
/// return it.
fn constant_string_value(schema : @schema.Schema) -> String? {
  guard schema is Object(o) else { return None }
  let is_string_or_none = match o.instance_type {
    Some(Single(String)) => true
    None => true
    _ => false
  }
  if !is_string_or_none {
    return None
  }
  if shape(o, some=F_ENUM, any=F_META | F_TYPE) {
    let values = o.enum_values.unwrap()
    if values.length() == 1 {
      return values[0].as_str()
    }
    return None
  }
  if shape(o, some=F_CONST, any=F_META | F_TYPE) {
    return o.const_value.unwrap().as_str()
  }
  None
}

///|
fn decode_segment(segment : String) -> String {
  segment.replace_all(old="~1", new="/").replace_all(old="~0", new="~")
}

///|
/// The definition key referenced by a `$ref` string.
fn ref_key(ref_name : String) -> RefKey raise TypifyError {
  if ref_name == "#" {
    return Root
  }
  match ref_name.rev_find("/") {
    Some(idx) =>
      Def(
        decode_segment(
          ref_name.unsafe_substring(start=idx + 1, end=ref_name.length()),
        ),
      )
    None => raise panic_with("expected a '/' in $ref: \{ref_name}")
  }
}

///|
/// Resolve a bare `$ref` schema to its definition.
fn resolve(
  schema : @schema.Schema,
  defs : Defs,
) -> @schema.Schema raise TypifyError {
  match schema {
    Bool(_) => schema
    Object(o) if shape(o, some=F_REF) => {
      let key = ref_key(o.reference.unwrap())
      match defs.get(key) {
        Some(s) => s
        None =>
          raise panic_with("unresolved reference: \{o.reference.unwrap()}")
      }
    }
    Object({ reference: None, .. }) => schema
    Object(_) => raise panic_with("not yet implemented")
  }
}

///|
/// A name for a schema, if one can be inferred (for untagged enum variants).
fn schema_is_named(schema : @schema.Schema) -> String? {
  guard schema is Object(o) else { return None }
  let raw_name = if shape(o, some=F_REF, any=F_META) {
    let reference = o.reference.unwrap()
    guard reference.rev_find("/") is Some(idx) else { return None }
    reference.unsafe_substring(start=idx + 1, end=reference.length())
  } else if o.metadata is Some({ title: Some(title), .. }) {
    title
  } else if shape(o, some=F_SUB, any=F_META | F_TYPE) {
    match singleton_subschema(o.subschemas.unwrap()) {
      Some(sub) => return schema_is_named(sub)
      None => return None
    }
  } else if o.instance_type is Some(Single(single)) {
    match (single, o.format) {
      (_, Some(format)) => @heck.to_pascal_case(format)
      (Boolean, _) => "Boolean"
      (Integer, _) => "Integer"
      (Number, _) => "Number"
      (String, _) => "String"
      (Array, _) => "Array"
      (Object, _) => "Object"
      (Null, _) => "Null"
    }
  } else {
    return None
  }
  Some(sanitize(raw_name, Pascal))
}

///|
/// Whether `additionalProperties` is absent or `false`.
fn schema_none_or_false(additional : @schema.Schema?) -> Bool {
  additional is (None | Some(Bool(false)))
}

///|
fn simple_object_validation(v : @schema.ObjectValidation) -> Bool {
  schema_none_or_false(v.additional_properties) &&
  v.max_properties is None &&
  v.min_properties is None &&
  v.pattern_properties.is_empty() &&
  v.property_names is None
}

///|
/// Return the metadata and object validation of an object schema of the
/// shape we know how to handle.
fn get_object(
  schema : @schema.Schema,
) -> (@schema.Metadata?, @schema.ObjectValidation)? {
  guard schema is Object(o) else { return None }
  if o.instance_type is Some(Single(Object)) &&
    shape(o, some=F_TYPE | F_OBJ, any=F_META | F_NUM | F_STR | F_ARR) &&
    simple_object_validation(o.object.unwrap()) {
    return Some((o.metadata, o.object.unwrap()))
  }
  if shape(o, some=F_OBJ, any=F_META) &&
    simple_object_validation(o.object.unwrap()) {
    return Some((o.metadata, o.object.unwrap()))
  }
  if shape(o, some=F_SUB, any=F_META | F_TYPE) {
    guard singleton_subschema(o.subschemas.unwrap()) is Some(sub) else {
      return None
    }
    return match get_object(sub) {
      Some((Some(_), validation)) => Some((o.metadata, validation))
      Some((None, validation)) => Some((None, validation))
      None => None
    }
  }
  None
}

///|
/// The lone schema of a one-element `allOf`, `anyOf` or `oneOf`.
fn singleton_subschema(s : @schema.SubschemaValidation) -> @schema.Schema? {
  let list = match sub_present(s) {
    m if m == S_ALL => s.all_of
    m if m == S_ANY => s.any_of
    m if m == S_ONE => s.one_of
    _ => None
  }
  match list {
    Some([only]) => Some(only)
    _ => None
  }
}

///|
/// Validates strings against `maxLength`, `minLength` and `pattern`.
priv struct StringValidator {
  max_length : UInt?
  min_length : UInt?
  pattern : @regex.Regex?
}

///|
fn StringValidator::new(
  type_name : Name,
  validation : @schema.StringValidation?,
) -> StringValidator raise TypifyError {
  match validation {
    None => { max_length: None, min_length: None, pattern: None, }
    Some(v) => {
      let pattern = match v.pattern {
        None => None
        Some(p) =>
          Some(
            @regex.Regex::new(p) catch {
              e =>
                raise InvalidSchema(
                  type_name=type_name.into_option(),
                  reason="invalid pattern '\{p}' \{e}",
                )
            },
          )
      }
      { max_length: v.max_length, min_length: v.min_length, pattern, }
    }
  }
}

///|
fn StringValidator::is_valid(self : StringValidator, s : String) -> Bool {
  // Lengths count code points.
  let len = s.char_length().reinterpret_as_uint()
  self.max_length.map_or(true, max => len <= max) &&
  self.min_length.map_or(true, min => len >= min) &&
  self.pattern.map_or(true, p => p.find(s) is Some(_))
}

///|
/// Instance types reordered so integers come before numbers.
fn reordered_rank(t : @schema.InstanceType) -> Int {
  match t {
    Null => 0
    Boolean => 1
    Integer => 2
    Number => 3
    String => 4
    Array => 5
    Object => 6
  }
}
