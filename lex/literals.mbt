///|
fn is_ascii_digit(cu : UInt16) -> Bool {
  cu >= 0x30 && cu <= 0x39
}

///|
fn is_ascii_alpha_or_underscore(cu : UInt16) -> Bool {
  (cu >= 0x41 && cu <= 0x5A) || (cu >= 0x61 && cu <= 0x7A) || cu == 0x5F
}

///|
fn is_ascii_key_rest(cu : UInt16) -> Bool {
  is_ascii_alpha_or_underscore(cu) || is_ascii_digit(cu) || cu == 0x2E // '.'
}

///|
/// Returns `true` iff `s` matches `/^[A-Za-z_][A-Za-z0-9_.]*$/` (TOON §7.3),
/// so it may be emitted as an unquoted key or header field name.
pub fn is_valid_unquoted_key(s : StringView) -> Bool {
  let len = s.length()
  if len == 0 {
    return false
  }
  if !is_ascii_alpha_or_underscore(s[0]) {
    return false
  }
  for i in 1..<len {
    if !is_ascii_key_rest(s[i]) {
      return false
    }
  }
  true
}

///|
/// Exact DFA for TOON §4 unquoted number decoding:
/// `/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/`
/// Rejects leading zeros (`05`, `-05`), leading `+`, trailing `.`, bare `.5`,
/// `Infinity`, `NaN`, hex (`0x10`), and underscores (`1_000`).
pub fn is_numeric_literal(s : StringView) -> Bool {
  let len = s.length()
  if len == 0 {
    return false
  }
  let mut i = 0
  if s[i] == cu_hyphen {
    i += 1
    if i >= len {
      return false
    }
  }
  if s[i] == 0x30 {
    i += 1
  } else if s[i] >= 0x31 && s[i] <= 0x39 {
    i += 1
    while i < len && is_ascii_digit(s[i]) {
      i += 1
    }
  } else {
    return false
  }
  if i < len && s[i] == 0x2E {
    i += 1
    if i >= len || !is_ascii_digit(s[i]) {
      return false
    }
    while i < len && is_ascii_digit(s[i]) {
      i += 1
    }
  }
  if i < len && (s[i] == 0x65 || s[i] == 0x45) {
    i += 1
    if i < len && (s[i] == 0x2B || s[i] == cu_hyphen) {
      i += 1
    }
    if i >= len || !is_ascii_digit(s[i]) {
      return false
    }
    while i < len && is_ascii_digit(s[i]) {
      i += 1
    }
  }
  i == len
}

///|
/// Exact DFA for TOON §7.2 encoder numeric-like quoting check:
/// `/^[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/`
pub fn is_numeric_like(s : StringView) -> Bool {
  let len = s.length()
  if len == 0 {
    return false
  }
  let mut i = 0
  if s[i] == 0x2B || s[i] == cu_hyphen {
    i += 1
    if i >= len {
      return false
    }
  }
  if !is_ascii_digit(s[i]) {
    return false
  }
  while i < len && is_ascii_digit(s[i]) {
    i += 1
  }
  if i < len && s[i] == 0x2E {
    i += 1
    if i >= len || !is_ascii_digit(s[i]) {
      return false
    }
    while i < len && is_ascii_digit(s[i]) {
      i += 1
    }
  }
  if i < len && (s[i] == 0x65 || s[i] == 0x45) {
    i += 1
    if i < len && (s[i] == 0x2B || s[i] == cu_hyphen) {
      i += 1
    }
    if i >= len || !is_ascii_digit(s[i]) {
      return false
    }
    while i < len && is_ascii_digit(s[i]) {
      i += 1
    }
  }
  i == len
}

///|
/// Returns `true` iff `s` can be emitted unquoted per TOON §7.2 under `delimiter`.
/// (Note: root strings starting with `U+FEFF` must additionally be quoted by
/// the root encoder per §7.2 / §12.)
pub fn is_safe_unquoted(s : StringView, delimiter : @types.Delimiter) -> Bool {
  let len = s.length()
  if len == 0 {
    return false
  }
  let first = s[0]
  let last = s[len - 1]
  // Leading or trailing SP/HTAB
  if first == cu_sp || first == cu_tab || last == cu_sp || last == cu_tab {
    return false
  }
  // Starts with '-' or '#'
  if first == cu_hyphen || first == cu_hash {
    return false
  }
  // Exact reserved words or numeric-like tokens
  if s == "true" || s == "false" || s == "null" {
    return false
  }
  if is_numeric_like(s) {
    return false
  }
  let delim_cu = delimiter.to_char().to_int().to_uint16()
  for i in 0..<len {
    let cu = s[i]
    if cu < 0x20 {
      // Controls U+0000..U+001F (includes HTAB, LF, CR)
      return false
    }
    if cu == delim_cu ||
      cu == cu_colon ||
      cu == cu_quote ||
      cu == cu_backslash ||
      cu == cu_lbracket ||
      cu == cu_rbracket ||
      cu == cu_lbrace ||
      cu == cu_rbrace {
      return false
    }
  }
  true
}

///|
/// Formats a JSON numeric spelling as TOON without rounding its decimal digits.
pub fn canonical_number_repr(input : StringView) -> String? {
  guard is_numeric_literal(input) else { return None }
  let negative = input[0] == cu_hyphen
  let start = if negative { 1 } else { 0 }
  let length = input.length()
  let exponent_at = input
    .find_code_unit(0x65)
    .unwrap_or(input.find_code_unit(0x45).unwrap_or(length))
  let mantissa = input[start:exponent_at]
  let point = mantissa.find_code_unit(0x2E).unwrap_or(mantissa.length())
  let digits = if point == mantissa.length() {
    mantissa.to_owned()
  } else {
    mantissa[:point].to_owned() + mantissa[point + 1:].to_owned()
  }
  let mut first = 0
  while first < digits.length() && digits[first] == 0x30 {
    first += 1
  }
  if first == digits.length() {
    return Some("0")
  }
  let mut end = digits.length()
  while digits[end - 1] == 0x30 {
    end -= 1
  }
  let significant = digits[first:end]
  let mut power = @bigint.BigInt::from_int(point - first - 1)
  if exponent_at < length {
    let start = if input[exponent_at + 1] == 0x2B {
      exponent_at + 2
    } else {
      exponent_at + 1
    }
    let exponent = @string.parse_bigint(input[start:]) catch {
      _ => return None
    }
    power = power + exponent
  }
  let magnitude = if power >= @bigint.BigInt::from_int(-6) &&
    power < @bigint.BigInt::from_int(21) {
    let decimal_point = power.to_int() + 1
    if decimal_point <= 0 {
      "0." + "0".repeat(-decimal_point) + significant.to_owned()
    } else if decimal_point >= significant.length() {
      significant.to_owned() + "0".repeat(decimal_point - significant.length())
    } else {
      significant[:decimal_point].to_owned() +
      "." +
      significant[decimal_point:].to_owned()
    }
  } else {
    let coefficient = if significant.length() == 1 {
      significant.to_owned()
    } else {
      significant[:1].to_owned() + "." + significant[1:].to_owned()
    }
    let sign = if power < @bigint.BigInt::from_int(0) { "" } else { "+" }
    "\{coefficient}e\{sign}\{power}"
  }
  Some(if negative { "-" + magnitude } else { magnitude })
}

///|
/// Decodes an unquoted or quoted primitive token per TOON §4.
pub fn parse_primitive_token(
  token : StringView,
  col_offset~ : Int32 = 0,
) -> Json raise @types.DecodeError {
  let (trimmed, lead) = trim_spaces_with_offset(token)
  if trimmed.is_empty() {
    return Json::string("")
  }
  if trimmed[0] == cu_quote {
    let s = parse_string_literal(trimmed, col_offset=col_offset + lead)
    return Json::string(s)
  }
  if trimmed == "true" {
    return Json::boolean(true)
  }
  if trimmed == "false" {
    return Json::boolean(false)
  }
  if trimmed == "null" {
    return Json::null()
  }
  if is_numeric_literal(trimmed) {
    let parsed = @json.parse(trimmed, preserve_number_repr=true) catch {
      _ => Json::null()
    }
    guard parsed is Number(n, ..) && n.is_finite() else {
      raise @types.DecodeError::new(
        kind=NumberOutOfRange,
        message="number is outside the supported floating-point range",
        span=@types.Span::at(0, col_offset + lead + 1, length=trimmed.length()),
      )
    }
    if n == 0.0 {
      // The retained spelling distinguishes a true zero from an underflow.
      if canonical_number_repr(trimmed) == Some("0") {
        return Json::number(0.0)
      }
      return Json::number(0.0, repr=trimmed.to_owned())
    }
    return parsed
  }
  Json::string(trimmed.to_owned())
}

///|
/// Splits a delimited row or inline array payload on unquoted `delimiter`,
/// returning `(trimmed_token_view, token_utf16_offset)` pairs.
/// An empty `input` returns an empty array `[]` (0 tokens).
pub fn split_delimited_values(
  input : StringView,
  delimiter : @types.Delimiter,
) -> Array[(StringView, Int32)] {
  let len = input.length()
  if len == 0 {
    return []
  }
  let delim_cu = delimiter.to_char().to_int().to_uint16()
  let out : Array[(StringView, Int32)] = []
  let mut seg_start = 0
  let mut in_quotes = false
  let mut i = 0
  while i < len {
    let cu = input[i]
    if in_quotes && cu == cu_backslash && i + 1 < len {
      i += 2
      continue
    }
    if cu == cu_quote {
      in_quotes = !in_quotes
      i += 1
      continue
    }
    if !in_quotes && cu == delim_cu {
      let (tok, lead) = trim_spaces_with_offset(input[seg_start:i])
      out.push((tok, seg_start + lead))
      seg_start = i + 1
    }
    i += 1
  }
  let (last_tok, last_lead) = trim_spaces_with_offset(input[seg_start:len])
  out.push((last_tok, seg_start + last_lead))
  out
}
