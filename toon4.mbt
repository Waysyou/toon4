///|
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
/// Supported TOON specification version targeted by `waysyou/toon4`.
pub fn spec_version() -> String {
  "4.4"
}

///|
/// Encodes a `Json` value into a TOON v4.4 string.
pub fn encode(
  value : Json,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> String raise EncodeError {
  @encode.encode(value, options~)
}

///|
/// Encodes a `Json` value into an array of TOON v4.4 lines.
pub fn encode_lines(
  value : Json,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> Array[String] raise EncodeError {
  @encode.encode_lines(value, options~)
}

///|
/// Streams TOON v4.4 lines for `value` directly to `emit`.
pub fn encode_to_lines(
  value : Json,
  emit : (String) -> Unit,
  options~ : EncodeOptions = EncodeOptions::default(),
) -> Unit raise EncodeError {
  @encode.encode_to_lines(value, emit, options~)
}

///|
/// Decodes a TOON v4.4 document string into a `Json` value.
pub fn decode(
  input : String,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Json raise DecodeError {
  @decode.decode(input, options~)
}

///|
/// Strictly validates UTF-8 bytes and decodes a TOON v4.4 document into `Json`.
pub fn decode_bytes(
  bytes : BytesView,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Json raise DecodeError {
  @decode.decode_bytes(bytes, options~)
}

///|
/// Streams `@types.StreamEvent` values from a TOON v4.4 document string.
pub fn decode_stream(
  input : String,
  on_event : (StreamEvent) -> Unit raise DecodeError,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Unit raise DecodeError {
  @decode.decode_stream(input, on_event, options~)
}

///|
/// Streams `@types.StreamEvent` values by pulling lines lazily from `next_line`.
pub fn decode_stream_lines(
  next_line : () -> String?,
  on_event : (StreamEvent) -> Unit raise DecodeError,
  options~ : DecodeOptions = DecodeOptions::default(),
) -> Unit raise DecodeError {
  @decode.decode_stream_lines(next_line, on_event, options~)
}

///|
/// Evaluates `value` across Pretty JSON, Compact JSON, and TOON (comma, tab,
/// pipe), returning byte/token comparisons, tabular coverage, and verdict.
pub fn analyze(
  value : Json,
  indent_size~ : Int32 = 2,
) -> CostReport raise EncodeError {
  @advisor.analyze(value, indent_size~)
}

///|
/// Measures exact UTF-8 bytes, syntax overhead bytes, and heuristic BPE tokens.
pub fn measure_text(text : String) -> TextMetrics {
  @advisor.measure_text(text)
}

///|
/// Formats a `DecodeError` with line/column span and source caret underline.
pub fn format_decode_error(err : DecodeError) -> String {
  err.format()
}

///|
/// Formats an `EncodeError` for human display.
pub fn format_encode_error(err : EncodeError) -> String {
  err.format()
}
