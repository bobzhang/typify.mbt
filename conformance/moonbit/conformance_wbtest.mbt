///|
test "generated MoonBit agrees with serde on every conformance case" {
  let report = []
  let mut bad = 0
  for name in fixture_names {
    let o = check_file(name)
    report.push(
      "\{name}: \{o.total} cases, \{o.agree_exact} exact, \{o.agree_canonical} canonical, \{o.same_acceptance} same acceptance",
    )
    if o.agree_canonical != o.total {
      bad += 1
      for f in o.failures[:o.failures.length().min(20)] {
        report.push("  \{f}")
      }
    }
  }
  if bad > 0 {
    fail(report.join("\n"))
  }
}
