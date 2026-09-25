use std::{fmt::Write, path::PathBuf};

fn main() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let oracle = root.join("tests/oracle/typify");
    println!("cargo:rerun-if-changed={}", oracle.display());
    let mut names: Vec<String> = std::fs::read_dir(&oracle)
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().map_or(false, |e| e == "tokens"))
        .map(|p| p.file_stem().unwrap().to_str().unwrap().to_string())
        // vega refers to user-supplied replacement types; the JsonSchema
        // variant only differs by a derive (same schema as various-enums).
        .filter(|n| n != "vega" && n != "various-enums-json-schema")
        .collect();
    names.sort();
    let mut modules = String::new();
    let mut table = String::from("pub fn dispatch(schema: &str, ty: &str, input: &str) -> Option<String> {\n    match (schema, ty) {\n");
    for name in &names {
        let module = name.replace('-', "_");
        let tokens = std::fs::read_to_string(oracle.join(format!("{name}.tokens"))).unwrap();
        writeln!(
            modules,
            "#[allow(clippy::all, dead_code, unused_imports, non_camel_case_types, unused_mut)]\npub mod {module} {{ {tokens} }}"
        )
        .unwrap();
        let types = std::fs::read_to_string(oracle.join(format!("{name}.types"))).unwrap();
        for line in types.lines() {
            let desc = line.split_once(": ").unwrap().1;
            let mut parts = desc.split(' ');
            let kind = parts.next().unwrap();
            if matches!(kind, "struct" | "enum" | "newtype") {
                let ty = parts.next().unwrap();
                writeln!(
                    table,
                    "        ({name:?}, {ty:?}) => Some(crate::roundtrip::<crate::generated::{module}::{ty}>(input)),"
                )
                .unwrap();
            }
        }
    }
    table.push_str("        _ => None,\n    }\n}\n");
    let out = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    std::fs::write(out.join("generated.rs"), modules).unwrap();
    std::fs::write(out.join("dispatch.rs"), table).unwrap();
}
