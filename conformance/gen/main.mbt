// Generates JSON instances for conformance testing directly from the fixture
// schemas (independently of the IR): mostly-valid instances plus mutations
// that probe serde's edge cases. Writes conformance/cases/<schema>.tsv as
// `schema<TAB>Type<TAB>json` lines.

///|
priv struct Gen {
  rng : @splitmix.RandomState
  defs : @collections.StrMap[@schema.Schema]
}

///|
fn Gen::below(self : Gen, n : Int) -> Int {
  if n <= 1 {
    0
  } else {
    self.rng.next_uint(limit=n.reinterpret_as_uint()).reinterpret_as_int()
  }
}

///|
fn Gen::chance(self : Gen, percent : Int) -> Bool {
  self.below(100) < percent
}

///|
fn[T] Gen::pick(self : Gen, xs : Array[T]) -> T {
  xs[self.below(xs.length())]
}

///|
fn int_value(n : Int64) -> @serde_json.Value {
  @serde_json.Value::from_i64(n)
}

///|
let interesting_ints : Array[String] = [
  "0", "1", "-1", "2", "7", "127", "128", "-128", "-129", "255", "256", "32767",
  "32768", "65535", "65536", "-32769", "2147483647", "2147483648", "4294967295",
  "4294967296", "9007199254740993", "9223372036854775807", "9223372036854775808",
  "18446744073709551615", "18446744073709551616", "-9223372036854775808", "-9223372036854775809",
  "1.0", "2.5",
]

///|
let interesting_numbers : Array[String] = [
  "0", "1", "-1", "1.5", "-2.25", "1e10", "1.0", "0.1", "3", "1e300", "123456789.125",
  "-0.0",
]

///|
let sample_strings : Array[String] = [
  "", "a", "abc", "Hello, World", "a-b_c", "1234", "é中文", "😀", "true", "null",
  "x y", "UPPER", "ok", "0x10", "with \"quotes\"",
]

///|
fn parse(s : String) -> @serde_json.Value {
  @serde_json.parse(s) catch {
    _ => abort("bad literal \{s}")
  }
}

///|
fn Gen::any(self : Gen, depth : Int) -> @serde_json.Value {
  match self.below(if depth > 1 { 5 } else { 7 }) {
    0 => Null
    1 => Bool(self.chance(50))
    2 => parse(self.pick(interesting_numbers))
    3 | 4 => String(self.pick(sample_strings))
    5 => Array(Array::makei(self.below(3), _ => self.any(depth + 1)))
    _ => {
      let o = @collections.StrMap::new()
      for i in 0..<self.below(3) {
        o.set("k\{i}", self.any(depth + 1))
      }
      Object(o)
    }
  }
}

///|
fn Gen::string_for(self : Gen, o : @schema.SchemaObject) -> @serde_json.Value {
  let formatted = match o.format {
    Some("uuid") =>
      Some(
        self.pick([
          "67e55044-10b1-426f-9247-bb680e5fe0c8", "67E55044-10B1-426F-9247-BB680E5FE0C8",
          "67e5504410b1426f9247bb680e5fe0c8", "urn:uuid:67e55044-10b1-426f-9247-bb680e5fe0c8",
          "{67e55044-10b1-426f-9247-bb680e5fe0c8}", "not-a-uuid",
        ]),
      )
    Some("date") =>
      Some(
        self.pick([
          "2024-02-29", "2023-02-29", "1999-12-31", "+10000-01-01", "2024-1-1", "20240101",
        ]),
      )
    Some("date-time") =>
      Some(
        self.pick([
          "2024-02-29T12:34:56Z", "2024-02-29T12:34:56.123Z", "2024-02-29T12:34:56+05:30",
          "2024-02-29t12:34:56z", "2024-02-29 12:34:56Z", "2024-02-29T12:34:56.123456789-00:00",
          "2024-02-29T12:34:60Z", "2024-02-29T12:34:56",
        ]),
      )
    Some("ip") | Some("ipv4") | Some("ipv6") =>
      Some(
        self.pick([
          "127.0.0.1", "0.0.0.0", "::1", "2001:db8::1", "2001:0db8:0000:0000:0000:ff00:0042:8329",
          "::ffff:1.2.3.4", "256.1.1.1", "fe80::1%eth0",
        ]),
      )
    _ => None
  }
  if formatted is Some(s) {
    return String(s)
  }
  let base = self.pick(sample_strings)
  match o.string {
    Some({ max_length: Some(max), .. }) if self.chance(40) => {
      let n = max.reinterpret_as_int() + self.below(3) - 1
      String("x".repeat(n.max(0)))
    }
    Some({ min_length: Some(min), .. }) if self.chance(40) => {
      let n = min.reinterpret_as_int() + self.below(3) - 1
      String("y".repeat(n.max(0)))
    }
    _ => String(base)
  }
}

///|
fn Gen::number_for(
  self : Gen,
  o : @schema.SchemaObject,
  integer : Bool,
) -> @serde_json.Value {
  if self.chance(30) && o.number is Some(n) {
    let candidates = [
      n.minimum,
      n.maximum,
      n.exclusive_minimum,
      n.exclusive_maximum,
    ].filter(x => x is Some(_))
    if candidates.length() > 0 {
      let v = self.pick(candidates).unwrap() + (self.below(3) - 1).to_double()
      return if integer && v == v.floor() {
        int_value(v.to_int64())
      } else {
        @serde_json.Value::from_f64(v)
      }
    }
  }
  parse(self.pick(if integer { interesting_ints } else { interesting_numbers }))
}

///|
fn Gen::of_type(
  self : Gen,
  t : @schema.InstanceType,
  o : @schema.SchemaObject,
  depth : Int,
) -> @serde_json.Value {
  match t {
    Null => Null
    Boolean => Bool(self.chance(50))
    Integer => self.number_for(o, true)
    Number => self.number_for(o, false)
    String => self.string_for(o)
    Array => self.array_for(o, depth)
    Object => self.object_for(o, depth)
  }
}

///|
fn Gen::array_for(
  self : Gen,
  o : @schema.SchemaObject,
  depth : Int,
) -> @serde_json.Value {
  match o.array {
    Some({ items: Some(Vec(items)), additional_items, .. }) => {
      let out = items.map(s => self.value(s, depth + 1))
      if self.chance(20) {
        ignore(out.pop())
      } else if self.chance(20) {
        out.push(
          match additional_items {
            Some(s) => self.value(s, depth + 1)
            None => self.any(depth + 1)
          },
        )
      }
      Array(out)
    }
    Some({ items: Some(Single(item)), min_items, max_items, .. }) => {
      let min = min_items.map(u => u.reinterpret_as_int()).unwrap_or(0)
      let max = max_items.map(u => u.reinterpret_as_int()).unwrap_or(min + 3)
      let n = if depth > 3 {
        min
      } else {
        min + self.below((max - min).min(3) + 1)
      }
      let n = if self.chance(10) { n + 1 } else { n }
      Array(Array::makei(n.min(6), _ => self.value(item, depth + 1)))
    }
    _ => Array(Array::makei(self.below(3), _ => self.any(depth + 1)))
  }
}

///|
fn Gen::object_for(
  self : Gen,
  o : @schema.SchemaObject,
  depth : Int,
) -> @serde_json.Value {
  let out = @collections.StrMap::new()
  guard o.object is Some(v) else {
    if self.chance(50) {
      out.set("key", self.any(depth + 1))
    }
    return Object(out)
  }
  for name, s in v.properties {
    let required = v.required.contains(name)
    if required || (depth < 4 && self.chance(60)) {
      out.set(name, self.value(s, depth + 1))
    }
  }
  for name in v.required.iter() {
    if !out.contains(name) {
      out.set(name, self.any(depth + 1))
    }
  }
  for pattern, s in v.pattern_properties {
    if self.chance(50) {
      let key = if pattern.contains("^") { "abc" } else { "key" }
      out.set(key, self.value(s, depth + 1))
    }
  }
  match v.additional_properties {
    Some(Object(_) as s) if self.chance(60) =>
      out.set("extra_key", self.value(s, depth + 1))
    _ => ()
  }
  Object(out)
}

///|
/// A mostly-valid instance of a schema.
fn Gen::value(
  self : Gen,
  schema : @schema.Schema,
  depth : Int,
) -> @serde_json.Value {
  guard schema is Object(o) else { return self.any(depth) }
  if depth > 6 {
    return Null
  }
  if o.reference is Some(r) {
    let key = match r.rev_find("/") {
      Some(i) => r.unsafe_substring(start=i + 1, end=r.length())
      None => r
    }
    return match
      self.defs.get(
        key.replace_all(old="~1", new="/").replace_all(old="~0", new="~"),
      ) {
      Some(def) => self.value(def, depth + 1)
      None => self.any(depth)
    }
  }
  if o.const_value is Some(c) {
    return c
  }
  if o.enum_values is Some(values) && values.length() > 0 {
    return self.pick(values)
  }
  if o.subschemas is Some(sub) {
    match (sub.all_of, sub.any_of, sub.one_of) {
      (Some(all), _, _) => {
        // Merge object instances of every member.
        let merged = @collections.StrMap::new()
        let mut last = @serde_json.Value::Null
        for s in all {
          let v = self.value(s, depth + 1)
          match v {
            Object(m) =>
              for k, x in m {
                merged.set(k, x)
              }
            _ => last = v
          }
        }
        return if merged.is_empty() { last } else { Object(merged) }
      }
      (_, Some(xs), _) | (_, _, Some(xs)) if xs.length() > 0 =>
        return self.value(self.pick(xs), depth + 1)
      _ => ()
    }
  }
  match o.instance_type {
    Some(Single(t)) => self.of_type(t, o, depth)
    Some(Vec(ts)) if ts.length() > 0 => self.of_type(self.pick(ts), o, depth)
    _ =>
      if o.object is Some(_) {
        self.object_for(o, depth)
      } else if o.array is Some(_) {
        self.array_for(o, depth)
      } else if o.string is Some(_) {
        self.string_for(o)
      } else {
        self.any(depth)
      }
  }
}

///|
/// Perturb an instance to probe error handling.
fn Gen::mutate(self : Gen, v : @serde_json.Value) -> @serde_json.Value {
  match v {
    Object(m) if !m.is_empty() => {
      let m = m.copy()
      let keys = m.keys()
      match self.below(5) {
        0 => ignore(m.remove(self.pick(keys)))
        1 => m.set("unexpected_field", self.any(2))
        2 => m.set(self.pick(keys), Null)
        3 => m.set(self.pick(keys), self.any(2))
        _ => {
          let k = self.pick(keys)
          m.set(k, self.mutate(m.get(k).unwrap()))
        }
      }
      Object(m)
    }
    Array(xs) if !xs.is_empty() && self.chance(50) => {
      let xs = xs.copy()
      let i = self.below(xs.length())
      xs[i] = self.mutate(xs[i])
      Array(xs)
    }
    _ =>
      match self.below(4) {
        0 => Null
        1 => Array([v])
        2 => self.any(1)
        _ => Object(@collections.StrMap::from_array([("wrapped", v)]))
      }
  }
}

///|
/// The Rust type name of a definition (typify's `sanitize(name, Pascal)`,
/// plus the rename patch used by the fixtures' settings).
fn type_name_of(def : String) -> String {
  let n = @typify.sanitize(def, Pascal)
  if n == "TypeThatNeedsMoreDerives" {
    "TypeThatHasMoreDerives"
  } else {
    n
  }
}

///|
fn main {
  let args = @env.args()
  guard args.length() >= 4 else {
    println("usage: gen <schema.json> <schema-name> <out.tsv> [per-type]")
    return
  }
  let path = args[1]
  let name = args[2]
  let out_path = args[3]
  let per_type = if args.length() > 4 {
    @string.parse_int(args[4]) catch {
      _ => 16
    }
  } else {
    16
  }
  let text = @fs.read_file_to_string(path) catch {
    e => abort("read \{path}: \{Repr(e)}")
  }
  let root = @schema.RootSchema::from_json_str(text) catch {
    e => abort("parse \{path}: \{e}")
  }
  let seed = name
    .iter()
    .fold(init=0x9E3779B97F4A7C15UL, (h, c) => h * 31UL + c.to_int().to_uint64())
  let gen : Gen = { rng: @splitmix.new(seed~), defs: root.definitions, }
  // Text-level variants use their own stream so that the plain instances
  // stay stable.
  let wild : Gen = {
    rng: @splitmix.new(seed=seed ^ 0x5DEECE66DUL),
    defs: root.definitions,
  }
  let lines = []
  let emit = (ty : String, schema : @schema.Schema) => {
    for i in 0..<per_type {
      let v = gen.value(schema, 0)
      let v = if i % 4 == 3 { gen.mutate(v) } else { v }
      lines.push("\{name}\t\{ty}\t\{v.to_string()}")
    }
    for i in 0..<(per_type / 2) {
      let v = wild.value(schema, 0)
      let v = if i % 4 == 3 { wild.mutate(v) } else { v }
      lines.push("\{name}\t\{ty}\t\{wild.render_text(v)}")
    }
  }
  for def, schema in root.definitions {
    emit(type_name_of(def), schema)
  }
  if root.schema.metadata is Some({ title: Some(title), .. }) {
    emit(type_name_of(title), Object(root.schema))
  }
  @fs.write_string_to_file(out_path, lines.join("\n") + "\n") catch {
    e => abort("write: \{Repr(e)}")
  }
}
