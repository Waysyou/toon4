///|
/// Re-exports codec options, TOON data types, and diagnostic types.
pub using @types {
  type Delimiter,
  type FieldNode,
  type ArrayHeader,
  type StreamEvent,
  type EncodeOptions,
  type DecodeOptions,
  type Span,
  type ErrorKind,
  type DecodeError,
  type EncodeError,
}

///|
/// Re-exports the advisor's measurements, findings, and recommendations.
pub using @advisor {
  type VerdictKind,
  type FormatStats,
  type StructuralAudit,
  type FallbackReason,
  type FallbackFinding,
  type CostReport,
  type TextMetrics,
}

///|
/// Returns the supported TOON specification version, `"4.4"`.
pub fn spec_version() -> String {
  "4.4"
}

///|
/// Encodes `value` as LF-separated TOON v4.4 text without a trailing newline.
/// `options` controls indentation and delimiters. Raises `EncodeError` on failure.
pub fn encode(
  value : Json,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> String raise EncodeError {
  @encode.encode(value, options~)
}

///|
/// Returns the TOON v4.4 lines for `value` without line terminators.
/// `options` controls indentation and delimiters. Raises `EncodeError` on failure.
pub fn encode_lines(
  value : Json,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> Array[String] raise EncodeError {
  @encode.encode_lines(value, options~)
}

///|
/// Calls `emit` in order for each TOON v4.4 line of `value`, without its line
/// terminator. `options` controls indentation and delimiters. An `EncodeError`
/// can occur after some lines have been emitted.
pub fn encode_to_lines(
  value : Json,
  emit : (String) -> Unit,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> Unit raise EncodeError {
  @encode.encode_to_lines(value, emit, options~)
}

///|
/// Decodes TOON v4.4 `input` into a `Json` value. `options` controls indentation
/// and strict validation. Raises `DecodeError` if decoding fails.
pub fn decode(
  input : String,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Json raise DecodeError {
  @decode.decode(input, options~)
}

///|
/// Decodes TOON v4.4 `bytes` as UTF-8 and returns the resulting `Json` value.
/// `options` controls TOON indentation and strict validation. Invalid UTF-8
/// always raises `DecodeError`, as do TOON errors under the selected options.
pub fn decode_bytes(
  bytes : BytesView,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Json raise DecodeError {
  @decode.decode_bytes(bytes, options~)
}

///|
/// Calls `on_event` for each event decoded from TOON v4.4 `input`.
/// `options` controls indentation and strict validation. Decode errors and
/// `DecodeError` values raised by `on_event` propagate to the caller.
pub fn decode_stream(
  input : String,
  on_event : (StreamEvent) -> Unit raise DecodeError,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Unit raise DecodeError {
  @decode.decode_stream(input, on_event, options~)
}

///|
/// Pulls one TOON line at a time from `next_line`, which returns `None` at EOF,
/// and passes decoded events to `on_event`. `options` controls indentation and
/// strict validation. Decode errors and callback `DecodeError` values propagate.
pub fn decode_stream_lines(
  next_line : () -> String?,
  on_event : (StreamEvent) -> Unit raise DecodeError,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Unit raise DecodeError {
  @decode.decode_stream_lines(next_line, on_event, options~)
}

///|
/// Compares `value` as pretty JSON, compact JSON, and comma-, tab-, and
/// pipe-delimited TOON. `indent_size` sets spaces per level for pretty JSON and
/// TOON. Returns format metrics, tabular coverage, and a recommendation, or
/// raises `EncodeError` if TOON encoding fails.
pub fn analyze(
  value : Json,
  indent_size~ : Int32 = 2,
) -> CostReport raise EncodeError {
  @advisor.analyze(value, indent_size~)
}

///|
/// Returns UTF-8 byte and Unicode scalar counts for `text`, plus syntax overhead
/// and a heuristic BPE token estimate.
pub fn measure_text(text : String) -> TextMetrics {
  @advisor.measure_text(text)
}

///|
/// Returns a diagnostic string for `err`, including its code and message.
/// Adds a location and a caret under the source excerpt when available.
pub fn format_decode_error(err : DecodeError) -> String {
  err.format()
}

///|
/// Returns a diagnostic string with the message and any JSON path carried by `err`.
pub fn format_encode_error(err : EncodeError) -> String {
  err.format()
}
