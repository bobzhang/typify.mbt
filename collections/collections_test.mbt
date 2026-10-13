///|
/// Reference implementation: lexicographic comparison of code point arrays.
fn ref_compare(a : String, b : String) -> Int {
  let xa = a.to_array()
  let xb = b.to_array()
  for i = 0; i < xa.length() && i < xb.length(); i = i + 1 {
    let c = xa[i].to_int().compare(xb[i].to_int())
    if c != 0 {
      break c
    }
  } nobreak {
    xa.length().compare(xb.length())
  }
}

///|
fn sign(x : Int) -> Int {
  if x < 0 {
    -1
  } else if x > 0 {
    1
  } else {
    0
  }
}

///|
test "compare_str basics" {
  inspect(@collections.compare_str("b", "aa"), content="1")
  inspect(@collections.compare_str("a", "ab"), content="-1")
  inspect(@collections.compare_str("", ""), content="0")
  // U+E000 is below U+10000 in code point (and UTF-8) order.
  inspect(@collections.compare_str("\u{E000}", "\u{10000}"), content="-1")
  inspect(@collections.compare_str("\u{10000}", "\u{FFFF}"), content="1")
}

///|
test "compare_str agrees with code point order" {
  @quickcheck.check((pair : (String, String)) => {
    let (a, b) = pair
    sign(@collections.compare_str(a, b)) == sign(ref_compare(a, b))
  })
}

///|
test "compare_str is antisymmetric" {
  @quickcheck.check((pair : (String, String)) => {
    let (a, b) = pair
    @collections.compare_str(a, b) == -@collections.compare_str(b, a)
  })
}

///|
test "StrMap basic operations" {
  let m : @collections.StrMap[Int] = @collections.StrMap::new()
  m.set("b", 2)
  m.set("aa", 1)
  m.set("c", 3)
  debug_inspect(m.insert("b", 20), content="Some(2)")
  debug_inspect(m.keys(), content="[\"aa\", \"b\", \"c\"]")
  debug_inspect(m.get("b"), content="Some(20)")
  debug_inspect(m.remove("aa"), content="Some(1)")
  debug_inspect(m.get("aa"), content="None")
  inspect(m.length(), content="2")
  let seen = []
  for k, v in m {
    seen.push("\{k}=\{v}")
  }
  debug_inspect(seen, content="[\"b=20\", \"c=3\"]")
}

///|
test "StrMap behaves like a model map with sorted keys" {
  @quickcheck.check((ops : Array[(String, Int)]) => {
    let m = @collections.StrMap::new()
    let model : Map[String, Int] = Map([])
    for op in ops {
      m.set(op.0, op.1)
      model[op.0] = op.1
    }
    let keys = m.keys()
    let sorted = for i = 1; i < keys.length(); i = i + 1 {
      if @collections.compare_str(keys[i - 1], keys[i]) >= 0 {
        break false
      }
    } nobreak {
      true
    }
    sorted &&
    m.length() == model.length() &&
    model.iter().all(kv => m.get(kv.0) == Some(kv.1))
  })
}

///|
test "StrMap::new_ordered keeps insertion order" {
  let m : @collections.StrMap[Int] = @collections.StrMap::new_ordered()
  m.set("b", 1)
  m.set("a", 2)
  m.set("c", 3)
  m.set("b", 4) // replacing keeps the position
  debug_inspect(m.keys(), content="[\"b\", \"a\", \"c\"]")
  debug_inspect(m.get("b"), content="Some(4)")
  ignore(m.remove("a"))
  debug_inspect(m.keys(), content="[\"b\", \"c\"]")
  // Equality ignores order, as for IndexMap and BTreeMap.
  let sorted = @collections.StrMap::from_array([("c", 3), ("b", 4)])
  assert_true(m == sorted)
  assert_true(m.map(x => x * 2).is_ordered())
}
