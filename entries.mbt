// Constructors and queries for type entries (upstream type_entry.rs).

///|
fn variants_unique(variants : Array[Variant]) -> Bool {
  unique(variants.map(v => v.ident_name.unwrap()))
}

///|
fn TypeEntryEnum::from_metadata(
  space : TypeSpace,
  type_name : Name,
  metadata : @schema.Metadata?,
  tag_type : EnumTagType,
  variants : Array[Variant],
  deny_unknown_fields : Bool,
  schema : @schema.Schema,
) -> TypeEntry raise TypifyError {
  // First try simple sanitization of the raw names.
  let mut variants = variants.map(v => {
    ..v,
    ident_name: Some(sanitize(v.raw_name, Pascal)),
  })
  // If they collide, turn elided characters into 'X's.
  if !variants_unique(variants) {
    variants = variants.map(v => {
      let buf = StringBuilder()
      for c in v.raw_name {
        buf.write_char(
          if c == '_' || !@unicode.is_xid_continue(c) {
            'X'
          } else {
            c
          },
        )
      }
      { ..v, ident_name: Some(sanitize(buf.to_string(), Pascal)), }
    })
  }
  if !variants_unique(variants) {
    let counts : Map[String, Int] = Map([])
    for v in variants {
      let n = v.ident_name.unwrap()
      counts[n] = match counts.get(n) {
        Some(c) => c + 1
        None => 0
      }
    }
    let dups = variants
      .filter(v => counts.get(v.ident_name.unwrap()).unwrap() > 0)
      .map(v => v.raw_name)
      .join(",")
    raise panic_with("Failed to make unique variant names for [\{dups}]")
  }
  guard get_type_name(type_name, metadata) is Some(name) else {
    raise panic_with("called `Option::unwrap()` on a `None` value (enum name)")
  }
  let patch = TypePatch::new(space.settings, name)
  {
    details: Enum({
      name: patch.name,
      rename: None,
      description: metadata_description(metadata),
      default: None,
      tag_type,
      variants,
      deny_unknown_fields,
      bespoke_impls: [],
      schema,
    }),
    extra_derives: patch.derives,
    extra_attrs: patch.attrs,
  }
}

///|
fn TypeEntryEnum::finalize(
  self : TypeEntryEnum,
  space : TypeSpace,
) -> TypeEntryEnum raise TypifyError {
  let impls = []
  // Not untagged, with all simple variants.
  if self.tag_type != Untagged &&
    !self.variants.is_empty() &&
    self.variants.iter().all(v => v.details is Simple) {
    impls.push(TypeEntryEnumImpl::AllSimpleVariants)
  }
  // Untagged and all variants impl FromStr, but none is irrefutably a String.
  if untagged_newtype_variants(
      space,
      self.tag_type,
      self.variants,
      FromStr,
      Some(FromStringIrrefutable),
    ) {
    impls.push(UntaggedFromStr)
  }
  if untagged_newtype_variants(
      space,
      self.tag_type,
      self.variants,
      Display,
      None,
    ) {
    impls.push(UntaggedDisplay)
  }
  if untagged_newtype_string(space, self.tag_type, self.variants) {
    impls.push(UntaggedFromStringIrrefutable)
  }
  { ..self, bespoke_impls: impls, }
}

///|
/// Untagged enum whose variants are all single-item newtypes implementing
/// `req_impl` (and, if given, none implementing `neg_impl`).
fn untagged_newtype_variants(
  space : TypeSpace,
  tag_type : EnumTagType,
  variants : Array[Variant],
  req_impl : TypeSpaceImpl,
  neg_impl : TypeSpaceImpl?,
) -> Bool raise TypifyError {
  if tag_type != Untagged {
    return false
  }
  for variant in variants {
    match variant.details {
      Item(type_id) => {
        let entry = space.entry_unchecked(type_id)
        if !entry.has_impl(space, req_impl) {
          return false
        }
        if neg_impl is Some(n) && entry.has_impl(space, n) {
          return false
        }
      }
      _ => return false
    }
  }
  true
}

///|
/// Untagged enum where some variant is irrefutably a string.
fn untagged_newtype_string(
  space : TypeSpace,
  tag_type : EnumTagType,
  variants : Array[Variant],
) -> Bool raise TypifyError {
  if tag_type != Untagged {
    return false
  }
  for variant in variants {
    if variant.details is Item(type_id) &&
      space.entry_unchecked(type_id).has_impl(space, FromStringIrrefutable) {
      return true
    }
  }
  false
}

///|
fn TypeEntryStruct::from_metadata(
  space : TypeSpace,
  type_name : Name,
  metadata : @schema.Metadata?,
  properties : Array[StructProperty],
  deny_unknown_fields : Bool,
  schema : @schema.Schema,
) -> TypeEntry raise TypifyError {
  guard get_type_name(type_name, metadata) is Some(name) else {
    raise panic_with(
      "called `Option::unwrap()` on a `None` value (struct name)",
    )
  }
  let patch = TypePatch::new(space.settings, name)
  {
    details: Struct({
      name: patch.name,
      rename: None,
      description: metadata_description(metadata),
      default: metadata_default(metadata),
      properties,
      deny_unknown_fields,
      schema,
    }),
    extra_derives: patch.derives,
    extra_attrs: patch.attrs,
  }
}

///|
fn TypeEntryNewtype::make(
  space : TypeSpace,
  type_name : Name,
  metadata : @schema.Metadata?,
  type_id : TypeId,
  constraints : TypeEntryNewtypeConstraints,
  schema : @schema.Schema,
) -> TypeEntry raise TypifyError {
  guard get_type_name(type_name, metadata) is Some(name) else {
    raise panic_with(
      "called `Option::unwrap()` on a `None` value (newtype name)",
    )
  }
  let patch = TypePatch::new(space.settings, name)
  {
    details: Newtype({
      name: patch.name,
      rename: None,
      description: metadata_description(metadata),
      default: None,
      type_id,
      constraints,
      schema,
    }),
    extra_derives: patch.derives,
    extra_attrs: patch.attrs,
  }
}

///|
fn TypeEntryNewtype::from_metadata(
  space : TypeSpace,
  type_name : Name,
  metadata : @schema.Metadata?,
  type_id : TypeId,
  schema : @schema.Schema,
) -> TypeEntry raise TypifyError {
  TypeEntryNewtype::make(
    space,
    type_name,
    metadata,
    type_id,
    NoConstraints,
    schema,
  )
}

///|
fn TypeEntryNewtype::from_metadata_with_enum_values(
  space : TypeSpace,
  type_name : Name,
  metadata : @schema.Metadata?,
  type_id : TypeId,
  enum_values : Array[@serde_json.Value],
  schema : @schema.Schema,
) -> TypeEntry raise TypifyError {
  TypeEntryNewtype::make(
    space,
    type_name,
    metadata,
    type_id,
    EnumValue(enum_values),
    schema,
  )
}

///|
fn TypeEntryNewtype::from_metadata_with_deny_values(
  space : TypeSpace,
  type_name : Name,
  metadata : @schema.Metadata?,
  type_id : TypeId,
  enum_values : Array[@serde_json.Value],
  schema : @schema.Schema,
) -> TypeEntry raise TypifyError {
  TypeEntryNewtype::make(
    space,
    type_name,
    metadata,
    type_id,
    DenyValue(enum_values),
    schema,
  )
}

///|
fn TypeEntryNewtype::from_metadata_with_string_validation(
  space : TypeSpace,
  type_name : Name,
  metadata : @schema.Metadata?,
  type_id : TypeId,
  validation : @schema.StringValidation,
  schema : @schema.Schema,
) -> TypeEntry raise TypifyError {
  TypeEntryNewtype::make(
    space,
    type_name,
    metadata,
    type_id,
    TypeEntryNewtypeConstraints::String(
      max_length=validation.max_length,
      min_length=validation.min_length,
      pattern=validation.pattern,
    ),
    schema,
  )
}

///|
/// Whether the type is known to implement `impl_name`.
pub fn TypeEntry::has_impl(
  self : TypeEntry,
  space : TypeSpace,
  impl_name : TypeSpaceImpl,
) -> Bool raise TypifyError {
  match self.details {
    Enum(details) =>
      match impl_name {
        Default => details.default is Some(_)
        FromStr =>
          details.bespoke_impls.contains(AllSimpleVariants) ||
          details.bespoke_impls.contains(UntaggedFromStr)
        Display =>
          details.bespoke_impls.contains(AllSimpleVariants) ||
          details.bespoke_impls.contains(UntaggedDisplay)
        FromStringIrrefutable =>
          details.bespoke_impls.contains(UntaggedFromStringIrrefutable)
      }
    Struct(details) => impl_name == Default && details.default is Some(_)
    Newtype(details) =>
      match (details.constraints, impl_name) {
        (_, Default) => details.default is Some(_)
        (String(..), FromStr) => true
        (String(..), Display) => true
        (NoConstraints, _) =>
          space.entry_unchecked(details.type_id).has_impl(space, impl_name)
        _ => false
      }
    Native(details) => details.impls.contains(impl_name)
    Box(type_id) =>
      if impl_name == Default {
        space.entry_unchecked(type_id).has_impl(space, impl_name)
      } else {
        false
      }
    JsonValue => false
    Unit | Option(_) | Vec(_) | Map(_, _) | Set(_) => impl_name == Default
    Tuple(type_ids) => {
      if impl_name != Default || type_ids.length() > 12 {
        return false
      }
      for id in type_ids {
        if !space.entry_unchecked(id).has_impl(space, Default) {
          return false
        }
      }
      true
    }
    Array(item_id, length) =>
      if length <= 32 && impl_name == Default {
        space.entry_unchecked(item_id).has_impl(space, impl_name)
      } else {
        false
      }
    Boolean | Integer(_) | Float(_) => impl_name != FromStringIrrefutable
    String => true
    Reference(_) => raise panic_with("internal error: entered unreachable code")
  }
}
