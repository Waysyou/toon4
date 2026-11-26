///|
/// Separator for TOON array values and tabular cells (TOON §11).
/// Comma is the default. Tab and pipe are declared in the array header.
#derive(Eq, @debug.Debug)
pub(all) enum Delimiter {
  Comma
  Tab
  Pipe
}

///|
/// Returns the wire character for this delimiter.
pub fn Delimiter::to_char(self : Delimiter) -> Char {
  match self {
    Comma => ','
    Tab => '\t'
    Pipe => '|'
  }
}

///|
/// Returns the delimiter represented by `ch`, or `None` for any character
/// other than comma, tab, or pipe.
pub fn Delimiter::from_char(ch : Char) -> Delimiter? {
  match ch {
    ',' => Some(Comma)
    '\t' => Some(Tab)
    '|' => Some(Pipe)
    _ => None
  }
}

///|
/// Returns the text that follows the declared count or keyed marker inside
/// the header brackets. The comma delimiter uses an empty suffix.
pub fn Delimiter::header_suffix(self : Delimiter) -> String {
  match self {
    Comma => ""
    Tab => "\t"
    Pipe => "|"
  }
}

///|
/// Returns the delimiter name `"comma"`, `"tab"`, or `"pipe"`.
pub fn Delimiter::label(self : Delimiter) -> String {
  match self {
    Comma => "comma"
    Tab => "tab"
    Pipe => "pipe"
  }
}

///|
/// A node in a TOON tabular header field list (TOON §6 and §9.3).
/// `Leaf` names a scalar column. `Group` names a nested object and lists its
/// child fields in column order.
#derive(Eq, @debug.Debug)
pub(all) enum FieldNode {
  Leaf(String)
  Group(String, Array[FieldNode])
}

///|
/// Returns the field name at this node.
pub fn FieldNode::name(self : FieldNode) -> String {
  match self {
    Leaf(name) => name
    Group(name, _) => name
  }
}

///|
/// Returns the number of scalar columns represented by this node.
pub fn FieldNode::count_leaves(self : FieldNode) -> Int32 {
  match self {
    Leaf(_) => 1
    Group(_, children) => count_leaf_fields(children)
  }
}

///|
/// Returns the total number of scalar columns represented by `fields`.
pub fn count_leaf_fields(fields : Array[FieldNode]) -> Int32 {
  let mut total = 0
  for field in fields {
    total += field.count_leaves()
  }
  total
}

///|
/// Appends this node's leaf column names to `out` in depth-first order.
pub fn FieldNode::collect_leaves(self : FieldNode, out : Array[String]) -> Unit {
  match self {
    Leaf(name) => out.push(name)
    Group(_, children) =>
      for child in children {
        child.collect_leaves(out)
      }
  }
}

///|
/// Returns the first duplicate name found among siblings in `fields` or a
/// nested group, or `None` if every group has unique names. Each brace level
/// has its own scope, so `{x,n{x}}` is valid.
pub fn find_duplicate_field(fields : Array[FieldNode]) -> String? {
  let seen : Map[String, Bool] = Map([])
  for field in fields {
    let name = field.name()
    if seen.contains(name) {
      return Some(name)
    }
    seen[name] = true
    match field {
      Leaf(_) => ()
      Group(_, children) =>
        match find_duplicate_field(children) {
          Some(dup) => return Some(dup)
          None => ()
        }
    }
  }
  None
}

///|
/// Parsed header metadata for an array or keyed table (TOON §6 and §9.5).
/// `key` and `fields` hold the optional name and column schema. `length` is
/// the declared item or entry count. `delimiter` selects the cell separator,
/// and `keyed` marks the `[N:]` form.
#derive(Eq, @debug.Debug)
pub(all) struct ArrayHeader {
  key : String?
  length : @bigint.BigInt
  delimiter : Delimiter
  fields : Array[FieldNode]?
  keyed : Bool
}

///|
/// One event in a streamed TOON document. Object and array events mark
/// container boundaries, `Key` names an object member, and `Primitive`
/// carries a scalar JSON value. `StartArray` carries the declared length
/// as a hint, capped at the maximum `Int32` value.
#derive(Eq, @debug.Debug)
pub(all) enum StreamEvent {
  StartObject
  EndObject
  StartArray(Int32)
  EndArray
  Key(String)
  Primitive(Json)
}

///|
/// TOON encoding options (TOON §13.1). `indent_size` is the number of spaces
/// per indentation level and `delimiter` selects the array and cell separator.
#derive(Eq, @debug.Debug)
pub(all) struct EncodeOptions {
  indent_size : Int32
  delimiter : Delimiter
}

///|
/// Returns encoding options with two spaces per level and a comma delimiter.
pub fn EncodeOptions::default() -> EncodeOptions {
  { indent_size: 2, delimiter: Comma, }
}

///|
/// Returns encoding options with `indent_size` spaces per level and the specified
/// `delimiter`. The defaults are two spaces and comma. Call `validate` to check
/// the spacing before use.
pub fn EncodeOptions::new(
  indent_size~ : Int32 = 2,
  delimiter~ : Delimiter = Comma,
) -> EncodeOptions {
  { indent_size, delimiter, }
}

///|
/// Checks that `indent_size` is at least one, raising `EncodeError` otherwise.
pub fn EncodeOptions::validate(self : EncodeOptions) -> Unit raise EncodeError {
  if self.indent_size < 1 {
    raise EncodeError(
      message="indent_size must be at least 1, got \{self.indent_size}",
      path=None,
    )
  }
}

///|
/// TOON decoding options (TOON §13.2). `indent_size` is the expected number
/// of spaces per level. Setting `strict` to `false` enables the recoveries
/// specified by TOON §14.4.
#derive(Eq, @debug.Debug)
pub(all) struct DecodeOptions {
  indent_size : Int32
  strict : Bool
}

///|
/// Returns decoding options with two spaces per level and strict validation.
pub fn DecodeOptions::default() -> DecodeOptions {
  { indent_size: 2, strict: true, }
}

///|
/// Returns decoding options with the given `indent_size` and `strict` mode.
/// The defaults are two spaces and strict validation. Call `validate` to
/// check the spacing before use.
pub fn DecodeOptions::new(
  indent_size~ : Int32 = 2,
  strict~ : Bool = true,
) -> DecodeOptions {
  { indent_size, strict, }
}

///|
/// Checks that `indent_size` is at least one. Otherwise raises a `DecodeError`
/// with kind `InvalidOption`.
pub fn DecodeOptions::validate(self : DecodeOptions) -> Unit raise DecodeError {
  if self.indent_size < 1 {
    raise DecodeError::new(
      kind=InvalidOption,
      message="indent_size must be at least 1, got \{self.indent_size}",
    )
  }
}
