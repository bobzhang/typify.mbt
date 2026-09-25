///|
/// A collection of types generated from JSON Schema (upstream `TypeSpace`).
pub struct TypeSpace {
  priv mut next_id : Int
  priv definitions : Map[RefKey, @schema.Schema]
  /// All types by id, in id order.
  id_to_entry : @sorted_map.SortedMap[TypeId, TypeEntry]
  priv type_to_id : Map[String, TypeId]
  priv name_to_id : Map[String, TypeId]
  priv ref_to_id : Map[RefKey, TypeId]
  mut uses_chrono : Bool
  mut uses_uuid : Bool
  mut uses_serde_json : Bool
  mut uses_regress : Bool
  settings : TypeSpaceSettings
  /// Schema conversions from settings (upstream `SchemaCache`).
  priv cache : Array[(@schema.SchemaObject, TypeEntry)]
  /// Shared default functions that generated code may call.
  defaults : Array[DefaultImpl]
}

///|
/// Create a type space with the given settings.
pub fn TypeSpace::new(settings : TypeSpaceSettings) -> TypeSpace {
  let cache = []
  for c in settings.convert {
    cache.push(
      (
        { ..c.schema, metadata: None, },
        TypeEntry::new_native(c.type_name, c.impls),
      ),
    )
  }
  {
    next_id: 1,
    definitions: Map([]),
    id_to_entry: @sorted_map.SortedMap([]),
    type_to_id: Map([]),
    name_to_id: Map([]),
    ref_to_id: Map([]),
    uses_chrono: false,
    uses_uuid: false,
    uses_serde_json: false,
    uses_regress: false,
    settings: settings.copy(),
    cache,
    defaults: [],
  }
}

///|
fn TypeSpace::cache_lookup(
  self : TypeSpace,
  schema : @schema.SchemaObject,
) -> TypeEntry? {
  let search = { ..schema, metadata: None, }
  for entry in self.cache {
    if entry.0 == search {
      return Some(entry.1)
    }
  }
  None
}

///|
/// The number of types in the space.
pub fn TypeSpace::type_count(self : TypeSpace) -> Int {
  self.id_to_entry.length()
}

///|
/// Look up a type entry.
pub fn TypeSpace::entry(
  self : TypeSpace,
  id : TypeId,
) -> TypeEntry raise TypifyError {
  match self.id_to_entry.get(id) {
    Some(e) => e
    None => raise InvalidTypeId
  }
}

///|
fn TypeSpace::entry_unchecked(
  self : TypeSpace,
  id : TypeId,
) -> TypeEntry raise TypifyError {
  match self.id_to_entry.get(id) {
    Some(e) => e
    None =>
      raise panic_with(
        "called `Option::unwrap()` on a `None` value (type \{id})",
      )
  }
}

///|
/// All type entries in id order.
pub fn TypeSpace::entries(self : TypeSpace) -> Array[(TypeId, TypeEntry)] {
  self.id_to_entry.to_array()
}

///|
/// Add named definitions that may reference each other. Each call must be
/// self-contained.
pub fn TypeSpace::add_ref_types(
  self : TypeSpace,
  type_defs : Array[(String, @schema.Schema)],
) -> Unit raise TypifyError {
  self.add_ref_types_impl(type_defs.map(d => (RefKey::Def(d.0), d.1)))
}

///|
fn TypeSpace::add_ref_types_impl(
  self : TypeSpace,
  definitions : Array[(RefKey, @schema.Schema)],
) -> Unit raise TypifyError {
  // Assign ids first so forward and cyclic references resolve.
  let base_id = self.next_id
  let def_len = definitions.length()
  self.next_id += def_len
  for index, def in definitions {
    self.ref_to_id[def.0] = TypeId(base_id + index)
    self.definitions[def.0] = def.1
  }
  for index, def in definitions {
    let (ref_name, schema) = def
    let type_id = TypeId(base_id + index)
    let maybe_replace = match ref_name {
      Root => None
      Def(def_name) => self.settings.replace.get(sanitize(def_name, Pascal))
    }
    match maybe_replace {
      None => {
        let type_name = match ref_name {
          Def(name) => Name::Required(name)
          Root => Unknown
        }
        self.convert_ref_type(type_name, schema, type_id)
      }
      Some(replace) =>
        self.id_to_entry.set(
          type_id,
          TypeEntry::new_native(replace.replace_type, replace.impls.copy()),
        )
    }
  }
  // Break containment cycles; a reference is needed to form a cycle.
  self.break_cycles(base_id, base_id + def_len)
  self.finalize_range(base_id)
}

///|
/// Finalize all entries with ids in `[base_id, next_id)`.
fn TypeSpace::finalize_range(
  self : TypeSpace,
  base_id : Int,
) -> Unit raise TypifyError {
  let end = self.next_id
  for index in base_id..<end {
    let type_id = TypeId(index)
    let entry = self.entry_unchecked(type_id)
    let entry = entry.finalize(self)
    self.id_to_entry.set(type_id, entry)
  }
}

///|
fn TypeSpace::convert_ref_type(
  self : TypeSpace,
  type_name : Name,
  schema : @schema.Schema,
  type_id : TypeId,
) -> Unit raise TypifyError {
  let (type_entry, metadata) = self.convert_schema(type_name, schema)
  let default = metadata_default(metadata)
  let type_entry = match type_entry.details {
    Enum(_) | Struct(_) | Newtype(_) => type_entry.with_default(default)
    // A simple alias to another definition.
    Reference(ref_id) =>
      TypeEntryNewtype::from_metadata(self, type_name, metadata, ref_id, schema)
    Native(native) if native.name_match(type_name) => type_entry
    // Unnamed types become newtypes.
    _ => {
      let subtype_id = self.assign_type(type_entry)
      TypeEntryNewtype::from_metadata(
        self, type_name, metadata, subtype_id, schema,
      )
    }
  }
  if type_entry.name() is Some(entry_name) {
    self.name_to_id[entry_name] = type_id
  }
  self.id_to_entry.set(type_id, type_entry)
}

///|
/// Add a type and return its id.
pub fn TypeSpace::add_type(
  self : TypeSpace,
  schema : @schema.Schema,
) -> TypeId raise TypifyError {
  self.add_type_with_name(schema, None)
}

///|
/// Add a type with a name hint and return its id.
pub fn TypeSpace::add_type_with_name(
  self : TypeSpace,
  schema : @schema.Schema,
  name_hint : String?,
) -> TypeId raise TypifyError {
  let base_id = self.next_id
  let name : Name = match name_hint {
    Some(s) => Suggested(s)
    None => Unknown
  }
  let (type_id, _) = self.id_for_schema(name, schema)
  self.finalize_range(base_id)
  type_id
}

///|
/// Add all definitions of a root schema, plus the root itself if it has a
/// title. Returns the root's id in that case.
pub fn TypeSpace::add_root_schema(
  self : TypeSpace,
  root : @schema.RootSchema,
) -> TypeId? raise TypifyError {
  let defs : Array[(RefKey, @schema.Schema)] = root.definitions
    .to_array()
    .map(d => (RefKey::Def(d.0), d.1))
  let root_type = metadata_title(root.schema.metadata) is Some(_)
  if root_type {
    defs.push((Root, Object(root.schema)))
  }
  self.add_ref_types_impl(defs)
  if root_type {
    self.ref_to_id.get(Root)
  } else {
    None
  }
}

///|
fn TypeSpace::assign(self : TypeSpace) -> TypeId {
  let id = TypeId(self.next_id)
  self.next_id += 1
  id
}

///|
/// Assign an id to an entry, resolving references and deduplicating: named
/// types by name (first wins), unnamed types structurally.
fn TypeSpace::assign_type(self : TypeSpace, ty : TypeEntry) -> TypeId {
  if ty.details is Reference(type_id) {
    return type_id
  }
  match ty.name() {
    Some(name) =>
      match self.name_to_id.get(name) {
        Some(type_id) => type_id
        None => {
          let type_id = self.assign()
          self.name_to_id[name] = type_id
          self.id_to_entry.set(type_id, ty)
          type_id
        }
      }
    None => {
      let key = ty.details.dedup_key()
      match self.type_to_id.get(key) {
        Some(type_id) => type_id
        None => {
          let type_id = self.assign()
          self.type_to_id[key] = type_id
          self.id_to_entry.set(type_id, ty)
          type_id
        }
      }
    }
  }
}

///|
/// Convert a schema and assign it an id (for sub-types).
fn TypeSpace::id_for_schema(
  self : TypeSpace,
  type_name : Name,
  schema : @schema.Schema,
) -> (TypeId, @schema.Metadata?) raise TypifyError {
  let (type_entry, metadata) = self.convert_schema(type_name, schema)
  let type_entry = match metadata {
    Some(m) => type_entry.with_default(m.default)
    None => type_entry
  }
  (self.assign_type(type_entry), metadata)
}

///|
fn TypeSpace::id_to_option(self : TypeSpace, id : TypeId) -> TypeId {
  self.assign_type(TypeEntry::from_details(Option(id)))
}

///|
fn TypeSpace::type_to_option(self : TypeSpace, ty : TypeEntry) -> TypeEntry {
  TypeEntry::from_details(Option(self.assign_type(ty)))
}

///|
fn TypeSpace::id_to_box(self : TypeSpace, id : TypeId) -> TypeId {
  self.assign_type(TypeEntry::from_details(Box(id)))
}

///|
fn TypeEntry::finalize(
  self : TypeEntry,
  space : TypeSpace,
) -> TypeEntry raise TypifyError {
  let entry = match self.details {
    Enum(e) => { ..self, details: Enum(e.finalize(space)), }
    _ => self
  }
  entry.check_defaults(space)
  entry
}

///|
fn TypeSpace::add_default_impl(self : TypeSpace, d : DefaultImpl) -> Unit {
  if !self.defaults.contains(d) {
    self.defaults.push(d)
    self.defaults.sort()
  }
}

///|
/// A short textual description of a type, for debugging (upstream
/// `TypeEntry::describe`).
pub fn TypeEntry::describe(self : TypeEntry) -> String {
  match self.details {
    Enum({ name, .. }) => "enum \{name}"
    Struct({ name, .. }) => "struct \{name}"
    Newtype({ name, type_id, .. }) => "newtype \{name} \{type_id.0}"
    Unit => "()"
    Option(t) => "option \{t.0}"
    Vec(t) => "vec \{t.0}"
    Map(k, v) => "map \{k.0} \{v.0}"
    Set(t) => "set \{t.0}"
    Box(t) => "box \{t.0}"
    Tuple(ts) => "tuple (\{ts.map(t => t.0.to_string()).join(", ")})"
    Array(t, n) => "array \{t.0}; \{n}"
    Boolean => "bool"
    Native({ type_name, .. }) | Integer(type_name) | Float(type_name) =>
      type_name
    String => "string"
    JsonValue => "json value"
    Reference(_) => "reference"
  }
}
