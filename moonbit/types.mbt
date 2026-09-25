// MoonBit types for IR types.

///|
fn entry(space : @typify.TypeSpace, id : @typify.TypeId) -> @typify.TypeEntry {
  match space.id_to_entry.get(id) {
    Some(e) => e
    None => abort("unresolved type id \{id}")
  }
}

///|
/// The kind of a Rust integer type name.
priv enum IntKind {
  I8
  U8
  I16
  U16
  I32
  U32
  I64
  U64
  NonZero(IntKind, String)
}

///|
fn int_kind(name : String) -> IntKind {
  match name {
    "i8" => I8
    "u8" => U8
    "i16" => I16
    "u16" => U16
    "i32" => I32
    "u32" => U32
    "i64" => I64
    "u64" => U64
    "::std::num::NonZeroU8" => NonZero(U8, "u8")
    "::std::num::NonZeroU16" => NonZero(U16, "u16")
    "::std::num::NonZeroU32" => NonZero(U32, "u32")
    "::std::num::NonZeroU64" => NonZero(U64, "u64")
    _ => I64
  }
}

///|
fn IntKind::mbt(self : IntKind) -> String {
  match self {
    I8 | I32 => "Int"
    U8 => "Byte"
    I16 => "Int16"
    U16 => "UInt16"
    U32 => "UInt"
    I64 => "Int64"
    U64 => "UInt64"
    NonZero(k, _) => k.mbt()
  }
}

///|
/// How a native (non-generated) Rust type is represented in MoonBit.
priv enum NativeKind {
  NUuid
  NDate
  NDateTime
  NIpAddr
  NIpv4
  NIpv6
  NString
  NJson
  /// `Option<T>` via x-rust-type.
  NOption(@typify.TypeId)
  /// Unknown: represented as `Json`.
  NUnknown(String)
}

///|
fn native_kind(native : @typify.TypeEntryNative) -> NativeKind {
  match native.type_name {
    "::uuid::Uuid" => NUuid
    "::chrono::naive::NaiveDate" => NDate
    "::chrono::DateTime<::chrono::offset::Utc>" => NDateTime
    "::std::net::IpAddr" => NIpAddr
    "::std::net::Ipv4Addr" => NIpv4
    "::std::net::Ipv6Addr" => NIpv6
    "String" | "::std::string::String" | "::std::path::PathBuf" => NString
    "serde_json::Value" | "::serde_json::Value" => NJson
    "::std::option::Option" =>
      match native.parameters {
        [p] => NOption(p)
        _ => NUnknown(native.type_name)
      }
    other => NUnknown(other)
  }
}

///|
/// The MoonBit type expression for an IR type.
fn Gen::mbt_type(self : Gen, id : @typify.TypeId) -> String {
  let e = entry(self.space, id)
  match e.details {
    Enum(_) | Struct(_) | Newtype(_) => self.type_name(id)
    Option(inner) =>
      match entry(self.space, inner).details {
        // Nested options are flattened, as in the Rust output.
        Option(_) => self.mbt_type(inner)
        _ => "\{self.mbt_type(inner)}?"
      }
    Box(inner) => self.mbt_type(inner)
    Vec(inner) | Set(inner) => "Array[\{self.mbt_type(inner)}]"
    Map(k, v) => "Map[\{self.mbt_type(k)}, \{self.mbt_type(v)}]"
    Array(inner, _) => "FixedArray[\{self.mbt_type(inner)}]"
    Tuple(ids) =>
      match ids {
        [] => "Unit"
        [only] => self.mbt_type(only)
        _ => "(\{ids.map(i => self.mbt_type(i)).join(", ")})"
      }
    Unit => "Unit"
    Boolean => "Bool"
    Integer(name) => int_kind(name).mbt()
    Float("f32") => "Float"
    Float(_) => "Double"
    String => "String"
    JsonValue => "Json"
    Native(n) =>
      match native_kind(n) {
        NUuid => "@typify_rt.Uuid"
        NDate => "@typify_rt.NaiveDate"
        NDateTime => "@typify_rt.DateTimeUtc"
        NIpAddr => "@typify_rt.IpAddr"
        NIpv4 => "@typify_rt.Ipv4Addr"
        NIpv6 => "@typify_rt.Ipv6Addr"
        NString => "String"
        NJson | NUnknown(_) => "Json"
        NOption(p) => "\{self.mbt_type(p)}?"
      }
    Reference(_) => abort("references should be resolved by now")
  }
}
