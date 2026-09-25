// Helpers for upstream's exhaustive `SchemaObject { field: None, .. }`
// patterns. A pattern lists fields that must be `Some`, fields that are
// ignored (`_`), and implicitly requires every other field to be `None`.
// `extensions` is always ignored, as in every upstream pattern.

///|
const F_META : Int = 1

///|
const F_TYPE : Int = 2

///|
const F_FORMAT : Int = 4

///|
const F_ENUM : Int = 8

///|
const F_CONST : Int = 16

///|
const F_SUB : Int = 32

///|
const F_NUM : Int = 64

///|
const F_STR : Int = 128

///|
const F_ARR : Int = 256

///|
const F_OBJ : Int = 512

///|
const F_REF : Int = 1024

///|
/// Which fields of the schema object are `Some`.
fn present(o : @schema.SchemaObject) -> Int {
  let mut m = 0
  if o.metadata is Some(_) {
    m = m | F_META
  }
  if o.instance_type is Some(_) {
    m = m | F_TYPE
  }
  if o.format is Some(_) {
    m = m | F_FORMAT
  }
  if o.enum_values is Some(_) {
    m = m | F_ENUM
  }
  if o.const_value is Some(_) {
    m = m | F_CONST
  }
  if o.subschemas is Some(_) {
    m = m | F_SUB
  }
  if o.number is Some(_) {
    m = m | F_NUM
  }
  if o.string is Some(_) {
    m = m | F_STR
  }
  if o.array is Some(_) {
    m = m | F_ARR
  }
  if o.object is Some(_) {
    m = m | F_OBJ
  }
  if o.reference is Some(_) {
    m = m | F_REF
  }
  m
}

///|
/// Fields in `some` are `Some`, fields in `any` are unconstrained, all other
/// fields are `None`.
fn shape(o : @schema.SchemaObject, some? : Int = 0, any? : Int = 0) -> Bool {
  let m = present(o)
  (m & some) == some && (m & (some | any).lnot()) == 0
}

///|
/// The single instance type, if `type` is a single value.
fn single_type(o : @schema.SchemaObject) -> @schema.InstanceType? {
  match o.instance_type {
    Some(Single(t)) => Some(t)
    _ => None
  }
}

///|
const S_ALL : Int = 1

///|
const S_ANY : Int = 2

///|
const S_ONE : Int = 4

///|
const S_NOT : Int = 8

///|
const S_IF : Int = 16

///|
const S_THEN : Int = 32

///|
const S_ELSE : Int = 64

///|
/// Which subschema fields are `Some`.
fn sub_present(s : @schema.SubschemaValidation) -> Int {
  let mut m = 0
  if s.all_of is Some(_) {
    m = m | S_ALL
  }
  if s.any_of is Some(_) {
    m = m | S_ANY
  }
  if s.one_of is Some(_) {
    m = m | S_ONE
  }
  if s.not is Some(_) {
    m = m | S_NOT
  }
  if s.if_schema is Some(_) {
    m = m | S_IF
  }
  if s.then_schema is Some(_) {
    m = m | S_THEN
  }
  if s.else_schema is Some(_) {
    m = m | S_ELSE
  }
  m
}

///|
/// `{ "subschemas": { <one field> } }`-style helper constructors.
fn only_subschemas(s : @schema.SubschemaValidation) -> @schema.SchemaObject {
  { ..@schema.SchemaObject::default(), subschemas: Some(s), }
}

///|
fn all_of_schema(schemas : Array[@schema.Schema]) -> @schema.Schema {
  Object(
    only_subschemas({
      ..@schema.SubschemaValidation::default(),
      all_of: Some(schemas),
    }),
  )
}

///|
fn not_schema(schema : @schema.Schema) -> @schema.Schema {
  Object(
    only_subschemas({
      ..@schema.SubschemaValidation::default(),
      not: Some(schema),
    }),
  )
}
