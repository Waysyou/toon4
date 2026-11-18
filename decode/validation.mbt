///|
fn utf16_span_length(
  raw : StringView,
  start : Int32,
  utf16_len : Int32,
) -> Int32 {
  if utf16_len <= 1 {
    return 1
  }
  let raw_len = raw.length()
  let safe_start = if start < 0 { 0 } else { start }
  let end = if safe_start + utf16_len > raw_len {
    raw_len
  } else {
    safe_start + utf16_len
  }
  if safe_start >= end {
    return 1
  }
  let mut count = 0
  let mut i = safe_start
  while i < end {
    let cu = raw[i]
    if cu >= 0xD800 &&
      cu <= 0xDBFF &&
      i + 1 < end &&
      raw[i + 1] >= 0xDC00 &&
      raw[i + 1] <= 0xDFFF {
      i += 2
    } else {
      i += 1
    }
    count += 1
  }
  if count < 1 {
    1
  } else {
    count
  }
}

///|
fn error_on_line(
  kind : @types.ErrorKind,
  message : String,
  line : @lex.ParsedLine,
  utf16_offset? : Int32,
  utf16_length~ : Int32 = 1,
) -> @types.DecodeError {
  let off = match utf16_offset {
    Some(o) => o
    None => line.content_offset
  }
  let col = @lex.utf16_offset_to_column(line.raw, off)
  let len = utf16_span_length(line.raw, off, utf16_length)
  @types.DecodeError::new(
    kind~,
    message~,
    span=@types.Span::at(line.line_number, col, length=len),
    source_line=Some(line.raw),
  )
}

///|
fn attach_line(
  err : @types.DecodeError,
  line : @lex.ParsedLine,
) -> @types.DecodeError {
  match err {
    DecodeError(kind~, message~, span~, source_line~) =>
      if span.line > 0 {
        err
      } else {
        let utf16_off = if span.column > 1 { span.column - 1 } else { 0 }
        let col = @lex.utf16_offset_to_column(line.raw, utf16_off)
        let len = utf16_span_length(line.raw, utf16_off, span.length)
        let next_src = match source_line {
          Some(_) => source_line
          None => Some(line.raw)
        }
        @types.DecodeError::new(
          kind~,
          message~,
          span=@types.Span::at(line.line_number, col, length=len),
          source_line=next_src,
        )
      }
  }
}

///|
/// Verifies that `actual` equals the arbitrary-precision `expected` count,
/// raising `CountMismatch` or `WidthMismatch` attached to `line`.
pub fn assert_expected_count(
  actual : Int32,
  expected : @bigint.BigInt,
  item_type : String,
  line : @lex.ParsedLine,
  kind~ : @types.ErrorKind = CountMismatch,
  col_offset? : Int32,
  utf16_length? : Int32,
) -> Unit raise @types.DecodeError {
  if !expected.equal_int(actual) {
    let off = match col_offset {
      Some(o) => o
      None => line.content_offset
    }
    let ulen = match utf16_length {
      Some(l) => l
      None => line.content.length()
    }
    raise error_on_line(
      kind,
      "expected \{expected.to_string()} \{item_type}, but got \{actual}",
      line,
      utf16_offset=off,
      utf16_length=ulen,
    )
  }
}

///|
/// Rejects extra list items at `item_depth` after `expected_count` items in strict mode.
pub fn validate_no_extra_list_items(
  next_line : @lex.ParsedLine?,
  item_depth : Int32,
  expected_count : @bigint.BigInt,
) -> Unit raise @types.DecodeError {
  match next_line {
    None => ()
    Some(line) =>
      if line.depth == item_depth &&
        (line.content == "-" || line.content.has_prefix("- ")) {
        raise error_on_line(
          CountMismatch,
          "expected \{expected_count.to_string()} list-form items, but found more",
          line,
          utf16_length=line.content.length(),
        )
      }
  }
}

///|
/// Rejects extra tabular rows at `row_depth` after `header.length` rows in strict mode.
pub fn validate_no_extra_tabular_rows(
  next_line : @lex.ParsedLine?,
  row_depth : Int32,
  header : @types.ArrayHeader,
) -> Unit raise @types.DecodeError {
  match next_line {
    None => ()
    Some(line) =>
      if line.depth == row_depth &&
        line.content != "-" &&
        !line.content.has_prefix("- ") &&
        is_data_row(line.content, header.delimiter) {
        raise error_on_line(
          CountMismatch,
          "expected \{header.length.to_string()} tabular rows, but found more",
          line,
          utf16_length=line.content.length(),
        )
      }
  }
}

///|
/// Rejects any blank line strictly between `start_line` and `end_line` in strict mode.
pub fn validate_no_blank_lines_in_range(
  start_line : Int32?,
  end_line : Int32?,
  blank_lines : Array[@lex.BlankLineInfo],
  context : String,
) -> Unit raise @types.DecodeError {
  match (start_line, end_line) {
    (Some(start_ln), Some(end_ln)) =>
      for blank in blank_lines {
        if blank.line > start_ln && blank.line < end_ln {
          let len = if blank.indent > 0 { blank.indent } else { 1 }
          raise @types.DecodeError::new(
            kind=BlankLineInScope,
            message="blank lines inside \{context} are not allowed in strict mode",
            span=@types.Span::at(blank.line, 1, length=len),
          )
        }
      }
    _ => ()
  }
}

///|
/// Classifies whether a line at tabular row depth is a data row per TOON §9.3:
/// - no unquoted colon -> row
/// - first unquoted active delimiter precedes first unquoted colon -> row
/// - otherwise (colon precedes delimiter or no unquoted delimiter) -> not a row
pub fn is_data_row(content : StringView, delimiter : @types.Delimiter) -> Bool {
  match @lex.find_unquoted_char(content, ':') {
    None => true
    Some(colon_pos) =>
      match @lex.find_unquoted_char(content, delimiter.to_char()) {
        Some(delim_pos) => delim_pos < colon_pos
        None => false
      }
  }
}
