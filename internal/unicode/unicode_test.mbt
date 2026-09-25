///|
test "ascii classification" {
  assert_true(@unicode.is_xid_start('a'))
  assert_false(@unicode.is_xid_start('_'))
  assert_false(@unicode.is_xid_start('1'))
  assert_true(@unicode.is_xid_continue('_'))
  assert_true(@unicode.is_xid_continue('9'))
  assert_false(@unicode.is_xid_continue('-'))
  assert_true(@unicode.is_alphanumeric('Z'))
  assert_false(@unicode.is_alphanumeric('_'))
}

///|
test "non-ascii classification" {
  assert_true(@unicode.is_xid_start('é'))
  assert_true(@unicode.is_xid_start('中'))
  assert_false(@unicode.is_xid_start('😀'))
  assert_true(@unicode.is_alphanumeric('٣')) // Arabic-Indic digit three
  assert_true(@unicode.is_uppercase('Σ'))
  assert_true(@unicode.is_lowercase('ß'))
  assert_false(@unicode.is_lowercase('中'))
  assert_false(@unicode.is_uppercase('中'))
}

///|
test "case mapping" {
  inspect(@unicode.to_uppercase('ß'), content="SS")
  inspect(@unicode.to_lowercase('Σ'), content="σ")
  inspect(@unicode.to_lowercase('İ'), content="i̇")
  inspect(@unicode.to_uppercase('ﬃ'), content="FFI")
  inspect(@unicode.to_lowercase('中'), content="中")
}

///|
test "xid_start implies xid_continue" {
  @quickcheck.check((c : Char) => {
    !@unicode.is_xid_start(c) || @unicode.is_xid_continue(c)
  })
}

///|
test "uppercase letters lowercase to something different" {
  // For every char, lowering an uppercase ASCII letter is its ASCII lowercase.
  @quickcheck.check((c : Char) => {
    !c.is_ascii_uppercase() ||
    @unicode.to_lowercase(c) == c.to_ascii_lowercase().to_string()
  })
}
