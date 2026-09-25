// A port of the `schemars` 0.8.22 JSON Schema model (src/schema.rs), which
// is the input representation of upstream typify.

///|
/// A JSON Schema: either a boolean schema or a schema object.
pub(all) enum Schema {
  Bool(Bool)
  Object(SchemaObject)
} derive(Eq, Debug)

///|
/// The type of a JSON value (`type` keyword). The declaration order matters:
/// it is schemars' derived `Ord`.
pub(all) enum InstanceType {
  Null
  Boolean
  Object
  Array
  Number
  String
  Integer
} derive(Eq, Compare, Hash, Debug)

///|
/// A single value or an array of values (schemars `SingleOrVec`).
pub(all) enum SingleOrVec[T] {
  Single(T)
  Vec(Array[T])
} derive(Eq, Debug)

///|
/// Annotations that do not affect validation.
pub(all) struct Metadata {
  id : String?
  title : String?
  description : String?
  default : @serde_json.Value?
  deprecated : Bool
  read_only : Bool
  write_only : Bool
  examples : Array[@serde_json.Value]
} derive(Eq, Debug)

///|
pub(all) struct SubschemaValidation {
  all_of : Array[Schema]?
  any_of : Array[Schema]?
  one_of : Array[Schema]?
  not : Schema?
  if_schema : Schema?
  then_schema : Schema?
  else_schema : Schema?
} derive(Eq, Debug)

///|
pub(all) struct NumberValidation {
  multiple_of : Double?
  maximum : Double?
  exclusive_maximum : Double?
  minimum : Double?
  exclusive_minimum : Double?
} derive(Eq, Debug)

///|
pub(all) struct StringValidation {
  max_length : UInt?
  min_length : UInt?
  pattern : String?
} derive(Eq, Debug)

///|
pub(all) struct ArrayValidation {
  items : SingleOrVec[Schema]?
  additional_items : Schema?
  max_items : UInt?
  min_items : UInt?
  unique_items : Bool?
  contains : Schema?
} derive(Eq, Debug)

///|
pub(all) struct ObjectValidation {
  max_properties : UInt?
  min_properties : UInt?
  required : @collections.StrSet
  properties : @collections.StrMap[Schema]
  pattern_properties : @collections.StrMap[Schema]
  additional_properties : Schema?
  property_names : Schema?
} derive(Eq, Debug)

///|
/// A schema object. Each validation group is `None` when it equals its
/// default, exactly as schemars' `skip_if_default` deserializes it.
pub(all) struct SchemaObject {
  metadata : Metadata?
  instance_type : SingleOrVec[InstanceType]?
  format : String?
  enum_values : Array[@serde_json.Value]?
  const_value : @serde_json.Value?
  subschemas : SubschemaValidation?
  number : NumberValidation?
  string : StringValidation?
  array : ArrayValidation?
  object : ObjectValidation?
  reference : String?
  extensions : @collections.StrMap[@serde_json.Value]
} derive(Eq, Debug)

///|
/// The root of a schema document.
pub(all) struct RootSchema {
  meta_schema : String?
  schema : SchemaObject
  definitions : @collections.StrMap[Schema]
} derive(Eq, Debug)

///|
pub fn Metadata::default() -> Metadata {
  {
    id: None,
    title: None,
    description: None,
    default: None,
    deprecated: false,
    read_only: false,
    write_only: false,
    examples: [],
  }
}

///|
pub fn SubschemaValidation::default() -> SubschemaValidation {
  {
    all_of: None,
    any_of: None,
    one_of: None,
    not: None,
    if_schema: None,
    then_schema: None,
    else_schema: None,
  }
}

///|
pub fn NumberValidation::default() -> NumberValidation {
  {
    multiple_of: None,
    maximum: None,
    exclusive_maximum: None,
    minimum: None,
    exclusive_minimum: None,
  }
}

///|
pub fn StringValidation::default() -> StringValidation {
  { max_length: None, min_length: None, pattern: None, }
}

///|
pub fn ArrayValidation::default() -> ArrayValidation {
  {
    items: None,
    additional_items: None,
    max_items: None,
    min_items: None,
    unique_items: None,
    contains: None,
  }
}

///|
pub fn ObjectValidation::default() -> ObjectValidation {
  {
    max_properties: None,
    min_properties: None,
    required: @collections.StrSet::new(),
    properties: @collections.StrMap::new(),
    pattern_properties: @collections.StrMap::new(),
    additional_properties: None,
    property_names: None,
  }
}

///|
pub fn SchemaObject::default() -> SchemaObject {
  {
    metadata: None,
    instance_type: None,
    format: None,
    enum_values: None,
    const_value: None,
    subschemas: None,
    number: None,
    string: None,
    array: None,
    object: None,
    reference: None,
    extensions: @collections.StrMap::new(),
  }
}

///|
/// A schema object holding only a `$ref`.
pub fn SchemaObject::new_ref(reference : String) -> SchemaObject {
  { ..SchemaObject::default(), reference: Some(reference), }
}

///|
pub fn SchemaObject::is_ref(self : SchemaObject) -> Bool {
  self.reference is Some(_)
}

///|
/// schemars `has_type`: true when `type` is absent or contains `ty`.
pub fn SchemaObject::has_type(self : SchemaObject, ty : InstanceType) -> Bool {
  match self.instance_type {
    None => true
    Some(t) => t.contains(ty)
  }
}

///|
pub fn[T : Eq] SingleOrVec::contains(self : SingleOrVec[T], x : T) -> Bool {
  match self {
    Single(s) => s == x
    Vec(v) => v.contains(x)
  }
}

///|
/// schemars `Schema::into_object`: `true` becomes `{}`, `false` becomes
/// `{"not": {}}`.
pub fn Schema::into_object(self : Schema) -> SchemaObject {
  match self {
    Object(o) => o
    Bool(true) => SchemaObject::default()
    Bool(false) =>
      {
        ..SchemaObject::default(),
        subschemas: Some({
          ..SubschemaValidation::default(),
          not: Some(Object(SchemaObject::default())),
        }),
      }
  }
}

///|
pub fn Schema::new_ref(reference : String) -> Schema {
  Object(SchemaObject::new_ref(reference))
}

///|
pub fn Schema::is_ref(self : Schema) -> Bool {
  self is Object(o) && o.is_ref()
}

///|
/// The JSON name of an instance type.
pub fn InstanceType::name(self : InstanceType) -> String {
  match self {
    Null => "null"
    Boolean => "boolean"
    Object => "object"
    Array => "array"
    Number => "number"
    String => "string"
    Integer => "integer"
  }
}
