///|
/// Pull-based line reader producing preprocessed non-blank, non-comment
/// `@lex.ParsedLine` records with at most one line of lookahead so scanner
/// errors and blank-line accounting preserve exact input order.
pub struct LineReader {
  priv next_raw : () -> String?
  mut lookahead : @lex.ParsedLine?
  mut done : Bool
  mut last_line : @lex.ParsedLine?
  scan_state : @lex.ScanState
  indent_size : Int32
  strict : Bool
}

///|
/// Creates a `LineReader` pulling raw lines from `next_raw`.
pub fn LineReader::new(
  next_raw : () -> String?,
  indent_size~ : Int32 = 2,
  strict~ : Bool = true,
) -> LineReader {
  {
    next_raw,
    lookahead: None,
    done: false,
    last_line: None,
    scan_state: @lex.ScanState::new(),
    indent_size,
    strict,
  }
}

///|
fn LineReader::fill(self : LineReader) -> Unit raise @types.DecodeError {
  while self.lookahead is None && !self.done {
    match (self.next_raw)() {
      None => self.done = true
      Some(raw) => {
        let parsed = @lex.scan_line_incremental(
          raw,
          self.scan_state,
          self.indent_size,
          self.strict,
        )
        if parsed is Some(_) {
          self.lookahead = parsed
        }
      }
    }
  }
}

///|
/// Returns the next preprocessed line without consuming it.
pub fn LineReader::peek(
  self : LineReader,
) -> @lex.ParsedLine? raise @types.DecodeError {
  self.fill()
  self.lookahead
}

///|
/// Consumes and returns the next preprocessed line, updating `last_line`.
pub fn LineReader::read(
  self : LineReader,
) -> @lex.ParsedLine? raise @types.DecodeError {
  self.fill()
  let line = self.lookahead
  if line is Some(_) {
    self.lookahead = None
    self.last_line = line
  }
  line
}
