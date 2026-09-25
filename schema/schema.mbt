///|
/// A parsed JSON Schema document. Placeholder until the schemars model is ported.
pub struct RootSchema {
  raw : Json
}

///|
pub fn RootSchema::parse(text : String) -> RootSchema raise {
  { raw: @json.parse(text), }
}
