// A minimal model of `proc_macro2` token streams. `to_string` reproduces the
// fallback implementation's `Display` exactly, which is what upstream typify's
// output is before rustfmt (and what survives rustfmt inside attributes).

///|
pub(all) enum Delim {
  Paren
  Brace
  Bracket
  NoDelim
} derive(Eq, Debug)

///|
pub(all) enum Token {
  Ident(String)
  /// A punctuation character; `joint` means it is glued to the next token.
  Punct(Char, joint~ : Bool)
  /// A literal with its source representation.
  Literal(String)
  Group(Delim, Tokens)
} derive(Eq, Debug)

///|
/// A token stream.
pub struct Tokens {
  priv toks : Array[Token]
} derive(Eq, Debug)

///|
pub fn Tokens::new() -> Tokens {
  { toks: [], }
}

///|
pub fn Tokens::from_array(toks : Array[Token]) -> Tokens {
  { toks, }
}

///|
pub fn Tokens::is_empty(self : Tokens) -> Bool {
  self.toks.is_empty()
}

///|
pub fn Tokens::push(self : Tokens, t : Token) -> Unit {
  self.toks.push(t)
}

///|
/// Append another stream (quote's `#stream` interpolation).
pub fn Tokens::append(self : Tokens, other : Tokens) -> Unit {
  self.toks.append(other.toks)
}

///|
pub fn Tokens::tokens(self : Tokens) -> Array[Token] {
  self.toks
}

///|
/// Concatenate streams.
pub fn concat(streams : Array[Tokens]) -> Tokens {
  let out = Tokens::new()
  for s in streams {
    out.append(s)
  }
  out
}

///|
/// Join streams with a separator punctuation (quote's `#(#xs),*`).
pub fn join(streams : Array[Tokens], sep : Char) -> Tokens {
  let out = Tokens::new()
  for i, s in streams {
    if i > 0 {
      out.push(Punct(sep, joint=false))
    }
    out.append(s)
  }
  out
}

///|
/// Streams each followed by a separator (quote's `#(#xs,)*`).
pub fn terminated(streams : Array[Tokens], sep : Char) -> Tokens {
  let out = Tokens::new()
  for s in streams {
    out.append(s)
    out.push(Punct(sep, joint=false))
  }
  out
}

///|
fn write_tokens(buf : StringBuilder, toks : Array[Token]) -> Unit {
  let mut joint = false
  for i, tt in toks {
    if i != 0 && !joint {
      buf.write_char(' ')
    }
    joint = false
    match tt {
      Group(delim, stream) => {
        let (open, close) = match delim {
          Paren => ("(", ")")
          Brace => ("{ ", "}")
          Bracket => ("[", "]")
          NoDelim => ("", "")
        }
        buf.write_string(open)
        write_tokens(buf, stream.toks)
        if delim == Brace && !stream.toks.is_empty() {
          buf.write_char(' ')
        }
        buf.write_string(close)
      }
      Ident(s) => buf.write_string(s)
      Punct(c, joint=j) => {
        joint = j
        buf.write_char(c)
      }
      Literal(s) => buf.write_string(s)
    }
  }
}

///|
/// `proc_macro2::TokenStream`'s `Display`.
pub fn Tokens::to_string(self : Tokens) -> String {
  let buf = StringBuilder()
  write_tokens(buf, self.toks)
  buf.to_string()
}

///|
pub impl Show for Tokens with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// An identifier (`format_ident!("{}", s)`).
pub fn ident(s : String) -> Tokens {
  { toks: [Ident(s)], }
}

///|
/// A string literal as `proc_macro2::Literal::string` renders it.
pub fn lit_str(s : String) -> Tokens {
  let buf = StringBuilder()
  buf.write_char('"')
  let chars = s.to_array()
  for i, c in chars {
    match c {
      '\u{0}' =>
        // Avoid an octal-looking escape before a digit.
        buf.write_string(
          if i + 1 < chars.length() &&
            chars[i + 1] >= '0' &&
            chars[i + 1] <= '7' {
            "\\x00"
          } else {
            "\\0"
          },
        )
      '\'' => buf.write_char('\'')
      '\t' => buf.write_string("\\t")
      '\r' => buf.write_string("\\r")
      '\n' => buf.write_string("\\n")
      '\\' => buf.write_string("\\\\")
      '"' => buf.write_string("\\\"")
      c if @unicode.needs_unicode_escape(c) => {
        buf.write_string("\\u{")
        buf.write_string(c.to_int().to_string(radix=16))
        buf.write_char('}')
      }
      c => buf.write_char(c)
    }
  }
  buf.write_char('"')
  { toks: [Literal(buf.to_string())], }
}

///|
/// An unsuffixed integer literal (e.g. `syn::Index`).
pub fn lit_int(n : Int) -> Tokens {
  { toks: [Literal(n.to_string())], }
}

///|
/// A `usize`-suffixed integer literal (`quote! { #n }` for `usize`).
pub fn lit_usize(n : Int) -> Tokens {
  { toks: [Literal("\{n}usize")], }
}

///|
/// A literal with a verbatim representation (`Literal::from_str`).
pub fn lit_raw(repr : String) -> Tokens {
  { toks: [Literal(repr)], }
}

///|
/// `true` / `false` (`quote! { #b }` for `bool`).
pub fn lit_bool(b : Bool) -> Tokens {
  ident(if b { "true" } else { "false" })
}
