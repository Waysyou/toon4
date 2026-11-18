///|
/// 1-based source location span used in TOON diagnostics.
#derive(Eq, @debug.Debug)
pub(all) struct Span {
  line : Int32
  column : Int32
  length : Int32
}

///|
/// Constructs a `Span` (clamping `line`, `column`, and `length` to `>= 1`
/// unless `line == 0` indicates an unattached line).
pub fn Span::at(line : Int32, column : Int32, length~ : Int32 = 1) -> Span {
  let safe_line = if line < 0 { 0 } else { line }
  let safe_col = if column < 1 { 1 } else { column }
  let safe_len = if length < 1 { 1 } else { length }
  { line: safe_line, column: safe_col, length: safe_len, }
}

///|
/// Machine-matchable error classification for TOON decoding failures.
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
/// Structured TOON decode error carrying diagnostic kind, human message,
/// 1-based line/column span, and optional offending source line.
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
/// Constructs a `DecodeError` with optional span and source line context.
pub fn DecodeError::new(
  kind~ : ErrorKind,
  message~ : String,
  span~ : Span = Span::at(0, 1, length=1),
  source_line~ : String? = None,
) -> DecodeError {
  DecodeError(kind~, message~, span~, source_line~)
}

///|
/// Returns a copy of this `DecodeError` bound to a specific 1-based line and
/// optional source line, adjusting column by `col_offset` if desired.
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
/// Renders the error as a multi-line human-readable diagnostic with source line
/// and `^` caret underline (visualizing `\t` as `→`).
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
/// Structured TOON encode error (e.g. invalid options or unpaired UTF-16 surrogates).
#derive(Eq, @debug.Debug)
pub(all) suberror EncodeError {
  EncodeError(message~ : String, path~ : String?)
}

///|
/// Formats an `EncodeError` for display.
pub fn EncodeError::format(self : EncodeError) -> String {
  match self {
    EncodeError(message~, path=None) => "EncodeError: \{message}"
    EncodeError(message~, path=Some(p)) => "EncodeError at \{p}: \{message}"
  }
}
