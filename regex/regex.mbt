///|
/// A regular expression syntax error; the text matches regress's messages.
pub(all) suberror RegexError {
  RegexError(String)
} derive(Debug, Eq)

///|
pub impl Show for RegexError with fn output(self, logger) {
  let RegexError(text) = self
  logger.write_string(text)
}

///|
/// A compiled ECMAScript regular expression with the semantics of the Rust
/// `regress` crate (0.12) under default flags, which is what typify and its
/// generated code use for JSON Schema `pattern`.
pub struct Regex {
  priv pattern : String
  priv node : Node
  priv group_count : Int
}

///|
/// A match: `start` and `end` are UTF-16 offsets into the searched string.
pub(all) struct Match {
  start : Int
  end : Int
} derive(Debug, Eq)

///|
/// Compile `pattern` (`regress::Regex::new`).
pub fn Regex::new(pattern : StringView) -> Regex raise RegexError {
  let input = []
  for c in pattern {
    input.push(c.to_int())
  }
  let p = Parser::{
    input,
    pos: 0,
    flags: { icase: false, multiline: false, dot_all: false, },
    loop_count: 0,
    group_count: 0,
    group_count_max: 0,
    named_group_indices: Map([]),
    depth: 0,
  }
  let node = p.try_parse()
  { pattern: pattern.to_owned(), node, group_count: p.group_count, }
}

///|
pub fn Regex::as_str(self : Regex) -> String {
  self.pattern
}

///|
/// Find the leftmost match in `text` (`regress::Regex::find`).
pub fn Regex::find(self : Regex, text : StringView) -> Match? {
  let chars = []
  let offsets = [] // UTF-16 offset of each code point, plus the end.
  let mut off = 0
  for c in text {
    chars.push(c.to_int())
    offsets.push(off)
    off += c.utf16_len()
  }
  offsets.push(off)
  let m = Matcher::new(chars, self.group_count)
  for start in 0..<=chars.length() {
    match m.run(self.node, start) {
      Some(end) => return Some({ start: offsets[start], end: offsets[end], })
      None => ()
    }
  }
  None
}

///|
/// Whether `text` contains a match.
pub fn Regex::is_match(self : Regex, text : StringView) -> Bool {
  self.find(text) is Some(_)
}
