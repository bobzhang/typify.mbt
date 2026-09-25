///|
let usage : String =
  #|Usage: typify [--lang rust|moonbit] [-o OUTPUT] INPUT.json

///|
fn main {
  // argv[0] is the program path.
  let args = @env.args()[1:]
  let mut lang = @gen.Lang::Rust
  let mut output : String? = None
  let mut input : String? = None
  let mut i = 0
  while i < args.length() {
    match args[i] {
      "--lang" | "-l" if i + 1 < args.length() => {
        lang = match args[i + 1] {
          "rust" | "rs" => Rust
          "moonbit" | "mbt" => MoonBit
          other => abort("unknown language: \{other}\n\{usage}")
        }
        i += 2
      }
      "--output" | "-o" if i + 1 < args.length() => {
        output = Some(args[i + 1])
        i += 2
      }
      "--help" | "-h" => {
        println(usage)
        return
      }
      arg => {
        input = Some(arg)
        i += 1
      }
    }
  }
  guard input is Some(path) else { abort(usage) }
  let code = try {
    let text = @fs.read_file_to_string(path)
    @gen.generate(@schema.RootSchema::from_json_str(text), lang~)
  } catch {
    e => abort("typify: \{Repr(e)}")
  }
  match output {
    Some(out) =>
      @fs.write_string_to_file(out, code) catch {
        e => abort("typify: \{Repr(e)}")
      }
    None => println(code.trim_end(chars="\n"))
  }
}
