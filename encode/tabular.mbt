///|
fn classify_column(
  name : String,
  rows : Array[Map[String, Json]],
) -> @types.FieldNode? {
  let mut all_prim = true
  let mut all_non_empty_obj = true
  for row in rows {
    match row.get(name) {
      Some(v) =>
        match v {
          Null | True | False | Number(_, ..) | String(_) =>
            all_non_empty_obj = false
          Object(sub) => {
            all_prim = false
            if sub.is_empty() {
              all_non_empty_obj = false
            }
          }
          Array(_) => {
            all_prim = false
            all_non_empty_obj = false
          }
        }
      None => return None
    }
    if !all_prim && !all_non_empty_obj {
      return None
    }
  }
  if all_prim {
    return Some(Leaf(name))
  }
  if all_non_empty_obj {
    let sub_items : Array[Json] = Array(capacity=rows.length())
    for row in rows {
      sub_items.push(row[name])
    }
    match extract_tabular_fields(sub_items) {
      Some(children) => Some(Group(name, children))
      None => None
    }
  } else {
    None
  }
}

///|
/// Classifies an array of JSON objects into a recursive tabular field tree per
/// TOON §9.3, or returns `None` when items are empty, non-object, empty-object,
/// have differing key sets, or have non-uniform columns.
pub fn extract_tabular_fields(items : Array[Json]) -> Array[@types.FieldNode]? {
  if items.is_empty() {
    return None
  }
  let rows : Array[Map[String, Json]] = Array(capacity=items.length())
  for item in items {
    match item {
      Object(obj) => if obj.is_empty() { return None } else { rows.push(obj) }
      _ => return None
    }
  }
  let first = rows[0]
  let first_len = first.length()
  for i in 1..<rows.length() {
    let row = rows[i]
    if row.length() != first_len {
      return None
    }
    for k, _ in first {
      if !row.contains(k) {
        return None
      }
    }
  }
  let fields : Array[@types.FieldNode] = Array(capacity=first_len)
  for k, _ in first {
    match classify_column(k, rows) {
      Some(node) => fields.push(node)
      None => return None
    }
  }
  Some(fields)
}

///|
/// Classifies an object's entry values as a keyed tabular field tree per TOON
/// §9.5 (requires `>= 2` entries whose values are all uniform non-empty objects).
pub fn extract_keyed_tabular_fields(
  obj : Map[String, Json],
) -> Array[@types.FieldNode]? {
  if obj.length() < 2 {
    return None
  }
  let values : Array[Json] = Array(capacity=obj.length())
  for _, v in obj {
    match v {
      Object(sub) => if sub.is_empty() { return None } else { values.push(v) }
      _ => return None
    }
  }
  extract_tabular_fields(values)
}

///|
/// Appends one row's leaf primitive values to `out` in depth-first pre-order
/// matching `fields` (§9.3, §9.5).
pub fn collect_row_leaves(
  obj : Map[String, Json],
  fields : Array[@types.FieldNode],
  out : Array[Json],
) -> Unit {
  for field in fields {
    match field {
      Leaf(name) =>
        match obj.get(name) {
          Some(v) => out.push(v)
          None => ()
        }
      Group(name, children) =>
        match obj.get(name) {
          Some(Object(sub)) => collect_row_leaves(sub, children, out)
          _ => ()
        }
    }
  }
}
