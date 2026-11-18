///|
priv struct ObjFrame {
  map : Map[String, Json]
  mut current_key : String?
}

///|
priv enum BuildFrame {
  Obj(ObjFrame)
  Arr(Array[Json])
}

///|
fn attach_value(
  stack : Array[BuildFrame],
  root : Ref[Json?],
  val : Json,
) -> Unit raise @types.DecodeError {
  if stack.is_empty() {
    match root.val {
      Some(_) =>
        raise @types.DecodeError::new(
          kind=UnexpectedContent,
          message="unexpected multiple root values in event stream",
        )
      None => root.val = Some(val)
    }
    return
  }
  let top = stack[stack.length() - 1]
  match top {
    Obj(frame) =>
      match frame.current_key {
        None =>
          raise @types.DecodeError::new(
            kind=UnexpectedContent,
            message="object value event without preceding key",
          )
        Some(key) => {
          frame.map[key] = val
          frame.current_key = None
        }
      }
    Arr(arr) => arr.push(val)
  }
}

///|
/// Builds a `Json` value by driving a synchronous `@types.StreamEvent` emitter.
pub fn build_value_from_stream(
  run : ((@types.StreamEvent) -> Unit raise @types.DecodeError) -> Unit raise @types.DecodeError,
) -> Json raise @types.DecodeError {
  let stack : Array[BuildFrame] = []
  let root : Ref[Json?] = { val: None, }
  let on_event = fn(
    event : @types.StreamEvent,
  ) -> Unit raise @types.DecodeError {
    match event {
      StartObject => {
        let frame : ObjFrame = { map: Map([]), current_key: None, }
        attach_value(stack, root, Json::object(frame.map))
        stack.push(Obj(frame))
      }
      EndObject => {
        if stack.is_empty() {
          raise @types.DecodeError::new(
            kind=UnexpectedContent,
            message="unexpected EndObject event",
          )
        }
        match stack.pop() {
          Some(Obj(frame)) =>
            if !(frame.current_key is None) {
              raise @types.DecodeError::new(
                kind=UnexpectedContent,
                message="dangling object key without value before EndObject",
              )
            }
          _ =>
            raise @types.DecodeError::new(
              kind=UnexpectedContent,
              message="mismatched EndObject event",
            )
        }
      }
      StartArray(_) => {
        let arr : Array[Json] = []
        attach_value(stack, root, Json::array(arr))
        stack.push(Arr(arr))
      }
      EndArray => {
        if stack.is_empty() {
          raise @types.DecodeError::new(
            kind=UnexpectedContent,
            message="unexpected EndArray event",
          )
        }
        match stack.pop() {
          Some(Arr(_)) => ()
          _ =>
            raise @types.DecodeError::new(
              kind=UnexpectedContent,
              message="mismatched EndArray event",
            )
        }
      }
      Key(key) => {
        if stack.is_empty() {
          raise @types.DecodeError::new(
            kind=UnexpectedContent,
            message="Key event outside of object context",
          )
        }
        match stack[stack.length() - 1] {
          Obj(frame) => {
            if !(frame.current_key is None) {
              raise @types.DecodeError::new(
                kind=UnexpectedContent,
                message="consecutive Key events without intermediate value",
              )
            }
            frame.current_key = Some(key)
          }
          Arr(_) =>
            raise @types.DecodeError::new(
              kind=UnexpectedContent,
              message="Key event inside array context",
            )
        }
      }
      Primitive(val) => attach_value(stack, root, val)
    }
  }
  run(on_event)
  if !stack.is_empty() {
    raise @types.DecodeError::new(
      kind=UnexpectedContent,
      message="incomplete event stream: unclosed objects or arrays",
    )
  }
  match root.val {
    Some(value) => value
    None =>
      raise @types.DecodeError::new(
        kind=UnexpectedContent,
        message="empty event stream: no root value produced",
      )
  }
}

///|
/// Decodes a TOON v4.4 document string into a `Json` value.
pub fn decode(
  input : String,
  options~ : @types.DecodeOptions = @types.DecodeOptions::default(),
) -> Json raise @types.DecodeError {
  options.validate()
  build_value_from_stream(on_event => decode_stream(input, on_event, options~))
}

///|
fn utf8_error_location(
  bytes : BytesView,
  malformed : BytesView,
) -> (Int32, Int32) {
  let valid_len = bytes.length() - malformed.length()
  let mut line : Int32 = 1
  let mut col : Int32 = 1
  let mut i = 0
  while i < valid_len {
    let b = bytes[i].to_int()
    if b == 0x0A {
      line += 1
      col = 1
    } else if (b & 0xC0) != 0x80 {
      col += 1
    }
    i += 1
  }
  (line, col)
}

///|
/// Validates UTF-8 strictly (without U+FFFD replacement) and decodes a TOON
/// document from raw bytes into a `Json` value.
pub fn decode_bytes(
  bytes : BytesView,
  options~ : @types.DecodeOptions = @types.DecodeOptions::default(),
) -> Json raise @types.DecodeError {
  options.validate()
  let text = @utf8.decode(bytes) catch {
    @utf8.Malformed(bad_tail) => {
      let (line, col) = utf8_error_location(bytes, bad_tail)
      raise @types.DecodeError::new(
        kind=InvalidUtf8,
        message="invalid UTF-8 byte sequence",
        span=@types.Span::at(line, col, length=1),
      )
    }
  }
  decode(text, options~)
}
