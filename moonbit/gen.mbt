// MoonBit code generation from the IR.

///|
priv struct Gen {
  space : @typify.TypeSpace
  /// Generated type names by type id.
  names : Map[Int, String]
  /// Constructor names by (enum type id, variant index).
  ctors : Map[Int, Array[String]]
  /// Field/label names by (type id, variant index or -1), property index.
  fields : Map[String, Array[String]]
  /// Global value names (defaults, patterns, allowed values).
  globals : Scope
  /// Whether maps serialize in key order (a `BTreeMap` map type).
  sorted_maps : Bool
}

///|
fn Gen::new(space : @typify.TypeSpace) -> Gen {
  let type_scope = Scope::new()
  let names : Map[Int, String] = Map([])
  let ctors : Map[Int, Array[String]] = Map([])
  let fields : Map[String, Array[String]] = Map([])
  for pair in space.entries() {
    let (id, e) = pair
    match e.details {
      Enum(d) => {
        names[id.0] = type_scope.alloc(upper_ident(d.name, reserved_type_names))
        let scope = Scope::new()
        ctors[id.0] = d.variants.map(v => {
          scope.alloc(upper_ident(v.ident_name.unwrap(), reserved_ctor_names))
        })
        for i, v in d.variants {
          if v.details is Struct(props) {
            fields["\{id.0}/\{i}"] = alloc_fields(props)
          }
        }
      }
      Struct(d) => {
        names[id.0] = type_scope.alloc(upper_ident(d.name, reserved_type_names))
        fields["\{id.0}/-1"] = alloc_fields(d.properties)
      }
      Newtype(d) =>
        names[id.0] = type_scope.alloc(upper_ident(d.name, reserved_type_names))
      _ => ()
    }
  }
  let map_type = space.settings.map_type
  {
    space,
    names,
    ctors,
    fields,
    globals: Scope::new(),
    sorted_maps: map_type.contains("BTreeMap"),
  }
}

///|
fn alloc_fields(props : Array[@typify.StructProperty]) -> Array[String] {
  let scope = Scope::new()
  props.map(p => scope.alloc(lower_ident(p.name)))
}

///|
fn Gen::type_name(self : Gen, id : @typify.TypeId) -> String {
  match self.names.get(id.0) {
    Some(n) => n
    None => abort("no name for \{id}")
  }
}

///|
/// A MoonBit string literal.
fn str_lit(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      c if c.to_int() < 0x20 || c.to_int() == 0x7F => {
        let hex = c.to_int().to_string(radix=16)
        buf.write_string("\\u{\{hex}}")
      }
      c => buf.write_char(c)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn str_array(xs : Array[String]) -> String {
  "[\{xs.map(str_lit).join(", ")}]"
}

// ---------------------------------------------------------------------------
// Decoding

///|
/// A function value decoding the type from a `@typify_rt.De`.
fn Gen::de_fn(self : Gen, id : @typify.TypeId) -> String {
  let e = entry(self.space, id)
  match e.details {
    Enum(_) | Struct(_) | Newtype(_) => "\{self.type_name(id)}::deserialize"
    Box(inner) => self.de_fn(inner)
    Boolean => "@typify_rt.de_bool"
    String => "@typify_rt.de_string"
    JsonValue => "@typify_rt.de_json"
    Unit => "@typify_rt.de_unit"
    Float("f32") => "@typify_rt.de_f32"
    Float(_) => "@typify_rt.de_f64"
    Integer(name) =>
      match int_kind(name) {
        I8 => "@typify_rt.de_i8"
        U8 => "@typify_rt.de_u8"
        I16 => "@typify_rt.de_i16"
        U16 => "@typify_rt.de_u16"
        I32 => "@typify_rt.de_i32"
        U32 => "@typify_rt.de_u32"
        I64 => "@typify_rt.de_i64"
        U64 => "@typify_rt.de_u64"
        NonZero(U8, _) => "@typify_rt.de_nonzero_u8"
        NonZero(U16, _) => "@typify_rt.de_nonzero_u16"
        NonZero(U32, _) => "@typify_rt.de_nonzero_u32"
        NonZero(_, _) => "@typify_rt.de_nonzero_u64"
      }
    Native(n) =>
      match native_kind(n) {
        NUuid => "@typify_rt.Uuid::deserialize"
        NDate => "@typify_rt.NaiveDate::deserialize"
        NDateTime => "@typify_rt.DateTimeUtc::deserialize"
        NIpAddr => "@typify_rt.IpAddr::deserialize"
        NIpv4 => "@typify_rt.Ipv4Addr::deserialize"
        NIpv6 => "@typify_rt.Ipv6Addr::deserialize"
        NString => "@typify_rt.de_string"
        NJson | NUnknown(_) => "@typify_rt.de_json"
        NOption(p) => "(d : @typify_rt.De) => @typify_rt.de_option(d, \{self.de_fn(p)})"
      }
    _ => "(d : @typify_rt.De) => \{self.de_expr(id, "d")}"
  }
}

///|
/// An expression decoding the type from the `De` expression `d`.
fn Gen::de_expr(self : Gen, id : @typify.TypeId, d : String) -> String {
  let e = entry(self.space, id)
  match e.details {
    Option(inner) =>
      match entry(self.space, inner).details {
        // `Option<Option<T>>` is emitted as `Option<T>` upstream.
        Option(_) => self.de_expr(inner, d)
        _ => "@typify_rt.de_option(\{d}, \{self.de_fn(inner)})"
      }
    Vec(inner) | Set(inner) => "@typify_rt.de_vec(\{d}, \{self.de_fn(inner)})"
    Map(k, v) =>
      "@typify_rt.de_map(\{d}, \{self.de_fn(k)}, \{self.de_fn(v)})"
    Tuple(ids) => {
      let elems = ids.mapi((i, t) => "let t\{i} = \{self.de_fn(t)}(s.next())")
      let result = match ids {
        [_] => "t0"
        _ => "(\{ids.mapi((i, _) => "t\{i}").join(", ")})"
      }
      "{ let s = @typify_rt.de_tuple(\{d}, \{ids.length()}); \{elems.join("; ")}; s.finish(); \{result} }"
    }
    Array(inner, n) =>
      "{ let s = @typify_rt.de_fixed(\{d}, \{n}); let xs = []; for _ in 0..<\{n} { xs.push(\{self.de_fn(inner)}(s.next())) }; s.finish(); FixedArray::from_array(xs) }"
    _ => "\{self.de_fn(id)}(\{d})"
  }
}

// ---------------------------------------------------------------------------
// Encoding

///|
/// A function value serializing the type to `@typify_rt.Content` (usable
/// where a `raise SerError` function is expected).
fn Gen::ser_fn(self : Gen, id : @typify.TypeId) -> String {
  let f = self.ser_callee(id)
  if f.has_prefix("@typify_rt.ser_") {
    // Primitive serializers do not raise; wrap them so they can be passed
    // where a raising function is expected.
    "(v : \{self.mbt_type(id)}) => \{f}(v)"
  } else {
    f
  }
}

///|
/// The function called to serialize the type directly.
fn Gen::ser_callee(self : Gen, id : @typify.TypeId) -> String {
  let e = entry(self.space, id)
  match e.details {
    Enum(_) | Struct(_) | Newtype(_) => "\{self.type_name(id)}::serialize"
    Box(inner) => self.ser_callee(inner)
    Boolean => "@typify_rt.ser_bool"
    String => "@typify_rt.ser_string"
    JsonValue => "@typify_rt.ser_json"
    Float("f32") => "@typify_rt.ser_f32"
    Float(_) => "@typify_rt.ser_f64"
    Integer(name) =>
      match int_kind(name) {
        I8 | I32 => "@typify_rt.ser_int"
        U8 => "@typify_rt.ser_byte"
        I16 => "@typify_rt.ser_i16"
        U16 => "@typify_rt.ser_u16"
        U32 => "@typify_rt.ser_uint"
        I64 => "@typify_rt.ser_i64"
        U64 => "@typify_rt.ser_u64"
        NonZero(k, _) =>
          match k {
            U8 => "@typify_rt.ser_byte"
            U16 => "@typify_rt.ser_u16"
            U32 => "@typify_rt.ser_uint"
            _ => "@typify_rt.ser_u64"
          }
      }
    Native(n) =>
      match native_kind(n) {
        NUuid => "@typify_rt.Uuid::serialize"
        NDate => "@typify_rt.NaiveDate::serialize"
        NDateTime => "@typify_rt.DateTimeUtc::serialize"
        NIpAddr => "@typify_rt.IpAddr::serialize"
        NIpv4 => "@typify_rt.Ipv4Addr::serialize"
        NIpv6 => "@typify_rt.Ipv6Addr::serialize"
        NString => "@typify_rt.ser_string"
        NJson | NUnknown(_) => "@typify_rt.ser_json"
        NOption(p) => "(v : \{self.mbt_type(id)}) => @typify_rt.ser_option(v, \{self.ser_fn(p)})"
      }
    _ => "(v : \{self.mbt_type(id)}) => \{self.ser_expr(id, "v")}"
  }
}

///|
/// An expression serializing the value expression `v`.
fn Gen::ser_expr(self : Gen, id : @typify.TypeId, v : String) -> String {
  let e = entry(self.space, id)
  match e.details {
    Unit => "@typify_rt.ser_unit()"
    Option(inner) =>
      match entry(self.space, inner).details {
        Option(_) => self.ser_expr(inner, v)
        _ => "@typify_rt.ser_option(\{v}, \{self.ser_fn(inner)})"
      }
    Vec(inner) | Set(inner) => "@typify_rt.ser_vec(\{v}, \{self.ser_fn(inner)})"
    Map(k, val) => {
      let key = "(k : \{self.mbt_type(k)}) => @typify_rt.map_key(\{self.ser_expr(k, "k")})"
      if self.sorted_maps && !(entry(self.space, k).details is String && entry(self.space, val).details is JsonValue) {
        "@typify_rt.ser_sorted_map(\{v}, \{self.key_cmp(k)}, \{key}, \{self.ser_fn(val)})"
      } else if entry(self.space, k).details is String &&
        entry(self.space, val).details is JsonValue {
        // serde_json::Map serializes in key order.
        "@typify_rt.ser_sorted_map(\{v}, @typify_rt.compare_keys, \{key}, \{self.ser_fn(val)})"
      } else {
        "@typify_rt.ser_map(\{v}, \{key}, \{self.ser_fn(val)})"
      }
    }
    Tuple(ids) =>
      match ids {
        [only] => "@typify_rt.Content::Array([\{self.ser_expr(only, v)}])"
        _ => {
          let parts = ids.mapi((i, t) => self.ser_expr(t, "\{v}.\{i}"))
          "@typify_rt.Content::Array([\{parts.join(", ")}])"
        }
      }
    Array(inner, _) => "@typify_rt.ser_vec(\{v}[:], \{self.ser_fn(inner)})"
    _ => "\{self.ser_callee(id)}(\{v})"
  }
}

///|
/// The ordering of map keys for `BTreeMap` output (the Rust key type's `Ord`).
fn Gen::key_cmp(self : Gen, k : @typify.TypeId) -> String {
  match entry(self.space, k).details {
    Enum(_) => "(a : \{self.type_name(k)}, b : \{self.type_name(k)}) => a.variant_index().compare(b.variant_index())"
    Newtype(_) => "(a : \{self.type_name(k)}, b : \{self.type_name(k)}) => @typify_rt.compare_keys(a.0.to_string(), b.0.to_string())"
    _ => "(a : \{self.mbt_type(k)}, b : \{self.mbt_type(k)}) => @typify_rt.compare_keys(a.to_string(), b.to_string())"
  }
}
