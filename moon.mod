name = "bobzhang/typify"

version = "0.1.0"

readme = "README.md"

repository = ""

license = "Apache-2.0"

keywords = [ "json-schema", "codegen", "rust", "moonbit" ]

description = "Generate Rust and MoonBit types from JSON Schema (port of oxidecomputer/typify)"

import {
  "moonbitlang/x@0.5.5",
}

preferred_target = "wasm"

warnings = "-implicit_impl_as_method"

options(
  exclude: [ "conformance", "scripts", "tests", "docs" ],
)
