// The type IR (upstream typify-impl/src/type_entry.rs). Rust type names
// (e.g. "i64", "::uuid::Uuid") are kept verbatim as upstream does; the
// MoonBit backend maps them to MoonBit types.

///|
/// Shared default-value helper functions (`defaults::default_*`).
pub(all) enum DefaultImpl {
  Boolean
  I64
  U64
  NZU64
} derive(Eq, Compare, Debug)

///|
pub fn DefaultImpl::fn_name(self : DefaultImpl) -> String {
  match self {
    Boolean => "default_bool"
    I64 => "default_i64"
    U64 => "default_u64"
    NZU64 => "default_nzu64"
  }
}

///|
/// Traits a type may be known to implement.
pub(all) enum TypeSpaceImpl {
  FromStr
  FromStringIrrefutable
  Display
  Default
} derive(Eq, Compare, Hash, Debug)

///|
/// Parse an impl name as accepted in settings ("FromStr", "Display",
/// "Default").
pub fn TypeSpaceImpl::parse(s : String) -> TypeSpaceImpl raise TypifyError {
  match s {
    "FromStr" => FromStr
    "Display" => Display
    "Default" => Default
    _ => raise panic_with("\{s} is not a valid trait specifier")
  }
}

///|
pub(all) enum TypeEntryEnumImpl {
  AllSimpleVariants
  UntaggedFromStr
  UntaggedDisplay
  UntaggedFromStringIrrefutable
} derive(Eq, Compare, Debug)

///|
pub(all) enum EnumTagType {
  External
  Internal(tag~ : String)
  Adjacent(tag~ : String, content~ : String)
  Untagged
} derive(Eq, Debug)

///|
pub(all) enum StructPropertyRename {
  NoRename
  Rename(String)
  Flatten
} derive(Eq, Debug)

///|
pub(all) enum StructPropertyState {
  Required
  Optional
  Default(@serde_json.Value)
} derive(Eq, Debug)

///|
pub(all) struct StructProperty {
  name : String
  rename : StructPropertyRename
  state : StructPropertyState
  description : String?
  type_id : TypeId
} derive(Eq, Debug)

///|
pub(all) enum VariantDetails {
  Simple
  Item(TypeId)
  Tuple(Array[TypeId])
  Struct(Array[StructProperty])
} derive(Eq, Debug)

///|
pub(all) struct Variant {
  raw_name : String
  ident_name : String?
  description : String?
  details : VariantDetails
} derive(Eq, Debug)

///|
pub fn Variant::new(
  raw_name : String,
  description : String?,
  details : VariantDetails,
) -> Variant {
  { raw_name, ident_name: None, description, details, }
}

///|
pub(all) struct TypeEntryEnum {
  name : String
  rename : String?
  description : String?
  default : @serde_json.Value?
  tag_type : EnumTagType
  variants : Array[Variant]
  deny_unknown_fields : Bool
  bespoke_impls : Array[TypeEntryEnumImpl]
  schema : @schema.Schema
} derive(Eq, Debug)

///|
pub(all) struct TypeEntryStruct {
  name : String
  rename : String?
  description : String?
  default : @serde_json.Value?
  properties : Array[StructProperty]
  deny_unknown_fields : Bool
  schema : @schema.Schema
} derive(Eq, Debug)

///|
pub(all) enum TypeEntryNewtypeConstraints {
  NoConstraints
  EnumValue(Array[@serde_json.Value])
  DenyValue(Array[@serde_json.Value])
  String(max_length~ : UInt?, min_length~ : UInt?, pattern~ : String?)
} derive(Eq, Debug)

///|
pub(all) struct TypeEntryNewtype {
  name : String
  rename : String?
  description : String?
  default : @serde_json.Value?
  type_id : TypeId
  constraints : TypeEntryNewtypeConstraints
  schema : @schema.Schema
} derive(Eq, Debug)

///|
pub(all) struct TypeEntryNative {
  type_name : String
  impls : Array[TypeSpaceImpl]
  parameters : Array[TypeId]
} derive(Eq, Debug)

///|
/// Whether a native type's last path segment matches a required type name.
pub fn TypeEntryNative::name_match(
  self : TypeEntryNative,
  type_name : Name,
) -> Bool {
  let segments = self.type_name.split("::").collect()
  let native_name = segments[segments.length() - 1].to_owned()
  !self.parameters.is_empty() ||
  (type_name is Required(req) && req == native_name)
}

///|
pub(all) enum TypeEntryDetails {
  Enum(TypeEntryEnum)
  Struct(TypeEntryStruct)
  Newtype(TypeEntryNewtype)
  /// A type exported from a well-known crate.
  Native(TypeEntryNative)
  Option(TypeId)
  Box(TypeId)
  Vec(TypeId)
  Map(TypeId, TypeId)
  Set(TypeId)
  Array(TypeId, Int)
  Tuple(Array[TypeId])
  Unit
  Boolean
  /// Integers, with their Rust type name.
  Integer(String)
  /// Floats, with their Rust type name.
  Float(String)
  String
  JsonValue
  /// Only used during conversion for aliases between named definitions.
  Reference(TypeId)
} derive(Eq, Debug)

///|
pub(all) struct TypeEntry {
  details : TypeEntryDetails
  extra_derives : @collections.StrSet
  extra_attrs : @collections.StrSet
} derive(Eq, Debug)

///|
pub fn TypeEntry::from_details(details : TypeEntryDetails) -> TypeEntry {
  {
    details,
    extra_derives: @collections.StrSet::new(),
    extra_attrs: @collections.StrSet::new(),
  }
}

///|
pub fn TypeEntry::new_native(
  type_name : String,
  impls : Array[TypeSpaceImpl],
) -> TypeEntry {
  TypeEntry::from_details(Native({ type_name, impls, parameters: [], }))
}

///|
pub fn TypeEntry::new_native_params(
  type_name : String,
  parameters : Array[TypeId],
) -> TypeEntry {
  TypeEntry::from_details(Native({ type_name, impls: [], parameters, }))
}

///|
pub fn TypeEntry::new_integer(type_name : String) -> TypeEntry {
  TypeEntry::from_details(Integer(type_name))
}

///|
pub fn TypeEntry::new_float(type_name : String) -> TypeEntry {
  TypeEntry::from_details(Float(type_name))
}

///|
/// The name of a named (enum, struct or newtype) type.
pub fn TypeEntry::name(self : TypeEntry) -> String? {
  match self.details {
    Enum({ name, .. }) | Struct({ name, .. }) | Newtype({ name, .. }) =>
      Some(name)
    _ => None
  }
}

///|
/// Replace the `default` of a named type (no-op for other types).
fn TypeEntry::with_default(
  self : TypeEntry,
  default : @serde_json.Value?,
) -> TypeEntry {
  let details : TypeEntryDetails = match self.details {
    Enum(e) => Enum({ ..e, default, })
    Struct(s) => Struct({ ..s, default, })
    Newtype(n) => Newtype({ ..n, default, })
    other => other
  }
  { ..self, details, }
}

///|
/// Structural key of an unnamed type, standing in for upstream's derived
/// `Ord` on `TypeEntryDetails` in the `type_to_id` map.
fn TypeEntryDetails::dedup_key(self : TypeEntryDetails) -> String {
  let ids = (xs : Array[TypeId]) => xs.map(x => x.0.to_string()).join(",")
  match self {
    Native({ type_name, impls, parameters, }) =>
      "Native(\{type_name};\{impls.map(i => Repr(i).to_string()).join(",")};\{ids(parameters)})"
    Option(t) => "Option(\{t.0})"
    Box(t) => "Box(\{t.0})"
    Vec(t) => "Vec(\{t.0})"
    Map(k, v) => "Map(\{k.0},\{v.0})"
    Set(t) => "Set(\{t.0})"
    Array(t, n) => "Array(\{t.0},\{n})"
    Tuple(ts) => "Tuple(\{ids(ts)})"
    Unit => "Unit"
    Boolean => "Boolean"
    Integer(n) => "Integer(\{n})"
    Float(n) => "Float(\{n})"
    String => "String"
    JsonValue => "JsonValue"
    Enum(_) | Struct(_) | Newtype(_) | Reference(_) =>
      abort("dedup_key on a named or reference type")
  }
}
