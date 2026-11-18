///|
fn parse_delimiter_opt(opts_obj : Map[String, Json]) -> @types.Delimiter raise {
  match opts_obj.get("delimiter") {
    None => Comma
    Some(String(",")) => Comma
    Some(String("\t")) => Tab
    Some(String("|")) => Pipe
    Some(other) => fail("unsupported fixture delimiter: \{other.stringify()}")
  }
}

///|
fn parse_indent_opt(opts_obj : Map[String, Json]) -> Int32 raise {
  match opts_obj.get("indentSize") {
    None => 2
    Some(Number(n, ..)) => n.to_int()
    Some(other) => fail("unsupported fixture indentSize: \{other.stringify()}")
  }
}

///|
fn parse_strict_opt(opts_obj : Map[String, Json]) -> Bool raise {
  match opts_obj.get("strict") {
    None => true
    Some(True) => true
    Some(False) => false
    Some(other) => fail("unsupported fixture strict: \{other.stringify()}")
  }
}

///|
fn json_semantically_equal(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Null, Null) => true
    (True, True) => true
    (False, False) => true
    (Number(x, ..), Number(y, ..)) => (x == 0.0 && y == 0.0) || x == y
    (String(x), String(y)) => x == y
    (Array(xs), Array(ys)) => {
      if xs.length() != ys.length() {
        return false
      }
      for i in 0..<xs.length() {
        if !json_semantically_equal(xs[i], ys[i]) {
          return false
        }
      }
      true
    }
    (Object(mx), Object(my)) => {
      if mx.length() != my.length() {
        return false
      }
      let keys_x = mx.keys().to_array()
      let keys_y = my.keys().to_array()
      for i in 0..<keys_x.length() {
        if keys_x[i] != keys_y[i] {
          return false
        }
        let k = keys_x[i]
        if !json_semantically_equal(mx[k], my[k]) {
          return false
        }
      }
      true
    }
    _ => false
  }
}

///|
async test "official TOON v4.4 encode fixtures (160 cases)" {
  let dir = "conformance/fixtures/encode"
  let files = @fs.readdir(dir, sort=true)
  let mut file_count = 0
  let mut total_cases = 0
  let failures : Array[String] = []
  for file in files {
    if !file.has_suffix(".json") {
      continue
    }
    file_count += 1
    let text = @fs.read_text("\{dir}/\{file}")
    let doc = @json.parse(text)
    guard doc is Object(root) else { fail("expected object in \{file}") }
    guard root.get("tests") is Some(Array(tests)) else {
      fail("missing tests array in \{file}")
    }
    for tc in tests {
      total_cases += 1
      guard tc is Object(obj) else { fail("expected test object in \{file}") }
      guard obj.get("name") is Some(String(name)) else {
        fail("missing name in \{file}")
      }
      guard obj.get("input") is Some(input) else {
        fail("missing input in \{file}::\{name}")
      }
      guard obj.get("expected") is Some(expected) else {
        fail("missing expected in \{file}::\{name}")
      }
      let should_error = match obj.get("shouldError") {
        Some(True) => true
        _ => false
      }
      let options = match obj.get("options") {
        Some(Object(opts_obj)) =>
          @types.EncodeOptions::new(
            indent_size=parse_indent_opt(opts_obj),
            delimiter=parse_delimiter_opt(opts_obj),
          )
        _ => @types.EncodeOptions::default()
      }
      if should_error {
        let raised = try {
          ignore(@encode.encode(input, options~))
          false
        } catch {
          @types.EncodeError(_) => true
        }
        if !raised {
          failures.push("\{file}::\{name} -> expected EncodeError")
        }
      } else {
        guard expected is String(exp_str) else {
          fail("expected string output in \{file}::\{name}")
        }
        let actual = @encode.encode(input, options~) catch {
          err => {
            failures.push(
              "\{file}::\{name} -> unexpected error: \{err.format()}",
            )
            continue
          }
        }
        if actual != exp_str {
          failures.push(
            "\{file}::\{name}\n  expected: \{exp_str.escape()}\n  actual:   \{actual.escape()}",
          )
        }
      }
    }
  }
  @test.assert_eq(file_count, 9)
  @test.assert_eq(total_cases, 160)
  if !failures.is_empty() {
    let summary = failures.join("\n---\n")
    fail(
      "Encode conformance failed (\{failures.length()}/\{total_cases}):\n\{summary}",
    )
  }
}

///|
async test "official TOON v4.4 decode fixtures (404 cases)" {
  let dir = "conformance/fixtures/decode"
  let files = @fs.readdir(dir, sort=true)
  let mut file_count = 0
  let mut total_cases = 0
  let failures : Array[String] = []
  for file in files {
    if !file.has_suffix(".json") {
      continue
    }
    file_count += 1
    let text = @fs.read_text("\{dir}/\{file}")
    let doc = @json.parse(text)
    guard doc is Object(root) else { fail("expected object in \{file}") }
    guard root.get("tests") is Some(Array(tests)) else {
      fail("missing tests array in \{file}")
    }
    for tc in tests {
      total_cases += 1
      guard tc is Object(obj) else { fail("expected test object in \{file}") }
      guard obj.get("name") is Some(String(name)) else {
        fail("missing name in \{file}")
      }
      guard obj.get("input") is Some(String(input)) else {
        fail("missing string input in \{file}::\{name}")
      }
      guard obj.get("expected") is Some(expected) else {
        fail("missing expected in \{file}::\{name}")
      }
      let should_error = match obj.get("shouldError") {
        Some(True) => true
        _ => false
      }
      let options = match obj.get("options") {
        Some(Object(opts_obj)) =>
          @types.DecodeOptions::new(
            indent_size=parse_indent_opt(opts_obj),
            strict=parse_strict_opt(opts_obj),
          )
        _ => @types.DecodeOptions::default()
      }
      if should_error {
        let outcome : Result[Json, @types.DecodeError] = Ok(
          @decode.decode(input, options~),
        ) catch {
          err => Err(err)
        }
        match outcome {
          Ok(val) =>
            failures.push(
              "\{file}::\{name} -> expected DecodeError, got: \{val.stringify()}",
            )
          Err(@types.DecodeError(span~, message~, ..)) =>
            if span.line < 1 || message.is_empty() {
              failures.push(
                "\{file}::\{name} -> DecodeError missing valid line span: line=\{span.line}, msg=\{message}",
              )
            }
        }
      } else {
        let actual = @decode.decode(input, options~) catch {
          err => {
            failures.push(
              "\{file}::\{name} -> unexpected error:\n\{err.format()}",
            )
            continue
          }
        }
        if !json_semantically_equal(actual, expected) {
          failures.push(
            "\{file}::\{name}\n  expected: \{expected.stringify()}\n  actual:   \{actual.stringify()}",
          )
        }
      }
    }
  }
  @test.assert_eq(file_count, 14)
  @test.assert_eq(total_cases, 404)
  if !failures.is_empty() {
    let summary = failures.join("\n---\n")
    fail(
      "Decode conformance failed (\{failures.length()}/\{total_cases}):\n\{summary}",
    )
  }
}

///|
test "raw UTF-8 byte decoding rejects ill-formed sequences (§1.2, §4)" {
  let cases : Array[Bytes] = [
    b"a: \x80", b"a: 1\nb: \xC3", b"a: \xC0\x80", b"a: \xED\xA0\x80",
  ]
  for raw in cases {
    let outcome : Result[Json, @types.DecodeError] = Ok(
      @decode.decode_bytes(raw),
    ) catch {
      err => Err(err)
    }
    guard outcome is Err(@types.DecodeError(kind=InvalidUtf8, span~, ..)) else {
      @test.fail("expected InvalidUtf8 DecodeError for malformed bytes")
    }
    assert_true(span.line >= 1)
    assert_true(span.column >= 1)
  }
  let valid = b"\xEF\xBB\xBF\xE5\x90\x8D: \xF0\x9F\x9A\x80"
  let parsed = @decode.decode_bytes(valid)
  guard parsed is Object(m) else { @test.fail("expected object") }
  @test.assert_eq(m.get("名"), Some(Json::string("🚀")))
}
