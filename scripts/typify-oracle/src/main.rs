use std::path::{Path, PathBuf};

use schemars::schema::RootSchema;
use typify_impl::{CrateVers, TypeSpace, TypeSpaceImpl, TypeSpacePatch, TypeSpaceSettings};

fn read_root(path: &Path) -> RootSchema {
    let text = std::fs::read_to_string(path).unwrap();
    serde_json::from_str(&text).unwrap()
}

/// Settings used by upstream `typify/tests/schemas.rs`.
fn schemas_settings(settings: &mut TypeSpaceSettings) -> &mut TypeSpaceSettings {
    let schema = serde_json::from_value(serde_json::json!({ "enum": [1, "one"] })).unwrap();
    settings
        .with_replacement("HandGeneratedType", "String", [TypeSpaceImpl::Display].into_iter())
        .with_patch(
            "TypeThatNeedsMoreDerives",
            TypeSpacePatch::default()
                .with_rename("TypeThatHasMoreDerives")
                .with_derive("Eq")
                .with_derive("PartialEq"),
        )
        .with_conversion(schema, "serde_json::Value", [TypeSpaceImpl::Display].into_iter())
        .with_crate("std", CrateVers::Version("1.0.0".parse().unwrap()), None)
        .with_struct_builder(true)
}

fn run(out_dir: &Path, name: &str, settings: &TypeSpaceSettings, root: RootSchema) {
    let mut space = TypeSpace::new(settings);
    match space.add_root_schema(root) {
        Ok(_) => {
            let describe: Vec<String> = space
                .iter_types()
                .enumerate()
                .map(|(i, t)| format!("{}: {}", i + 1, t.describe()))
                .collect();
            std::fs::write(out_dir.join(format!("{name}.types")), describe.join("\n") + "\n")
                .unwrap();
            std::fs::write(
                out_dir.join(format!("{name}.tokens")),
                space.to_stream().to_string(),
            )
            .unwrap();
        }
        Err(e) => {
            std::fs::write(out_dir.join(format!("{name}.error")), format!("{e}\n")).unwrap();
        }
    }
}

fn main() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let out_dir = root.join("tests/oracle/typify");
    std::fs::create_dir_all(&out_dir).unwrap();

    let mut files: Vec<PathBuf> = std::fs::read_dir(root.join("tests/upstream/schemas"))
        .unwrap()
        .map(|e| e.unwrap().path())
        .filter(|p| p.extension().map_or(false, |e| e == "json"))
        .collect();
    files.sort();
    for f in &files {
        let stem = f.file_stem().unwrap().to_str().unwrap();
        let mut settings = TypeSpaceSettings::default();
        run(&out_dir, stem, schemas_settings(&mut settings), read_root(f));
    }
    // Variants tested by schemas.rs with extra settings.
    let maps = root.join("tests/upstream/schemas/maps.json");
    let mut settings = TypeSpaceSettings::default();
    settings.with_map_type("std::collections::BTreeMap");
    run(&out_dir, "maps_custom", schemas_settings(&mut settings), read_root(&maps));
    let enums = root.join("tests/upstream/schemas/various-enums.json");
    let mut settings = TypeSpaceSettings::default();
    settings.with_derive("schemars::JsonSchema".to_string());
    run(&out_dir, "various-enums-json-schema", schemas_settings(&mut settings), read_root(&enums));

    // typify-impl/tests/test_github.rs
    let mut schema = read_root(&root.join("tests/upstream/impl/github.json"));
    schema.schema.metadata().title = Some("Everything".to_string());
    run(&out_dir, "github", &TypeSpaceSettings::default(), schema);

    let mut settings = TypeSpaceSettings::default();
    let conv = serde_json::from_value(serde_json::json!({
        "enum": [null, "normal", "bold", "lighter", "bolder", "100", "200", "300", "400",
                 "500", "600", "700", "800", "900", 100, 200, 300, 400, 500, 600, 700, 800, 900]
    }))
    .unwrap();
    settings
        .with_conversion(conv, "MyEnum", [TypeSpaceImpl::FromStr].into_iter())
        .with_replacement("ColorValue", "ColorValue", [].into_iter());
    let mut schema = read_root(&root.join("tests/upstream/impl/vega.json"));
    schema.schema.metadata().title = Some("Everything".to_string());
    run(&out_dir, "vega", &settings, schema);
}
