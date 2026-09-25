//! Oracle for the runtime's format types: prints a MoonBit test file of
//! `(kind, json input, "OK <output>" | "ERR <message>")` triples computed by
//! the real serde impls of uuid, chrono and std::net.
//!
//! cargo run --release --bin formats > ../../runtime/formats_oracle_test.mbt

use serde::{de::DeserializeOwned, Serialize};

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

fn run<T: DeserializeOwned + Serialize>(input: &str) -> String {
    match serde_json::from_str::<T>(input) {
        Ok(v) => match serde_json::to_string(&v) {
            Ok(s) => format!("OK {s}"),
            Err(e) => format!("SERERR {e}"),
        },
        Err(e) => {
            let msg = e.to_string();
            let msg = match msg.rfind(" at line ") {
                Some(i) => msg[..i].to_string(),
                None => msg,
            };
            format!("ERR {msg}")
        }
    }
}

fn mbt_string(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 || c == '\u{7f}' => out.push_str(&format!("\\u{{{:x}}}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// Random edits: truncate, delete, insert or replace characters.
fn mutate(rng: &mut Rng, s: &str, alphabet: &[char]) -> String {
    let mut cs: Vec<char> = s.chars().collect();
    let edits = 1 + rng.below(2);
    for _ in 0..edits {
        let n = cs.len() as u64;
        match rng.below(5) {
            0 if n > 0 => {
                let at = rng.below(n) as usize;
                cs.truncate(at);
            }
            1 if n > 0 => {
                let at = rng.below(n) as usize;
                cs.remove(at);
            }
            2 => {
                let at = rng.below(n + 1) as usize;
                cs.insert(at, *rng.pick(alphabet));
            }
            _ if n > 0 => {
                let at = rng.below(n) as usize;
                cs[at] = *rng.pick(alphabet);
            }
            _ => cs.push(*rng.pick(alphabet)),
        }
    }
    cs.into_iter().collect()
}

fn digits(rng: &mut Rng, min: u64, max: u64) -> String {
    let n = min + rng.below(max - min + 1);
    (0..n).map(|_| char::from(b'0' + rng.below(10) as u8)).collect()
}

fn num(rng: &mut Rng, lo: u64, hi: u64, width: usize) -> String {
    let v = lo + rng.below(hi - lo + 1);
    if rng.chance(85) {
        format!("{v:0width$}")
    } else {
        format!("{v}")
    }
}

fn year(rng: &mut Rng) -> String {
    match rng.below(10) {
        0 => format!("+{}", digits(rng, 1, 7)),
        1 => format!("-{}", digits(rng, 1, 7)),
        2 => digits(rng, 1, 6),
        _ => format!("{}", 1900 + rng.below(250)),
    }
}

fn date(rng: &mut Rng) -> String {
    let (m, d) = if rng.chance(85) {
        (num(rng, 1, 12, 2), num(rng, 1, 31, 2))
    } else {
        (num(rng, 0, 99, 2), num(rng, 0, 99, 2))
    };
    let sp = |rng: &mut Rng| if rng.chance(5) { " ".to_string() } else { String::new() };
    format!("{}{}-{}{}-{}", year(rng), sp(rng), m, sp(rng), d)
}

fn datetime(rng: &mut Rng) -> String {
    let sep = rng.pick(&["T", "T", "T", "t", " ", "_", ""]).to_string();
    let (h, mi, s) = if rng.chance(90) {
        (num(rng, 0, 23, 2), num(rng, 0, 59, 2), num(rng, 0, 60, 2))
    } else {
        (num(rng, 0, 99, 2), num(rng, 0, 99, 2), num(rng, 0, 99, 2))
    };
    let frac = match rng.below(6) {
        0 => format!(".{}", digits(rng, 1, 12)),
        1 => format!(".{}", digits(rng, 0, 3)),
        2 => format!(",{}", digits(rng, 1, 3)),
        _ => String::new(),
    };
    let off = match rng.below(12) {
        0..=3 => "Z".to_string(),
        4 => "z".to_string(),
        5 => format!("+{}:{}", num(rng, 0, 23, 2), num(rng, 0, 59, 2)),
        6 => format!("-{}:{}", num(rng, 0, 30, 2), num(rng, 0, 70, 2)),
        7 => format!("+{}{}", num(rng, 0, 23, 2), num(rng, 0, 59, 2)),
        8 => rng.pick(&["UTC", "utc", " UTC", "GMT", " Z", "+00", "-0", "+1:00", "+01:"]).to_string(),
        9 => String::new(),
        _ => format!("{}{}", rng.pick(&["+", "-", "\u{2212}"]), digits(rng, 1, 5)),
    };
    let tail = if rng.chance(5) { rng.pick(&[" ", "  ", "x", "Z"]).to_string() } else { String::new() };
    format!("{}{}{}:{}:{}{}{}{}", date(rng), sep, h, mi, s, frac, off, tail)
}

fn uuid(rng: &mut Rng) -> String {
    let hex: String = (0..32).map(|_| *rng.pick(&"0123456789abcdefABCDEF".chars().collect::<Vec<_>>())).collect();
    let hy = format!("{}-{}-{}-{}-{}", &hex[..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..]);
    match rng.below(6) {
        0 => hex,
        1 => format!("{{{hy}}}"),
        2 => format!("urn:uuid:{hy}"),
        _ => hy,
    }
}

fn ipv4(rng: &mut Rng) -> String {
    let parts = if rng.chance(90) { 4 } else { 1 + rng.below(6) };
    (0..parts)
        .map(|_| match rng.below(10) {
            0 => digits(rng, 0, 4),
            1 => format!("0{}", rng.below(100)),
            2 => format!("{}", rng.below(400)),
            _ => format!("{}", rng.below(256)),
        })
        .collect::<Vec<_>>()
        .join(".")
}

fn ipv6(rng: &mut Rng) -> String {
    let hexd: Vec<char> = "0123456789abcdefABCDEF".chars().collect();
    let group = |rng: &mut Rng| -> String {
        if rng.chance(30) {
            "0".to_string()
        } else {
            let max = if rng.chance(95) { 4 } else { 5 };
            let n = 1 + rng.below(max);
            (0..n).map(|_| *rng.pick(&hexd)).collect()
        }
    };
    let embedded = rng.chance(15);
    let total = if embedded { 6 } else { 8 };
    let mut groups: Vec<String> = (0..total).map(|_| group(rng)).collect();
    if rng.chance(50) {
        // Compress a run with `::`.
        let start = rng.below(total as u64 + 1) as usize;
        let len = rng.below((total - start) as u64 + 1) as usize;
        let head = groups[..start].join(":");
        let tail = groups[start + len..].join(":");
        let mut s = format!("{head}::{tail}");
        if embedded {
            s = if tail.is_empty() { format!("{s}{}", ipv4(rng)) } else { format!("{s}:{}", ipv4(rng)) };
        }
        return s;
    }
    if rng.chance(5) {
        groups.push(group(rng));
    }
    let mut s = groups.join(":");
    if embedded {
        s = format!("{s}:{}", ipv4(rng));
    }
    s
}

fn main() {
    let mut rng = Rng(0xf0f0_1234_5678_9abc);
    let mut cases: Vec<(&str, String)> = Vec::new();
    let non_strings = ["null", "true", "1", "-1.5", "[]", "{}", "[\"a\"]", "{\"a\":1}"];
    for kind in ["uuid", "date", "datetime", "ipv4", "ipv6", "ip"] {
        for ns in non_strings {
            cases.push((kind, ns.to_string()));
        }
    }
    let fixed_dt = [
        "2024-02-29T12:34:56Z", "2023-02-29T00:00:00Z", "2024-01-01T00:00:00.123456789+05:30",
        "2024-01-01 00:00:00+0000", "2024-01-01T23:59:60Z", "2024-01-01T23:59:60.5+01:00",
        "+12345-01-01T00:00:00Z", "-0001-12-31T23:59:59-23:59", "2024-01-01T00:00:00+24:00",
        "2024-1-1T1:2:3Z", "2024-01-01T00:00:00 UTC", "2024-01-01T00:00:00.Z", "", " ",
        "2024-01-01T00:00:00.1234567891Z", "0000-01-01T00:00:00Z", "9999-12-31T23:59:59.999999999Z",
        "2024-01-01T00:00:00.000Z", "2024-01-01T00:00:00.100Z", "2024-01-01T00:00:00.000001Z",
        "262143-12-31T23:59:59Z", "+262143-12-31T23:59:59Z", "-262144-01-01T00:00:00Z",
        "2024-01-01T00:00:00+23:59", "2024-01-01T00:00:00-00:00", "1970-01-01T00:00:00Z ",
    ];
    for s in fixed_dt {
        cases.push(("datetime", serde_json::to_string(s).unwrap()));
    }
    for s in ["2024-02-29", "2023-02-29", "2024-1-1", "+2024-01-01", "-0001-01-01", "2024-01-01 ", " 2024-01-01", "2024 - 01 - 01", "20240101", "2024-13-01", "2024-00-10", "262143-12-31", "262144-01-01"] {
        cases.push(("date", serde_json::to_string(s).unwrap()));
    }
    for s in ["", "urn:uuid:", "{}", "67e55044-10b1-426f-9247-bb680e5fe0c8", "67e5504410b1426f9247bb680e5fe0c8", "{67e55044-10b1-426f-9247-bb680e5fe0c8}", "urn:uuid:67E55044-10B1-426F-9247-BB680E5FE0C8", "67e55044-10b1-426f-9247-bb680e5fe0c", "67e55044-10b1-426f-9247-bb680e5fe0c8a", "67e5504410b1-426f-9247-bb680e5fe0c8", "67e55044-10b1-426f-9247bb680e5fe0c8", "67e55044x10b1-426f-9247-bb680e5fe0c8", "g7e55044-10b1-426f-9247-bb680e5fe0c8", "{67e55044-10b1-426f-9247-bb680e5fe0c8", "é7e55044-10b1-426f-9247-bb680e5fe0c8", "67e55044-10b1-426f-9247-bb680e5fe0cé"] {
        cases.push(("uuid", serde_json::to_string(s).unwrap()));
    }
    for s in ["0.0.0.0", "255.255.255.255", "256.0.0.1", "01.2.3.4", "1.2.3", "1.2.3.4.5", "1..2.3", "", "::", "::1", "1::", "::ffff:1.2.3.4", "::1.2.3.4", "1:2:3:4:5:6:7:8", "1:2:3:4:5:6:7:8:9", "1::2::3", "fe80::1%eth0", "1:2:3:4:5:6:1.2.3.4", "1:2:3:4:5:6:7:1.2.3.4", "12345::", ":1::", "1:0:0:0:0:0:0:1", "0:0:0:0:0:ffff:102:304", "1:0:0:2:0:0:0:3", "2001:db8:0:0:1:0:0:1", "0:0:1:0:0:0:0:0", "::0:0:1", "1:2::3:4:5:6:7"] {
        for kind in ["ipv4", "ipv6", "ip"] {
            cases.push((kind, serde_json::to_string(s).unwrap()));
        }
    }
    let dt_alpha: Vec<char> = "0123456789-:TZ+. tUz,".chars().collect();
    let uuid_alpha: Vec<char> = "0123456789abcdefABCDEF-{}urn:idgxé".chars().collect();
    let ip_alpha: Vec<char> = "0123456789abcdefABCDEF.:x%".chars().collect();
    for _ in 0..1500 {
        let s = datetime(&mut rng);
        let s = if rng.chance(30) { mutate(&mut rng, &s, &dt_alpha) } else { s };
        cases.push(("datetime", serde_json::to_string(&s).unwrap()));
    }
    for _ in 0..600 {
        let s = date(&mut rng);
        let s = if rng.chance(30) { mutate(&mut rng, &s, &dt_alpha) } else { s };
        cases.push(("date", serde_json::to_string(&s).unwrap()));
    }
    for _ in 0..800 {
        let s = uuid(&mut rng);
        let s = if rng.chance(50) { mutate(&mut rng, &s, &uuid_alpha) } else { s };
        cases.push(("uuid", serde_json::to_string(&s).unwrap()));
    }
    for _ in 0..600 {
        let s = ipv4(&mut rng);
        let s = if rng.chance(30) { mutate(&mut rng, &s, &ip_alpha) } else { s };
        let kind = *rng.pick(&["ipv4", "ip"]);
        cases.push((kind, serde_json::to_string(&s).unwrap()));
    }
    for _ in 0..1200 {
        let s = ipv6(&mut rng);
        let s = if rng.chance(30) { mutate(&mut rng, &s, &ip_alpha) } else { s };
        let kind = *rng.pick(&["ipv6", "ip"]);
        cases.push((kind, serde_json::to_string(&s).unwrap()));
    }

    println!("// Generated by conformance/rust (bin formats); DO NOT EDIT.\n");
    println!("///|\n/// (type, JSON input, serde's result)");
    println!("let format_cases : Array[(String, String, String)] = [");
    for (kind, input) in &cases {
        let out = match *kind {
            "uuid" => run::<uuid::Uuid>(input),
            "date" => run::<chrono::NaiveDate>(input),
            "datetime" => run::<chrono::DateTime<chrono::Utc>>(input),
            "ipv4" => run::<std::net::Ipv4Addr>(input),
            "ipv6" => run::<std::net::Ipv6Addr>(input),
            "ip" => run::<std::net::IpAddr>(input),
            _ => unreachable!(),
        };
        println!("  ({}, {}, {}),", mbt_string(kind), mbt_string(input), mbt_string(&out));
    }
    println!("]\n");
    println!(r#"///|
fn format_roundtrip(kind : String, input : String) -> String {{
  try {{
    let d = @runtime.De::from_str(input)
    let c = match kind {{
      "uuid" => @runtime.Uuid::deserialize(d).serialize()
      "date" => @runtime.NaiveDate::deserialize(d).serialize()
      "datetime" => @runtime.DateTimeUtc::deserialize(d).serialize()
      "ipv4" => @runtime.Ipv4Addr::deserialize(d).serialize()
      "ipv6" => @runtime.Ipv6Addr::deserialize(d).serialize()
      _ => @runtime.IpAddr::deserialize(d).serialize()
    }}
    "OK \{{@runtime.to_json_string(c)}}"
  }} catch {{
    @runtime.DeError(msg) => "ERR \{{msg}}"
    e => "OTHER \{{e}}"
  }}
}}

///|
test "differential: format types against uuid, chrono and std::net" {{
  let failures = []
  for case in format_cases {{
    let (kind, input, want) = case
    let got = format_roundtrip(kind, input)
    if got != want {{
      failures.push("\{{kind}} \{{input}}\n  want: \{{want}}\n  got:  \{{got}}")
    }}
  }}
  if failures.length() > 0 {{
    fail("\{{failures.length()}} mismatches:\n" + failures[:failures.length().min(40)].join("\n"))
  }}
}}"#);
}
