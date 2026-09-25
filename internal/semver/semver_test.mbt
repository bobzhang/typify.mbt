///|
fn m(req : String, ver : String) -> Bool raise {
  @semver.VersionReq::parse(req).matches(@semver.Version::parse(ver))
}

///|
test "caret, tilde, wildcard and comparison" {
  assert_true(m("1.2.3", "1.9.0"))
  assert_false(m("1.2.3", "2.0.0"))
  assert_true(m("^0.2.3", "0.2.9"))
  assert_false(m("^0.2.3", "0.3.0"))
  assert_false(m("^0.0.3", "0.0.4"))
  assert_true(m("~1.2", "1.2.7"))
  assert_false(m("~1.2", "1.3.0"))
  assert_true(m("1.*", "1.5.0"))
  assert_true(m("*", "0.0.1"))
  assert_true(m(">=1.0, <2", "1.99.0"))
  assert_false(m(">=1.0, <2", "2.0.0"))
  assert_true(m("=1.2.3", "1.2.3"))
}

///|
test "pre-releases need an explicit comparator" {
  assert_false(m("^1.0.0", "1.1.0-alpha"))
  assert_true(m("^1.1.0-alpha", "1.1.0-beta"))
  assert_true(m(">=1.0.0-alpha.2", "1.0.0-alpha.10"))
  assert_false(m(">1.0.0-alpha", "1.0.0-alpha"))
}

///|
test "parse errors" {
  for bad in ["", "1", "1.2", "01.2.3", "1.2.3-", "1.2.3 x", "a.b.c"] {
    let ok = try {
      ignore(@semver.Version::parse(bad))
      true
    } catch {
      _ => false
    }
    assert_false(ok, msg=bad)
  }
  for bad in ["*, 1", "1.2.3.4", ">=", "1.*.3"] {
    let ok = try {
      ignore(@semver.VersionReq::parse(bad))
      true
    } catch {
      _ => false
    }
    assert_false(ok, msg=bad)
  }
}
