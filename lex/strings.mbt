///|
let cu_sp : UInt16 = 0x20

///|
let cu_tab : UInt16 = 0x09

///|
let cu_lf : UInt16 = 0x0A

///|
let cu_cr : UInt16 = 0x0D

///|
let cu_quote : UInt16 = 0x22

///|
let cu_backslash : UInt16 = 0x5C

///|
let cu_colon : UInt16 = 0x3A

///|
let cu_pipe : UInt16 = 0x7C

///|
let cu_lbracket : UInt16 = 0x5B

///|
let cu_rbracket : UInt16 = 0x5D

///|
let cu_lbrace : UInt16 = 0x7B

///|
let cu_rbrace : UInt16 = 0x7D

///|
let cu_hash : UInt16 = 0x23

///|
let cu_hyphen : UInt16 = 0x2D

///|
let cu_bom : UInt16 = 0xFEFF

///|
fn is_high_surrogate(cu : UInt16) -> Bool {
  cu >= 0xD800 && cu <= 0xDBFF
}

///|
fn is_low_surrogate(cu : UInt16) -> Bool {
  cu >= 0xDC00 && cu <= 0xDFFF
}

///|
fn is_surrogate_code(code : Int32) -> Bool {
  code >= 0xD800 && code <= 0xDFFF
}

///|
/// Trims leading and trailing ASCII space (`U+0020`) ONLY (TOON §12).
/// Never removes `HTAB`, `NBSP` (`U+00A0`), or other Unicode spaces.
pub fn trim_spaces(s : StringView) -> StringView {
  let (trimmed, _) = trim_spaces_with_offset(s)
  trimmed
}

///|
/// Trims ASCII space (`U+0020`) ONLY and returns `(trimmed, leading_count)`.
pub fn trim_spaces_with_offset(s : StringView) -> (StringView, Int32) {
  let len = s.length()
  let mut start = 0
  while start < len && s[start] == cu_sp {
    start += 1
  }
  let mut end = len
  while end > start && s[end - 1] == cu_sp {
    end -= 1
  }
  (s[start:end], start)
}

///|
/// Trims trailing ASCII space (`U+0020`) ONLY.
pub fn trim_trailing_spaces(s : StringView) -> StringView {
  let mut end = s.length()
  while end > 0 && s[end - 1] == cu_sp {
    end -= 1
  }
  s[0:end]
}

///|
/// Trims leading and trailing ASCII whitespace (`SP` and `HTAB` only).
pub fn trim_ascii_whitespace(s : StringView) -> StringView {
  let len = s.length()
  let mut start = 0
  while start < len && (s[start] == cu_sp || s[start] == cu_tab) {
    start += 1
  }
  let mut end = len
  while end > start && (s[end - 1] == cu_sp || s[end - 1] == cu_tab) {
    end -= 1
  }
  s[start:end]
}

///|
/// Returns `true` if `s` ends with ASCII `SP` or `HTAB`.
pub fn ends_with_ascii_whitespace(s : StringView) -> Bool {
  let len = s.length()
  if len == 0 {
    return false
  }
  let last = s[len - 1]
  last == cu_sp || last == cu_tab
}

///|
/// Converts a 0-based UTF-16 code-unit offset inside `s` into a 1-based Unicode
/// scalar column index for accurate error caret alignment.
pub fn utf16_offset_to_column(s : StringView, utf16_offset : Int32) -> Int32 {
  let len = s.length()
  let limit = if utf16_offset < 0 {
    0
  } else if utf16_offset > len {
    len
  } else {
    utf16_offset
  }
  let mut col = 1
  let mut i = 0
  while i < limit {
    let cu = s[i]
    if is_high_surrogate(cu) && i + 1 < len && is_low_surrogate(s[i + 1]) {
      i += 2
    } else {
      i += 1
    }
    col += 1
  }
  col
}

///|
/// Validates that `s` contains no unpaired UTF-16 surrogates (`U+D800..U+DFFF`).
pub fn check_no_unpaired_surrogates(
  s : StringView,
  path~ : String? = None,
) -> Unit raise @types.EncodeError {
  let len = s.length()
  let mut i = 0
  while i < len {
    let cu = s[i]
    if is_high_surrogate(cu) {
      if i + 1 < len && is_low_surrogate(s[i + 1]) {
        i += 2
        continue
      }
      raise @types.EncodeError(
        message="unpaired UTF-16 high surrogate in string",
        path~,
      )
    } else if is_low_surrogate(cu) {
      raise @types.EncodeError(
        message="unpaired UTF-16 low surrogate in string",
        path~,
      )
    }
    i += 1
  }
}

///|
/// Finds the UTF-16 index of the closing `"` matching the opening `"` at
/// `open_idx`, respecting `\\` and `\"` escape sequences.
pub fn find_closing_quote(s : StringView, open_idx : Int32) -> Int32? {
  let len = s.length()
  let mut i = open_idx + 1
  while i < len {
    let cu = s[i]
    if cu == cu_backslash {
      i += 2
      continue
    }
    if cu == cu_quote {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// Finds the UTF-16 index of the first unquoted occurrence of ASCII `target`
/// starting at `start`.
pub fn find_unquoted_char(
  s : StringView,
  target : Char,
  start~ : Int32 = 0,
) -> Int32? {
  let len = s.length()
  let target_cu = target.to_int().to_uint16()
  let mut in_quotes = false
  let mut i = start
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
    if !in_quotes && cu == target_cu {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// Checks whether `s` contains an unquoted delimiter differing from `expected`.
pub fn find_unquoted_mismatched_delimiter(
  s : StringView,
  expected : @types.Delimiter,
) -> @types.Delimiter? {
  let candidates : Array[@types.Delimiter] = [Comma, Tab, Pipe]
  for cand in candidates {
    if cand == expected {
      continue
    }
    match find_unquoted_char(s, cand.to_char()) {
      Some(_) => return Some(cand)
      None => ()
    }
  }
  None
}

///|
fn hex_digit_lower(n : Int32) -> Char {
  if n < 10 {
    (0x30 + n).unsafe_to_char()
  } else {
    (0x61 + (n - 10)).unsafe_to_char()
  }
}

///|
fn parse_hex_digit(cu : UInt16) -> Int32? {
  if cu >= 0x30 && cu <= 0x39 {
    Some((cu - 0x30).to_int())
  } else if cu >= 0x61 && cu <= 0x66 {
    Some((cu - 0x61).to_int() + 10)
  } else if cu >= 0x41 && cu <= 0x46 {
    Some((cu - 0x41).to_int() + 10)
  } else {
    None
  }
}

///|
/// Escapes a string value or key according to TOON §7.1:
/// `\\`, `\"`, `\n`, `\r`, `\t`, and `\u00xx` (lowercase hex) for ASCII
/// control characters `U+0000..U+001F`. Other BMP and supplementary scalars
/// (including `U+007F`, `U+0085`, `U+2028`, and emojis) stay literal.
pub fn escape_string(s : StringView) -> String {
  let sb = StringBuilder(capacity=s.length() + 4)
  for ch in s {
    let code = ch.to_int()
    if ch == '\\' {
      sb.write_string("\\\\")
    } else if ch == '"' {
      sb.write_string("\\\"")
    } else if ch == '\n' {
      sb.write_string("\\n")
    } else if ch == '\r' {
      sb.write_string("\\r")
    } else if ch == '\t' {
      sb.write_string("\\t")
    } else if code < 0x20 {
      sb.write_string("\\u00")
      sb.write_char(hex_digit_lower((code >> 4) & 0xF))
      sb.write_char(hex_digit_lower(code & 0xF))
    } else {
      sb.write_char(ch)
    }
  }
  sb.to_string()
}

///|
/// Unescapes the inner body of a quoted TOON string per §7.1.
/// Accepts ONLY `\\`, `\"`, `\n`, `\r`, `\t`, and `\uXXXX` (rejecting
/// surrogates `U+D800..U+DFFF`, truncated `\u`, invalid hex, and unknown escapes).
pub fn unescape_string(
  s : StringView,
  col_offset~ : Int32 = 0,
) -> String raise @types.DecodeError {
  let len = s.length()
  let sb = StringBuilder(capacity=len)
  let mut i = 0
  while i < len {
    let cu = s[i]
    if is_high_surrogate(cu) {
      if i + 1 < len && is_low_surrogate(s[i + 1]) {
        match s.get_char(i) {
          Some(ch) => sb.write_char(ch)
          None => ()
        }
        i += 2
        continue
      }
      raise @types.DecodeError::new(
        kind=InvalidSurrogate,
        message="unpaired UTF-16 surrogate in string",
        span=@types.Span::at(0, 1 + col_offset + i, length=1),
      )
    }
    if is_low_surrogate(cu) {
      raise @types.DecodeError::new(
        kind=InvalidSurrogate,
        message="unpaired UTF-16 surrogate in string",
        span=@types.Span::at(0, 1 + col_offset + i, length=1),
      )
    }
    if cu != cu_backslash {
      sb.write_char(cu.to_int().unsafe_to_char())
      i += 1
      continue
    }
    if i + 1 >= len {
      raise @types.DecodeError::new(
        kind=InvalidEscape,
        message="trailing backslash in quoted string",
        span=@types.Span::at(0, 1 + col_offset + i, length=1),
      )
    }
    let next = s[i + 1]
    if next == cu_backslash {
      sb.write_char('\\')
      i += 2
    } else if next == cu_quote {
      sb.write_char('"')
      i += 2
    } else if next == 0x6E {
      // 'n'
      sb.write_char('\n')
      i += 2
    } else if next == 0x72 {
      // 'r'
      sb.write_char('\r')
      i += 2
    } else if next == 0x74 {
      // 't'
      sb.write_char('\t')
      i += 2
    } else if next == 0x75 {
      // 'u'
      if i + 5 >= len {
        raise @types.DecodeError::new(
          kind=InvalidEscape,
          message="truncated \\uXXXX escape sequence",
          span=@types.Span::at(0, 1 + col_offset + i, length=len - i),
        )
      }
      let mut code = 0
      for j in 0..<4 {
        let hex_cu = s[i + 2 + j]
        match parse_hex_digit(hex_cu) {
          Some(d) => code = (code << 4) | d
          None =>
            raise @types.DecodeError::new(
              kind=InvalidEscape,
              message="invalid hex digit in \\uXXXX escape sequence",
              span=@types.Span::at(0, 1 + col_offset + i, length=6),
            )
        }
      }
      if is_surrogate_code(code) {
        raise @types.DecodeError::new(
          kind=InvalidSurrogate,
          message="surrogate code point \\uXXXX is forbidden in TOON strings",
          span=@types.Span::at(0, 1 + col_offset + i, length=6),
        )
      }
      sb.write_char(code.unsafe_to_char())
      i += 6
    } else {
      let esc_ch = next.to_int().unsafe_to_char()
      raise @types.DecodeError::new(
        kind=InvalidEscape,
        message="invalid escape sequence '\\\{esc_ch}'",
        span=@types.Span::at(0, 1 + col_offset + i, length=2),
      )
    }
  }
  sb.to_string()
}

///|
/// Parses a quoted or unquoted string literal token per §7.4.
/// Enforces quoted-token boundary: if trimmed token begins with `"`, the
/// matching closing `"` must be its final character.
pub fn parse_string_literal(
  s : StringView,
  col_offset~ : Int32 = 0,
) -> String raise @types.DecodeError {
  let (trimmed, lead) = trim_spaces_with_offset(s)
  if trimmed.is_empty() {
    return ""
  }
  if trimmed[0] == cu_quote {
    match find_closing_quote(trimmed, 0) {
      None =>
        raise @types.DecodeError::new(
          kind=UnterminatedString,
          message="unterminated string: missing closing quote",
          span=@types.Span::at(
            0,
            1 + col_offset + lead,
            length=trimmed.length(),
          ),
        )
      Some(close_idx) => {
        if close_idx != trimmed.length() - 1 {
          raise @types.DecodeError::new(
            kind=TrailingCharacters,
            message="unexpected characters after closing quote",
            span=@types.Span::at(
              0,
              1 + col_offset + lead + close_idx + 1,
              length=trimmed.length() - 1 - close_idx,
            ),
          )
        }
        unescape_string(trimmed[1:close_idx], col_offset=col_offset + lead + 1)
      }
    }
  } else {
    trimmed.to_owned()
  }
}

///|
/// Parses a key token starting at UTF-16 index `start` in `s` up through `:`.
/// Returns `(decoded_key, index_after_colon)`.
pub fn parse_key_token(
  s : StringView,
  start~ : Int32 = 0,
  col_offset~ : Int32 = 0,
) -> (String, Int32) raise @types.DecodeError {
  let len = s.length()
  if start < len && s[start] == cu_quote {
    match find_closing_quote(s, start) {
      None =>
        raise @types.DecodeError::new(
          kind=UnterminatedString,
          message="unterminated quoted key",
          span=@types.Span::at(0, 1 + col_offset + start, length=len - start),
        )
      Some(close_idx) => {
        let key = unescape_string(
          s[start + 1:close_idx],
          col_offset=col_offset + start + 1,
        )
        let mut pos = close_idx + 1
        while pos < len && s[pos] == cu_sp {
          pos += 1
        }
        if pos >= len || s[pos] != cu_colon {
          raise @types.DecodeError::new(
            kind=MissingColon,
            message="missing colon after quoted key",
            span=@types.Span::at(0, 1 + col_offset + pos, length=1),
          )
        }
        (key, pos + 1)
      }
    }
  } else {
    match find_unquoted_char(s, ':', start~) {
      None =>
        raise @types.DecodeError::new(
          kind=MissingColon,
          message="missing colon after key",
          span=@types.Span::at(0, 1 + col_offset + start, length=1),
        )
      Some(colon_idx) => {
        let key = trim_spaces(s[start:colon_idx]).to_owned()
        (key, colon_idx + 1)
      }
    }
  }
}
