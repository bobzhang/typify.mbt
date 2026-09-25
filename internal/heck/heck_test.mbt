// Test cases are taken verbatim from heck 0.5.0's own test suite.

///|
test "snake case (heck test suite)" {
  let cases = [
    ("CamelCase", "camel_case"),
    ("This is Human case.", "this_is_human_case"),
    (
      "MixedUP CamelCase, with some Spaces", "mixed_up_camel_case_with_some_spaces",
    ),
    (
      "mixed_up_ snake_case with some _spaces", "mixed_up_snake_case_with_some_spaces",
    ),
    ("kebab-case", "kebab_case"),
    ("SHOUTY_SNAKE_CASE", "shouty_snake_case"),
    ("snake_case", "snake_case"),
    (
      "this-contains_ ALLKinds OfWord_Boundaries", "this_contains_all_kinds_of_word_boundaries",
    ),
    ("XΣXΣ baﬄe", "xσxς_baﬄe"),
    ("XMLHttpRequest", "xml_http_request"),
    ("FIELD_NAME11", "field_name11"),
    ("99BOTTLES", "99bottles"),
    ("FieldNamE11", "field_nam_e11"),
    ("abc123def456", "abc123def456"),
    ("abc123DEF456", "abc123_def456"),
    ("abc123Def456", "abc123_def456"),
    ("abc123DEf456", "abc123_d_ef456"),
    ("ABC123def456", "abc123def456"),
    ("ABC123DEF456", "abc123def456"),
    ("ABC123Def456", "abc123_def456"),
    ("ABC123DEf456", "abc123d_ef456"),
    ("ABC123dEEf456FOO", "abc123d_e_ef456_foo"),
    ("abcDEF", "abc_def"),
    ("ABcDE", "a_bc_de"),
  ]
  for case in cases {
    let (input, expected) = case
    assert_eq(@heck.to_snake_case(input), expected)
  }
}

///|
test "pascal case (heck test suite)" {
  let cases = [
    ("CamelCase", "CamelCase"),
    ("This is Human case.", "ThisIsHumanCase"),
    ("MixedUP_CamelCase, with some Spaces", "MixedUpCamelCaseWithSomeSpaces"),
    (
      "mixed_up_ snake_case, with some _spaces", "MixedUpSnakeCaseWithSomeSpaces",
    ),
    ("kebab-case", "KebabCase"),
    ("SHOUTY_SNAKE_CASE", "ShoutySnakeCase"),
    ("snake_case", "SnakeCase"),
    (
      "this-contains_ ALLKinds OfWord_Boundaries", "ThisContainsAllKindsOfWordBoundaries",
    ),
    ("XΣXΣ baﬄe", "XσxςBaﬄe"),
    ("XMLHttpRequest", "XmlHttpRequest"),
  ]
  for case in cases {
    let (input, expected) = case
    assert_eq(@heck.to_pascal_case(input), expected)
  }
}

///|
test "kebab case (heck test suite)" {
  let cases = [
    ("CamelCase", "camel-case"),
    ("This is Human case.", "this-is-human-case"),
    (
      "MixedUP CamelCase, with some Spaces", "mixed-up-camel-case-with-some-spaces",
    ),
    (
      "mixed_up_ snake_case with some _spaces", "mixed-up-snake-case-with-some-spaces",
    ),
    ("kebab-case", "kebab-case"),
    ("SHOUTY_SNAKE_CASE", "shouty-snake-case"),
    ("snake_case", "snake-case"),
    (
      "this-contains_ ALLKinds OfWord_Boundaries", "this-contains-all-kinds-of-word-boundaries",
    ),
    ("XΣXΣ baﬄe", "xσxς-baﬄe"),
    ("XMLHttpRequest", "xml-http-request"),
    (
      "لِنَذْهَبْ إِلَى السِّيْنَمَا", "لِنَذْهَبْ-إِلَى-السِّيْنَمَا",
    ),
    ("ファイルを読み込み", "ファイルを読み込み"),
    ("祝你一天过得愉快", "祝你一天过得愉快"),
  ]
  for case in cases {
    let (input, expected) = case
    assert_eq(@heck.to_kebab_case(input), expected)
  }
}

///|
test "edge cases" {
  assert_eq(@heck.to_snake_case(""), "")
  assert_eq(@heck.to_pascal_case("---"), "")
  assert_eq(@heck.to_snake_case("a"), "a")
  assert_eq(@heck.to_pascal_case("ß"), "SS")
}

///|
test "snake case is idempotent" {
  @quickcheck.check((s : String) => {
    let once = @heck.to_snake_case(s)
    @heck.to_snake_case(once) == once
  })
}

///|
test "kebab and snake agree modulo separator" {
  @quickcheck.check((s : String) => {
    @heck.to_kebab_case(s) ==
    @heck.to_snake_case(s).replace_all(old="_", new="-")
  })
}
