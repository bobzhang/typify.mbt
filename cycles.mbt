// Containment-cycle breaking (upstream cycles.rs): a child type that is on the
// active DFS path is replaced by a `Box` of itself.

///|
priv enum CycleNode {
  Start(TypeId)
  Processing(TypeId, Array[TypeId])
}

///|
/// Child ids through which a containment cycle may pass, in order.
fn child_ids(entry : TypeEntry) -> Array[TypeId] {
  match entry.details {
    Enum({ variants, .. }) => {
      let out = []
      for v in variants {
        match v.details {
          Simple => ()
          Item(id) => out.push(id)
          Tuple(ids) => out.append(ids)
          Struct(props) =>
            for p in props {
              out.push(p.type_id)
            }
        }
      }
      out
    }
    Struct({ properties, .. }) => properties.map(p => p.type_id)
    Newtype({ type_id, .. }) => [type_id]
    Option(id) => [id]
    Array(id, _) => [id]
    Tuple(ids) => ids.copy()
    _ => []
  }
}

///|
/// Replace child ids per `replace` (the in-place mutation upstream performs).
fn replace_child_ids(
  entry : TypeEntry,
  replace : Map[TypeId, TypeId],
) -> TypeEntry {
  let r = (id : TypeId) => replace.get(id).unwrap_or(id)
  let props = (ps : Array[StructProperty]) => {
    ps.map(p => StructProperty::{ ..p, type_id: r(p.type_id), })
  }
  let details : TypeEntryDetails = match entry.details {
    Enum(e) =>
      Enum({
        ..e,
        variants: e.variants.map(v => {
          let details : VariantDetails = match v.details {
            Simple => Simple
            Item(id) => Item(r(id))
            Tuple(ids) => Tuple(ids.map(r))
            Struct(ps) => Struct(props(ps))
          }
          Variant::{ ..v, details, }
        }),
      })
    Struct(s) => Struct({ ..s, properties: props(s.properties), })
    Newtype(n) => Newtype({ ..n, type_id: r(n.type_id), })
    Option(id) => Option(r(id))
    Array(id, n) => Array(r(id), n)
    Tuple(ids) => Tuple(ids.map(r))
    other => other
  }
  { ..entry, details, }
}

///|
fn TypeSpace::break_cycles(
  self : TypeSpace,
  start : Int,
  end : Int,
) -> Unit raise TypifyError {
  let visited : Map[TypeId, Unit] = Map([])
  for id in start..<end {
    let type_id = TypeId(id)
    if visited.contains(type_id) {
      continue
    }
    let active : Map[TypeId, Unit] = Map::from_array([(type_id, ())])
    let stack : Array[CycleNode] = [Start(type_id)]
    while stack.last() is Some(top) {
      match top {
        Start(type_id) if visited.contains(type_id) =>
          stack[stack.length() - 1] = Processing(type_id, [])
        Start(type_id) => {
          visited[type_id] = ()
          let entry = self.entry_unchecked(type_id)
          let snip = []
          let descend = []
          for child in child_ids(entry) {
            if active.contains(child) {
              snip.push(child)
            } else {
              descend.push(child)
            }
          }
          let replace : Map[TypeId, TypeId] = Map([])
          for child in snip {
            replace[child] = self.id_to_box(child)
          }
          // Re-read: boxing may not change this entry, but mirror upstream.
          let entry = self.entry_unchecked(type_id)
          self.id_to_entry.set(type_id, replace_child_ids(entry, replace))
          stack[stack.length() - 1] = Processing(type_id, descend)
        }
        Processing(type_id, children) =>
          match children.pop() {
            Some(child) => {
              active[child] = ()
              stack.push(Start(child))
            }
            None => {
              active.remove(type_id)
              ignore(stack.pop())
            }
          }
      }
    }
  }
}
