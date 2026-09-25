//! Random JSON Schemas exercising typify's conversions, with upstream
//! typify's results: `tests/oracle/typify-random/cases.jsonl`, one JSON
//! object per line: `{"schema": ..., "types": "...", "tokens": "..."}` or
//! `{"schema": ..., "error": "..."}` or `{"schema": ..., "panic": "..."}`.

use serde_json::{json, Map, Value};
use std::path::PathBuf;
use typify_impl::{TypeSpace, TypeSpaceSettings};

struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
    fn chance(&mut self, pct: u64) -> bool {
        self.below(100) < pct
    }
    fn pick<'a, T>(&mut self, xs: &'a [T]) -> &'a T {
        &xs[self.below(xs.len() as u64) as usize]
    }
}

const NAMES: &[&str] = &[
    "id", "name", "type", "value", "kind", "items", "ref", "self", "Type", "a-b", "a_b", "aB",
    "x y", "1st", "", "ok", "Option", "String", "data", "tag", "content", "é", "enum", "match",
];
const DEF_NAMES: &[&str] = &[
    "Foo", "Bar", "baz", "Qux", "thing-one", "ThingTwo", "Option", "Vec", "String", "Result",
    "node", "Tree", "Id", "Name",
];
const STRINGS: &[&str] = &["a", "b", "A", "a-b", "a_b", "", "1", "x y", "Foo", "foo", "é", "null"];

struct Gen {
    rng: Rng,
    defs: Vec<String>,
}

impl Gen {
    fn string_enum(&mut self) -> Value {
        let n = 1 + self.rng.below(4);
        let mut vals: Vec<Value> = (0..n).map(|_| json!(*self.rng.pick(STRINGS))).collect();
        if self.rng.chance(80) {
            vals.sort_by_key(|v| v.to_string());
            vals.dedup();
        }
        if self.rng.chance(15) {
            vals.push(Value::Null);
        }
        if self.rng.chance(10) {
            vals.push(json!(self.rng.below(3)));
        }
        let mut o = json!({ "enum": vals });
        if self.rng.chance(60) {
            o["type"] = json!("string");
        }
        o
    }

    fn leaf(&mut self) -> Value {
        match self.rng.below(16) {
            0 => json!({"type": "string"}),
            1 => json!({"type": "string", "format": *self.rng.pick(&["uuid", "date", "date-time", "ip", "ipv4", "ipv6", "email", "uri"])}),
            2 => json!({"type": "string", "minLength": self.rng.below(3), "maxLength": 3 + self.rng.below(5)}),
            3 => json!({"type": "string", "pattern": *self.rng.pick(&["^[a-z]+$", "^x", "[0-9]{2}", "^(a|b)$"])}),
            4 => json!({"type": "integer"}),
            5 => {
                let mut o = json!({"type": "integer"});
                if self.rng.chance(60) { o["minimum"] = json!(*self.rng.pick(&[0, 1, -128, 0])); }
                if self.rng.chance(50) { o["maximum"] = json!(*self.rng.pick(&[255, 65535, 127, 4294967295u64, 10])); }
                if self.rng.chance(30) { o["format"] = json!(*self.rng.pick(&["int8", "uint8", "int32", "uint64", "int64"])); }
                o
            }
            6 => json!({"type": "number"}),
            7 => json!({"type": "number", "format": "float"}),
            8 => json!({"type": "boolean"}),
            9 => json!({"type": "null"}),
            10 => self.string_enum(),
            11 => json!({"const": *self.rng.pick(&[json!("x"), json!(1), json!(true), json!(null)])}),
            12 => json!({"type": ["string", "null"]}),
            13 => json!({"type": ["integer", "string"]}),
            14 => json!({}),
            _ => json!(self.rng.chance(50)),
        }
    }

    fn schema(&mut self, depth: u32) -> Value {
        if depth > 3 || self.rng.chance(35) {
            return self.leaf();
        }
        let mut s = match self.rng.below(13) {
            0 | 1 | 2 => self.object(depth),
            3 => {
                let mut o = json!({"type": "array", "items": self.schema(depth + 1)});
                if self.rng.chance(20) { o["uniqueItems"] = json!(true); }
                if self.rng.chance(20) {
                    let n = self.rng.below(3);
                    o["minItems"] = json!(n);
                    o["maxItems"] = json!(n + self.rng.below(2));
                }
                o
            }
            4 => {
                let n = 1 + self.rng.below(3);
                let items: Vec<Value> = (0..n).map(|_| self.schema(depth + 1)).collect();
                json!({"type": "array", "items": items, "minItems": n, "maxItems": n})
            }
            5 | 6 => {
                let kw = *self.rng.pick(&["oneOf", "anyOf", "allOf"]);
                let n = 1 + self.rng.below(3);
                let xs: Vec<Value> = (0..n).map(|_| self.schema(depth + 1)).collect();
                json!({ kw: xs })
            }
            7 | 8 if !self.defs.is_empty() => {
                let d = self.rng.pick(&self.defs).clone();
                json!({"$ref": format!("#/definitions/{d}")})
            }
            9 => json!({"type": "object", "additionalProperties": self.schema(depth + 1)}),
            10 if self.rng.chance(10) => json!({"not": self.leaf()}),
            10 | 11 => self.extra(depth),
            _ => self.leaf(),
        };
        if s.is_object() && self.rng.chance(10) {
            s["description"] = json!("A description.");
        }
        if s.is_object() && self.rng.chance(8) {
            s["title"] = json!(*self.rng.pick(DEF_NAMES));
        }
        s
    }

    /// Tagged unions, merges, defaults and other typify special cases.
    fn extra(&mut self, depth: u32) -> Value {
        match self.rng.below(12) {
            0 | 1 => {
                // Internally/adjacently tagged: objects with a const-like tag.
                let tag = *self.rng.pick(&["type", "kind", "tag"]);
                let n = 1 + self.rng.below(3);
                let adjacent = self.rng.chance(40);
                let variants: Vec<Value> = (0..n)
                    .map(|i| {
                        let mut props = Map::new();
                        let tag_value = if self.rng.chance(85) {
                            json!({"type": "string", "enum": [*self.rng.pick(STRINGS)]})
                        } else {
                            json!({"const": format!("v{i}")})
                        };
                        props.insert(tag.to_string(), tag_value);
                        let mut req = vec![json!(tag)];
                        if adjacent {
                            props.insert("content".to_string(), self.schema(depth + 1));
                            if self.rng.chance(70) {
                                req.push(json!("content"));
                            }
                        } else {
                            for _ in 0..self.rng.below(3) {
                                let k = self.rng.pick(NAMES).to_string();
                                props.insert(k.clone(), self.schema(depth + 1));
                                if self.rng.chance(50) {
                                    req.push(json!(k));
                                }
                            }
                        }
                        let mut o = json!({"type": "object", "properties": props, "required": req});
                        if self.rng.chance(30) {
                            o["additionalProperties"] = json!(false);
                        }
                        o
                    })
                    .collect();
                json!({ *self.rng.pick(&["oneOf", "anyOf"]): variants })
            }
            2 => {
                // Externally tagged: single required property objects.
                let n = 1 + self.rng.below(3);
                let variants: Vec<Value> = (0..n)
                    .map(|_| {
                        let k = self.rng.pick(STRINGS).to_string();
                        json!({"type": "object", "properties": {k.clone(): self.schema(depth + 1)}, "required": [k], "additionalProperties": false})
                    })
                    .collect();
                json!({"oneOf": variants})
            }
            3 => json!({"allOf": [self.object(depth + 1), self.object(depth + 1)]}),
            4 => {
                let mut l = self.leaf();
                if l.is_object() {
                    let d = match l.get("type").and_then(|t| t.as_str()) {
                        Some("string") => json!(*self.rng.pick(STRINGS)),
                        Some("integer") => json!(self.rng.below(300)),
                        Some("number") => json!(1.5),
                        Some("boolean") => json!(true),
                        _ => json!(null),
                    };
                    l["default"] = d;
                }
                l
            }
            5 => json!({"type": "integer", "enum": [1, 2, 3]}),
            6 => {
                let mut o = self.object(depth + 1);
                o["type"] = json!(["object", "null"]);
                o
            }
            7 => json!({"type": "object", "patternProperties": {"^x-": self.leaf()}, "additionalProperties": false}),
            8 => json!({"type": "object", "additionalProperties": self.leaf(), "propertyNames": {"pattern": "^[a-z]+$"}}),
            9 => json!({"$ref": "#"}),
            10 => json!({"type": "object", "x-rust-type": {"crate": "foo", "version": "1.0.0", "path": "foo::Bar"}}),
            _ => json!({"type": "array", "items": self.schema(depth + 1), "default": []}),
        }
    }

    fn object(&mut self, depth: u32) -> Value {
        let n = self.rng.below(5);
        let mut props = Map::new();
        for _ in 0..n {
            props.insert(self.rng.pick(NAMES).to_string(), self.schema(depth + 1));
        }
        let mut o = json!({"type": "object", "properties": props});
        let keys: Vec<String> = props_keys(&o);
        if !keys.is_empty() && self.rng.chance(60) {
            let req: Vec<&String> = keys.iter().filter(|_| self.rng.chance(50)).collect();
            o["required"] = json!(req);
        }
        match self.rng.below(6) {
            0 => o["additionalProperties"] = json!(false),
            1 => o["additionalProperties"] = self.schema(depth + 1),
            _ => {}
        }
        if self.rng.chance(8) && !keys.is_empty() {
            let mut d = Map::new();
            d.insert(keys[0].clone(), json!("a"));
            o["default"] = Value::Object(d);
        }
        o
    }
}

fn props_keys(o: &Value) -> Vec<String> {
    o["properties"].as_object().map_or(vec![], |m| m.keys().cloned().collect())
}

pub fn main(n: usize) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let out_dir = root.join("tests/oracle/typify-random");
    std::fs::create_dir_all(&out_dir).unwrap();
    let mut lines = Vec::new();
    for i in 0..n {
        let mut g = Gen { rng: Rng(0x9e37_79b9_7f4a_7c15 ^ (i as u64 + 1) * 0x1000_0000_01b3), defs: vec![] };
        let ndefs = g.rng.below(4);
        g.defs = (0..ndefs).map(|_| g.rng.pick(DEF_NAMES).to_string()).collect();
        g.defs.sort();
        g.defs.dedup();
        let mut defs = Map::new();
        for d in g.defs.clone() {
            let s = g.schema(1);
            defs.insert(d, s);
        }
        let mut schema = g.schema(0);
        if !schema.is_object() {
            schema = json!({"type": "object"});
        }
        schema["definitions"] = Value::Object(defs);
        schema["title"] = json!(format!("Root{i}"));
        let text = serde_json::to_string(&schema).unwrap();
        // Each schema runs in a child process: some degenerate schemas make
        // upstream overflow its stack, which cannot be caught.
        let exe = std::env::current_exe().unwrap();
        let tmp = out_dir.join("schema.tmp.json");
        std::fs::write(&tmp, &text).unwrap();
        let out = run_with_timeout(&exe, &tmp, std::time::Duration::from_secs(10));
        let entry = if let Some(out) = out.filter(|o| o.status.success()) {
            let mut v: Value = serde_json::from_slice(&out.stdout).unwrap();
            v["schema"] = schema;
            v
        } else {
            // A stack overflow, or a runaway expansion (killed after 10s).
            json!({"schema": schema, "crash": "upstream crashed or timed out"})
        };
        lines.push(serde_json::to_string(&entry).unwrap());
    }
    let _ = std::fs::remove_file(out_dir.join("schema.tmp.json"));
    std::fs::write(out_dir.join("cases.jsonl"), lines.join("\n") + "\n").unwrap();
    let count = |k: &str| lines.iter().filter(|l| l.contains(&format!("\"{k}\":"))).count();
    eprintln!(
        "{n} schemas: {} ok, {} errors, {} panics, {} crashes",
        count("tokens"),
        count("error"),
        count("panic"),
        count("crash")
    );
}

/// Convert one schema file; prints the JSON result object.
pub fn one(path: &str) {
    let text = std::fs::read_to_string(path).unwrap();
    std::panic::set_hook(Box::new(|_| {}));
    let result = std::panic::catch_unwind(|| {
        let root_schema: schemars::schema::RootSchema =
            serde_json::from_str(&text).map_err(|e| format!("schema: {e}"))?;
        let mut space = TypeSpace::new(&TypeSpaceSettings::default());
        space.add_root_schema(root_schema).map_err(|e| e.to_string())?;
        let types: Vec<String> = space
            .iter_types()
            .enumerate()
            .map(|(i, t)| format!("{}: {}", i + 1, t.describe()))
            .collect();
        Ok::<_, String>((types.join("\n") + "\n", space.to_stream().to_string()))
    });
    let entry = match result {
        Ok(Ok((types, tokens))) => json!({"types": types, "tokens": tokens}),
        Ok(Err(e)) => json!({"error": e}),
        Err(p) => {
            let msg = p
                .downcast_ref::<String>()
                .cloned()
                .or_else(|| p.downcast_ref::<&str>().map(|s| s.to_string()))
                .unwrap_or_default();
            json!({"panic": msg})
        }
    };
    println!("{}", serde_json::to_string(&entry).unwrap());
}

/// Run `exe one <schema>` in a child process, killing it after `limit`.
fn run_with_timeout(
    exe: &std::path::Path,
    schema: &std::path::Path,
    limit: std::time::Duration,
) -> Option<std::process::Output> {
    let mut child = std::process::Command::new(exe)
        .arg("one")
        .arg(schema)
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .unwrap();
    // Drain stdout concurrently so a large result cannot block the child.
    let mut stdout = child.stdout.take().unwrap();
    let reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        std::io::Read::read_to_end(&mut stdout, &mut buf).map(|_| buf)
    });
    let start = std::time::Instant::now();
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            let stdout = reader.join().unwrap().unwrap_or_default();
            return Some(std::process::Output { status, stdout, stderr: vec![] });
        }
        if start.elapsed() > limit {
            let _ = child.kill();
            let _ = child.wait();
            return None;
        }
        std::thread::sleep(std::time::Duration::from_millis(5));
    }
}
