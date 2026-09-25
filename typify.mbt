///|
/// Target language for generated code.
pub(all) enum Lang {
  Rust
  MoonBit
}

///|
/// Generate source code for `lang` from a JSON Schema. Placeholder.
pub fn generate(root : @schema.RootSchema, lang~ : Lang) -> String {
  ignore(root)
  match lang {
    Rust => "// TODO: Rust output\n"
    MoonBit => "// TODO: MoonBit output\n"
  }
}
