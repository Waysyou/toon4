///|
/// Outcome of attempting to parse a line as a TOON §6 / §9.5 header.
#derive(Eq, @debug.Debug)
pub(all) enum HeaderParse {
  Header(
    header~ : @types.ArrayHeader,
    inline_values~ : String?,
    inline_offset~ : Int32,
    strict_error~ : @types.DecodeError?,
  )
  NotHeader
  Invalid(@types.DecodeError)
}

///|
/// Finds the matching `}` for an opening `{` at `brace_start`, ignoring quoted
/// strings and tracking nested `{...}` groups.
pub fn find_matching_brace(s : StringView, brace_start : Int32) -> Int32? {
  let len = s.length()
  let mut in_quotes = false
  let mut depth = 0
  let mut i = brace_start
  while i < len {
    let cu = s[i]
    if in_quotes && cu == cu_backslash && i + 1 < len {
      i += 2
      continue
    }
    if cu == cu_quote {
      in_quotes = !in_quotes
      i += 1
      continue
    }
    if !in_quotes {
      if cu == cu_lbrace {
        depth += 1
      } else if cu == cu_rbrace {
        depth -= 1
        if depth == 0 {
          return Some(i)
        }
      }
    }
    i += 1
  }
  None
}

///|
/// Parses bracket interior `[...]` into `(length, delimiter, keyed)` per §6.
pub fn parse_bracket_segment(
  seg : StringView,
  default_delim : @types.Delimiter,
  col_offset~ : Int32 = 0,
) -> (@bigint.BigInt, @types.Delimiter, Bool) raise @types.DecodeError {
  let mut view = seg
  let mut delim = default_delim
  let len0 = view.length()
  if len0 > 0 && view[len0 - 1] == cu_tab {
    delim = Tab
    view = view[0:len0 - 1]
  } else if len0 > 0 && view[len0 - 1] == cu_pipe {
    delim = Pipe
    view = view[0:len0 - 1]
  }
  let mut keyed = false
  let len1 = view.length()
  if len1 > 0 && view[len1 - 1] == cu_colon {
    keyed = true
    view = view[0:len1 - 1]
  }
  let len2 = view.length()
  let valid_num = if len2 == 0 {
    false
  } else if len2 == 1 {
    is_ascii_digit(view[0])
  } else if view[0] == 0x30 {
    // Leading zeros like `[03]` are forbidden by §6
    false
  } else {
    let mut ok = true
    for i in 0..<len2 {
      if !is_ascii_digit(view[i]) {
        ok = false
        break
      }
    }
    ok
  }
  if !valid_num {
    raise @types.DecodeError::new(
      kind=MalformedHeader,
      message="invalid array length in bracket segment '[\{seg.to_owned()}]'",
      span=@types.Span::at(0, 1 + col_offset, length=seg.length()),
    )
  }
  let length = @string.parse_bigint(view) catch {
    _ =>
      raise @types.DecodeError::new(
        kind=MalformedHeader,
        message="invalid integer length '\{view.to_owned()}'",
        span=@types.Span::at(0, 1 + col_offset, length=view.length()),
      )
  }
  (length, delim, keyed)
}

///|
fn split_field_entries(
  content : StringView,
  delimiter : @types.Delimiter,
  col_offset : Int32,
) -> Array[(StringView, Int32)] raise @types.DecodeError {
  let len = content.length()
  let delim_cu = delimiter.to_char().to_int().to_uint16()
  let entries : Array[(StringView, Int32)] = []
  let mut seg_start = 0
  let mut in_quotes = false
  let mut brace_depth = 0
  let mut i = 0
  while i < len {
    let cu = content[i]
    if in_quotes && cu == cu_backslash && i + 1 < len {
      i += 2
      continue
    }
    if cu == cu_quote {
      in_quotes = !in_quotes
      i += 1
      continue
    }
    if !in_quotes {
      if cu == cu_lbrace {
        brace_depth += 1
      } else if cu == cu_rbrace {
        brace_depth -= 1
        if brace_depth < 0 {
          raise @types.DecodeError::new(
            kind=MalformedHeader,
            message="unexpected '}' in field list",
            span=@types.Span::at(0, 1 + col_offset + i, length=1),
          )
        }
      } else if cu == delim_cu && brace_depth == 0 {
        entries.push((content[seg_start:i], col_offset + seg_start))
        seg_start = i + 1
      }
    }
    i += 1
  }
  if in_quotes {
    raise @types.DecodeError::new(
      kind=UnterminatedString,
      message="unterminated quoted field name in header",
      span=@types.Span::at(
        0,
        1 + col_offset + seg_start,
        length=len - seg_start,
      ),
    )
  }
  if brace_depth != 0 {
    raise @types.DecodeError::new(
      kind=MalformedHeader,
      message="unmatched '{' in field list",
      span=@types.Span::at(
        0,
        1 + col_offset + seg_start,
        length=len - seg_start,
      ),
    )
  }
  entries.push((content[seg_start:len], col_offset + seg_start))
  entries
}

///|
/// Recursively parses `{...}` body into `Array[@types.FieldNode]`.
pub fn parse_field_entries(
  fields_content : StringView,
  delimiter : @types.Delimiter,
  col_offset~ : Int32 = 0,
) -> Array[@types.FieldNode] raise @types.DecodeError {
  if fields_content.is_empty() {
    raise @types.DecodeError::new(
      kind=MalformedHeader,
      message="empty field list in header",
      span=@types.Span::at(0, 1 + col_offset, length=1),
    )
  }
  let raw_entries = split_field_entries(fields_content, delimiter, col_offset)
  let nodes : Array[@types.FieldNode] = []
  for pair in raw_entries {
    let (entry, entry_off) = pair
    let (trimmed, lead) = trim_spaces_with_offset(entry)
    let trimmed_off = entry_off + lead
    if trimmed.is_empty() {
      raise @types.DecodeError::new(
        kind=MalformedHeader,
        message="empty field name in field list",
        span=@types.Span::at(0, 1 + entry_off, length=1),
      )
    }
    match find_unquoted_char(trimmed, '{') {
      None => {
        let name = parse_string_literal(trimmed, col_offset=trimmed_off)
        nodes.push(@types.FieldNode::Leaf(name))
      }
      Some(g_start) => {
        let name_part = trimmed[0:g_start]
        if name_part.is_empty() {
          raise @types.DecodeError::new(
            kind=MalformedHeader,
            message="missing field name before nested field group",
            span=@types.Span::at(0, 1 + trimmed_off + g_start, length=1),
          )
        }
        if ends_with_ascii_whitespace(name_part) {
          raise @types.DecodeError::new(
            kind=MalformedHeader,
            message="unexpected whitespace before nested field group",
            span=@types.Span::at(
              0,
              1 + trimmed_off + name_part.length() - 1,
              length=1,
            ),
          )
        }
        match find_matching_brace(trimmed, g_start) {
          None =>
            raise @types.DecodeError::new(
              kind=MalformedHeader,
              message="unmatched brace in nested field group",
              span=@types.Span::at(0, 1 + trimmed_off + g_start, length=1),
            )
          Some(g_end) => {
            if g_end != trimmed.length() - 1 {
              raise @types.DecodeError::new(
                kind=MalformedHeader,
                message="unexpected content after nested field group",
                span=@types.Span::at(
                  0,
                  1 + trimmed_off + g_end + 1,
                  length=trimmed.length() - 1 - g_end,
                ),
              )
            }
            let group_name = parse_string_literal(
              name_part,
              col_offset=trimmed_off,
            )
            let children = parse_field_entries(
              trimmed[g_start + 1:g_end],
              delimiter,
              col_offset=trimmed_off + g_start + 1,
            )
            nodes.push(@types.FieldNode::Group(group_name, children))
          }
        }
      }
    }
  }
  nodes
}

///|
/// Parses a trimmed line body as a TOON §6 / §9.5 array or keyed-tabular header.
pub fn parse_array_header_line(
  content : StringView,
  default_delim : @types.Delimiter,
  line_col_offset~ : Int32 = 0,
) -> HeaderParse {
  let len = content.length()
  if len == 0 {
    return NotHeader
  }
  let bracket_start = if content[0] == cu_quote {
    match find_closing_quote(content, 0) {
      None => return NotHeader
      Some(close_idx) =>
        if close_idx + 1 < len && content[close_idx + 1] == cu_lbracket {
          close_idx + 1
        } else {
          return NotHeader
        }
    }
  } else {
    match find_unquoted_char(content, '[') {
      None => return NotHeader
      Some(idx) => idx
    }
  }
  // A header requires an unquoted colon after `[` (so `k: [1,2]` is key-value).
  // Once `[` precedes the first unquoted `:`, the line commits to header parsing.
  match find_unquoted_char(content, ':') {
    None => return NotHeader
    Some(first_colon) => if first_colon < bracket_start { return NotHeader }
  }
  let bracket_end = match
    find_unquoted_char(content, ']', start=bracket_start) {
    None =>
      return Invalid(
        @types.DecodeError::new(
          kind=MalformedHeader,
          message="unterminated bracket segment",
          span=@types.Span::at(
            0,
            1 + line_col_offset + bracket_start,
            length=len - bracket_start,
          ),
        ),
      )
    Some(idx) => idx
  }
  // Parse optional key before `[` (no whitespace allowed between key and `[`)
  let key : String? = if bracket_start > 0 {
    let raw_key = content[0:bracket_start]
    if ends_with_ascii_whitespace(raw_key) {
      return Invalid(
        @types.DecodeError::new(
          kind=MalformedHeader,
          message="unexpected whitespace between key and bracket segment",
          span=@types.Span::at(
            0,
            1 + line_col_offset + bracket_start - 1,
            length=1,
          ),
        ),
      )
    }
    if raw_key[0] == cu_quote {
      let decoded = parse_string_literal(raw_key, col_offset=line_col_offset) catch {
        err => return Invalid(err)
      }
      Some(decoded)
    } else {
      Some(raw_key.to_owned())
    }
  } else {
    None
  }
  let (length, delim, keyed) = parse_bracket_segment(
    content[bracket_start + 1:bracket_end],
    default_delim,
    col_offset=line_col_offset + bracket_start + 1,
  ) catch {
    err => return Invalid(err)
  }
  // Check optional `{fields}` between `]` and the header-terminating `:`
  let colon_after_bracket = find_unquoted_char(
    content,
    ':',
    start=bracket_end + 1,
  )
  let mut fields : Array[@types.FieldNode]? = None
  let mut after_fields_idx = bracket_end + 1
  match find_unquoted_char(content, '{', start=bracket_end + 1) {
    Some(brace_start) => {
      let before_colon = match colon_after_bracket {
        None => true
        Some(c_idx) => brace_start < c_idx
      }
      if before_colon {
        let gap = content[bracket_end + 1:brace_start]
        if !gap.is_empty() {
          let trimmed_gap = trim_ascii_whitespace(gap)
          let msg = if trimmed_gap.is_empty() {
            "unexpected whitespace between bracket segment and field list"
          } else {
            "unexpected content '\{trimmed_gap.to_owned()}' between bracket segment and field list"
          }
          return Invalid(
            @types.DecodeError::new(
              kind=MalformedHeader,
              message=msg,
              span=@types.Span::at(
                0,
                1 + line_col_offset + bracket_end + 1,
                length=gap.length(),
              ),
            ),
          )
        }
        let brace_end = match find_matching_brace(content, brace_start) {
          None =>
            return Invalid(
              @types.DecodeError::new(
                kind=MalformedHeader,
                message="unmatched '{' in header field list",
                span=@types.Span::at(
                  0,
                  1 + line_col_offset + brace_start,
                  length=1,
                ),
              ),
            )
          Some(idx) => idx
        }
        after_fields_idx = brace_end + 1
        let fields_body = content[brace_start + 1:brace_end]
        match find_unquoted_mismatched_delimiter(fields_body, delim) {
          Some(bad_delim) =>
            return Invalid(
              @types.DecodeError::new(
                kind=HeaderDelimiterMismatch,
                message="header delimiter mismatch: bracket declares '\{delim.label()}' but field list contains unquoted '\{bad_delim.label()}'",
                span=@types.Span::at(
                  0,
                  1 + line_col_offset + brace_start + 1,
                  length=fields_body.length(),
                ),
              ),
            )
          None => ()
        }
        let parsed_fields = parse_field_entries(
          fields_body,
          delim,
          col_offset=line_col_offset + brace_start + 1,
        ) catch {
          err => return Invalid(err)
        }
        fields = Some(parsed_fields)
      }
    }
    None => ()
  }
  let colon_idx = match
    find_unquoted_char(content, ':', start=after_fields_idx) {
    None =>
      return Invalid(
        @types.DecodeError::new(
          kind=MalformedHeader,
          message="missing colon after array header",
          span=@types.Span::at(
            0,
            1 + line_col_offset + after_fields_idx,
            length=1,
          ),
        ),
      )
    Some(idx) => idx
  }
  let gap_before_colon = content[after_fields_idx:colon_idx]
  if !gap_before_colon.is_empty() {
    let trimmed_gap = trim_ascii_whitespace(gap_before_colon)
    let msg = if trimmed_gap.is_empty() {
      "unexpected whitespace before header colon"
    } else {
      "unexpected content '\{trimmed_gap.to_owned()}' before header colon"
    }
    return Invalid(
      @types.DecodeError::new(
        kind=MalformedHeader,
        message=msg,
        span=@types.Span::at(
          0,
          1 + line_col_offset + after_fields_idx,
          length=gap_before_colon.length(),
        ),
      ),
    )
  }
  let duplicate_err : @types.DecodeError? = match fields {
    None => None
    Some(fs) =>
      match @types.find_duplicate_field(fs) {
        None => None
        Some(dup) =>
          Some(
            @types.DecodeError::new(
              kind=DuplicateField,
              message="duplicate field name '\{dup}' in header field list",
              span=@types.Span::at(0, 1 + line_col_offset, length=colon_idx + 1),
            ),
          )
      }
  }
  if keyed && fields is None {
    return Invalid(
      @types.DecodeError::new(
        kind=MalformedHeader,
        message="keyed header '[N:]' requires a '{fields}' list",
        span=@types.Span::at(
          0,
          1 + line_col_offset + bracket_start,
          length=bracket_end - bracket_start + 1,
        ),
      ),
    )
  }
  let (after_colon, after_lead) = trim_spaces_with_offset(
    content[colon_idx + 1:len],
  )
  if !(fields is None) && !after_colon.is_empty() {
    match duplicate_err {
      Some(err) => return Invalid(err)
      None =>
        return Invalid(
          @types.DecodeError::new(
            kind=MalformedHeader,
            message="unexpected inline content after fields-bearing header colon",
            span=@types.Span::at(
              0,
              1 + line_col_offset + colon_idx + 1 + after_lead,
              length=after_colon.length(),
            ),
          ),
        )
    }
  }
  let inline_values = if after_colon.is_empty() {
    None
  } else {
    Some(after_colon.to_owned())
  }
  Header(
    header={ key, length, delimiter: delim, fields, keyed, },
    inline_values~,
    inline_offset=line_col_offset + colon_idx + 1 + after_lead,
    strict_error=duplicate_err,
  )
}
