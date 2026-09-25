///|
fn find(pattern : String, text : String) -> String {
  let re = @regex.Regex::new(pattern) catch { e => return "ERR: \{e}" }
  match re.find(text) {
    Some(m) => "\{m.start}..\{m.end}"
    None => "NONE"
  }
}

///|
test "typical JSON Schema patterns" {
  inspect(find("^[a-zA-Z0-9_]+$", "abc_123"), content="0..7")
  inspect(find("^[a-zA-Z0-9_]+$", "abc-123"), content="NONE")
  inspect(find("^[0-9]{3}-[0-9]{4}$", "555-1234"), content="0..8")
  // Unanchored search, like regress's `find`.
  inspect(find("[0-9]+", "abc 42 def"), content="4..6")
}

///|
test "lookahead conjunctions from merged patterns" {
  // Both assertions must hold at the same position.
  inspect(find("(?=a)(?=b)", "ab"), content="NONE")
  inspect(find("^(?=.*a)(?=.*b)", "xbxa"), content="0..0")
  inspect(find("^(?!.*\\.\\.)[a-z.]+$", "a..b"), content="NONE")
  inspect(find("^(?!.*\\.\\.)[a-z.]+$", "a.b"), content="0..3")
}

///|
test "lookbehind, backreferences and named groups" {
  inspect(find("(?<=a)b", "cbab"), content="3..4")
  inspect(find("(?<!a)b", "abcb"), content="3..4")
  inspect(find("(a|b)\\1", "abba"), content="1..3")
  inspect(find("(?<q>['\"]).*\\k<q>", "say \"hi\" now"), content="4..8")
}

///|
test "empty-loop and capture-reset semantics" {
  inspect(find("(a*)*b", "aaab"), content="0..4")
  inspect(find("^(?:(a)|b)*$", "ab"), content="0..2")
  inspect(find("(z)((a+)?(b+)?(c))*", "zaacbbbcac"), content="0..10")
}

///|
test "code points, not UTF-16 units" {
  inspect(find("^.$", "😀"), content="0..2")
  inspect(find("é+", "caféé"), content="3..5")
}

///|
test "syntax errors" {
  inspect(find("a**", ""), content="ERR: Invalid atom character")
  inspect(find("(a", ""), content="ERR: Unbalanced parenthesis")
  inspect(
    find("[z-a]", ""),
    content="ERR: Range values reversed, start char code is greater than end char code.",
  )
  inspect(find("a{3,1}", ""), content="ERR: Invalid quantifier")
  inspect(
    find("(?<a>x)(?<a>y)", ""),
    content="ERR: Duplicate capture group name",
  )
  // Annex B leniency.
  inspect(find("x{", "x{"), content="0..2")
  inspect(find("\\8", "8"), content="0..1")
}

///|
/// Escape every character so it is matched literally.
fn escape_literal(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    if c.is_ascii_alphabetic() || c.is_ascii_digit() {
      buf.write_char(c)
    } else {
      let hex = c.to_int().to_string(radix=16)
      buf.write_string("\\u{\{hex}}")
    }
  }
  buf.to_string()
}

///|
test "an escaped literal matches itself exactly" {
  @quickcheck.check((s : String) => {
    let re = @regex.Regex::new("^" + escape_literal(s) + "$") catch {
      _ => return false
    }
    re.find(s) == Some({ start: 0, end: s.length(), })
  })
}

///|
test "matches lie within the subject" {
  @quickcheck.check((s : String) => {
    let re = @regex.Regex::new("[a-m]+|\\d") catch { _ => return false }
    match re.find(s) {
      Some(m) => 0 <= m.start && m.start <= m.end && m.end <= s.length()
      None => true
    }
  })
}
