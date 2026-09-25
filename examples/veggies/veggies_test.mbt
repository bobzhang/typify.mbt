///|
test "README example" {
  let veggies = @veggies.Veggies::from_json_str(
    "{\"fruits\":[\"apple\"],\"vegetables\":[{\"veggieName\":\"leek\",\"veggieLike\":true}]}",
  )
  inspect(veggies.vegetables[0].veggie_name, content="leek")
  inspect(
    veggies.to_json_string(),
    content=(
      #|{"fruits":["apple"],"vegetables":[{"veggieLike":true,"veggieName":"leek"}]}
    ),
  )
}

///|
test "serde errors" {
  let err = (s : String) => {
    try @veggies.Veggies::from_json_str(s) catch {
      @typify_rt.DeError(msg) => msg
    } noraise {
      _ => "ok"
    }
  }
  inspect(
    err("{\"vegetables\":[{\"veggieName\":\"leek\"}]}"),
    content="missing field `veggieLike`",
  )
  inspect(
    err("{\"fruits\":[],\"fruits\":[]}"),
    content="duplicate field `fruits`",
  )
  inspect(
    err("{\"fruits\":[1]}"),
    content="invalid type: integer `1`, expected a string",
  )
}
