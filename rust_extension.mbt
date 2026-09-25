// The `x-rust-type` schema extension (upstream rust_extension.rs).

///|
priv struct RustExtension {
  crate_name : String
  version : String
  path : String
  parameters : Array[@schema.Schema]
}

///|
/// serde's derived `Deserialize` for the extension value.
fn parse_rust_extension(v : @serde_json.Value) -> RustExtension? {
  guard v is Object(o) else { return None }
  guard o.get("crate") is Some(String(crate_name)) else { return None }
  guard o.get("version") is Some(String(version)) else { return None }
  guard o.get("path") is Some(String(path)) else { return None }
  let parameters = match o.get("parameters") {
    None => []
    Some(Array(xs)) => {
      let out = []
      for x in xs {
        let s = @schema.decode_schema(x) catch { _ => return None }
        out.push(s)
      }
      out
    }
    Some(_) => return None
  }
  Some({ crate_name, version, path, parameters, })
}

///|
fn TypeSpace::convert_rust_extension(
  self : TypeSpace,
  schema : @schema.SchemaObject,
) -> TypeEntry? raise TypifyError {
  guard schema.extensions.get("x-rust-type") is Some(x_rust) else {
    return None
  }
  guard parse_rust_extension(x_rust) is Some(ext) else { return None }
  let req = try @semver.VersionReq::parse(ext.version) catch {
    _ => return None
  } noraise {
    r => r
  }
  let crate_ident = ext.crate_name.replace_all(old="-", new="_")
  guard ext.path.find("::") is Some(path_sep) else { return None }
  if crate_ident != ext.path.unsafe_substring(start=0, end=path_sep) {
    return None
  }
  let path = match self.settings.crates.get(ext.crate_name) {
    Some(spec) => {
      let ok_version = match spec.version {
        Any => true
        Version(v) => req.matches(v)
        Never => false
      }
      if !ok_version {
        return None
      }
      match spec.rename {
        Some(new_crate) =>
          new_crate.replace_all(old="-", new="_") +
          ext.path.unsafe_substring(start=path_sep, end=ext.path.length())
        None => ext.path
      }
    }
    None =>
      match self.settings.unknown_crates {
        Generate | Deny => return None
        Allow => ext.path
      }
  }
  // Convert the type parameters; any failure means "don't use the type".
  let param_ids = []
  for p in ext.parameters {
    match ok(() => self.id_for_schema(Unknown, p).0) {
      Some(id) => param_ids.push(id)
      None => return None
    }
  }
  Some(TypeEntry::new_native_params("::\{path}", param_ids))
}
