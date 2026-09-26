///|
/// Policy for `x-rust-type` extensions naming crates not configured with
/// `with_crate`.
pub(all) enum UnknownPolicy {
  /// Generate the type from the schema.
  Generate
  /// Use the named type by path.
  Allow
  /// Currently behaves like `Generate`.
  Deny
} derive(Eq, Debug)

///|
/// A crate version to accept for `x-rust-type`.
pub(all) enum CrateVers {
  Version(@semver.Version)
  Any
  Never
} derive(Debug)

///|
/// Parse `!` (never), `*` (any) or a semver version.
pub fn CrateVers::parse(s : String) -> CrateVers? {
  match s {
    "!" => Some(Never)
    "*" => Some(Any)
    _ =>
      try @semver.Version::parse(s) catch {
        _ => None
      } noraise {
        v => Some(Version(v))
      }
  }
}

///|
priv struct CrateSpec {
  version : CrateVers
  rename : String?
}

///|
/// Modifications applied to a generated type with a given name.
pub struct TypeSpacePatch {
  mut rename : String?
  derives : Array[String]
  attrs : Array[String]
} derive(Debug)

///|
pub fn TypeSpacePatch::new() -> TypeSpacePatch {
  { rename: None, derives: [], attrs: [], }
}

///|
pub fn TypeSpacePatch::with_rename(
  self : TypeSpacePatch,
  rename : String,
) -> TypeSpacePatch {
  self.rename = Some(rename)
  self
}

///|
pub fn TypeSpacePatch::with_derive(
  self : TypeSpacePatch,
  derive_name : String,
) -> TypeSpacePatch {
  self.derives.push(derive_name)
  self
}

///|
pub fn TypeSpacePatch::with_attr(
  self : TypeSpacePatch,
  attr : String,
) -> TypeSpacePatch {
  self.attrs.push(attr)
  self
}

///|
/// A replacement of a named definition by an existing type.
pub(all) struct TypeSpaceReplace {
  replace_type : String
  impls : Array[TypeSpaceImpl]
} derive(Debug)

///|
priv struct TypeSpaceConversion {
  schema : @schema.SchemaObject
  type_name : String
  impls : Array[TypeSpaceImpl]
}

///|
/// Settings that alter type generation (upstream `TypeSpaceSettings`).
pub struct TypeSpaceSettings {
  mut type_mod : String?
  extra_derives : Array[String]
  extra_attrs : Array[String]
  mut struct_builder : Bool
  mut unknown_crates : UnknownPolicy
  priv crates : Map[String, CrateSpec]
  /// The map type path, e.g. `::std::collections::HashMap`.
  mut map_type : String
  patch : Map[String, TypeSpacePatch]
  replace : Map[String, TypeSpaceReplace]
  priv convert : Array[TypeSpaceConversion]
  /// Keep struct properties in schema order instead of sorting them by name
  /// (an extension: upstream typify always sorts).
  mut preserve_property_order : Bool
}

///|
pub fn TypeSpaceSettings::default() -> TypeSpaceSettings {
  {
    type_mod: None,
    extra_derives: [],
    extra_attrs: [],
    struct_builder: false,
    unknown_crates: Generate,
    crates: Map([]),
    map_type: "::std::collections::HashMap",
    patch: Map([]),
    replace: Map([]),
    convert: [],
    preserve_property_order: false,
  }
}

///|
fn TypeSpaceSettings::copy(self : TypeSpaceSettings) -> TypeSpaceSettings {
  {
    type_mod: self.type_mod,
    extra_derives: self.extra_derives.copy(),
    extra_attrs: self.extra_attrs.copy(),
    struct_builder: self.struct_builder,
    unknown_crates: self.unknown_crates,
    crates: self.crates.copy(),
    map_type: self.map_type,
    patch: self.patch.copy(),
    replace: self.replace.copy(),
    convert: self.convert.copy(),
    preserve_property_order: self.preserve_property_order,
  }
}

///|
/// Path prefix for types defined in the type space.
pub fn TypeSpaceSettings::with_type_mod(
  self : TypeSpaceSettings,
  type_mod : String,
) -> TypeSpaceSettings {
  self.type_mod = Some(type_mod)
  self
}

///|
/// Add a derive macro applied to all defined types.
pub fn TypeSpaceSettings::with_derive(
  self : TypeSpaceSettings,
  derive_name : String,
) -> TypeSpaceSettings {
  if !self.extra_derives.contains(derive_name) {
    self.extra_derives.push(derive_name)
  }
  self
}

///|
/// Add an attribute applied to all defined types.
pub fn TypeSpaceSettings::with_attr(
  self : TypeSpaceSettings,
  attr : String,
) -> TypeSpaceSettings {
  if !self.extra_attrs.contains(attr) {
    self.extra_attrs.push(attr)
  }
  self
}

///|
/// Generate builder types for structs.
pub fn TypeSpaceSettings::with_struct_builder(
  self : TypeSpaceSettings,
  struct_builder : Bool,
) -> TypeSpaceSettings {
  self.struct_builder = struct_builder
  self
}

///|
/// Replace a named definition with an existing type (last one wins).
pub fn TypeSpaceSettings::with_replacement(
  self : TypeSpaceSettings,
  type_name : String,
  replace_type : String,
  impls : Array[TypeSpaceImpl],
) -> TypeSpaceSettings {
  self.replace[type_name] = { replace_type, impls, }
  self
}

///|
/// Patch a generated type by name (last one wins).
pub fn TypeSpaceSettings::with_patch(
  self : TypeSpaceSettings,
  type_name : String,
  patch : TypeSpacePatch,
) -> TypeSpaceSettings {
  self.patch[type_name] = patch
  self
}

///|
/// Map schemas exactly equal to `schema` (ignoring metadata) to a named type
/// (first one wins).
pub fn TypeSpaceSettings::with_conversion(
  self : TypeSpaceSettings,
  schema : @schema.SchemaObject,
  type_name : String,
  impls : Array[TypeSpaceImpl],
) -> TypeSpaceSettings {
  self.convert.push({ schema, type_name, impls, })
  self
}

///|
pub fn TypeSpaceSettings::with_unknown_crates(
  self : TypeSpaceSettings,
  policy : UnknownPolicy,
) -> TypeSpaceSettings {
  self.unknown_crates = policy
  self
}

///|
/// Accept `x-rust-type` types from `crate_name` at `version`, optionally
/// renaming the crate in paths.
pub fn TypeSpaceSettings::with_crate(
  self : TypeSpaceSettings,
  crate_name : String,
  version : CrateVers,
  rename? : String,
) -> TypeSpaceSettings {
  self.crates[crate_name] = { version, rename, }
  self
}

///|
/// The map-like type used in generated code.
/// Keep struct properties in the order the schema lists them, so generated
/// structs declare, and serde writes, fields in that order. Upstream typify
/// always sorts properties by name; this is an extension, off by default.
/// The schema must be parsed with `RootSchema::from_json_str(text,
/// preserve_order=true)` for its order to be known.
pub fn TypeSpaceSettings::with_preserve_property_order(
  self : TypeSpaceSettings,
  preserve : Bool,
) -> TypeSpaceSettings {
  self.preserve_property_order = preserve
  self
}

///|
pub fn TypeSpaceSettings::with_map_type(
  self : TypeSpaceSettings,
  map_type : String,
) -> TypeSpaceSettings {
  self.map_type = map_type
  self
}
