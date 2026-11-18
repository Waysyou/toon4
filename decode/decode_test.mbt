///|
fn assert_decode_error(
  input : String,
  expected_kind : @types.ErrorKind,
  expected_line : Int32,
  expected_col : Int32,
  options~ : @types.DecodeOptions = @types.DecodeOptions::default(),
) -> Unit raise {
  let caught : @types.DecodeError? = try {
    ignore(@decode.decode(input, options~))
    None
  } catch {
    err => Some(err)
  }
  guard caught is Some(DecodeError(kind~, span~, ..)) else {
    @test.fail("expected DecodeError(\{expected_kind.code()}), got success")
  }
  @test.assert_eq(kind, expected_kind)
  @test.assert_eq(span.line, expected_line)
  @test.assert_eq(span.column, expected_col)
}

///|
fn map_keys(m : Map[String, Json]) -> Array[String] {
  let keys : Array[String] = []
  m.each(fn(k, _v) { keys.push(k) })
  keys
}

///|
test "root forms: empty, comments-only, [], scalar, root array, root keyed" {
  @test.assert_eq(@decode.decode(""), Json::object(Map([])))
  @test.assert_eq(@decode.decode("\n# c\n\n# d\n"), Json::object(Map([])))
  @test.assert_eq(@decode.decode("#hello"), Json::object(Map([])))
  @test.assert_eq(@decode.decode("[]"), Json::array([]))
  @test.assert_eq(@decode.decode("\nhello"), Json::string("hello"))
  @test.assert_eq(@decode.decode("items[2]"), Json::string("items[2]"))
  @test.assert_eq(@decode.decode("k\"x[2]: 1,2"), Json::string("k\"x[2]: 1,2"))
  @test.assert_eq(@decode.decode("1e6"), Json::number(1000000.0))
  @test.assert_eq(@decode.decode("05"), Json::string("05"))
  @test.assert_eq(
    @decode.decode("[3|]: a|true|42"),
    Json::array([Json::string("a"), Json::boolean(true), Json::number(42.0)]),
  )
  @test.assert_eq(@decode.decode("[0]:"), Json::array([]))

  // Trailing content after root forms must error in both modes
  assert_decode_error("[2]: 1,2\njunk: 3", UnexpectedContent, 2, 1)
  assert_decode_error(
    "[2]: 1,2\njunk: 3",
    UnexpectedContent,
    2,
    1,
    options=@types.DecodeOptions::new(strict=false),
  )
  assert_decode_error("[]\njunk: 3", UnexpectedContent, 2, 1)
  assert_decode_error(
    "[2:]{v}:\n  a: 1\n  b: 2\njunk: 3",
    UnexpectedContent,
    4,
    1,
  )
  assert_decode_error("hello\nworld", UnexpectedContent, 1, 1)
  assert_decode_error("  a: 1", OverIndentation, 1, 1)
}

///|
test "TOON 4.4 §9.5 keyed tabular objects, root keyed, [0:], and nested groups" {
  let doc =
    #|servers[2:]{name,score}:
    #|  alpha: ada,98.5
    #|  beta: bob,100
  let expected = Json::object(
    Map([
      (
        "servers",
        Json::object(
          Map([
            (
              "alpha",
              Json::object(
                Map([
                  ("name", Json::string("ada")),
                  ("score", Json::number(98.5)),
                ]),
              ),
            ),
            (
              "beta",
              Json::object(
                Map([
                  ("name", Json::string("bob")),
                  ("score", Json::number(100.0)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ]),
  )
  @test.assert_eq(@decode.decode(doc), expected)

  // Root keyed tabular header [2:]{...}:
  let root_keyed =
    #|[2:]{age,city}:
    #|  alice: 30,Berlin
    #|  bob: 25,Oslo
  let expected_root = Json::object(
    Map([
      (
        "alice",
        Json::object(
          Map([("age", Json::number(30.0)), ("city", Json::string("Berlin"))]),
        ),
      ),
      (
        "bob",
        Json::object(
          Map([("age", Json::number(25.0)), ("city", Json::string("Oslo"))]),
        ),
      ),
    ]),
  )
  @test.assert_eq(@decode.decode(root_keyed), expected_root)

  // Keyed [0:] decodes to empty object {}
  @test.assert_eq(
    @decode.decode("m[0:]{v}:"),
    Json::object(Map([("m", Json::object(Map([])))])),
  )

  // Nested field groups geo{lat,lon} with pipe/tab and quoted entry keys
  let nested =
    #|regions[2:|]{name|geo{lat|lon}}:
    #|  "a:b": Europe|50|10
    #|  us: America|40|-100
    #|after: 1
  let expected_nested = Json::object(
    Map([
      (
        "regions",
        Json::object(
          Map([
            (
              "a:b",
              Json::object(
                Map([
                  ("name", Json::string("Europe")),
                  (
                    "geo",
                    Json::object(
                      Map([
                        ("lat", Json::number(50.0)),
                        ("lon", Json::number(10.0)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            (
              "us",
              Json::object(
                Map([
                  ("name", Json::string("America")),
                  (
                    "geo",
                    Json::object(
                      Map([
                        ("lat", Json::number(40.0)),
                        ("lon", Json::number(-100.0)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
      ("after", Json::number(1.0)),
    ]),
  )
  @test.assert_eq(@decode.decode(nested), expected_nested)

  // Keyed entry row missing colon errors in BOTH strict and non-strict modes
  assert_decode_error("u[2:]{x}:\n  a: 1\n  boom", MissingColon, 3, 3)
  assert_decode_error(
    "u[2:]{x}:\n  a: 1\n  boom",
    MissingColon,
    3,
    3,
    options=@types.DecodeOptions::new(strict=false),
  )

  // Keyed entry cell width mismatch errors in BOTH strict and non-strict modes
  assert_decode_error("m[1:]{a,b}:\n  k: 1", WidthMismatch, 2, 6)
  assert_decode_error(
    "m[1:]{a,b}:\n  k: 1",
    WidthMismatch,
    2,
    6,
    options=@types.DecodeOptions::new(strict=false),
  )
  assert_decode_error("m[1:]{v}:\n  a:", WidthMismatch, 2, 4)
}

///|
test "tabular arrays, nested field groups, is_data_row URL, and [] as string cell" {
  assert_true(@decode.is_data_row("1,http://a:b", Comma))
  assert_true(@decode.is_data_row("1,\"http://a:b\"", Comma))
  assert_true(@decode.is_data_row("1|a:b", Pipe))
  assert_false(@decode.is_data_row("c: 3,4", Comma))
  assert_false(@decode.is_data_row("x: 2", Comma))

  let url_doc =
    #|links[2]{id,url}:
    #|  1,http://a:b
    #|  2,"https://example.com?q=a:b"
  let expected_urls = Json::object(
    Map([
      (
        "links",
        Json::array([
          Json::object(
            Map([("id", Json::number(1.0)), ("url", Json::string("http://a:b"))]),
          ),
          Json::object(
            Map([
              ("id", Json::number(2.0)),
              ("url", Json::string("https://example.com?q=a:b")),
            ]),
          ),
        ]),
      ),
    ]),
  )
  @test.assert_eq(@decode.decode(url_doc), expected_urls)

  // Deeply nested field groups without depth cap and cross-level repeated names
  let deep_tab =
    #|shipments[1]{id,sender{id,geo{lat,lon}},receiver{id,city}}:
    #|  s1,ACME,52.5,13.4,Globex,Oslo
  let expected_deep = Json::object(
    Map([
      (
        "shipments",
        Json::array([
          Json::object(
            Map([
              ("id", Json::string("s1")),
              (
                "sender",
                Json::object(
                  Map([
                    ("id", Json::string("ACME")),
                    (
                      "geo",
                      Json::object(
                        Map([
                          ("lat", Json::number(52.5)),
                          ("lon", Json::number(13.4)),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
              (
                "receiver",
                Json::object(
                  Map([
                    ("id", Json::string("Globex")),
                    ("city", Json::string("Oslo")),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ]),
  )
  @test.assert_eq(@decode.decode(deep_tab), expected_deep)

  // Literal [] inside inline, tabular, and keyed entry rows decodes as string "[]"
  let brackets_as_strings =
    #|inline[1]: []
    #|tab[1]{v}:
    #|  []
    #|keyed[1:]{v}:
    #|  k: []
    #|empty: []
  let expected_brackets = Json::object(
    Map([
      ("inline", Json::array([Json::string("[]")])),
      ("tab", Json::array([Json::object(Map([("v", Json::string("[]"))]))])),
      (
        "keyed",
        Json::object(
          Map([("k", Json::object(Map([("v", Json::string("[]"))])))]),
        ),
      ),
      ("empty", Json::array([])),
    ]),
  )
  @test.assert_eq(@decode.decode(brackets_as_strings), expected_brackets)
}

///|
test "list items: empty -, - [], - [M]:, keyed & tabular first fields, sibling fields" {
  let doc =
    #|items[5]:
    #|  -
    #|  - []
    #|  - [2]: 1,2
    #|  - users[2]{id,name}:
    #|      1,Ada
    #|      2,Bob
    #|    status: active
    #|  - config[2:]{x}:
    #|      a: 1
    #|      b: 2
    #|    flag: true
  let expected = Json::object(
    Map([
      (
        "items",
        Json::array([
          Json::object(Map([])),
          Json::array([]),
          Json::array([Json::number(1.0), Json::number(2.0)]),
          Json::object(
            Map([
              (
                "users",
                Json::array([
                  Json::object(
                    Map([
                      ("id", Json::number(1.0)),
                      ("name", Json::string("Ada")),
                    ]),
                  ),
                  Json::object(
                    Map([
                      ("id", Json::number(2.0)),
                      ("name", Json::string("Bob")),
                    ]),
                  ),
                ]),
              ),
              ("status", Json::string("active")),
            ]),
          ),
          Json::object(
            Map([
              (
                "config",
                Json::object(
                  Map([
                    ("a", Json::object(Map([("x", Json::number(1.0))]))),
                    ("b", Json::object(Map([("x", Json::number(2.0))]))),
                  ]),
                ),
              ),
              ("flag", Json::boolean(true)),
            ]),
          ),
        ]),
      ),
    ]),
  )
  @test.assert_eq(@decode.decode(doc), expected)

  // Keyless header misuse checks
  assert_decode_error("a:\n  [2]: 1,2", KeylessHeaderMisuse, 2, 3)
  assert_decode_error("a: 1\n[2]: x,y", KeylessHeaderMisuse, 2, 1)
  assert_decode_error("items[1]:\n  - [0]{x}:", KeylessHeaderMisuse, 2, 5)
  assert_decode_error(
    "items[1]:\n  - [2:]{v}:\n      a: 1\n      b: 2",
    KeylessHeaderMisuse,
    2,
    5,
  )
  assert_decode_error(
    "a[1]:\n  - b: 1\n    [2]: x,y",
    KeylessHeaderMisuse,
    3,
    5,
  )
}

///|
test "all 5 §14.4 non-strict recoveries and preserved first-seen LWW key order" {
  let non_strict = @types.DecodeOptions::new(strict=false)

  // 1. Declared count ignored without truncating (inline, list, tabular, keyed)
  let counts_doc =
    #|inline[1]: a,b,c
    #|list[1]:
    #|  - x
    #|  - y
    #|tab[1]{v}:
    #|  10
    #|  20
    #|keyed[1:]{v}:
    #|  p: 1
    #|  q: 2
  let expected_counts = Json::object(
    Map([
      (
        "inline",
        Json::array([Json::string("a"), Json::string("b"), Json::string("c")]),
      ),
      ("list", Json::array([Json::string("x"), Json::string("y")])),
      (
        "tab",
        Json::array([
          Json::object(Map([("v", Json::number(10.0))])),
          Json::object(Map([("v", Json::number(20.0))])),
        ]),
      ),
      (
        "keyed",
        Json::object(
          Map([
            ("p", Json::object(Map([("v", Json::number(1.0))]))),
            ("q", Json::object(Map([("v", Json::number(2.0))]))),
          ]),
        ),
      ),
    ]),
  )
  @test.assert_eq(
    @decode.decode(counts_doc, options=non_strict),
    expected_counts,
  )

  // 2. Duplicate sibling keys, header fields, and entry keys resolve LWW preserving first-seen key order
  let lww_doc =
    #|first: 1
    #|mid: 2
    #|first: 99
    #|tab[1]{x,y,x}:
    #|  1,2,3
    #|keyed[2:]{v}:
    #|  k1: 10
    #|  k2: 20
    #|  k1: 30
  let decoded_lww = @decode.decode(lww_doc, options=non_strict)
  guard decoded_lww is Object(root_map) else {
    @test.fail("expected root object")
  }
  @test.assert_eq(map_keys(root_map), ["first", "mid", "tab", "keyed"])
  @test.assert_eq(root_map["first"], Json::number(99.0))
  guard root_map["tab"] is Array(tab_arr) && tab_arr[0] is Object(row_map) else {
    @test.fail("expected tabular row object")
  }
  @test.assert_eq(map_keys(row_map), ["x", "y"])
  @test.assert_eq(row_map["x"], Json::number(3.0))
  guard root_map["keyed"] is Object(keyed_map) else {
    @test.fail("expected keyed object")
  }
  @test.assert_eq(map_keys(keyed_map), ["k1", "k2"])
  @test.assert_eq(
    keyed_map["k1"],
    Json::object(Map([("v", Json::number(30.0))])),
  )

  // 3. Tab & non-multiple indentation handled by scanner
  let indent_doc = "a:\n   b:\n \t c: 1\n  d: 2"
  @test.assert_eq(
    @decode.decode(indent_doc, options=non_strict),
    Json::object(
      Map([
        (
          "a",
          Json::object(
            Map([
              ("b", Json::object(Map([("c", Json::number(1.0))]))),
              ("d", Json::number(2.0)),
            ]),
          ),
        ),
      ]),
    ),
  )

  // 4. Blank lines inside header spans ignored
  let blank_doc =
    #|items[2]:
    #|  - a
    #|
    #|  - b
    #|rows[2]{x}:
    #|  1
    #|
    #|  2
    #|m[2:]{v}:
    #|  a: 1
    #|
    #|  b: 2
  @test.assert_eq(
    @decode.decode(blank_doc, options=non_strict),
    Json::object(
      Map([
        ("items", Json::array([Json::string("a"), Json::string("b")])),
        (
          "rows",
          Json::array([
            Json::object(Map([("x", Json::number(1.0))])),
            Json::object(Map([("x", Json::number(2.0))])),
          ]),
        ),
        (
          "m",
          Json::object(
            Map([
              ("a", Json::object(Map([("v", Json::number(1.0))]))),
              ("b", Json::object(Map([("v", Json::number(2.0))]))),
            ]),
          ),
        ),
      ]),
    ),
  )

  // 5. Depth jump adoption in nested scopes, and rejection after non-scope-opening hyphen fields
  let jump_doc =
    #|a:
    #|    b:
    #|      x: 1
    #|    c: 2
    #|l[1]:
    #|  - k:
    #|        x: 1
  @test.assert_eq(
    @decode.decode(jump_doc, options=non_strict),
    Json::object(
      Map([
        (
          "a",
          Json::object(
            Map([
              ("b", Json::object(Map([("x", Json::number(1.0))]))),
              ("c", Json::number(2.0)),
            ]),
          ),
        ),
        (
          "l",
          Json::array([
            Json::object(
              Map([("k", Json::object(Map([("x", Json::number(1.0))])))]),
            ),
          ]),
        ),
      ]),
    ),
  )
  // Shallower than adopted depth must still error in non-strict mode
  assert_decode_error(
    "a:\n    b: 1\n  c: 2",
    OverIndentation,
    3,
    1,
    options=non_strict,
  )
  // Non-scope-opening hyphen fields must NOT adopt deeper lines
  assert_decode_error(
    "items[1]:\n  - a: 1\n      b: 2",
    OverIndentation,
    3,
    1,
    options=non_strict,
  )
  assert_decode_error(
    "items[1]:\n  - a[2]: 1,2\n      b: 2",
    OverIndentation,
    3,
    1,
    options=non_strict,
  )
  assert_decode_error(
    "items[1]:\n  - a: []\n      b: 2",
    OverIndentation,
    3,
    1,
    options=non_strict,
  )
}

///|
test "strict mode error kinds, line/column spans with non-BMP emoji, and caret formatting" {
  // Duplicate sibling key & entry key & header field
  assert_decode_error("name: Ada\n\"name\": Bob", DuplicateKey, 2, 1)
  assert_decode_error("m[2:]{v}:\n  a: 1\n  a: 2", DuplicateKey, 3, 3)
  assert_decode_error("items[0]{a,a{x}}:", DuplicateField, 1, 1)

  // Blank line inside header spans (list, tabular, keyed, and nested inside last item)
  assert_decode_error("items[2]:\n  - a\n\n  - b", BlankLineInScope, 3, 1)
  assert_decode_error("items[2]{id}:\n  1\n\n  2", BlankLineInScope, 3, 1)
  assert_decode_error("m[2:]{v}:\n  a: 1\n\n  b: 2", BlankLineInScope, 3, 1)
  assert_decode_error("items[1]:\n  - a: 1\n\n    b: 2", BlankLineInScope, 3, 1)

  // Depth jump and over-indentation
  assert_decode_error("a:\n    b: 1", DepthJump, 2, 1)
  assert_decode_error("a: 1\n  b: 2", OverIndentation, 2, 1)
  assert_decode_error("a:\n\tb: 1", InvalidIndentation, 2, 1)
  assert_decode_error("a:\n   b: 1", InvalidIndentation, 2, 1)

  // Emoji-aware column calculation via utf16_offset_to_column
  // Line 2: "  \"👋\\x\": 1" -> col 1:' ', 2:' ', 3:'"', 4:'👋', 5:'\\', 6:'x'
  let emoji_err : @types.DecodeError? = try {
    ignore(@decode.decode("root:\n  \"👋\\x\": 1"))
    None
  } catch {
    err => Some(err)
  }
  guard emoji_err
    is Some(DecodeError(kind~, span~, source_line~, ..) as full_err) else {
    @test.fail("expected InvalidEscape")
  }
  @test.assert_eq(kind, InvalidEscape)
  @test.assert_eq(span.line, 2)
  @test.assert_eq(span.column, 5)
  @test.assert_eq(span.length, 2)
  @test.assert_eq(source_line, Some("  \"👋\\x\": 1"))
  let formatted = full_err.format()
  assert_true(formatted.contains("line 2, column 5"))
  assert_true(formatted.contains("  2 |   \"👋\\x\": 1"))
}

///|
test "BigInt oversized count strict error vs non-strict pass" {
  assert_decode_error("a[99999999999999999999]: 1", CountMismatch, 1, 26)
  assert_decode_error("a[18446744073709551617]: 1", CountMismatch, 1, 26)
  let non_strict = @types.DecodeOptions::new(strict=false)
  @test.assert_eq(
    @decode.decode("a[99999999999999999999]: 1", options=non_strict),
    Json::object(Map([("a", Json::array([Json::number(1.0)]))])),
  )
  @test.assert_eq(
    @decode.decode("a[99999999999999999999]:\n  - ok", options=non_strict),
    Json::object(Map([("a", Json::array([Json::string("ok")]))])),
  )
}

///|
test "decode_bytes valid UTF-8 with BOM/CRLF and invalid UTF-8 rejection" {
  let valid_bytes = b"\xEF\xBB\xBFmsg: \"hi\"\r\nn: 42\r\n"
  @test.assert_eq(
    @decode.decode_bytes(valid_bytes[:]),
    Json::object(Map([("msg", Json::string("hi")), ("n", Json::number(42.0))])),
  )

  // Invalid byte 0xFF at line 2, column 4
  let bad_bytes = b"a: 1\nb: \xFF"
  let bad_err : @types.DecodeError? = try {
    ignore(@decode.decode_bytes(bad_bytes[:]))
    None
  } catch {
    err => Some(err)
  }
  guard bad_err is Some(DecodeError(kind~, span~, ..)) else {
    @test.fail("expected InvalidUtf8 for 0xFF")
  }
  @test.assert_eq(kind, InvalidUtf8)
  @test.assert_eq(span.line, 2)
  @test.assert_eq(span.column, 4)

  // Truncated multi-byte sequence and UTF-8 encoded surrogate U+D800
  let trunc_err : @types.DecodeError? = try {
    ignore(@decode.decode_bytes(b"k: \xE2\x82"[:]))
    None
  } catch {
    err => Some(err)
  }
  guard trunc_err is Some(DecodeError(kind=trunc_kind, ..)) else {
    @test.fail("expected InvalidUtf8 for truncated sequence")
  }
  @test.assert_eq(trunc_kind, InvalidUtf8)

  let surr_err : @types.DecodeError? = try {
    ignore(@decode.decode_bytes(b"k: \xED\xA0\x80"[:]))
    None
  } catch {
    err => Some(err)
  }
  guard surr_err is Some(DecodeError(kind=surr_kind, ..)) else {
    @test.fail("expected InvalidUtf8 for surrogate bytes")
  }
  @test.assert_eq(surr_kind, InvalidUtf8)
}

///|
test "LineReader pull-based incremental streaming and StreamEvent emission" {
  let raw_lines = ["a: 1", "# comment", "", "b[2]: x,y"]
  let mut idx = 0
  let events : Array[@types.StreamEvent] = []
  @decode.decode_stream_lines(
    fn() {
      if idx >= raw_lines.length() {
        None
      } else {
        let s = raw_lines[idx]
        idx += 1
        Some(s)
      }
    },
    ev => events.push(ev),
  )
  @test.assert_eq(events, [
    StartObject,
    Key("a"),
    Primitive(Json::number(1.0)),
    Key("b"),
    StartArray(2),
    Primitive(Json::string("x")),
    Primitive(Json::string("y")),
    EndArray,
    EndObject,
  ])

  // Security §15: __proto__, constructor, prototype as ordinary own keys; NBSP preserved
  let sec_doc = "__proto__: polluted\nconstructor: 1\nprototype: 2\na: \u{00a0}v\nb: v\t"
  @test.assert_eq(
    @decode.decode(sec_doc),
    Json::object(
      Map([
        ("__proto__", Json::string("polluted")),
        ("constructor", Json::number(1.0)),
        ("prototype", Json::number(2.0)),
        ("a", Json::string("\u{00a0}v")),
        ("b", Json::string("v\t")),
      ]),
    ),
  )

  // Invalid options rejected
  @test.assert_raise(() => {
    @decode.decode("a: 1", options=@types.DecodeOptions::new(indent_size=0))
  })
}

///|
test "blank-lines, comments, whitespace, BOM, CRLF, mid-token quotes, empty keys, and custom indent" {
  // Tab-only line: errors in strict, blank in non-strict
  assert_decode_error("a: 1\n\t\nb: 2", InvalidIndentation, 2, 1)
  @test.assert_eq(
    @decode.decode(
      "a: 1\n\t\nb: 2",
      options=@types.DecodeOptions::new(strict=false),
    ),
    Json::object(Map([("a", Json::number(1.0)), ("b", Json::number(2.0))])),
  )

  // Blank lines between header and first row/item/entry are valid in strict mode
  @test.assert_eq(
    @decode.decode("items[2]:\n\n  - a\n  - b"),
    Json::object(
      Map([("items", Json::array([Json::string("a"), Json::string("b")]))]),
    ),
  )
  @test.assert_eq(
    @decode.decode("m[2:]{v}:\n\n  a: 1\n  b: 2"),
    Json::object(
      Map([
        (
          "m",
          Json::object(
            Map([
              ("a", Json::object(Map([("v", Json::number(1.0))]))),
              ("b", Json::object(Map([("v", Json::number(2.0))]))),
            ]),
          ),
        ),
      ]),
    ),
  )

  // Blank line inside outer list span before inner tabular first row errors in strict mode
  assert_decode_error(
    "outer[2]:\n  - inner[1]{a}:\n\n      1\n  - x",
    BlankLineInScope,
    3,
    1,
  )

  // BOM, CRLF, double-CR, extra spaces after '-', empty unquoted keys, hyphen off item depth
  let ws_doc = "\u{feff}\u{feff}a: x\r\r\n\u{feff}b: 1\r\n: empty\r\nitems[2]:\r\n  -  \u{00a0}v\r\n  -   [2]: 1,2\r\n- top: 9\r\n"
  @test.assert_eq(
    @decode.decode(ws_doc),
    Json::object(
      Map([
        ("\u{feff}a", Json::string("x\r")),
        ("\u{feff}b", Json::number(1.0)),
        ("", Json::string("empty")),
        (
          "items",
          Json::array([
            Json::string("\u{00a0}v"),
            Json::array([Json::number(1.0), Json::number(2.0)]),
          ]),
        ),
        ("- top", Json::number(9.0)),
      ]),
    ),
  )

  // Tab after '-' at list item depth must fail
  assert_decode_error("items[1]:\n  -\tx", CountMismatch, 1, 1)

  // Mid-token quotes in keys and delimited values
  let mid_doc = "a\"b:c\"d: 1\ne\"[1]:\"f: 2\na\"b\"[2]: x,y\narr[2]: a\"b,c\",d"
  @test.assert_eq(
    @decode.decode(mid_doc),
    Json::object(
      Map([
        ("a\"b:c\"d", Json::number(1.0)),
        ("e\"[1]:\"f", Json::number(2.0)),
        ("a\"b\"", Json::array([Json::string("x"), Json::string("y")])),
        ("arr", Json::array([Json::string("a\"b,c\""), Json::string("d")])),
      ]),
    ),
  )

  // Custom indent_size = 4
  let indent4 = "a:\n    b: 1\nl[2]:\n    - b: 1\n        c: 2\n    - 1"
  @test.assert_eq(
    @decode.decode(indent4, options=@types.DecodeOptions::new(indent_size=4)),
    Json::object(
      Map([
        ("a", Json::object(Map([("b", Json::number(1.0))]))),
        (
          "l",
          Json::array([
            Json::object(
              Map([("b", Json::number(1.0)), ("c", Json::number(2.0))]),
            ),
            Json::number(1.0),
          ]),
        ),
      ]),
    ),
  )

  // Normalization-distinct keys, header errors, trailing chars, and build_value_from_stream checks
  @test.assert_eq(
    @decode.decode("\u{00e9}: 1\ne\u{0301}: 2"),
    Json::object(
      Map([("\u{00e9}", Json::number(1.0)), ("e\u{0301}", Json::number(2.0))]),
    ),
  )
  assert_decode_error("a[1:", MalformedHeader, 1, 2)
  assert_decode_error("a[2:]{x}", MalformedHeader, 1, 9)
  assert_decode_error("a[1:]{x}:\t\n  k: 1", MalformedHeader, 1, 10)
  assert_decode_error("k: \"a\"\t", TrailingCharacters, 1, 7)
  assert_decode_error("\"a\"\t: 1", MissingColon, 1, 4)
  assert_decode_error("a[1]:", CountMismatch, 1, 1)
  assert_decode_error("a[1]:\n  - x\n  - y", CountMismatch, 3, 3)
  assert_decode_error("[1]{id}:\n  1\n  2", CountMismatch, 3, 3)

  // build_value_from_stream rejects invalid event streams
  @test.assert_raise(() => {
    @decode.build_value_from_stream(emit => emit(StartObject))
  })
  @test.assert_raise(() => {
    @decode.build_value_from_stream(emit => emit(Key("orphan")))
  })
  @test.assert_raise(() => {
    @decode.build_value_from_stream(emit => {
      emit(StartObject)
      emit(Key("a"))
      emit(EndObject)
    })
  })

  // Additional spec edge cases: list-item nested list/tabular/empty-obj, dedent with delimiter, hyphen off item depth, backslash in unquoted key
  let extra_doc =
    #|items[2]:
    #|  - matrix[2]:
    #|      - [2]: 1,2
    #|      - [2]: 3,4
    #|    name: grid
    #|  - a:
    #|    b: 1
    #|    - y: 2
    #|t[1]{a,b}:
    #|  - y,2
    #|x: 3,4
    #|k: b:c
    #|a\: b
  let expected_extra = Json::object(
    Map([
      (
        "items",
        Json::array([
          Json::object(
            Map([
              (
                "matrix",
                Json::array([
                  Json::array([Json::number(1.0), Json::number(2.0)]),
                  Json::array([Json::number(3.0), Json::number(4.0)]),
                ]),
              ),
              ("name", Json::string("grid")),
            ]),
          ),
          Json::object(
            Map([
              ("a", Json::object(Map([]))),
              ("b", Json::number(1.0)),
              ("- y", Json::number(2.0)),
            ]),
          ),
        ]),
      ),
      (
        "t",
        Json::array([
          Json::object(
            Map([("a", Json::string("- y")), ("b", Json::number(2.0))]),
          ),
        ]),
      ),
      ("x", Json::string("3,4")),
      ("k", Json::string("b:c")),
      ("a\\", Json::string("b")),
    ]),
  )
  @test.assert_eq(@decode.decode(extra_doc), expected_extra)
}
