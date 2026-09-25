//! Reads `schema<TAB>type<TAB>json` lines from stdin and prints, per line,
//! `OK <compact json>` (deserialize then serialize) or `ERR <message>`.

use std::io::{BufRead, Write};

#[allow(clippy::all)]
pub mod generated {
    include!(concat!(env!("OUT_DIR"), "/generated.rs"));
}

include!(concat!(env!("OUT_DIR"), "/dispatch.rs"));

pub fn roundtrip<T: serde::de::DeserializeOwned + serde::Serialize>(input: &str) -> String {
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

fn main() {
    std::panic::set_hook(Box::new(|_| {}));
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        let mut parts = line.splitn(3, '\t');
        let (schema, ty, input) = (
            parts.next().unwrap(),
            parts.next().unwrap(),
            parts.next().unwrap_or(""),
        );
        let result = std::panic::catch_unwind(|| dispatch(schema, ty, input))
            .map(|r| r.unwrap_or_else(|| "NOTYPE".to_string()))
            .unwrap_or_else(|_| "PANIC".to_string());
        writeln!(out, "{result}").unwrap();
    }
}
