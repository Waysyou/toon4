///|
fn capture_decode_err(
  input : String,
  options~ : @types.DecodeOptions = @types.DecodeOptions::default(),
) -> @types.DecodeError raise {
  let outcome : Result[Json, @types.DecodeError] = Ok(
    @decode.decode(input, options~),
  ) catch {
    err => Err(err)
  }
  match outcome {
    Ok(v) => fail("expected DecodeError, got: \{v.stringify()}")
    Err(err) => err
  }
}

///|
test "TOON 4.4 differential cases: keyed tabular, nested groups, tabs, comments, empty arrays" {
  // 1. Keyed tabular (§9.5) — `users[2:]{name,score}:` fails in legacy TOON 3 decoders
  let keyed_src =
    #|users[2:]{name,score}:
    #|  alice: Alice,95
    #|  bob: Bob,88
  let keyed_val = @decode.decode(keyed_src)
  @test.assert_eq(
    keyed_val,
    Json::object(
      Map([
        (
          "users",
          Json::object(
            Map([
              (
                "alice",
                Json::object(
                  Map([
                    ("name", Json::string("Alice")),
                    ("score", Json::number(95.0)),
                  ]),
                ),
              ),
              (
                "bob",
                Json::object(
                  Map([
                    ("name", Json::string("Bob")),
                    ("score", Json::number(88.0)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]),
    ),
  )
  @test.assert_eq(@encode.encode(keyed_val), keyed_src)

  // 2. Nested field groups inside keyed tabular (`regions[2:]{name,geo{lat,lon}}:`)
  let nested_keyed =
    #|regions[2:]{name,geo{lat,lon}}:
    #|  east: East,31.2,121.5
    #|  west: West,30.6,104.1
  let nested_decoded = @decode.decode(nested_keyed)
  @test.assert_eq(@encode.encode(nested_decoded), nested_keyed)

  // 3. Tab delimiter `[2\t]` without header trimming corruption
  let tab_src = "items[2\t]: a\tb"
  let tab_val = @decode.decode(tab_src)
  @test.assert_eq(
    @encode.encode(tab_val, options=@types.EncodeOptions::new(delimiter=Tab)),
    tab_src,
  )

  // 4. Comments (#), empty arrays (key: [], [], - [0]:), strict numbers, nested arrays
  let comment_src =
    #|# header comment "with unclosed quote
    #|   # non-multiple space comment
    #|tags: []
    #|ratio: 1e5
    #|code: 05
    #|plus: +1
    #|matrix[2]:
    #|  - [2]: 1,2
    #|  - [0]:
  let decoded = @decode.decode(comment_src)
  guard decoded is Object(m) else { fail("expected object") }
  @test.assert_eq(m.get("tags"), Some(Json::array([])))
  @test.assert_eq(m.get("ratio"), Some(Json::number(100000.0)))
  @test.assert_eq(m.get("code"), Some(Json::string("05")))
  @test.assert_eq(m.get("plus"), Some(Json::string("+1")))
  @test.assert_eq(
    m.get("matrix"),
    Some(
      Json::array([
        Json::array([Json::number(1.0), Json::number(2.0)]),
        Json::array([]),
      ]),
    ),
  )

  // 5. UTF-16 non-BMP emoji keys + tabular URL colon disambiguation
  let mixed =
    #|👋k[2]: 1,2
    #|links[2]{id,url}:
    #|  1,https://moonbitlang.com:443
    #|  2,http://localhost:8080
  let mixed_decoded = @decode.decode(mixed)
  let canonical_mixed = @encode.encode(mixed_decoded)
  @test.assert_eq(
    canonical_mixed,
    (
      #|"👋k"[2]: 1,2
      #|links[2]{id,url}:
      #|  1,"https://moonbitlang.com:443"
      #|  2,"http://localhost:8080"
    ),
  )
  @test.assert_eq(@decode.decode(canonical_mixed), mixed_decoded)
}

///|
test "pinpoint caret diagnostics report exact line, column, error code, and snippet" {
  // 1. TOON 4.4 keyed header missing {fields}
  let e1 = capture_decode_err("users[2:]:\n  alice,1")
  @test.assert_eq(
    e1.format(),
    (
      #|DecodeError[E_HEADER] at line 1, column 6: keyed header '[N:]' requires a '{fields}' list
      #|  1 | users[2:]:
      #|    |      ^^^^
    ),
  )

  // 2. Delimiter mismatch between bracket [2|] and field list {a,b}
  let e2 = capture_decode_err("items[2|]{a,b}:\n  1|2\n  3|4")
  @test.assert_eq(
    e2.format(),
    (
      #|DecodeError[E_HEADER_DELIM] at line 1, column 11: header delimiter mismatch: bracket declares 'pipe' but field list contains unquoted 'comma'
      #|  1 | items[2|]{a,b}:
      #|    |           ^^^
    ),
  )

  // 3. Keyed entry row width mismatch highlights the cell span on line 3
  let e3 = capture_decode_err("users[2:]{a,b}:\n  alice: 1,2\n  bob: 3")
  @test.assert_eq(
    e3.format(),
    (
      #|DecodeError[E_WIDTH] at line 3, column 8: expected 2 keyed entry cells, but got 1
      #|  3 |   bob: 3
      #|    |        ^
    ),
  )

  // 4. Keyed entry missing colon in non-strict mode still errors on line 2
  let e4 = capture_decode_err(
    "users[1:]{a,b}:\n  bob 1,2",
    options=@types.DecodeOptions::new(strict=false),
  )
  @test.assert_eq(
    e4.format(),
    (
      #|DecodeError[E_COLON] at line 2, column 3: missing colon after key
      #|  2 |   bob 1,2
      #|    |   ^
    ),
  )

  // 5. Strict tab indentation visualizes tab as '→'
  let e5 = capture_decode_err("a:\n\tb: 1")
  @test.assert_eq(
    e5.format(),
    (
      #|DecodeError[E_INDENT] at line 2, column 1: tabs are not allowed in indentation in strict mode
      #|  2 | →b: 1
      #|    | ^
    ),
  )

  // 6. Quoted token trailing characters & invalid escape point directly at offending characters
  let e6 = capture_decode_err("k: \"a\" \"b\"")
  @test.assert_eq(
    e6.format(),
    (
      #|DecodeError[E_TRAILING] at line 1, column 7: unexpected characters after closing quote
      #|  1 | k: "a" "b"
      #|    |       ^^^^
    ),
  )
  let e7 = capture_decode_err("👋: \"bad\\q\"")
  @test.assert_eq(
    e7.format(),
    (
      #|DecodeError[E_ESCAPE] at line 1, column 8: invalid escape sequence '\q'
      #|  1 | 👋: "bad\q"
      #|    |        ^^
    ),
  )
}
