// A backtracking matcher implementing ECMAScript (ES2018+) pattern semantics
// over code points, as regress does for `&str` input.

///|
priv struct Matcher {
  input : Array[Int]
  /// Capture start/end per 0-based group; -1 when unset.
  caps : Array[Int]
}

///|
fn Matcher::new(input : Array[Int], group_count : Int) -> Matcher {
  { input, caps: Array::make(group_count * 2, -1), }
}

///|
fn Matcher::snapshot(self : Matcher, from : Int, to : Int) -> Array[Int] {
  self.caps[from * 2:to * 2].to_owned()
}

///|
fn Matcher::restore(self : Matcher, from : Int, saved : Array[Int]) -> Unit {
  for i, v in saved {
    self.caps[from * 2 + i] = v
  }
}

///|
/// Run a full match of `node` starting at `start`; returns the end position.
fn Matcher::run(self : Matcher, node : Node, start : Int) -> Int? {
  for i in 0..<self.caps.length() {
    self.caps[i] = -1
  }
  let mut result = None
  let ok = self.m(node, start, true, end => {
    result = Some(end)
    true
  })
  if ok {
    result
  } else {
    None
  }
}

///|
fn single_matches(node : Node, c : Int) -> Bool {
  match node {
    Char(x, icase~) => chars_equal(c, x, icase)
    Bracket(set, invert~, icase~) => {
      let hit = if icase {
        bracket_contains_icase(set, c)
      } else {
        set.contains(c)
      }
      hit != invert
    }
    AnyChar(dot_all~) => dot_all || !is_line_terminator(c)
    _ => abort("not a single-character node")
  }
}

///|
/// Match `node` at `pos` in direction `fwd`, then call the continuation `k`.
fn Matcher::m(
  self : Matcher,
  node : Node,
  pos : Int,
  fwd : Bool,
  k : (Int) -> Bool,
) -> Bool {
  let n = self.input.length()
  match node {
    Empty => k(pos)
    Char(_, ..) | Bracket(_, ..) | AnyChar(..) =>
      if fwd {
        pos < n && single_matches(node, self.input[pos]) && k(pos + 1)
      } else {
        pos > 0 && single_matches(node, self.input[pos - 1]) && k(pos - 1)
      }
    StartAnchor(multiline~) =>
      (pos == 0 || (multiline && is_line_terminator(self.input[pos - 1]))) &&
      k(pos)
    EndAnchor(multiline~) =>
      (pos == n || (multiline && is_line_terminator(self.input[pos]))) && k(pos)
    WordBoundary(invert~) => {
      let a = pos > 0 && is_word_char(self.input[pos - 1])
      let b = pos < n && is_word_char(self.input[pos])
      (a != b) != invert && k(pos)
    }
    Cat(nodes) =>
      self.cat(nodes, if fwd { 0 } else { nodes.length() - 1 }, pos, fwd, k)
    Alt(nodes) => nodes.iter().any(alt => self.m(alt, pos, fwd, k))
    Group(id, body) => {
      let old_start = self.caps[id * 2]
      let old_end = self.caps[id * 2 + 1]
      let ok = self.m(body, pos, fwd, end => {
        let s = self.caps[id * 2]
        let e = self.caps[id * 2 + 1]
        if fwd {
          self.caps[id * 2] = pos
          self.caps[id * 2 + 1] = end
        } else {
          self.caps[id * 2] = end
          self.caps[id * 2 + 1] = pos
        }
        if k(end) {
          true
        } else {
          self.caps[id * 2] = s
          self.caps[id * 2 + 1] = e
          false
        }
      })
      if !ok {
        self.caps[id * 2] = old_start
        self.caps[id * 2 + 1] = old_end
      }
      ok
    }
    BackRef(group, icase~) => {
      let s = self.caps.get((group - 1) * 2).unwrap_or(-1)
      let e = self.caps.get((group - 1) * 2 + 1).unwrap_or(-1)
      if s < 0 || e < 0 {
        return k(pos)
      }
      let len = e - s
      if fwd {
        if pos + len > n {
          return false
        }
        for i in 0..<len {
          if !chars_equal(self.input[pos + i], self.input[s + i], icase) {
            return false
          }
        }
        k(pos + len)
      } else {
        if pos - len < 0 {
          return false
        }
        for i in 0..<len {
          if !chars_equal(self.input[pos - len + i], self.input[s + i], icase) {
            return false
          }
        }
        k(pos - len)
      }
    }
    Look(body, negate~, backwards~) => {
      let saved = self.caps.copy()
      let found = self.m(body, pos, !backwards, _ => true)
      if negate {
        self.restore(0, saved)
        !found && k(pos)
      } else if !found {
        self.restore(0, saved)
        false
      } else if k(pos) {
        true
      } else {
        self.restore(0, saved)
        false
      }
    }
    Loop(body, min~, max~, greedy~, first_group~, end_group~) =>
      if body.is_single_char() && first_group == end_group {
        self.loop_single(body, min, max, greedy, pos, fwd, k)
      } else {
        self.repeat(body, min, max, greedy, first_group, end_group, pos, fwd, k)
      }
  }
}

///|
fn Matcher::cat(
  self : Matcher,
  nodes : Array[Node],
  i : Int,
  pos : Int,
  fwd : Bool,
  k : (Int) -> Bool,
) -> Bool {
  if i < 0 || i >= nodes.length() {
    return k(pos)
  }
  self.m(nodes[i], pos, fwd, p => {
    self.cat(nodes, if fwd { i + 1 } else { i - 1 }, p, fwd, k)
  })
}

///|
/// ES RepeatMatcher.
fn Matcher::repeat(
  self : Matcher,
  body : Node,
  min : Int,
  max : Int?,
  greedy : Bool,
  first_group : Int,
  end_group : Int,
  pos : Int,
  fwd : Bool,
  k : (Int) -> Bool,
) -> Bool {
  if max is Some(0) {
    return k(pos)
  }
  let try_body = () => {
    // Captures inside the quantified atom are reset on every iteration.
    let saved = self.snapshot(first_group, end_group)
    for i in (first_group * 2)..<(end_group * 2) {
      self.caps[i] = -1
    }
    let ok = self.m(body, pos, fwd, y => {
      // An iteration may not match the empty string once `min` is satisfied.
      if min == 0 && y == pos {
        return false
      }
      self.repeat(
        body,
        if min == 0 {
          0
        } else {
          min - 1
        },
        max.map(m => m - 1),
        greedy,
        first_group,
        end_group,
        y,
        fwd,
        k,
      )
    })
    if !ok {
      self.restore(first_group, saved)
    }
    ok
  }
  if min != 0 {
    try_body()
  } else if !greedy {
    k(pos) || try_body()
  } else {
    try_body() || k(pos)
  }
}

///|
/// A loop whose body matches exactly one character and has no captures:
/// iterate without recursion per character.
fn Matcher::loop_single(
  self : Matcher,
  body : Node,
  min : Int,
  max : Int?,
  greedy : Bool,
  pos : Int,
  fwd : Bool,
  k : (Int) -> Bool,
) -> Bool {
  let n = self.input.length()
  let limit = match max {
    Some(m) => m
    None => 2147483647
  }
  // Count how many characters the body can consume in a row.
  let mut count = 0
  while count < limit {
    let p = if fwd { pos + count } else { pos - count - 1 }
    if p < 0 || p >= n || !single_matches(body, self.input[p]) {
      break
    }
    count += 1
  }
  if count < min {
    return false
  }
  let at = (i : Int) => if fwd { pos + i } else { pos - i }
  if greedy {
    for i = count; i >= min; i = i - 1 {
      if k(at(i)) {
        return true
      }
    }
    false
  } else {
    for i in min..<=count {
      if k(at(i)) {
        return true
      }
    }
    false
  }
}
