///|
/// Source location for a TOON diagnostic. `line` and `column` are 1-based,
/// with line zero indicating that no line number is attached. `length`
/// gives the width of the caret underline.
#derive(Eq, @debug.Debug)
pub(all) struct Span {
  line : Int32
  column : Int32
  length : Int32
}

///|
/// Returns a span with `line` clamped to zero or above, and `column` and
/// `length` clamped to one or above. `length` defaults to one.
pub fn Span::at(line : Int32, column : Int32, length~ : Int32 = 1) -> Span {
  let safe_line = if line < 0 { 0 } else { line }
  let safe_col = if column < 1 { 1 } else { column }
  let safe_len = if length < 1 { 1 } else { length }
  { line: safe_line, column: safe_col, length: safe_len, }
}

///|
/// Classification of a TOON decoding failure. Use `code` for the stable
/// identifier associated with each variant.
#derive(Eq, @debug.Debug)
pub(all) enum ErrorKind {
  InvalidUtf8
  InvalidIndentation
  BlankLineInScope
  MalformedHeader
  HeaderDelimiterMismatch
  UnexpectedContent
  NumberOutOfRange
  MissingColon
  UnterminatedString
  InvalidEscape
  InvalidSurrogate
  TrailingCharacters
  CountMismatch
  WidthMismatch
  DuplicateKey
  DuplicateField
  DepthJump
  OverIndentation
  KeylessHeaderMisuse
  InvalidOption
}

///|
/// Returns a stable diagnostic error code string (e.g. `E_HEADER`).
pub fn ErrorKind::code(self : ErrorKind) -> String {
  match self {
    InvalidUtf8 => "E_UTF8"
    InvalidIndentation => "E_INDENT"
    BlankLineInScope => "E_BLANK"
    MalformedHeader => "E_HEADER"
    HeaderDelimiterMismatch => "E_HEADER_DELIM"
    UnexpectedContent => "E_UNEXPECTED"
    NumberOutOfRange => "E_NUMBER"
    MissingColon => "E_COLON"
    UnterminatedString => "E_STRING"
    InvalidEscape => "E_ESCAPE"
    InvalidSurrogate => "E_SURROGATE"
    TrailingCharacters => "E_TRAILING"
    CountMismatch => "E_COUNT"
    WidthMismatch => "E_WIDTH"
    DuplicateKey => "E_DUP_KEY"
    DuplicateField => "E_DUP_FIELD"
    DepthJump => "E_DEPTH"
    OverIndentation => "E_OVER_INDENT"
    KeylessHeaderMisuse => "E_KEYLESS"
    InvalidOption => "E_OPTION"
  }
}

///|
/// A TOON decoding failure with an `ErrorKind`, a descriptive message, a
/// source span, and an optional source line for display.
#derive(Eq, @debug.Debug)
pub(all) suberror DecodeError {
  DecodeError(
    kind~ : ErrorKind,
    message~ : String,
    span~ : Span,
    source_line~ : String?,
  )
}

///|
/// Returns a decode error with the given `kind` and `message`. The default
/// `span` has no line number, and `source_line` defaults to `None`.
pub fn DecodeError::new(
  kind~ : ErrorKind,
  message~ : String,
  span~ : Span = Span::at(0, 1, length=1),
  source_line~ : String? = None,
) -> DecodeError {
  DecodeError(kind~, message~, span~, source_line~)
}

///|
/// Returns a copy of the error on `line`, adding `col_offset` to its column
/// and keeping the result at least one. A supplied `source_line` replaces
/// the existing excerpt. `None` retains it.
pub fn DecodeError::at_line(
  self : DecodeError,
  line : Int32,
  source_line~ : String? = None,
  col_offset~ : Int32 = 0,
) -> DecodeError {
  match self {
    DecodeError(kind~, message~, span~, source_line=existing_src) => {
      let next_col = if span.column + col_offset < 1 {
        1
      } else {
        span.column + col_offset
      }
      let next_src = match source_line {
        Some(_) => source_line
        None => existing_src
      }
      DecodeError(
        kind~,
        message~,
        span=Span::at(line, next_col, length=span.length),
        source_line=next_src,
      )
    }
  }
}

///|
/// Returns the error code, message, and location when known. If the error
/// carries a source line, includes a caret underline and displays tabs as `→`.
pub fn DecodeError::format(self : DecodeError) -> String {
  match self {
    DecodeError(kind~, message~, span~, source_line~) => {
      let code = kind.code()
      let sb = StringBuilder()
      if span.line > 0 {
        sb.write_string(
          "DecodeError[\{code}] at line \{span.line}, column \{span.column}: \{message}",
        )
      } else {
        sb.write_string("DecodeError[\{code}]: \{message}")
      }
      match source_line {
        None => ()
        Some(raw) => {
          let line_str = if span.line > 0 { span.line.to_string() } else { "?" }
          let prefix = "  \{line_str} | "
          let blank_gutter = String::make(prefix.length() - 2, ' ') + "| "
          let visible = StringBuilder()
          for ch in raw {
            if ch == '\t' {
              visible.write_char('→')
            } else if ch == '\r' {
              ()
            } else {
              visible.write_char(ch)
            }
          }
          let visible_str = visible.to_string()
          let vis_len = visible_str.char_length()
          let col0 = if span.column <= 1 {
            0
          } else if span.column - 1 > vis_len {
            vis_len
          } else {
            span.column - 1
          }
          let caret_len = if span.length < 1 { 1 } else { span.length }
          sb.write_char('\n')
          sb.write_string(prefix)
          sb.write_string(visible_str)
          sb.write_char('\n')
          sb.write_string(blank_gutter)
          sb.write_string(String::make(col0, ' '))
          sb.write_string(String::make(caret_len, '^'))
        }
      }
      sb.to_string()
    }
  }
}

///|
/// A TOON encoding failure with a descriptive message and an optional JSON
/// path to the value that could not be encoded.
#derive(Eq, @debug.Debug)
pub(all) suberror EncodeError {
  EncodeError(message~ : String, path~ : String?)
}

///|
/// Returns a display string with the error message and its path, if present.
pub fn EncodeError::format(self : EncodeError) -> String {
  match self {
    EncodeError(message~, path=None) => "EncodeError: \{message}"
    EncodeError(message~, path=Some(p)) => "EncodeError at \{p}: \{message}"
  }
}
