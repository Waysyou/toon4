///|
/// Streams TOON lines pulled from `next_line` as `@types.StreamEvent` values.
pub fn decode_stream_lines(
  next_line : () -> String?,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
  options~ : @types.DecodeOptions = @types.DecodeOptions::default(),
) -> Unit raise @types.DecodeError {
  options.validate()
  let reader = LineReader::new(
    next_line,
    indent_size=options.indent_size,
    strict=options.strict,
  )
  decode_document(reader, options, on_event)
}

///|
/// Streams a complete TOON document string as `@types.StreamEvent` values.
pub fn decode_stream(
  input : String,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
  options~ : @types.DecodeOptions = @types.DecodeOptions::default(),
) -> Unit raise @types.DecodeError {
  options.validate()
  let len = input.length()
  let mut pos : Int32 = 0
  let mut finished = input.is_empty()
  let next_line = fn() -> String? {
    if finished {
      return None
    }
    let start = pos
    let mut i = start
    while i < len {
      if input[i] == 0x0A {
        pos = i + 1
        return Some(input[start:i].to_owned())
      }
      i += 1
    }
    finished = true
    Some(input[start:len].to_owned())
  }
  decode_stream_lines(next_line, on_event, options~)
}

///|
fn decode_document(
  reader : LineReader,
  options : @types.DecodeOptions,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  let first = match reader.peek() {
    None => {
      on_event(StartObject)
      on_event(EndObject)
      return
    }
    Some(line) => line
  }
  if first.depth != 0 {
    raise over_indented_error(first, 0)
  }
  if first.content == "[]" {
    ignore(reader.read())
    on_event(StartArray(0))
    on_event(EndArray)
    assert_fully_consumed(reader)
    return
  }
  match resolve_array_header(first, options.strict) {
    Some((header, inline_values, inline_offset)) if header.key is None => {
      ignore(reader.read())
      decode_array_from_header(
        header, inline_values, inline_offset, reader, 0, options, first, on_event,
      )
      assert_fully_consumed(reader)
      return
    }
    _ => ()
  }
  ignore(reader.read())
  let following = reader.peek()
  let has_colon = !(@lex.find_unquoted_char(first.content, ':') is None)
  if following is None && !has_colon {
    let prim = parse_primitive_on_line(
      first.content,
      first.content_offset,
      first,
    )
    on_event(Primitive(prim))
    return
  }
  if !has_colon {
    match following {
      Some(next) if next.depth == 0 =>
        raise error_on_line(
          UnexpectedContent,
          "top-level document must start with a key-value or array-header line",
          first,
          utf16_length=first.content.length(),
        )
      _ => ()
    }
  }
  let root_seen_keys : Map[String, Bool]? = if options.strict {
    Some(Map([]))
  } else {
    None
  }
  on_event(StartObject)
  decode_key_value(first, reader, 0, options, root_seen_keys, on_event)
  while true {
    match reader.peek() {
      None => break
      Some(line) => {
        if line.depth != 0 {
          raise over_indented_error(line, 0)
        }
        ignore(reader.read())
        decode_key_value(line, reader, 0, options, root_seen_keys, on_event)
      }
    }
  }
  on_event(EndObject)
}

///|
fn decode_key_value(
  line : @lex.ParsedLine,
  reader : LineReader,
  base_depth : Int32,
  options : @types.DecodeOptions,
  seen_keys : Map[String, Bool]?,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  match resolve_array_header(line, options.strict) {
    Some((header, inline_values, inline_offset)) =>
      match header.key {
        None => raise keyless_header_error(header, line)
        Some(key) => {
          check_duplicate_key(key, line, seen_keys, utf16_length=key.length())
          on_event(Key(key))
          decode_array_from_header(
            header, inline_values, inline_offset, reader, base_depth, options, line,
            on_event,
          )
          return
        }
      }
    None => ()
  }
  let (key, value_start) = @lex.parse_key_token(
    line.content,
    start=0,
    col_offset=line.content_offset,
  ) catch {
    err => raise attach_line(err, line)
  }
  check_duplicate_key(key, line, seen_keys, utf16_length=value_start - 1)
  on_event(Key(key))
  let (rest, rest_lead) = @lex.trim_spaces_with_offset(
    line.content[value_start:line.content.length()],
  )
  if rest.is_empty() {
    match reader.peek() {
      Some(next_line) if next_line.depth > base_depth => {
        if options.strict && next_line.depth > base_depth + 1 {
          raise depth_jump_error(next_line, base_depth + 1)
        }
        on_event(StartObject)
        decode_object_fields(reader, base_depth + 1, options, on_event)
        on_event(EndObject)
      }
      _ => {
        on_event(StartObject)
        on_event(EndObject)
      }
    }
    return
  }
  if rest == "[]" {
    on_event(StartArray(0))
    on_event(EndArray)
    return
  }
  let prim = parse_primitive_on_line(
    rest,
    line.content_offset + value_start + rest_lead,
    line,
  )
  on_event(Primitive(prim))
}

///|
fn decode_object_fields(
  reader : LineReader,
  min_depth : Int32,
  options : @types.DecodeOptions,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  let mut computed_depth : Int32? = None
  let seen_keys : Map[String, Bool]? = if options.strict {
    Some(Map([]))
  } else {
    None
  }
  while true {
    match reader.peek() {
      None => break
      Some(line) => {
        if line.depth < min_depth {
          break
        }
        let target_depth = match computed_depth {
          Some(d) => d
          None => {
            computed_depth = Some(line.depth)
            line.depth
          }
        }
        if line.depth != target_depth {
          raise over_indented_error(line, target_depth)
        }
        ignore(reader.read())
        decode_key_value(
          line, reader, target_depth, options, seen_keys, on_event,
        )
      }
    }
  }
}

///|
fn decode_array_from_header(
  header : @types.ArrayHeader,
  inline_values : String?,
  inline_offset : Int32,
  reader : LineReader,
  base_depth : Int32,
  options : @types.DecodeOptions,
  header_line : @lex.ParsedLine,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  if header.keyed {
    decode_keyed_object(
      header, reader, base_depth, options, header_line, on_event,
    )
    return
  }
  on_event(StartArray(clamp_length_hint(header.length)))
  match inline_values {
    Some(iv) => {
      decode_inline_primitive_array(
        header, iv, inline_offset, options, header_line, on_event,
      )
      on_event(EndArray)
      return
    }
    None => ()
  }
  match header.fields {
    Some(fields) if !fields.is_empty() => {
      decode_tabular_array(
        header, fields, reader, base_depth, options, header_line, on_event,
      )
      on_event(EndArray)
      return
    }
    _ => ()
  }
  decode_list_array(header, reader, base_depth, options, header_line, on_event)
  on_event(EndArray)
}

///|
fn decode_inline_primitive_array(
  header : @types.ArrayHeader,
  inline_values : String,
  inline_offset : Int32,
  options : @types.DecodeOptions,
  header_line : @lex.ParsedLine,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  let values = @lex.split_delimited_values(inline_values, header.delimiter)
  let primitives = parse_row_primitives(values, inline_offset, header_line)
  if options.strict {
    assert_expected_count(
      primitives.length(),
      header.length,
      "inline-form values",
      header_line,
      col_offset=inline_offset,
      utf16_length=inline_values.length(),
    )
  }
  for prim in primitives {
    on_event(Primitive(prim))
  }
}

///|
fn decode_keyed_object(
  header : @types.ArrayHeader,
  reader : LineReader,
  base_depth : Int32,
  options : @types.DecodeOptions,
  header_line : @lex.ParsedLine,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  let fields = match header.fields {
    Some(fs) if !fs.is_empty() => fs
    _ =>
      raise error_on_line(
        MalformedHeader,
        "keyed header requires a non-empty field list",
        header_line,
        utf16_length=header_line.content.length(),
      )
  }
  let entry_depth = scope_content_depth(reader, base_depth, options.strict)
  let leaf_field_count = @types.count_leaf_fields(fields)
  let seen_entry_keys : Map[String, Bool]? = if options.strict {
    Some(Map([]))
  } else {
    None
  }
  let mut entry_count = 0
  let mut start_line : Int32? = None
  let mut end_line : Int32? = None
  let mut last_entry_line = header_line
  on_event(StartObject)
  while true {
    let line = match reader.peek() {
      None => break
      Some(l) => l
    }
    if line.depth <= base_depth {
      break
    }
    if line.depth != entry_depth {
      raise over_indented_error(line, entry_depth)
    }
    let (entry_key, cells_start) = @lex.parse_key_token(
      line.content,
      start=0,
      col_offset=line.content_offset,
    ) catch {
      err => raise attach_line(err, line)
    }
    ignore(reader.read())
    if start_line is None {
      start_line = Some(line.line_number)
    }
    end_line = Some(line.line_number)
    last_entry_line = line
    check_duplicate_key(
      entry_key,
      line,
      seen_entry_keys,
      utf16_length=cells_start - 1,
    )
    on_event(Key(entry_key))
    let (cells_content, cells_lead) = @lex.trim_spaces_with_offset(
      line.content[cells_start:line.content.length()],
    )
    let cells_offset = line.content_offset + cells_start + cells_lead
    let values = if cells_content.is_empty() {
      []
    } else {
      @lex.split_delimited_values(cells_content, header.delimiter)
    }
    let width_off = if cells_content.is_empty() {
      line.content_offset + cells_start - 1
    } else {
      cells_offset
    }
    let width_len = if cells_content.is_empty() {
      1
    } else {
      cells_content.length()
    }
    assert_expected_count(
      values.length(),
      @bigint.BigInt::from_int(leaf_field_count),
      "keyed entry cells",
      line,
      kind=WidthMismatch,
      col_offset=width_off,
      utf16_length=width_len,
    )
    let primitives = parse_row_primitives(values, cells_offset, line)
    emit_object_from_fields(fields, primitives, on_event)
    entry_count += 1
  }
  if options.strict {
    assert_expected_count(
      entry_count,
      header.length,
      "keyed entries",
      last_entry_line,
    )
    validate_no_blank_lines_in_range(
      start_line,
      end_line,
      reader.scan_state.blank_lines,
      "keyed tabular object",
    )
  }
  on_event(EndObject)
}

///|
fn decode_tabular_array(
  header : @types.ArrayHeader,
  fields : Array[@types.FieldNode],
  reader : LineReader,
  base_depth : Int32,
  options : @types.DecodeOptions,
  header_line : @lex.ParsedLine,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  let row_depth = scope_content_depth(reader, base_depth, options.strict)
  let leaf_field_count = @types.count_leaf_fields(fields)
  let mut row_count = 0
  let mut start_line : Int32? = None
  let mut end_line : Int32? = None
  let mut last_row_line = header_line
  while !options.strict || header.length.compare_int(row_count) > 0 {
    let line = match reader.peek() {
      None => break
      Some(l) => l
    }
    if line.depth <= base_depth {
      break
    }
    if line.depth != row_depth {
      raise over_indented_error(line, row_depth)
    }
    if !is_data_row(line.content, header.delimiter) {
      break
    }
    if start_line is None {
      start_line = Some(line.line_number)
    }
    end_line = Some(line.line_number)
    last_row_line = line
    ignore(reader.read())
    let values = @lex.split_delimited_values(line.content, header.delimiter)
    assert_expected_count(
      values.length(),
      @bigint.BigInt::from_int(leaf_field_count),
      "tabular row values",
      line,
      kind=WidthMismatch,
    )
    let primitives = parse_row_primitives(values, line.content_offset, line)
    emit_object_from_fields(fields, primitives, on_event)
    row_count += 1
  }
  if options.strict {
    assert_expected_count(
      row_count,
      header.length,
      "tabular rows",
      last_row_line,
    )
    validate_no_blank_lines_in_range(
      start_line,
      end_line,
      reader.scan_state.blank_lines,
      "tabular array",
    )
    validate_no_extra_tabular_rows(reader.peek(), row_depth, header)
  }
}

///|
fn decode_list_array(
  header : @types.ArrayHeader,
  reader : LineReader,
  base_depth : Int32,
  options : @types.DecodeOptions,
  header_line : @lex.ParsedLine,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  let item_depth = scope_content_depth(reader, base_depth, options.strict)
  let mut item_count = 0
  let mut start_line : Int32? = None
  let mut end_line : Int32? = None
  let mut last_item_line = header_line
  while !options.strict || header.length.compare_int(item_count) > 0 {
    let line = match reader.peek() {
      None => break
      Some(l) => l
    }
    if line.depth <= base_depth {
      break
    }
    if line.depth != item_depth {
      raise over_indented_error(line, item_depth)
    }
    if !(line.content == "-" || line.content.has_prefix("- ")) {
      break
    }
    if start_line is None {
      start_line = Some(line.line_number)
    }
    end_line = Some(line.line_number)
    last_item_line = line
    decode_list_item(reader, item_depth, options, on_event)
    match reader.last_line {
      Some(last_consumed) => {
        end_line = Some(last_consumed.line_number)
        last_item_line = last_consumed
      }
      None => ()
    }
    item_count += 1
  }
  if options.strict {
    assert_expected_count(
      item_count,
      header.length,
      "list-form items",
      last_item_line,
    )
    validate_no_blank_lines_in_range(
      start_line,
      end_line,
      reader.scan_state.blank_lines,
      "list-form array",
    )
    validate_no_extra_list_items(reader.peek(), item_depth, header.length)
  }
}

///|
fn decode_list_item(
  reader : LineReader,
  base_depth : Int32,
  options : @types.DecodeOptions,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  let line = match reader.read() {
    Some(l) => l
    None =>
      raise @types.DecodeError::new(
        kind=UnexpectedContent,
        message="expected list item",
      )
  }
  if line.content == "-" {
    on_event(StartObject)
    on_event(EndObject)
    return
  }
  if !line.content.has_prefix("- ") {
    raise error_on_line(
      UnexpectedContent,
      "expected list item to start with '- '",
      line,
      utf16_length=line.content.length(),
    )
  }
  let len = line.content.length()
  let mut after_off = 1
  while after_off < len && line.content[after_off] == 0x20 {
    after_off += 1
  }
  let after_hyphen = line.content[after_off:len].to_owned()
  if after_hyphen.is_empty() {
    on_event(StartObject)
    on_event(EndObject)
    return
  }
  if after_hyphen == "[]" {
    on_event(StartArray(0))
    on_event(EndArray)
    return
  }
  let item_line : @lex.ParsedLine = {
    raw: line.raw,
    indent: line.indent,
    content: after_hyphen,
    content_offset: line.content_offset + after_off,
    depth: line.depth,
    line_number: line.line_number,
  }
  match resolve_array_header(item_line, options.strict) {
    Some((header, inline_values, inline_offset)) =>
      match header.key {
        None => {
          if header.keyed || !(header.fields is None) {
            raise keyless_header_error(header, item_line)
          }
          decode_array_from_header(
            header, inline_values, inline_offset, reader, base_depth, options, item_line,
            on_event,
          )
          return
        }
        Some(key) => {
          let seen_keys : Map[String, Bool]? = if options.strict {
            Some(Map([(key, true)]))
          } else {
            None
          }
          on_event(StartObject)
          on_event(Key(key))
          decode_array_from_header(
            header,
            inline_values,
            inline_offset,
            reader,
            base_depth + 1,
            options,
            item_line,
            on_event,
          )
          follow_sibling_fields(
            reader,
            base_depth + 1,
            options,
            seen_keys,
            on_event,
          )
          on_event(EndObject)
          return
        }
      }
    None => ()
  }
  if !(@lex.find_unquoted_char(item_line.content, ':') is None) {
    let seen_keys : Map[String, Bool]? = if options.strict {
      Some(Map([]))
    } else {
      None
    }
    on_event(StartObject)
    decode_key_value(
      item_line,
      reader,
      base_depth + 1,
      options,
      seen_keys,
      on_event,
    )
    follow_sibling_fields(reader, base_depth + 1, options, seen_keys, on_event)
    on_event(EndObject)
    return
  }
  let prim = parse_primitive_on_line(
    item_line.content,
    item_line.content_offset,
    item_line,
  )
  on_event(Primitive(prim))
}

///|
fn follow_sibling_fields(
  reader : LineReader,
  follow_depth : Int32,
  options : @types.DecodeOptions,
  seen_keys : Map[String, Bool]?,
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  while true {
    match reader.peek() {
      None => break
      Some(next_line) => {
        if next_line.depth < follow_depth {
          break
        }
        if next_line.depth != follow_depth {
          raise over_indented_error(next_line, follow_depth)
        }
        ignore(reader.read())
        decode_key_value(
          next_line, reader, follow_depth, options, seen_keys, on_event,
        )
      }
    }
  }
}

///|
fn resolve_array_header(
  line : @lex.ParsedLine,
  strict : Bool,
) -> (@types.ArrayHeader, String?, Int32)? raise @types.DecodeError {
  match
    @lex.parse_array_header_line(
      line.content,
      Comma,
      line_col_offset=line.content_offset,
    ) {
    NotHeader => None
    Invalid(err) => raise attach_line(err, line)
    Header(header~, inline_values~, inline_offset~, strict_error~) => {
      if strict {
        match strict_error {
          Some(err) => raise attach_line(err, line)
          None => ()
        }
      }
      Some((header, inline_values, inline_offset))
    }
  }
}

///|
fn scope_content_depth(
  reader : LineReader,
  base_depth : Int32,
  strict : Bool,
) -> Int32 raise @types.DecodeError {
  match reader.peek() {
    None => base_depth + 1
    Some(first) =>
      if first.depth <= base_depth + 1 {
        base_depth + 1
      } else {
        if strict {
          raise depth_jump_error(first, base_depth + 1)
        }
        first.depth
      }
  }
}

///|
fn parse_primitive_on_line(
  token : StringView,
  col_offset : Int32,
  line : @lex.ParsedLine,
) -> Json raise @types.DecodeError {
  @lex.parse_primitive_token(token, col_offset~) catch {
    err => raise attach_line(err, line)
  }
}

///|
fn parse_row_primitives(
  values : Array[(StringView, Int32)],
  base_offset : Int32,
  line : @lex.ParsedLine,
) -> Array[Json] raise @types.DecodeError {
  let out : Array[Json] = []
  for pair in values {
    let (tok, tok_off) = pair
    out.push(parse_primitive_on_line(tok, base_offset + tok_off, line))
  }
  out
}

///|
fn emit_object_from_fields(
  fields : Array[@types.FieldNode],
  primitives : Array[Json],
  on_event : (@types.StreamEvent) -> Unit raise @types.DecodeError,
) -> Unit raise @types.DecodeError {
  let mut cell_index = 0
  fn walk(nodes : Array[@types.FieldNode]) -> Unit raise @types.DecodeError {
    on_event(StartObject)
    for node in nodes {
      match node {
        Leaf(name) => {
          on_event(Key(name))
          on_event(Primitive(primitives[cell_index]))
          cell_index += 1
        }
        Group(name, children) => {
          on_event(Key(name))
          walk(children)
        }
      }
    }
    on_event(EndObject)
  }
  walk(fields)
}

///|
fn assert_fully_consumed(reader : LineReader) -> Unit raise @types.DecodeError {
  match reader.peek() {
    None => ()
    Some(line) =>
      raise error_on_line(
        UnexpectedContent,
        "unexpected content after document root",
        line,
        utf16_length=line.content.length(),
      )
  }
}

///|
fn check_duplicate_key(
  key : String,
  line : @lex.ParsedLine,
  seen_keys : Map[String, Bool]?,
  utf16_length~ : Int32 = 1,
) -> Unit raise @types.DecodeError {
  match seen_keys {
    None => ()
    Some(seen) => {
      if seen.contains(key) {
        raise error_on_line(
          DuplicateKey,
          "duplicate sibling key '\{key}'",
          line,
          utf16_length~,
        )
      }
      seen[key] = true
    }
  }
}

///|
fn clamp_length_hint(length : @bigint.BigInt) -> Int32 {
  if length.compare_int(0x7FFFFFFF) > 0 {
    0x7FFFFFFF
  } else {
    length.to_int()
  }
}

///|
fn over_indented_error(
  line : @lex.ParsedLine,
  expected_depth : Int32,
) -> @types.DecodeError {
  let len = if line.indent > 0 { line.indent } else { 1 }
  error_on_line(
    OverIndentation,
    "over-indented line: expected depth \{expected_depth}, but found \{line.depth}",
    line,
    utf16_offset=0,
    utf16_length=len,
  )
}

///|
fn depth_jump_error(
  line : @lex.ParsedLine,
  expected_depth : Int32,
) -> @types.DecodeError {
  let len = if line.indent > 0 { line.indent } else { 1 }
  error_on_line(
    DepthJump,
    "indentation depth jump: expected depth \{expected_depth}, but found \{line.depth}",
    line,
    utf16_offset=0,
    utf16_length=len,
  )
}

///|
fn keyless_header_error(
  header : @types.ArrayHeader,
  line : @lex.ParsedLine,
) -> @types.DecodeError {
  let msg = if header.keyed {
    "keyless keyed header is only valid at the document root"
  } else if !(header.fields is None) {
    "keyless header with a field list is only valid at the document root"
  } else {
    "keyless array header is only valid at the document root or as a list item"
  }
  error_on_line(
    KeylessHeaderMisuse,
    msg,
    line,
    utf16_length=line.content.length(),
  )
}
