///|
test "trim_spaces preserves NBSP and HTAB" {
  @test.assert_eq(
    @lex.trim_spaces("  \u{00a0}hello\t  ").to_owned(),
    "\u{00a0}hello\t",
  )
  @test.assert_eq(@lex.trim_trailing_spaces("- ").to_owned(), "-")
}

///|
test "UTF-16 safe key/unquoted search with non-BMP emojis" {
  let line = "👋a: \"x:y\" , 🚀b[2]: 1,2"
  let colon = @lex.find_unquoted_char(line, ':')
  assert_true(!(colon is None))
  let (k, next_off) = @lex.parse_key_token(line)
  @test.assert_eq(k, "👋a")
  assert_true(next_off > 3)
  // Visual column: "👋" (col 1, 2 UTF-16 units) + "a" (col 2) -> ":" is at col 3
  @test.assert_eq(@lex.utf16_offset_to_column(line, colon.unwrap()), 3)
}

///|
test "§4 strict number DFA vs §7.2 encoder numeric-like" {
  @test.assert_eq(@lex.parse_primitive_token("42"), Json::number(42.0))
  @test.assert_eq(@lex.parse_primitive_token("-1E+03"), Json::number(-1000.0))
  @test.assert_eq(@lex.parse_primitive_token("2.5e2"), Json::number(250.0))
  @test.assert_eq(@lex.parse_primitive_token("-0.0"), Json::number(0.0))
  @test.assert_eq(@lex.parse_primitive_token("05"), Json::string("05"))
  @test.assert_eq(@lex.parse_primitive_token("-05"), Json::string("-05"))
  @test.assert_eq(@lex.parse_primitive_token("+1"), Json::string("+1"))
  @test.assert_eq(@lex.parse_primitive_token(".5"), Json::string(".5"))
  @test.assert_eq(@lex.parse_primitive_token("1."), Json::string("1."))
  @test.assert_eq(@lex.parse_primitive_token("0x10"), Json::string("0x10"))
  @test.assert_eq(@lex.parse_primitive_token("1_000"), Json::string("1_000"))
  @test.assert_eq(
    @lex.parse_primitive_token("Infinity"),
    Json::string("Infinity"),
  )
  @test.assert_eq(@lex.parse_primitive_token("NaN"), Json::string("NaN"))
  @test.assert_eq(@lex.parse_primitive_token("true"), Json::boolean(true))
  @test.assert_eq(@lex.parse_primitive_token("True"), Json::string("True"))
  assert_false(@lex.is_safe_unquoted("+1", Comma))
  assert_false(@lex.is_safe_unquoted("#note", Comma))
  assert_true(@lex.is_safe_unquoted("hello 👋 world", Comma))
  assert_false(@lex.is_safe_unquoted("a,\u{0301}b", Comma))
}

///|
test "§7.1 escaping, unescaping, and surrogate/trailing errors" {
  let esc = @lex.escape_string("a\u{0004}\b\u{000c}b\u{007f}\u{2028}🚀")
  @test.assert_eq(esc, "a\\u0004\\u0008\\u000cb\u{007f}\u{2028}🚀")
  @test.assert_eq(
    @lex.unescape_string(esc),
    "a\u{0004}\b\u{000c}b\u{007f}\u{2028}🚀",
  )
  @test.assert_raise(() => @lex.unescape_string("\\uD800"))
  @test.assert_raise(() => @lex.unescape_string("\\x"))
  @test.assert_raise(() => @lex.parse_string_literal("\"a\" \"b\""))
  @test.assert_raise(() => @lex.parse_string_literal("\"unterminated"))
}

///|
test "split_delimited_values handles empty, trailing empty, and quotes" {
  let empty_parts = @lex.split_delimited_values("", Comma)
  @test.assert_eq(empty_parts.length(), 0)
  let parts = @lex.split_delimited_values("a, \"x,y\", , ", Comma).map(fn(p) {
    p.0.to_owned()
  })
  @test.assert_eq(parts, ["a", "\"x,y\"", "", ""])
}

///|
test "TOON 4.4 §6 & §9.5 header parser" {
  // Keyed tabular header with nested field groups and pipe delimiter
  let h1 = @lex.parse_array_header_line(
    "regions[2:|]{name|geo{lat|lon}}:",
    Comma,
  )
  guard h1
    is Header(
      header={
        key: Some("regions"),
        length,
        delimiter: Pipe,
        fields: Some(fields),
        keyed: true,
      },
      inline_values=None,
      ..
    ) else {
    @test.fail("expected valid keyed header")
  }
  @test.assert_eq(length.to_string(), "2")
  @test.assert_eq(@types.count_leaf_fields(fields), 3)

  // Oversized length does not overflow 32-bit int
  let h_big = @lex.parse_array_header_line("[99999999999999999999]:", Comma)
  guard h_big is Header(header={ length: big_len, .. }, ..) else {
    @test.fail("expected huge header length to parse as BigInt")
  }
  @test.assert_eq(big_len.to_string(), "99999999999999999999")

  // Invalid headers
  assert_true(@lex.parse_array_header_line("users[03]:", Comma) is Invalid(_))
  assert_true(@lex.parse_array_header_line("users[2:]:", Comma) is Invalid(_))
  assert_true(@lex.parse_array_header_line("users [2]:", Comma) is Invalid(_))
  assert_true(
    @lex.parse_array_header_line("users[2|]{a,b}:", Comma) is Invalid(_),
  )
  assert_true(
    @lex.parse_array_header_line("\"users[2]\": 1", Comma) is NotHeader,
  )
}

///|
test "scanner BOM, CR, comment pre-pass, and strict indentation" {
  let state = @lex.ScanState::new()
  // Line 1: BOM stripped once, trailing single CR stripped
  let l1 = @lex.scan_line_incremental("\u{feff}\u{feff}a: 1\r", state, 2, true)
  guard l1 is Some(pl1) else { @test.fail("expected parsed line 1") }
  @test.assert_eq(pl1.content, "\u{feff}a: 1")
  // Line 2: comment with 3 spaces is exempt from strict indent check
  let l2 = @lex.scan_line_incremental(
    "   # comment \"unterminated", state, 2, true,
  )
  @test.assert_eq(l2, None)
  // Line 3: tab before # is NOT a comment and errors in strict mode
  @test.assert_raise(() => {
    @lex.scan_line_incremental("\t# not a comment", state, 2, true)
  })
}
