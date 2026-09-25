///|
test "IR matches upstream typify (type descriptions)" {
  let failures = []
  for case in oracle_cases() {
    let (name, path, settings, everything) = case
    let root = load_root(path, everything)
    let space = @typify.TypeSpace::new(settings)
    let expected_error = "tests/oracle/typify/\{name}.error"
    let error = try space.add_root_schema(root) catch {
      e => Some(e.to_string())
    } noraise {
      _ => None
    }
    if file_exists(expected_error) {
      if error is None {
        failures.push("\{name}: expected an error")
      }
      continue
    }
    if error is Some(e) {
      failures.push("\{name}: \{e}")
      continue
    }
    let got = space
      .entries()
      .mapi((i, e) => "\{i + 1}: \{e.1.describe()}")
      .join("\n") +
      "\n"
    let want = read_file("tests/oracle/typify/\{name}.types")
    if got != want {
      let gl = got.split("\n").collect()
      let wl = want.split("\n").collect()
      let mut first = 0
      while first < gl.length() && first < wl.length() && gl[first] == wl[first] {
        first += 1
      }
      failures.push(
        "\{name}: first difference at line \{first + 1}: want \{Repr(wl.get(first).map(s => s.to_owned()))}, got \{Repr(gl.get(first).map(s => s.to_owned()))}",
      )
    }
  }
  if !failures.is_empty() {
    fail(failures.join("\n"))
  }
}
