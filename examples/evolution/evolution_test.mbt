// Each test: what a v2 writer produces and whether a v1 reader accepts it
// ("forward compatible"), then the reverse ("backward compatible").

///|
test "add an optional property: compatible" {
  let new = @v2.AddOptional(a="x", b="y").to_json_string()
  inspect(
    new,
    content=(
      #|{"a":"x","b":"y"}
    ),
  )
  inspect(
    @evolution.read(
      @v1.AddOptional::from_json_str,
      @v1.AddOptional::to_json_string,
      new,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
  let old = @v1.AddOptional(a="x").to_json_string()
  inspect(
    @evolution.read(
      @v2.AddOptional::from_json_str,
      @v2.AddOptional::to_json_string,
      old,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
}

///|
test "add an optional property to a closed object: old readers reject" {
  let new = @v2.AddOptionalClosed(a="x", b="y").to_json_string()
  inspect(
    @evolution.read(
      @v1.AddOptionalClosed::from_json_str,
      @v1.AddOptionalClosed::to_json_string,
      new,
    ),
    content=(
      #|ERR unknown field `b`, expected `a`
    ),
  )
  // Unless the new property is left unset.
  let unset = @v2.AddOptionalClosed(a="x").to_json_string()
  inspect(
    @evolution.read(
      @v1.AddOptionalClosed::from_json_str,
      @v1.AddOptionalClosed::to_json_string,
      unset,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
  let old = @v1.AddOptionalClosed(a="x").to_json_string()
  inspect(
    @evolution.read(
      @v2.AddOptionalClosed::from_json_str,
      @v2.AddOptionalClosed::to_json_string,
      old,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
}

///|
test "add an optional property with a default: compatible" {
  let new = @v2.AddOptionalDefault(a="x", b=7).to_json_string()
  inspect(
    @evolution.read(
      @v1.AddOptionalDefault::from_json_str,
      @v1.AddOptionalDefault::to_json_string,
      new,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
  let old = @v1.AddOptionalDefault(a="x").to_json_string()
  inspect(
    @evolution.read(
      @v2.AddOptionalDefault::from_json_str,
      @v2.AddOptionalDefault::to_json_string,
      old,
    ),
    content=(
      #|{"a":"x","b":1}
    ),
  )
}

///|
test "add a required property: new readers reject old data" {
  let new = @v2.AddRequired(a="x", b="y").to_json_string()
  inspect(
    @evolution.read(
      @v1.AddRequired::from_json_str,
      @v1.AddRequired::to_json_string,
      new,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
  let old = @v1.AddRequired(a="x").to_json_string()
  inspect(
    @evolution.read(
      @v2.AddRequired::from_json_str,
      @v2.AddRequired::to_json_string,
      old,
    ),
    content=(
      #|ERR missing field `b`
    ),
  )
}

///|
test "add a required property with a default: the default is ignored" {
  let old = @v1.AddRequiredDefault(a="x").to_json_string()
  inspect(
    @evolution.read(
      @v2.AddRequiredDefault::from_json_str,
      @v2.AddRequiredDefault::to_json_string,
      old,
    ),
    content=(
      #|ERR missing field `b`
    ),
  )
  let new = @v2.AddRequiredDefault(a="x", b=1).to_json_string()
  inspect(
    @evolution.read(
      @v1.AddRequiredDefault::from_json_str,
      @v1.AddRequiredDefault::to_json_string,
      new,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
}

///|
test "remove a required property: old readers reject new data" {
  let new = @v2.RemoveRequired(a="x").to_json_string()
  inspect(
    @evolution.read(
      @v1.RemoveRequired::from_json_str,
      @v1.RemoveRequired::to_json_string,
      new,
    ),
    content=(
      #|ERR missing field `b`
    ),
  )
  let old = @v1.RemoveRequired(a="x", b="y").to_json_string()
  inspect(
    @evolution.read(
      @v2.RemoveRequired::from_json_str,
      @v2.RemoveRequired::to_json_string,
      old,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
}

///|
test "remove an optional property: compatible" {
  let new = @v2.RemoveOptional(a="x").to_json_string()
  inspect(
    @evolution.read(
      @v1.RemoveOptional::from_json_str,
      @v1.RemoveOptional::to_json_string,
      new,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
  let old = @v1.RemoveOptional(a="x", b="y").to_json_string()
  inspect(
    @evolution.read(
      @v2.RemoveOptional::from_json_str,
      @v2.RemoveOptional::to_json_string,
      old,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
}

///|
test "required to optional: old readers reject data without it" {
  let new = @v2.RequiredToOptional(a="x").to_json_string()
  inspect(
    new,
    content=(
      #|{"a":"x"}
    ),
  )
  inspect(
    @evolution.read(
      @v1.RequiredToOptional::from_json_str,
      @v1.RequiredToOptional::to_json_string,
      new,
    ),
    content=(
      #|ERR missing field `b`
    ),
  )
  let old = @v1.RequiredToOptional(a="x", b="y").to_json_string()
  inspect(
    @evolution.read(
      @v2.RequiredToOptional::from_json_str,
      @v2.RequiredToOptional::to_json_string,
      old,
    ),
    content=(
      #|{"a":"x","b":"y"}
    ),
  )
}

///|
test "rename a property: incompatible both ways" {
  let new = @v2.Rename(full_name="Ada").to_json_string()
  inspect(
    @evolution.read(@v1.Rename::from_json_str, @v1.Rename::to_json_string, new),
    content=(
      #|ERR missing field `name`
    ),
  )
  let old = @v1.Rename(name="Ada").to_json_string()
  inspect(
    @evolution.read(@v2.Rename::from_json_str, @v2.Rename::to_json_string, old),
    content=(
      #|ERR missing field `full_name`
    ),
  )
}

///|
test "tighten a constraint: new readers reject old values" {
  let new = @v2.Tighten(code=@v2.TightenCode::new("abc")).to_json_string()
  inspect(
    @evolution.read(
      @v1.Tighten::from_json_str,
      @v1.Tighten::to_json_string,
      new,
    ),
    content=(
      #|{"code":"abc"}
    ),
  )
  let old = @v1.Tighten(code="abcdef").to_json_string()
  inspect(
    @evolution.read(
      @v2.Tighten::from_json_str,
      @v2.Tighten::to_json_string,
      old,
    ),
    content=(
      #|ERR longer than 3 characters
    ),
  )
}

///|
test "widen an integer: old readers reject large values" {
  let new = @v2.Widen(n=5000000000L).to_json_string()
  inspect(
    @evolution.read(@v1.Widen::from_json_str, @v1.Widen::to_json_string, new),
    content=(
      #|ERR invalid value: integer `5000000000`, expected i32
    ),
  )
  let old = @v1.Widen(n=42).to_json_string()
  inspect(
    @evolution.read(@v2.Widen::from_json_str, @v2.Widen::to_json_string, old),
    content=(
      #|{"n":42}
    ),
  )
}

///|
test "add an enum value: old readers reject it" {
  let new = @v2.ClosedEnum::Cancelled.to_json_string()
  inspect(
    @evolution.read(
      @v1.ClosedEnum::from_json_str,
      @v1.ClosedEnum::to_json_string,
      new,
    ),
    content=(
      #|ERR unknown variant `cancelled`, expected `pending` or `shipped`
    ),
  )
  let old = @v1.ClosedEnum::Shipped.to_json_string()
  inspect(
    @evolution.read(
      @v2.ClosedEnum::from_json_str,
      @v2.ClosedEnum::to_json_string,
      old,
    ),
    content=(
      #|"shipped"
    ),
  )
}

///|
test "add a value to an open enum: compatible both ways" {
  // v2 knows `cancelled`; v1 reads it as the catch-all string variant.
  let new = @v2.OpenEnum::Variant0(Cancelled).to_json_string()
  let v1 = @v1.OpenEnum::from_json_str(new)
  debug_inspect(
    v1,
    content=(
      #|Variant1(OpenEnumVariant1("cancelled"))
    ),
  )
  inspect(
    v1.to_json_string(),
    content=(
      #|"cancelled"
    ),
  )
  // v1 wrote `cancelled` through its catch-all; v2 reads it as known.
  let old = @v1.OpenEnum::Variant1(@v1.OpenEnumVariant1::new("cancelled")).to_json_string()
  debug_inspect(
    @v2.OpenEnum::from_json_str(old),
    content=(
      #|Variant0(Cancelled)
    ),
  )
}

///|
test "required to optional with a default: compatible (still written)" {
  let new = @v2.RequiredToDefault(a="x").to_json_string()
  inspect(
    new,
    content=(
      #|{"a":"x","b":0}
    ),
  )
  inspect(
    @evolution.read(
      @v1.RequiredToDefault::from_json_str,
      @v1.RequiredToDefault::to_json_string,
      new,
    ),
    content=(
      #|{"a":"x","b":0}
    ),
  )
  let old = @v1.RequiredToDefault(a="x", b=5).to_json_string()
  inspect(
    @evolution.read(
      @v2.RequiredToDefault::from_json_str,
      @v2.RequiredToDefault::to_json_string,
      old,
    ),
    content=(
      #|{"a":"x","b":5}
    ),
  )
}

///|
test "rename an optional property: accepted, but the value is lost" {
  let new = @v2.RenameOptional(full_name="Ada").to_json_string()
  inspect(
    @evolution.read(
      @v1.RenameOptional::from_json_str,
      @v1.RenameOptional::to_json_string,
      new,
    ),
    content=(
      #|{}
    ),
  )
  let old = @v1.RenameOptional(name="Ada").to_json_string()
  inspect(
    @evolution.read(
      @v2.RenameOptional::from_json_str,
      @v2.RenameOptional::to_json_string,
      old,
    ),
    content=(
      #|{}
    ),
  )
}

///|
test "optional to required but nullable: the key must be present" {
  let old = @v1.OptionalToRequiredNullable(a="x").to_json_string()
  inspect(
    @evolution.read(
      @v2.OptionalToRequiredNullable::from_json_str,
      @v2.OptionalToRequiredNullable::to_json_string,
      old,
    ),
    content=(
      #|ERR missing field `b`
    ),
  )
  inspect(
    @evolution.read(
      @v2.OptionalToRequiredNullable::from_json_str,
      @v2.OptionalToRequiredNullable::to_json_string,
      "{\"a\":\"x\",\"b\":null}",
    ),
    content=(
      #|{"a":"x","b":null}
    ),
  )
  let new = @v2.OptionalToRequiredNullable(a="x").to_json_string()
  inspect(
    new,
    content=(
      #|{"a":"x","b":null}
    ),
  )
  inspect(
    @evolution.read(
      @v1.OptionalToRequiredNullable::from_json_str,
      @v1.OptionalToRequiredNullable::to_json_string,
      new,
    ),
    content=(
      #|{"a":"x"}
    ),
  )
}

///|
test "a numeric maximum typify does not enforce" {
  // `minimum: 1, maximum: 100` becomes a non-zero u64: 500 is still accepted.
  let old = @v1.TightenBound(n=500).to_json_string()
  inspect(
    @evolution.read(
      @v2.TightenBound::from_json_str,
      @v2.TightenBound::to_json_string,
      old,
    ),
    content=(
      #|{"n":500}
    ),
  )
  let new = @v2.TightenBound(n=50).to_json_string()
  inspect(
    @evolution.read(
      @v1.TightenBound::from_json_str,
      @v1.TightenBound::to_json_string,
      new,
    ),
    content=(
      #|{"n":50}
    ),
  )
}

///|
test "additionalProperties: {} keeps unknown fields through old readers" {
  let new = @v2.Preserve(a="x", b="y").to_json_string()
  // v1 has no `b`, but keeps it in `extra` and writes it back.
  let v1 = @v1.Preserve::from_json_str(new)
  debug_inspect(
    v1.extra,
    content=(
      #|{ "b": String("y") }
    ),
  )
  inspect(
    v1.to_json_string(),
    content=(
      #|{"a":"x","b":"y"}
    ),
  )
}

///|
test "fix an array's length: new readers reject other lengths" {
  let new = @v2.FixedLength(xs=FixedArray::from_array([1L, 2])).to_json_string()
  inspect(
    @evolution.read(
      @v1.FixedLength::from_json_str,
      @v1.FixedLength::to_json_string,
      new,
    ),
    content=(
      #|{"xs":[1,2]}
    ),
  )
  let old = @v1.FixedLength(xs=[1, 2, 3]).to_json_string()
  inspect(
    @evolution.read(
      @v2.FixedLength::from_json_str,
      @v2.FixedLength::to_json_string,
      old,
    ),
    content=(
      #|ERR trailing characters
    ),
  )
}

///|
test "change a default: stored data without the property reads differently" {
  let stored = "{\"a\":\"x\"}"
  inspect(
    @evolution.read(
      @v1.ChangeDefault::from_json_str,
      @v1.ChangeDefault::to_json_string,
      stored,
    ),
    content=(
      #|{"a":"x","b":1}
    ),
  )
  inspect(
    @evolution.read(
      @v2.ChangeDefault::from_json_str,
      @v2.ChangeDefault::to_json_string,
      stored,
    ),
    content=(
      #|{"a":"x","b":2}
    ),
  )
}
