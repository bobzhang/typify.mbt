///|
/// Which character class escape (`\d`, `\s`, `\w`).
priv enum ClassType {
  Digits
  Spaces
  Words
}

///|
fn ClassType::codepoints(self : ClassType, positive : Bool) -> CharSet {
  let cps = match self {
    Digits => digits()
    Spaces => spaces()
    Words => word_chars()
  }
  if positive {
    cps
  } else {
    cps.inverted()
  }
}

///|
/// Regex IR, mirroring regress's `ir::Node` for the non-Unicode dialect.
priv enum Node {
  Empty
  /// A literal code point; `icase` compares case-insensitively.
  Char(Int, icase~ : Bool)
  /// A bracket expression or class escape.
  Bracket(CharSet, invert~ : Bool, icase~ : Bool)
  /// `.`; `dot_all` also matches line terminators.
  AnyChar(dot_all~ : Bool)
  StartAnchor(multiline~ : Bool)
  EndAnchor(multiline~ : Bool)
  WordBoundary(invert~ : Bool)
  Cat(Array[Node])
  /// Ordered alternation.
  Alt(Array[Node])
  /// Capture group with 0-based index.
  Group(Int, Node)
  /// Backreference to a 1-based group number.
  BackRef(Int, icase~ : Bool)
  Look(Node, negate~ : Bool, backwards~ : Bool)
  Loop(
    Node,
    min~ : Int,
    max~ : Int?,
    greedy~ : Bool,
    first_group~ : Int,
    end_group~ : Int
  )
}

///|
fn make_cat(nodes : Array[Node]) -> Node {
  match nodes.length() {
    0 => Empty
    1 => nodes[0]
    _ => Cat(nodes)
  }
}

///|
fn make_alt(nodes : Array[Node]) -> Node {
  match nodes.length() {
    0 => Empty
    1 => nodes[0]
    _ => Alt(nodes)
  }
}

///|
/// Whether the node matches exactly one character (enables the iterative
/// single-character loop, like regress's `Loop1CharBody`).
fn Node::is_single_char(self : Node) -> Bool {
  self is (Char(_, ..) | Bracket(_, ..) | AnyChar(..))
}
