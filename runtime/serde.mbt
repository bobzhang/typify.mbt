///|
/// A type with serde-compatible JSON codecs. Generated types implement
/// `deserialize` and `serialize` and attach the conveniences with
/// `pub extend T with @typify_rt.Serde::{...}`, so they are called as
/// `T::from_json_str(text)` and `value.to_json_string()`.
pub(open) trait Serde {
  /// Decode from a deserializer (the equivalent of `Deserialize`).
  fn deserialize(De) -> Self raise DeError
  /// Encode as an ordered JSON document (the equivalent of `Serialize`).
  fn serialize(Self) -> Content raise SerError
  /// Decode from JSON text, like `serde_json::from_str`.
  fn from_json_str(StringView) -> Self raise DeError = _
  /// Encode as compact JSON text, like `serde_json::to_string`.
  fn to_json_string(Self) -> String raise SerError = _
  /// Decode from a builtin `Json` value. Duplicate keys and number lexemes
  /// are not representable in `Json`; prefer `from_json_str`.
  fn from_json(Json) -> Self raise DeError = _
}

///|
impl Serde with fn from_json_str(text) {
  Self::deserialize(De::from_str(text))
}

///|
impl Serde with fn to_json_string(self) {
  to_json_string(self.serialize())
}

///|
impl Serde with fn from_json(json) {
  Self::deserialize(De::from_json(json))
}

///|
/// `ToJson` for a `Serde` type (serialization errors, such as flattening a
/// non-object, abort with the type's name).
pub fn[T : Serde] json_of(
  value : T,
  type_name : String,
  preserve_order? : Bool = false,
) -> Json {
  content_to_json(value.serialize(), preserve_order~) catch {
    e => abort("\{type_name}::to_json: \{e}")
  }
}
