///|
fn is_canonical_decimal_int(r : String, is_negative : Bool) -> Bool {
  let len = r.length()
  if len == 0 {
    return false
  }
  let mut i = 0
  if is_negative {
    if r.unsafe_get(0) != 0x2D {
      return false
    }
    i = 1
    if i >= len {
      return false
    }
  } else if r.unsafe_get(0) == 0x2D {
    return false
  }
  let first = r.unsafe_get(i)
  if first < 0x31 || first > 0x39 {
    return false
  }
  for j in (i + 1)..<len {
    let cu = r.unsafe_get(j)
    if cu < 0x30 || cu > 0x39 {
      return false
    }
  }
  true
}

///|
/// Formats a JSON number according to TOON §2 and §3:
/// - `NaN` and `±Infinity` map to `"null"`
/// - `-0.0` and `0.0` normalize to `"0"`
/// - Preserves lossless integer `repr` when `|n| >= 2^53` and `repr` is a
///   canonical decimal integer string matching `n`'s sign.
pub fn format_number(n : Double, repr~ : String? = None) -> String {
  if !n.is_finite() {
    return "null"
  }
  if n == 0.0 {
    return "0"
  }
  match repr {
    Some(r) =>
      if n.abs() >= 9007199254740992.0 && is_canonical_decimal_int(r, n < 0.0) {
        return r
      }
    None => ()
  }
  n.to_string()
}

///|
fn quote_and_escape(s : String) -> String {
  let sb = StringBuilder(capacity=s.length() + 2)
  sb.write_char('"')
  sb.write_string(@lex.escape_string(s))
  sb.write_char('"')
  sb.to_string()
}

///|
/// Encodes a string value per TOON §7.1 and §7.2 under `delimiter`.
/// Validates against unpaired UTF-16 surrogates (§3) and quotes root strings
/// starting with `U+FEFF` (§7.2 / §12).
pub fn encode_string_literal(
  s : String,
  delimiter : @types.Delimiter,
  is_root~ : Bool = false,
  path~ : String? = None,
) -> String raise @types.EncodeError {
  @lex.check_no_unpaired_surrogates(s, path~)
  let needs_bom_quote = is_root && s.has_prefix("\u{feff}")
  if !needs_bom_quote && @lex.is_safe_unquoted(s, delimiter) {
    s
  } else {
    quote_and_escape(s)
  }
}

///|
/// Encodes an object key, entry key, or header field name per TOON §7.3.
/// Unquoted iff matching `/^[A-Za-z_][A-Za-z0-9_.]*$/`; otherwise quoted and
/// escaped per §7.1.
pub fn encode_key(
  key : String,
  path~ : String? = None,
) -> String raise @types.EncodeError {
  @lex.check_no_unpaired_surrogates(key, path~)
  if @lex.is_valid_unquoted_key(key) {
    key
  } else {
    quote_and_escape(key)
  }
}

///|
fn encode_primitive(
  value : Json,
  delimiter : @types.Delimiter,
  is_root~ : Bool = false,
) -> String raise @types.EncodeError {
  match value {
    Null => "null"
    True => "true"
    False => "false"
    Number(n, repr~) => format_number(n, repr~)
    String(s) => encode_string_literal(s, delimiter, is_root~)
    Array(_) | Object(_) =>
      raise @types.EncodeError(
        message="expected primitive JSON value",
        path=None,
      )
  }
}

///|
fn encode_and_join_primitives(
  values : Array[Json],
  delimiter : @types.Delimiter,
  index_paths~ : Bool = false,
) -> String raise @types.EncodeError {
  let delim_ch = delimiter.to_char()
  let sb = StringBuilder()
  for i, v in values {
    if i > 0 {
      sb.write_char(delim_ch)
    }
    let encoded = encode_primitive(v, delimiter) catch {
      @types.EncodeError(message~, path~) =>
        if index_paths && path is None {
          raise @types.EncodeError(message~, path=Some("[\{i}]"))
        } else {
          raise @types.EncodeError(message~, path~)
        }
    }
    sb.write_string(encoded)
  }
  sb.to_string()
}

///|
fn write_field_segment(
  fields : Array[@types.FieldNode],
  delim_ch : Char,
  sb : StringBuilder,
) -> Unit raise @types.EncodeError {
  for i, field in fields {
    if i > 0 {
      sb.write_char(delim_ch)
    }
    match field {
      Leaf(name) => sb.write_string(encode_key(name, path=Some(name)))
      Group(name, children) => {
        sb.write_string(encode_key(name, path=Some(name)))
        sb.write_char('{')
        write_field_segment(children, delim_ch, sb)
        sb.write_char('}')
      }
    }
  }
}

///|
/// Formats the inner field entries of a `{...}` header segment using
/// `delimiter`, recursing into nested field groups (§6, §9.3).
pub fn format_field_segment(
  fields : Array[@types.FieldNode],
  delimiter : @types.Delimiter,
) -> String raise @types.EncodeError {
  let sb = StringBuilder()
  write_field_segment(fields, delimiter.to_char(), sb)
  sb.to_string()
}

///|
/// Formats a TOON §6 / §9.5 array or keyed-tabular header line prefix ending
/// with `:`.
pub fn format_header(
  length : Int32,
  key~ : String? = None,
  fields~ : Array[@types.FieldNode]? = None,
  delimiter~ : @types.Delimiter = Comma,
  keyed~ : Bool = false,
) -> String raise @types.EncodeError {
  let sb = StringBuilder()
  match key {
    Some(k) => sb.write_string(encode_key(k, path=Some(k)))
    None => ()
  }
  sb.write_char('[')
  sb.write_string(length.to_string())
  if keyed {
    sb.write_char(':')
  }
  sb.write_string(delimiter.header_suffix())
  sb.write_char(']')
  match fields {
    Some(fs) => {
      sb.write_char('{')
      write_field_segment(fs, delimiter.to_char(), sb)
      sb.write_char('}')
    }
    None => ()
  }
  sb.write_char(':')
  sb.to_string()
}
