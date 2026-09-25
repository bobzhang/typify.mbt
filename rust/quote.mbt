// `quote!`-style templates. A template is Rust source text lexed the way rustc
// hands tokens to `quote!`: multi-character operators are joint punctuation,
// lifetimes are a joint `'` followed by an identifier, and `#name` is an
// interpolation hole. Lexed templates are cached.

///|
priv enum Tpl {
  Tok(Token)
  Hole(String)
  TplGroup(Delim, Array[Tpl])
}

///|
let template_cache : Map[String, Array[Tpl]] = Map([])

///|
/// Operators rustc lexes as single tokens, longest first.
let operators : Array[String] = [
  "...", "..=", "<<=", ">>=", "::", "->", "=>", "==", "!=", "<=", ">=", "&&", "||",
  "..", "+=", "-=", "*=", "/=", "%=", "^=", "&=", "|=", "<<", ">>",
]

///|
fn is_ident_start(c : Char) -> Bool {
  c.is_ascii_alphabetic() ||
  c == '_' ||
  (c.to_int() > 0x7F && @unicode.is_xid_start(c))
}

///|
fn is_ident_continue(c : Char) -> Bool {
  c.is_ascii_alphabetic() ||
  c.is_ascii_digit() ||
  c == '_' ||
  (c.to_int() > 0x7F && @unicode.is_xid_continue(c))
}

///|
priv struct TplLexer {
  chars : Array[Char]
  mut pos : Int
}

///|
fn TplLexer::peek(self : TplLexer, k : Int) -> Char? {
  self.chars.get(self.pos + k)
}

///|
fn TplLexer::ident(self : TplLexer) -> String {
  let start = self.pos
  while self.peek(0) is Some(c) && is_ident_continue(c) {
    self.pos += 1
  }
  String::from_array(self.chars[start:self.pos])
}

///|
/// Lex until the closing delimiter `close` (or the end).
fn TplLexer::lex(self : TplLexer, close : Char?) -> Array[Tpl] {
  let out = []
  for ;; {
    guard self.peek(0) is Some(c) else { break }
    if Some(c) == close {
      self.pos += 1
      break
    }
    if c is (' ' | '\n' | '\t' | '\r') {
      self.pos += 1
      continue
    }
    // Line comments are dropped.
    if c == '/' && self.peek(1) == Some('/') {
      while self.peek(0) is Some(d) && d != '\n' {
        self.pos += 1
      }
      continue
    }
    match c {
      '(' => {
        self.pos += 1
        out.push(TplGroup(Paren, self.lex(Some(')'))))
      }
      '[' => {
        self.pos += 1
        out.push(TplGroup(Bracket, self.lex(Some(']'))))
      }
      '{' => {
        self.pos += 1
        out.push(TplGroup(Brace, self.lex(Some('}'))))
      }
      '#' if self.peek(1) is Some(d) && is_ident_start(d) => {
        self.pos += 1
        out.push(Hole(self.ident()))
      }
      '"' => {
        let start = self.pos
        self.pos += 1
        while self.peek(0) is Some(d) && d != '"' {
          if d == '\\' {
            self.pos += 1
          }
          self.pos += 1
        }
        self.pos += 1
        out.push(Tok(Literal(String::from_array(self.chars[start:self.pos]))))
      }
      '\'' => {
        // Lifetimes only (templates contain no char literals).
        self.pos += 1
        out.push(Tok(Punct('\'', joint=true)))
        out.push(Tok(Ident(self.ident())))
      }
      c if c.is_ascii_digit() => {
        let start = self.pos
        while self.peek(0) is Some(d) && (is_ident_continue(d) || d == '.') {
          // Stop before `..` (ranges) and method calls on literals.
          if d == '.' && !(self.peek(1) is Some(e) && e.is_ascii_digit()) {
            break
          }
          self.pos += 1
        }
        out.push(Tok(Literal(String::from_array(self.chars[start:self.pos]))))
      }
      // Raw strings: r"..." and r#"..."#.
      'r' if self.peek(1) == Some('"') ||
        (self.peek(1) == Some('#') && self.peek(2) == Some('"')) => {
        let start = self.pos
        self.pos += 1
        let mut hashes = 0
        while self.peek(0) == Some('#') {
          hashes += 1
          self.pos += 1
        }
        self.pos += 1
        for ;; {
          guard self.peek(0) is Some(d) else { break }
          self.pos += 1
          if d == '"' {
            let mut n = 0
            while n < hashes && self.peek(0) == Some('#') {
              n += 1
              self.pos += 1
            }
            if n == hashes {
              break
            }
          }
        }
        out.push(Tok(Literal(String::from_array(self.chars[start:self.pos]))))
      }
      'r' if self.peek(1) == Some('#') &&
        self.peek(2) is Some(d) &&
        is_ident_start(d) => {
        self.pos += 2
        out.push(Tok(Ident("r#" + self.ident())))
      }
      c if is_ident_start(c) => out.push(Tok(Ident(self.ident())))
      _ => {
        let op = operators.search_by(op => {
          let n = op.length()
          self.pos + n <= self.chars.length() &&
          String::from_array(self.chars[self.pos:self.pos + n]) == op
        })
        match op {
          Some(i) => {
            let op = operators[i].to_array()
            for j, oc in op {
              out.push(Tok(Punct(oc, joint=j + 1 < op.length())))
            }
            self.pos += op.length()
          }
          None => {
            out.push(Tok(Punct(c, joint=false)))
            self.pos += 1
          }
        }
      }
    }
  }
  out
}

///|
fn lex_template(template : String) -> Array[Tpl] {
  match template_cache.get(template) {
    Some(t) => t
    None => {
      let t = TplLexer::{ chars: template.to_array(), pos: 0, }.lex(None)
      template_cache[template] = t
      t
    }
  }
}

///|
fn instantiate(
  tpl : Array[Tpl],
  args : Map[String, Tokens],
  out : Tokens,
) -> Unit {
  for t in tpl {
    match t {
      Tok(tok) => out.push(tok)
      Hole(name) =>
        match args.get(name) {
          Some(s) => out.append(s)
          None => abort("quote: missing argument #\{name}")
        }
      TplGroup(delim, inner) => {
        let g = Tokens::new()
        instantiate(inner, args, g)
        out.push(Group(delim, g))
      }
    }
  }
}

///|
/// Build tokens from a template with `#name` holes.
pub fn quote(
  template : String,
  args? : Map[String, Tokens] = Map([]),
) -> Tokens {
  let out = Tokens::new()
  instantiate(lex_template(template), args, out)
  out
}

///|
/// Tokens for a Rust path or type as `syn` prints it (e.g. a derive name or
/// a native type path): operator-based spacing like `quote!`.
pub fn path_tokens(path : String) -> Tokens {
  let out = Tokens::new()
  instantiate(
    TplLexer::{ chars: path.to_array(), pos: 0, }
    .lex(None)
    .map(t => {
      match t {
        // A `#` in a type path is not an interpolation.
        Hole(name) =>
          TplGroup(NoDelim, [Tok(Punct('#', joint=false)), Tok(Ident(name))])
        other => other
      }
    }),
    Map([]),
    out,
  )
  out
}

///|
/// Parse text the way `proc_macro2`'s fallback lexer does
/// (`str::parse::<TokenStream>()`): punctuation is joint when directly
/// followed by another punctuation character.
pub fn parse_tokens(src : String) -> Tokens {
  let chars = src.to_array()
  let pos : Ref[Int] = { val: 0, }
  fn punct_char(c : Char) -> Bool {
    "~!@#$%^&*-=+|;:,<.>/?'".contains_char(c)
  }
  fn go(chars : Array[Char], pos : Ref[Int], close : Char?) -> Tokens {
    let out = Tokens::new()
    for ;; {
      guard chars.get(pos.val) is Some(c) else { break }
      if Some(c) == close {
        pos.val += 1
        break
      }
      if c is (' ' | '\n' | '\t' | '\r') {
        pos.val += 1
        continue
      }
      match c {
        '(' => {
          pos.val += 1
          out.push(Group(Paren, go(chars, pos, Some(')'))))
        }
        '[' => {
          pos.val += 1
          out.push(Group(Bracket, go(chars, pos, Some(']'))))
        }
        '{' => {
          pos.val += 1
          out.push(Group(Brace, go(chars, pos, Some('}'))))
        }
        '"' => {
          let start = pos.val
          pos.val += 1
          while chars.get(pos.val) is Some(d) && d != '"' {
            if d == '\\' {
              pos.val += 1
            }
            pos.val += 1
          }
          pos.val += 1
          out.push(Literal(String::from_array(chars[start:pos.val])))
        }
        '\'' if chars.get(pos.val + 1) is Some(d) && is_ident_start(d) => {
          pos.val += 1
          out.push(Punct('\'', joint=true))
          let start = pos.val
          while chars.get(pos.val) is Some(d) && is_ident_continue(d) {
            pos.val += 1
          }
          out.push(Ident(String::from_array(chars[start:pos.val])))
        }
        c if c.is_ascii_digit() => {
          let start = pos.val
          while chars.get(pos.val) is Some(d) &&
                (is_ident_continue(d) || d == '.') {
            pos.val += 1
          }
          out.push(Literal(String::from_array(chars[start:pos.val])))
        }
        c if is_ident_start(c) => {
          let start = pos.val
          while chars.get(pos.val) is Some(d) && is_ident_continue(d) {
            pos.val += 1
          }
          out.push(Ident(String::from_array(chars[start:pos.val])))
        }
        c => {
          pos.val += 1
          let joint = chars.get(pos.val) is Some(d) && punct_char(d)
          out.push(Punct(c, joint~))
        }
      }
    }
    out
  }
  go(chars, pos, None)
}
