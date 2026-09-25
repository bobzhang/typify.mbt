///|
test "identifiers" {
  inspect(lower_ident("Type"), content="type_")
  inspect(lower_ident("member"), content="member_")
  inspect(lower_ident("1st"), content="x1st")
  inspect(lower_ident("é"), content="ue9")
  inspect(lower_ident("中文"), content="u4e2du6587")
  inspect(lower_ident(""), content="x")
  inspect(upper_ident("foo", []), content="Foo")
  inspect(upper_ident("_x", []), content="X_x")
  inspect(upper_ident("Option", ["Option"]), content="Option_")
  inspect(upper_ident("Éclair", []), content="Uc9clair")
}
