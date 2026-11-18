///|
/// Delimiter character used in array headers, inline arrays, tabular rows, and
/// keyed tabular entry rows per TOON §11.
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
/// Parses a wire character into a `Delimiter`, returning `None` for any other char.
pub fn Delimiter::from_char(ch : Char) -> Delimiter? {
  match ch {
    ',' => Some(Comma)
    '\t' => Some(Tab)
    '|' => Some(Pipe)
    _ => None
  }
}

///|
/// Returns the bracket suffix emitted in TOON headers (empty for comma).
pub fn Delimiter::header_suffix(self : Delimiter) -> String {
  match self {
    Comma => ""
    Tab => "\t"
    Pipe => "|"
  }
}

///|
/// Returns a human-readable name for CLI and advisor reporting.
pub fn Delimiter::label(self : Delimiter) -> String {
  match self {
    Comma => "comma"
    Tab => "tab"
    Pipe => "pipe"
  }
}

///|
/// Recursive schema node inside `{...}` header field lists (TOON §6 & §9.3),
/// representing either a scalar leaf column or a nested uniform object group.
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
/// Counts the number of leaf columns expanded in depth-first pre-order.
pub fn FieldNode::count_leaves(self : FieldNode) -> Int32 {
  match self {
    Leaf(_) => 1
    Group(_, children) => count_leaf_fields(children)
  }
}

///|
/// Counts total leaf columns across a field-node slice.
pub fn count_leaf_fields(fields : Array[FieldNode]) -> Int32 {
  let mut total = 0
  for field in fields {
    total += field.count_leaves()
  }
  total
}

///|
/// Appends leaf column names in depth-first pre-order.
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
/// Detects duplicate field names within the same brace level, recursing into
/// nested groups independently (so `{x,n{x}}` is valid while `{a,a}` and
/// `{n{x,x}}` return the duplicated field name).
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
/// Parsed array or keyed-tabular header metadata (TOON §6 & §9.5).
#derive(Eq, @debug.Debug)
pub(all) struct ArrayHeader {
  key : String?
  length : @bigint.BigInt
  delimiter : Delimiter
  fields : Array[FieldNode]?
  keyed : Bool
}

///|
/// Streaming decode event emitted by the recursive-descent TOON decoder.
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
/// Options controlling TOON encoding (TOON §13.1).
#derive(Eq, @debug.Debug)
pub(all) struct EncodeOptions {
  indent_size : Int32
  delimiter : Delimiter
}

///|
/// Default encoding options: `indent_size = 2`, `delimiter = Comma`.
pub fn EncodeOptions::default() -> EncodeOptions {
  { indent_size: 2, delimiter: Comma, }
}

///|
/// Creates encoding options with optional overrides.
pub fn EncodeOptions::new(
  indent_size~ : Int32 = 2,
  delimiter~ : Delimiter = Comma,
) -> EncodeOptions {
  { indent_size, delimiter, }
}

///|
/// Validates `EncodeOptions`, raising `EncodeError` if `indent_size < 1`.
pub fn EncodeOptions::validate(self : EncodeOptions) -> Unit raise EncodeError {
  if self.indent_size < 1 {
    raise EncodeError(
      message="indent_size must be at least 1, got \{self.indent_size}",
      path=None,
    )
  }
}

///|
/// Options controlling TOON decoding (TOON §13.2).
#derive(Eq, @debug.Debug)
pub(all) struct DecodeOptions {
  indent_size : Int32
  strict : Bool
}

///|
/// Default decoding options: `indent_size = 2`, `strict = true`.
pub fn DecodeOptions::default() -> DecodeOptions {
  { indent_size: 2, strict: true, }
}

///|
/// Creates decoding options with optional overrides.
pub fn DecodeOptions::new(
  indent_size~ : Int32 = 2,
  strict~ : Bool = true,
) -> DecodeOptions {
  { indent_size, strict, }
}

///|
/// Validates `DecodeOptions`, raising `DecodeError` if `indent_size < 1`.
pub fn DecodeOptions::validate(self : DecodeOptions) -> Unit raise DecodeError {
  if self.indent_size < 1 {
    raise DecodeError::new(
      kind=InvalidOption,
      message="indent_size must be at least 1, got \{self.indent_size}",
    )
  }
}
