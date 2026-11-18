///|
fn is_primitive_json(v : Json) -> Bool {
  match v {
    Null | True | False | Number(_, ..) | String(_) => true
    Array(_) | Object(_) => false
  }
}

///|
fn is_array_of_primitives(arr : Array[Json]) -> Bool {
  for item in arr {
    if !is_primitive_json(item) {
      return false
    }
  }
  true
}

///|
fn is_array_of_objects(arr : Array[Json]) -> Bool {
  for item in arr {
    match item {
      Object(_) => ()
      _ => return false
    }
  }
  true
}

///|
fn prepend_key_path(key : String, sub : String?) -> String? {
  match sub {
    None => Some(key)
    Some(p) =>
      if p.has_prefix("[") {
        Some(key + p)
      } else {
        Some(key + "." + p)
      }
  }
}

///|
fn prepend_index_path(idx : Int32, sub : String?) -> String? {
  let seg = "[\{idx}]"
  match sub {
    None => Some(seg)
    Some(p) =>
      if p.has_prefix("[") {
        Some(seg + p)
      } else {
        Some(seg + "." + p)
      }
  }
}

///|
fn indented_line(
  depth : Int32,
  content : String,
  indent_size : Int32,
) -> String {
  if depth <= 0 {
    content
  } else {
    String::make(depth * indent_size, ' ') + content
  }
}

///|
fn indented_list_item(
  depth : Int32,
  content : String,
  indent_size : Int32,
) -> String {
  indented_line(depth, "- " + content, indent_size)
}

///|
fn emit_head_line(
  depth : Int32,
  content : String,
  as_list_item : Bool,
  indent_size : Int32,
  emit : (String) -> Unit,
) -> Unit {
  if as_list_item {
    emit(indented_list_item(depth - 1, content, indent_size))
  } else {
    emit(indented_line(depth, content, indent_size))
  }
}

///|
fn format_inline_array(
  arr : Array[Json],
  delimiter : @types.Delimiter,
  key~ : String? = None,
) -> String raise @types.EncodeError {
  let header = format_header(arr.length(), key~, delimiter~)
  if arr.is_empty() {
    header
  } else {
    "\{header} \{encode_and_join_primitives(arr, delimiter, index_paths=true)}"
  }
}

///|
fn emit_tabular_rows(
  items : Array[Json],
  fields : Array[@types.FieldNode],
  depth : Int32,
  options : @types.EncodeOptions,
  emit : (String) -> Unit,
) -> Unit raise @types.EncodeError {
  for i, item in items {
    match item {
      Object(obj) => {
        let leaves : Array[Json] = []
        collect_row_leaves(obj, fields, leaves)
        let row_text = encode_and_join_primitives(leaves, options.delimiter) catch {
          @types.EncodeError(message~, path~) =>
            raise @types.EncodeError(message~, path=prepend_index_path(i, path))
        }
        emit(indented_line(depth, row_text, options.indent_size))
      }
      _ => ()
    }
  }
}

///|
fn encode_keyed_object(
  key : String?,
  obj : Map[String, Json],
  fields : Array[@types.FieldNode],
  depth : Int32,
  options : @types.EncodeOptions,
  emit : (String) -> Unit,
  as_list_item~ : Bool = false,
) -> Unit raise @types.EncodeError {
  let header = format_header(
    obj.length(),
    key~,
    fields=Some(fields),
    delimiter=options.delimiter,
    keyed=true,
  )
  emit_head_line(depth, header, as_list_item, options.indent_size, emit)
  for entry_key, entry_val in obj {
    match entry_val {
      Object(sub) => {
        let encoded_entry_key = encode_key(entry_key, path=Some(entry_key))
        let leaves : Array[Json] = []
        collect_row_leaves(sub, fields, leaves)
        let joined = encode_and_join_primitives(leaves, options.delimiter) catch {
          @types.EncodeError(message~, path~) =>
            raise @types.EncodeError(
              message~,
              path=prepend_key_path(entry_key, path),
            )
        }
        emit(
          indented_line(
            depth + 1,
            "\{encoded_entry_key}: \{joined}",
            options.indent_size,
          ),
        )
      }
      _ => ()
    }
  }
}

///|
fn encode_array(
  key : String?,
  arr : Array[Json],
  depth : Int32,
  options : @types.EncodeOptions,
  emit : (String) -> Unit,
  as_list_item~ : Bool = false,
) -> Unit raise @types.EncodeError {
  if arr.is_empty() {
    let line = match key {
      Some(k) => "\{encode_key(k, path=Some(k))}: []"
      None => "[]"
    }
    emit_head_line(depth, line, as_list_item, options.indent_size, emit)
    return
  }
  if is_array_of_primitives(arr) {
    let line = format_inline_array(arr, options.delimiter, key~)
    emit_head_line(depth, line, as_list_item, options.indent_size, emit)
    return
  }
  if is_array_of_objects(arr) {
    match extract_tabular_fields(arr) {
      Some(fields) => {
        let header = format_header(
          arr.length(),
          key~,
          fields=Some(fields),
          delimiter=options.delimiter,
        )
        emit_head_line(depth, header, as_list_item, options.indent_size, emit)
        emit_tabular_rows(arr, fields, depth + 1, options, emit)
        return
      }
      None => ()
    }
  }
  let header = format_header(arr.length(), key~, delimiter=options.delimiter)
  emit_head_line(depth, header, as_list_item, options.indent_size, emit)
  for i, item in arr {
    encode_list_item_value(item, depth + 1, options, emit) catch {
      @types.EncodeError(message~, path~) =>
        raise @types.EncodeError(message~, path=prepend_index_path(i, path))
    }
  }
}

///|
fn encode_list_item_value(
  value : Json,
  depth : Int32,
  options : @types.EncodeOptions,
  emit : (String) -> Unit,
) -> Unit raise @types.EncodeError {
  match value {
    Null | True | False | Number(_, ..) | String(_) =>
      emit(
        indented_list_item(
          depth,
          encode_primitive(value, options.delimiter),
          options.indent_size,
        ),
      )
    Array(arr) =>
      if is_array_of_primitives(arr) {
        let line = format_inline_array(arr, options.delimiter)
        emit(indented_list_item(depth, line, options.indent_size))
      } else {
        let header = format_header(arr.length(), delimiter=options.delimiter)
        emit(indented_list_item(depth, header, options.indent_size))
        for i, item in arr {
          encode_list_item_value(item, depth + 1, options, emit) catch {
            @types.EncodeError(message~, path~) =>
              raise @types.EncodeError(
                message~,
                path=prepend_index_path(i, path),
              )
          }
        }
      }
    Object(obj) => encode_object_as_list_item(obj, depth, options, emit)
  }
}

///|
fn encode_object_as_list_item(
  obj : Map[String, Json],
  depth : Int32,
  options : @types.EncodeOptions,
  emit : (String) -> Unit,
) -> Unit raise @types.EncodeError {
  if obj.is_empty() {
    emit(indented_line(depth, "-", options.indent_size))
    return
  }
  let mut is_first = true
  for key, val in obj {
    encode_key_value_pair(
      key,
      val,
      depth + 1,
      options,
      emit,
      as_list_item=is_first,
    )
    is_first = false
  }
}

///|
fn encode_key_value_pair(
  key : String,
  value : Json,
  depth : Int32,
  options : @types.EncodeOptions,
  emit : (String) -> Unit,
  as_list_item~ : Bool = false,
) -> Unit raise @types.EncodeError {
  let encoded_key = encode_key(key, path=Some(key))
  try {
    match value {
      Null | True | False | Number(_, ..) | String(_) => {
        let encoded_val = encode_primitive(value, options.delimiter)
        emit_head_line(
          depth,
          "\{encoded_key}: \{encoded_val}",
          as_list_item,
          options.indent_size,
          emit,
        )
      }
      Array(arr) =>
        encode_array(Some(key), arr, depth, options, emit, as_list_item~)
      Object(sub) =>
        match extract_keyed_tabular_fields(sub) {
          Some(keyed_fields) =>
            encode_keyed_object(
              Some(key),
              sub,
              keyed_fields,
              depth,
              options,
              emit,
              as_list_item~,
            )
          None => {
            emit_head_line(
              depth,
              "\{encoded_key}:",
              as_list_item,
              options.indent_size,
              emit,
            )
            if !sub.is_empty() {
              encode_object(sub, depth + 1, options, emit)
            }
          }
        }
    }
  } catch {
    @types.EncodeError(message~, path~) =>
      raise @types.EncodeError(message~, path=prepend_key_path(key, path))
  }
}

///|
fn encode_object(
  obj : Map[String, Json],
  depth : Int32,
  options : @types.EncodeOptions,
  emit : (String) -> Unit,
) -> Unit raise @types.EncodeError {
  for key, val in obj {
    encode_key_value_pair(key, val, depth, options, emit)
  }
}

///|
fn encode_root(
  value : Json,
  options : @types.EncodeOptions,
  emit : (String) -> Unit,
) -> Unit raise @types.EncodeError {
  match value {
    Null | True | False | Number(_, ..) | String(_) =>
      emit(encode_primitive(value, options.delimiter, is_root=true))
    Array(arr) => encode_array(None, arr, 0, options, emit)
    Object(obj) =>
      match extract_keyed_tabular_fields(obj) {
        Some(keyed_fields) =>
          encode_keyed_object(None, obj, keyed_fields, 0, options, emit)
        None => encode_object(obj, 0, options, emit)
      }
  }
}

///|
/// Streams TOON-encoded lines for `value` to `emit` without trailing spaces,
/// blank lines, or trailing newlines (§8–§12).
pub fn encode_to_lines(
  value : Json,
  emit : (String) -> Unit,
  options~ : @types.EncodeOptions = @types.EncodeOptions::default(),
) -> Unit raise @types.EncodeError {
  options.validate()
  encode_root(value, options, emit)
}

///|
/// Encodes `value` into an array of TOON lines using `options`.
pub fn encode_lines(
  value : Json,
  options~ : @types.EncodeOptions = @types.EncodeOptions::default(),
) -> Array[String] raise @types.EncodeError {
  let lines : Array[String] = []
  encode_to_lines(value, line => lines.push(line), options~)
  lines
}

///|
/// Encodes `value` into a LF-delimited TOON v4.4 string using `options`.
pub fn encode(
  value : Json,
  options~ : @types.EncodeOptions = @types.EncodeOptions::default(),
) -> String raise @types.EncodeError {
  let sb = StringBuilder()
  let mut first = true
  encode_to_lines(
    value,
    line => {
      if !first {
        sb.write_char('\n')
      }
      first = false
      sb.write_string(line)
    },
    options~,
  )
  sb.to_string()
}
