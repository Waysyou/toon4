///|
/// Metadata recorded for blank lines encountered during lexical scanning.
#derive(Eq, @debug.Debug)
pub(all) struct BlankLineInfo {
  line : Int32
  indent : Int32
  depth : Int32
}

///|
/// A non-blank, non-comment preprocessed TOON line.
#derive(Eq, @debug.Debug)
pub(all) struct ParsedLine {
  raw : String
  indent : Int32
  content : String
  content_offset : Int32
  depth : Int32
  line_number : Int32
}

///|
/// Stateful line scanner state across a TOON document or stream.
pub(all) struct ScanState {
  mut line_number : Int32
  blank_lines : Array[BlankLineInfo]
}

///|
/// Creates a fresh `ScanState`.
pub fn ScanState::new() -> ScanState {
  { line_number: 0, blank_lines: [], }
}

///|
/// Splits an input document on `LF` (`\n`) without stripping `\r` prematurely.
pub fn split_lines_raw(input : String) -> Array[String] {
  if input.is_empty() {
    return []
  }
  let lines : Array[String] = []
  let len = input.length()
  let mut start = 0
  for i in 0..<len {
    if input[i] == cu_lf {
      lines.push(input[start:i].to_owned())
      start = i + 1
    }
  }
  lines.push(input[start:len].to_owned())
  lines
}

///|
/// Scans a single raw line per TOON §5.1 & §12 in exact normative order:
/// 1. Strip single leading `U+FEFF` on line 1
/// 2. Strip single trailing `U+000D` (`\r`)
/// 3. Measure leading `[ \t]*` whitespace
/// 4. Strip trailing `U+0020` spaces from the line body
/// 5. Drop full-line `#` comments (spaces-only indent) before blank/indent checks
/// 6. Record blank lines or validate strict indentation
pub fn scan_line_incremental(
  raw_input : String,
  state : ScanState,
  indent_size : Int32,
  strict : Bool,
) -> ParsedLine? raise @types.DecodeError {
  state.line_number += 1
  let line_num = state.line_number
  let mut line = raw_input[:]
  if line_num == 1 && !line.is_empty() && line[0] == cu_bom {
    line = line[1:line.length()]
  }
  let len0 = line.length()
  if len0 > 0 && line[len0 - 1] == cu_cr {
    line = line[0:len0 - 1]
  }
  let len = line.length()
  let mut ws_end = 0
  let mut first_tab_idx = -1
  let mut tab_count = 0
  while ws_end < len {
    let cu = line[ws_end]
    if cu == cu_sp {
      ws_end += 1
    } else if cu == cu_tab {
      if first_tab_idx == -1 {
        first_tab_idx = ws_end
      }
      tab_count += 1
      ws_end += 1
    } else {
      break
    }
  }
  let indent = if strict && first_tab_idx != -1 {
    first_tab_idx
  } else {
    ws_end
  }
  let tab_indent = if strict || first_tab_idx == -1 { 0 } else { tab_count }
  let body = trim_trailing_spaces(line[indent:len])
  // Comment lines: optional leading SP (never HTAB) followed by '#'
  if first_tab_idx == -1 && !body.is_empty() && body[0] == cu_hash {
    return None
  }
  let depth = (indent - tab_indent) / indent_size + tab_indent
  if body.is_empty() {
    state.blank_lines.push({ line: line_num, indent, depth, })
    return None
  }
  let raw_str = line.to_owned()
  if strict {
    if first_tab_idx != -1 {
      raise @types.DecodeError::new(
        kind=InvalidIndentation,
        message="tabs are not allowed in indentation in strict mode",
        span=@types.Span::at(line_num, first_tab_idx + 1, length=1),
        source_line=Some(raw_str),
      )
    }
    if indent > 0 && indent % indent_size != 0 {
      raise @types.DecodeError::new(
        kind=InvalidIndentation,
        message="indentation must be an exact multiple of \{indent_size}, found \{indent} spaces",
        span=@types.Span::at(line_num, 1, length=indent),
        source_line=Some(raw_str),
      )
    }
  }
  Some({
    raw: raw_str,
    indent,
    content: body.to_owned(),
    content_offset: indent,
    depth,
    line_number: line_num,
  })
}
