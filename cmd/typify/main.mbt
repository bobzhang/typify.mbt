///|
fn main {
  // argv[0] is the program path.
  let args = @env.args()[1:]
  let command = @cli.parse_args(args) catch {
    e => {
      println("error: \{e}\n\nFor more information, try '--help'.")
      @sys.exit(1)
      return
    }
  }
  match command {
    Help => print_str(@cli.help)
    Version => println("typify \{@cli.version}")
    Run(args) => {
      let text = @fs.read_file_to_string(args.input) catch {
        e => {
          println("Error: Failed to open input file: \{args.input}: \{Repr(e)}")
          @sys.exit(1)
          return
        }
      }
      let code = @cli.convert(args, text) catch {
        e => {
          println("Error: \{e}")
          @sys.exit(1)
          return
        }
      }
      match args.output_path() {
        Some(path) =>
          @fs.write_string_to_file(path, code) catch {
            e => {
              println(
                "Error: Failed to write output to file: \{path}: \{Repr(e)}",
              )
              @sys.exit(1)
              return
            }
          }
        None => print_str(code)
      }
    }
  }
}

///|
/// Print without adding a newline.
fn print_str(s : String) -> Unit {
  let s = if s.has_suffix("\n") {
    s.unsafe_substring(start=0, end=s.length() - 1)
  } else {
    s
  }
  println(s)
}
