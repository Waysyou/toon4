///|
/// Reason why a JSON array or object could not use TOON tabular/keyed-tabular compression.
#derive(Eq, @debug.Debug)
pub(all) enum FallbackReason {
  NonUniformObjectKeys(String)
  NonPrimitiveColumn(String)
  SingleEntryKeyedObject
  MixedElementTypes
  EmptyCollection
}

///|
/// Path-level diagnostic explaining why a nested collection fell back from
/// compact tabular encoding.
#derive(Eq, @debug.Debug)
pub(all) struct FallbackFinding {
  path : String
  reason : FallbackReason
  item_count : Int32
  explanation : String
}

///|
/// Summary of tabular eligibility across a JSON payload.
#derive(Eq, @debug.Debug)
pub(all) struct StructuralAudit {
  tabular_items : Int32
  non_tabular_items : Int32
  array_tabular_blocks : Int32
  keyed_tabular_blocks : Int32
  tabular_coverage_pct : Double
  fallbacks : Array[FallbackFinding]
}

///|
priv struct AuditAcc {
  mut tabular_items : Int32
  mut non_tabular_items : Int32
  mut array_tabular_blocks : Int32
  mut keyed_tabular_blocks : Int32
  fallbacks : Array[FallbackFinding]
}

///|
fn child_path(parent : String, key : String) -> String {
  if parent == "$" {
    key
  } else {
    "\{parent}.\{key}"
  }
}

///|
fn diagnose_array_fallback(
  arr : Array[Json],
  path : String,
  acc : AuditAcc,
) -> Unit {
  if arr.is_empty() {
    acc.fallbacks.push({
      path,
      reason: EmptyCollection,
      item_count: 0,
      explanation: "empty array emits '[]' rather than tabular rows",
    })
    return
  }
  // Check if all primitive (inline primitive array is already compact, not a tabular failure)
  let mut all_prim = true
  let mut all_obj = true
  for item in arr {
    match item {
      Null | True | False | Number(_, ..) | String(_) => all_obj = false
      Object(m) => {
        all_prim = false
        if m.is_empty() {
          all_obj = false
        }
      }
      Array(_) => {
        all_prim = false
        all_obj = false
      }
    }
  }
  if all_prim {
    return
  }
  acc.non_tabular_items += arr.length()
  if !all_obj {
    acc.fallbacks.push({
      path,
      reason: MixedElementTypes,
      item_count: arr.length(),
      explanation: "contains non-object, empty-object, or nested-array elements; uses list form ('- ')",
    })
    for idx, item in arr {
      audit_node(item, "\{path}[\{idx}]", acc)
    }
    return
  }
  // All non-empty objects: pinpoint first mismatched key or non-uniform column
  guard arr[0] is Object(first_obj) else { return }
  for i in 1..<arr.length() {
    guard arr[i] is Object(cur_obj) else { continue }
    for k, _ in first_obj {
      if !cur_obj.contains(k) {
        acc.fallbacks.push({
          path,
          reason: NonUniformObjectKeys(k),
          item_count: arr.length(),
          explanation: "element [\{i}] is missing key '\{k}' present in [0]; falls back to list form",
        })
        for idx, item in arr {
          audit_node(item, "\{path}[\{idx}]", acc)
        }
        return
      }
    }
    for k, _ in cur_obj {
      if !first_obj.contains(k) {
        acc.fallbacks.push({
          path,
          reason: NonUniformObjectKeys(k),
          item_count: arr.length(),
          explanation: "element [\{i}] adds extra key '\{k}' absent in [0]; falls back to list form",
        })
        for idx, item in arr {
          audit_node(item, "\{path}[\{idx}]", acc)
        }
        return
      }
    }
  }
  // Key sets match; a column must contain arrays or inconsistent object/primitive mix
  for k, _ in first_obj {
    for i, item in arr {
      guard item is Object(cur_obj) else { continue }
      match cur_obj.get(k) {
        Some(Array(_)) => {
          acc.fallbacks.push({
            path,
            reason: NonPrimitiveColumn(k),
            item_count: arr.length(),
            explanation: "column '\{k}' (first seen at [\{i}]) holds an array, preventing tabular flattening",
          })
          for idx, elem in arr {
            audit_node(elem, "\{path}[\{idx}]", acc)
          }
          return
        }
        _ => ()
      }
    }
  }
  acc.fallbacks.push({
    path,
    reason: NonPrimitiveColumn("nested"),
    item_count: arr.length(),
    explanation: "a nested object column has non-uniform sub-keys across elements; falls back to list form",
  })
  for idx, elem in arr {
    audit_node(elem, "\{path}[\{idx}]", acc)
  }
}

///|
fn is_leaf_record_object(obj : Map[String, Json]) -> Bool {
  if obj.is_empty() {
    return false
  }
  for _, v in obj {
    match v {
      Array(_) | Object(_) => return false
      _ => ()
    }
  }
  true
}

///|
fn audit_node(value : Json, path : String, acc : AuditAcc) -> Unit {
  match value {
    Null | True | False | Number(_, ..) | String(_) => ()
    Array(arr) =>
      match @encode.extract_tabular_fields(arr) {
        Some(_) => {
          acc.tabular_items += arr.length()
          acc.array_tabular_blocks += 1
        }
        None => diagnose_array_fallback(arr, path, acc)
      }
    Object(obj) =>
      match @encode.extract_keyed_tabular_fields(obj) {
        Some(_) => {
          acc.tabular_items += obj.length()
          acc.keyed_tabular_blocks += 1
        }
        None => {
          if obj.length() == 1 {
            for _, v in obj {
              if v is Object(sub) && is_leaf_record_object(sub) {
                acc.non_tabular_items += 1
                acc.fallbacks.push({
                  path,
                  reason: SingleEntryKeyedObject,
                  item_count: 1,
                  explanation: "object has only 1 entry (< 2 minimum for TOON 4.4 keyed tabular '[N:]')",
                })
              }
            }
          }
          for k, v in obj {
            audit_node(v, child_path(path, k), acc)
          }
        }
      }
  }
}

///|
/// Audits a JSON document to measure tabular coverage and pinpoint exact paths
/// that fall back from TOON tabular or §9.5 keyed-tabular compression.
pub fn audit_structure(value : Json) -> StructuralAudit {
  let acc : AuditAcc = {
    tabular_items: 0,
    non_tabular_items: 0,
    array_tabular_blocks: 0,
    keyed_tabular_blocks: 0,
    fallbacks: [],
  }
  audit_node(value, "$", acc)
  let total = acc.tabular_items + acc.non_tabular_items
  let coverage = if total == 0 {
    0.0
  } else {
    acc.tabular_items.to_double() * 100.0 / total.to_double()
  }
  {
    tabular_items: acc.tabular_items,
    non_tabular_items: acc.non_tabular_items,
    array_tabular_blocks: acc.array_tabular_blocks,
    keyed_tabular_blocks: acc.keyed_tabular_blocks,
    tabular_coverage_pct: coverage,
    fallbacks: acc.fallbacks,
  }
}
