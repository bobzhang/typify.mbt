///|
test "ordered Json codecs keep key order" {
  let text = "{\"z\":1,\"a\":{\"y\":true,\"b\":null}}"
  let sorted = @runtime.de_json(@runtime.De::from_str(text))
  inspect(
    @runtime.to_json_string(@runtime.ser_json(sorted)),
    content=(
      #|{"a":{"b":null,"y":true},"z":1}
    ),
  )
  let ordered = @runtime.de_json_ordered(@runtime.De::from_str(text))
  inspect(
    @runtime.to_json_string(@runtime.ser_json_ordered(ordered)),
    content=text,
  )
}
