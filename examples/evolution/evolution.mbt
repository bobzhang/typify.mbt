// Evidence for docs/schema-evolution.md: v1/ and v2/ are generated from
// the schemas next to them; the tests decode each version's output with the
// other version's types.

///|
/// Decode `text` and re-encode it, or report serde's error.
pub fn[T] read(
  decode : (StringView) -> T raise @typify_rt.DeError,
  encode : (T) -> String raise @typify_rt.SerError,
  text : String,
) -> String {
  try decode(text) catch {
    @typify_rt.DeError(msg) => "ERR \{msg}"
  } noraise {
    v => encode(v) catch { _ => "SERERR" }
  }
}
