// Runs conformance cases through the generated MoonBit types and compares
// with serde's behaviour recorded by conformance/rust.

///|
/// Decode then re-encode, formatted like the Rust harness.
fn[T] run(
  input : String,
  decode : (StringView) -> T raise @typify_rt.DeError,
  encode : (T) -> String raise @typify_rt.SerError,
) -> String {
  let v = decode(input) catch {
    @typify_rt.DeError(msg) =>
      return if msg.has_prefix("panic:") { "PANIC" } else { "ERR \{msg}" }
  }
  let s = encode(v) catch { @typify_rt.SerError(msg) => return "SERERR \{msg}" }
  "OK \{s}"
}

///|
/// Canonical form of an `OK` payload (object keys sorted, for types whose
/// output includes unordered hash maps).
fn canonical(s : String) -> String {
  (try? @typify_rt.parse(s)).map(j => @typify_rt.stringify(@typify_rt.sort_keys(j))).unwrap_or(s)
}

///|
priv struct Outcome {
  total : Int
  agree_exact : Int
  agree_canonical : Int
  same_acceptance : Int
  failures : Array[String]
}

///|
fn check_file(name : String) -> Outcome {
  let cases = @fs.read_file_to_string("conformance/cases/\{name}.tsv") catch { _ => "" }
  let expected = @fs.read_file_to_string("conformance/cases/\{name}.expected") catch { _ => "" }
  let cases = cases.split("\n").filter(l => !l.is_empty()).map(l => l.to_owned()).collect()
  let expected = expected.split("\n").filter(l => !l.is_empty()).map(l => l.to_owned()).collect()
  let mut exact = 0
  let mut canon = 0
  let mut accept = 0
  let failures = []
  for i, line in cases {
    let parts = line.split("\t").map(p => p.to_owned()).collect()
    let (schema, ty) = (parts[0], parts[1])
    let input = parts[2:].to_owned().join("\t")
    let want = expected.get(i).unwrap_or("")
    let got = dispatch(schema, ty, input)
    let want_ok = want.has_prefix("OK ")
    let got_ok = got.has_prefix("OK ")
    if want == got {
      exact += 1
      canon += 1
      accept += 1
    } else if want_ok && got_ok && canonical(want.unsafe_substring(start=3, end=want.length())) ==
      canonical(got.unsafe_substring(start=3, end=got.length())) {
      canon += 1
      accept += 1
    } else if want_ok == got_ok && want.has_prefix("ERR") == got.has_prefix("ERR") &&
      want.has_prefix("PANIC") == got.has_prefix("PANIC") {
      accept += 1
      if want_ok {
        failures.push("\{ty} \{input}\n    want: \{want}\n    got:  \{got}")
      }
    } else {
      failures.push("\{ty} \{input}\n    want: \{want}\n    got:  \{got}")
    }
  }
  { total: cases.length(), agree_exact: exact, agree_canonical: canon, same_acceptance: accept, failures }
}

///|
let fixture_names : Array[String] = [
  "arrays-and-tuples", "deny-list", "extraneous-enum", "flatten-default", "github", "id-or-name",
  "maps", "maps_custom", "merged-schemas", "more_types", "multiple-instance-types", "noisy-types",
  "property-pattern", "reflexive", "rust-collisions", "simple-types", "string-enum-with-default",
  "type-with-modified-generation", "types-with-defaults", "types-with-more-impls",
  "untyped-enum-with-null", "various-enums", "x-rust-type",
]
