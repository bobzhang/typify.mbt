///|
/// Errors from type generation (upstream `typify_impl::Error`).
///
/// `Panic` stands for the places where upstream typify panics (`panic!`,
/// `todo!`, `unimplemented!`, failed `unwrap`s). It is kept distinct so that
/// code which deliberately ignores ordinary errors (upstream's `.ok()`) does
/// not swallow what upstream would treat as a crash.
pub(all) suberror TypifyError {
  BadValue(String, @serde_json.Value)
  InvalidTypeId
  InvalidValue
  InvalidSchema(type_name~ : String?, reason~ : String)
  Panic(String)
} derive(Debug)

///|
pub impl Show for TypifyError with fn output(self, logger) {
  match self {
    BadValue(_, _) => logger.write_string("unexpected value type")
    InvalidTypeId => logger.write_string("invalid TypeId")
    InvalidValue =>
      logger.write_string("value does not conform to the given schema")
    InvalidSchema(type_name~, reason~) => {
      let name = type_name.unwrap_or("<unknown type>")
      logger.write_string("invalid schema for \{name}: \{reason}")
    }
    Panic(msg) => logger.write_string("internal error: \{msg}")
  }
}

///|
/// Upstream `panic!`.
fn panic_with(msg : String) -> TypifyError {
  Panic(msg)
}

///|
/// Run `f`, turning ordinary errors into `None` (upstream `.ok()`), but
/// propagating `Panic`.
fn[T] ok(f : () -> T raise TypifyError) -> T? raise TypifyError {
  try f() catch {
    Panic(_) as e => raise e
    _ => None
  } noraise {
    v => Some(v)
  }
}
