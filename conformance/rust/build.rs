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
    // Optionally, the random suite (scripts/random-conformance.sh):
    // `CONFORMANCE_RANDOM=<dir>` holds `<name>.tokens` and `<name>.types`.
    println!("cargo:rerun-if-env-changed=CONFORMANCE_RANDOM");
    let mut sources: Vec<(String, PathBuf)> =
        names.iter().map(|n| (n.clone(), oracle.clone())).collect();
    if let Ok(dir) = std::env::var("CONFORMANCE_RANDOM") {
        let dir = PathBuf::from(dir);
        println!("cargo:rerun-if-changed={}", dir.display());
        let mut random: Vec<String> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .filter(|p| p.extension().map_or(false, |e| e == "tokens"))
            .map(|p| p.file_stem().unwrap().to_str().unwrap().to_string())
            .collect();
        random.sort();
        sources.extend(random.into_iter().map(|n| (n, dir.clone())));
    }
    let mut modules = String::new();
    let mut table = String::from("pub fn dispatch(schema: &str, ty: &str, input: &str) -> Option<String> {\n    match (schema, ty) {\n");
    for (name, dir) in &sources {
        let module = name.replace('-', "_");
        let tokens = std::fs::read_to_string(dir.join(format!("{name}.tokens"))).unwrap();
        writeln!(
            modules,
            "#[allow(clippy::all, dead_code, unused_imports, non_camel_case_types, unused_mut)]\npub mod {module} {{ {tokens} }}"
        )
        .unwrap();
        let types = std::fs::read_to_string(dir.join(format!("{name}.types"))).unwrap();
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
