///|
fn make_utf16_string(units : Array[Int32]) -> String {
  String::from_array(units.map(u => u.unsafe_to_char()))
}

///|
test "format_number handles specials, zero, canonical range, and large integer repr" {
  let nan = 0.0 / 0.0
  let pos_inf = 1.0 / 0.0
  let neg_inf = -1.0 / 0.0
  @test.assert_eq(@encode.format_number(nan), "null")
  @test.assert_eq(@encode.format_number(pos_inf), "null")
  @test.assert_eq(@encode.format_number(neg_inf), "null")
  @test.assert_eq(
    @encode.format_number(pos_inf, repr=Some("99999999999999999999")),
    "null",
  )
  @test.assert_eq(@encode.format_number(0.0), "0")
  @test.assert_eq(@encode.format_number(-0.0), "0")
  @test.assert_eq(@encode.format_number(-0.0, repr=Some("-0")), "0")
  @test.assert_eq(@encode.format_number(1.0), "1")
  @test.assert_eq(@encode.format_number(1.5), "1.5")
  @test.assert_eq(@encode.format_number(1.0e-6), "0.000001")
  @test.assert_eq(@encode.format_number(-1.0e-6), "-0.000001")
  @test.assert_eq(@encode.format_number(1.0e-7), "1e-7")
  @test.assert_eq(@encode.format_number(1.0e6), "1000000")
  @test.assert_eq(@encode.format_number(1.0e20), "100000000000000000000")
  @test.assert_eq(@encode.format_number(1.0e21), "1e+21")
  @test.assert_eq(
    @encode.format_number(0.3333333333333333),
    "0.3333333333333333",
  )
  @test.assert_eq(
    @encode.format_number(0.30000000000000004),
    "0.30000000000000004",
  )
  @test.assert_eq(@encode.format_number(9007199254740991.0), "9007199254740991")
  @test.assert_eq(
    @encode.format_number(123456789012345680000.0),
    "123456789012345680000",
  )
  @test.assert_eq(
    @encode.format_number(9007199254740992.0, repr=Some("9007199254740993")),
    "9007199254740993",
  )
  @test.assert_eq(
    @encode.format_number(-9007199254740992.0, repr=Some("-9007199254740993")),
    "-9007199254740993",
  )
  @test.assert_eq(@encode.format_number(42.0, repr=Some("042")), "42")
  @test.assert_eq(@encode.format_number(1.0e25, repr=Some("1e25")), "1e+25")
}

///|
test "primitives encoding: strings, BOM, combining marks, controls, emoji, numbers" {
  let nan = 0.0 / 0.0
  let pos_inf = 1.0 / 0.0
  let neg_inf = -1.0 / 0.0
  @test.assert_eq(@encode.encode(Json::string("hello")), "hello")
  @test.assert_eq(@encode.encode(Json::string("Ada_99")), "Ada_99")
  @test.assert_eq(@encode.encode(Json::string("")), "\"\"")
  @test.assert_eq(@encode.encode(Json::string("true")), "\"true\"")
  @test.assert_eq(@encode.encode(Json::string("false")), "\"false\"")
  @test.assert_eq(@encode.encode(Json::string("null")), "\"null\"")
  @test.assert_eq(@encode.encode(Json::string("42")), "\"42\"")
  @test.assert_eq(@encode.encode(Json::string("3.14")), "\"3.14\"")
  @test.assert_eq(@encode.encode(Json::string("1e-6")), "\"1e-6\"")
  @test.assert_eq(@encode.encode(Json::string("05")), "\"05\"")
  @test.assert_eq(@encode.encode(Json::string("+1")), "\"+1\"")
  @test.assert_eq(@encode.encode(Json::string("#hello")), "\"#hello\"")
  @test.assert_eq(@encode.encode(Json::string("- item")), "\"- item\"")
  @test.assert_eq(@encode.encode(Json::string("a-b #c")), "a-b #c")
  @test.assert_eq(@encode.encode(Json::string("a[test]")), "\"a[test]\"")
  @test.assert_eq(@encode.encode(Json::string("{key}")), "\"{key}\"")
  @test.assert_eq(
    @encode.encode(Json::string("Users\\path")),
    "\"Users\\\\path\"",
  )
  @test.assert_eq(@encode.encode(Json::string("café")), "café")
  @test.assert_eq(
    @encode.encode(Json::string("hello 👋 world")),
    "hello 👋 world",
  )
  @test.assert_eq(@encode.encode(Json::string("a,🚀")), "\"a,🚀\"")
  @test.assert_eq(@encode.encode(Json::string("\u{feff}8")), "\"\u{feff}8\"")
  @test.assert_eq(@encode.encode(Json::string("\u{feff}")), "\"\u{feff}\"")
  @test.assert_eq(@encode.encode(Json::boolean(true)), "true")
  @test.assert_eq(@encode.encode(Json::boolean(false)), "false")
  @test.assert_eq(@encode.encode(Json::null()), "null")
  @test.assert_eq(@encode.encode(Json::number(42.0)), "42")
  @test.assert_eq(@encode.encode(Json::number(-0.0)), "0")
  @test.assert_eq(@encode.encode(Json::number(nan)), "null")
  @test.assert_eq(@encode.encode(Json::number(pos_inf)), "null")
  @test.assert_eq(@encode.encode(Json::number(neg_inf)), "null")
  @test.assert_eq(
    @encode.encode(Json::number(123456789012345680000.0)),
    "123456789012345680000",
  )
  @test.assert_eq(
    @encode.encode(
      Json::number(123456789012345683968.0, repr="123456789012345680000"),
    ),
    "123456789012345680000",
  )
  @test.assert_eq(
    @encode.encode(Json::number(9007199254740992.0, repr="9007199254740993")),
    "9007199254740993",
  )
  let ctrl_obj : Json = {
    "val": "a\u{0004}\b\u{000c}b",
    "sep": "a:\u{007f}\u{0085}\u{2028}b",
  }
  @test.assert_eq(
    @encode.encode(ctrl_obj),
    "val: \"a\\u0004\\u0008\\u000cb\"\nsep: \"a:\u{007f}\u{0085}\u{2028}b\"",
  )
  let esc_arr : Json = ["line1\nline2", "tab\there", "return\rcarriage"]
  @test.assert_eq(
    @encode.encode(esc_arr),
    "[3]: \"line1\\nline2\",\"tab\\there\",\"return\\rcarriage\"",
  )
  let combining : Json = {
    "items": ["a,\u{0301}b", "-\u{0301}", "#\u{0301}"],
    "k": "x:\u{0301}",
  }
  @test.assert_eq(
    @encode.encode(combining),
    "items[3]: \"a,\u{0301}b\",\"-\u{0301}\",\"#\u{0301}\"\nk: \"x:\u{0301}\"",
  )
}

///|
test "objects encoding: empty, nested, quoted/dotted keys, BOM non-root, NBSP" {
  @test.assert_eq(@encode.encode(Json::empty_object()), "")
  @test.assert_eq(@encode.encode_lines(Json::empty_object()), [])
  let simple : Json = {
    "id": 123,
    "name": "Ada",
    "active": true,
    "value": null,
  }
  @test.assert_eq(
    @encode.encode(simple),
    "id: 123\nname: Ada\nactive: true\nvalue: null",
  )
  let quoted_keys : Json = {
    "order:id": 7,
    "[index]": 5,
    "{key}": 6,
    "a,b": 1,
    "full name": "Ada",
    " a ": 1,
    "-lead": 1,
    "a-b": 2,
    "123": "x",
    "": 1,
    "café": 1,
    "a.b": 1,
    "true": 2,
    "__proto__": "polluted",
  }
  @test.assert_eq(
    @encode.encode(quoted_keys),
    "\"order:id\": 7\n\"[index]\": 5\n\"{key}\": 6\n\"a,b\": 1\n\"full name\": Ada\n\" a \": 1\n\"-lead\": 1\n\"a-b\": 2\n\"123\": x\n\"\": 1\n\"café\": 1\na.b: 1\ntrue: 2\n__proto__: polluted",
  )
  let ctrl_keys : Json = {
    "line\n": 1,
    "he said \"hi\"": 2,
    "tab\there": 3,
    "a\u{0004}b": 4,
    "x\u{001f}y": 5,
  }
  @test.assert_eq(
    @encode.encode(ctrl_keys),
    "\"line\\n\": 1\n\"he said \\\"hi\\\"\": 2\n\"tab\\there\": 3\n\"a\\u0004b\": 4\n\"x\\u001fy\": 5",
  )
  let nested : Json = {
    "a": { "b": { "c": "deep" } },
    "user": {},
    "": { "x": 1 },
  }
  @test.assert_eq(
    @encode.encode(nested),
    "a:\n  b:\n    c: deep\nuser:\n\"\":\n  x: 1",
  )
  let unquoted_lookalikes : Json = {
    "a": ".5",
    "b": "NaN",
    "c": "True",
    "d": "\u{feff}x",
    "e": "a\u{007f}b",
    "f": "\u{0664}\u{0662}",
    "g": "\u{00a0}x\u{00a0}",
    "h": "1E6",
  }
  @test.assert_eq(
    @encode.encode(unquoted_lookalikes),
    "a: .5\nb: NaN\nc: True\nd: \u{feff}x\ne: a\u{007f}b\nf: \u{0664}\u{0662}\ng: \u{00a0}x\u{00a0}\nh: \"1E6\"",
  )
}

///|
test "headers and field segment helpers" {
  let fields : Array[@types.FieldNode] = [
    Leaf("id"),
    Group("customer", [
      Leaf("full name"),
      Group("geo", [Leaf("lat"), Leaf("lon")]),
    ]),
    Leaf("total"),
  ]
  @test.assert_eq(
    @encode.format_field_segment(fields, Comma),
    "id,customer{\"full name\",geo{lat,lon}},total",
  )
  @test.assert_eq(
    @encode.format_header(2, key=Some("orders"), fields=Some(fields)),
    "orders[2]{id,customer{\"full name\",geo{lat,lon}},total}:",
  )
  @test.assert_eq(
    @encode.format_header(
      2,
      key=Some("regions"),
      fields=Some([Leaf("name"), Group("geo", [Leaf("lat"), Leaf("lon")])]),
      delimiter=Pipe,
      keyed=true,
    ),
    "regions[2:|]{name|geo{lat|lon}}:",
  )
  @test.assert_eq(@encode.format_header(0, delimiter=Tab), "[0\t]:")
}

///|
test "primitive, nested, and mixed arrays" {
  @test.assert_eq(@encode.encode(Json::array([])), "[]")
  @test.assert_eq(
    @encode.encode({ "items": [], "": [1, 2, 3], "s": [""] }),
    "items: []\n\"\"[3]: 1,2,3\ns[1]: \"\"",
  )
  @test.assert_eq(
    @encode.encode(["x", "y", "true", true, 10]),
    "[5]: x,y,\"true\",true,10",
  )
  @test.assert_eq(
    @encode.encode({ "pairs": [["a", "b"], ["c,d", "e:f", "true"]] }),
    "pairs[2]:\n  - [2]: a,b\n  - [3]: \"c,d\",\"e:f\",\"true\"",
  )
  @test.assert_eq(
    @encode.encode({ "pairs": [[], []] }),
    "pairs[2]:\n  - [0]:\n  - [0]:",
  )
  @test.assert_eq(@encode.encode([[1, 2], []]), "[2]:\n  - [2]: 1,2\n  - [0]:")
  @test.assert_eq(@encode.encode([[[1]]]), "[1]:\n  - [1]:\n    - [1]: 1")
  @test.assert_eq(
    @encode.encode({ "a": [[{ "x": 1 }, { "x": 2 }]] }),
    "a[1]:\n  - [2]:\n    - x: 1\n    - x: 2",
  )
  @test.assert_eq(
    @encode.encode([
      "summary",
      { "id": 1, "name": "Ada" },
      [{ "id": 2 }, { "status": "draft" }],
    ]),
    "[3]:\n  - summary\n  - id: 1\n    name: Ada\n  - [2]:\n    - id: 2\n    - status: draft",
  )
  @test.assert_eq(
    @encode.encode({ "a": [[1, { "x": 1 }], 2] }),
    "a[2]:\n  - [2]:\n    - 1\n    - x: 1\n  - 2",
  )
}

///|
test "tabular arrays including nested FieldNode groups and fallbacks" {
  let root_tab : Json = [{ "id": 1 }, { "id": 2 }]
  @test.assert_eq(@encode.encode(root_tab), "[2]{id}:\n  1\n  2")
  let orders : Json = {
    "orders": [
      { "id": 1, "customer": { "name": "Ada", "country": "DK" }, "total": 99 },
      { "id": 2, "customer": { "country": "UK", "name": "Bob" }, "total": 149 },
    ],
  }
  @test.assert_eq(
    @encode.encode(orders),
    "orders[2]{id,customer{name,country},total}:\n  1,Ada,DK,99\n  2,Bob,UK,149",
  )
  let deep : Json = {
    "items": [
      { "id": 1, "geo": { "point": { "lat": 1.5, "lon": 2.5 } } },
      { "id": 2, "geo": { "point": { "lat": 3, "lon": 4 } } },
    ],
  }
  @test.assert_eq(
    @encode.encode(deep),
    "items[2]{id,geo{point{lat,lon}}}:\n  1,1.5,2.5\n  2,3,4",
  )
  // Keyed-eligible object inside tabular column collapses as nested field group, not keyed form
  let col_keyed_shape : Json = {
    "a": [{ "t": { "p": { "x": 1 }, "q": { "x": 2 } }, "other": 9 }],
  }
  @test.assert_eq(
    @encode.encode(col_keyed_shape),
    "a[1]{t{p{x},q{x}},other}:\n  1,2,9",
  )
  // Fallbacks to list form
  let diff_nested : Json = {
    "entries": [
      { "id": 1, "meta": { "a": 1 } },
      { "id": 2, "meta": { "b": 2 } },
    ],
  }
  @test.assert_eq(
    @encode.encode(diff_nested),
    "entries[2]:\n  - id: 1\n    meta:\n      a: 1\n  - id: 2\n    meta:\n      b: 2",
  )
  let null_mix : Json = {
    "orders": [
      { "id": 1, "customer": { "name": "Ada" } },
      { "id": 2, "customer": null },
    ],
  }
  @test.assert_eq(
    @encode.encode(null_mix),
    "orders[2]:\n  - id: 1\n    customer:\n      name: Ada\n  - id: 2\n    customer: null",
  )
  let nested_arr : Json = {
    "orders": [{ "id": 1, "customer": { "name": "Ada", "tags": ["x"] } }],
  }
  @test.assert_eq(
    @encode.encode(nested_arr),
    "orders[1]:\n  - id: 1\n    customer:\n      name: Ada\n      tags[1]: x",
  )
  let nested_empty : Json = { "items": [{ "id": 1, "meta": {} }] }
  @test.assert_eq(
    @encode.encode(nested_empty),
    "items[1]:\n  - id: 1\n    meta:",
  )
  let empty_elems : Json = { "items": [{}, {}] }
  @test.assert_eq(@encode.encode(empty_elems), "items[2]:\n  -\n  -")
  // Direct tabular helpers
  let rows : Array[Json] = [
    { "id": 1, "n": { "x": "a", "y": true } },
    { "id": 2, "n": { "y": false, "x": "b" } },
  ]
  guard @encode.extract_tabular_fields(rows) is Some(f) else {
    @test.fail("expected tabular fields")
  }
  @test.assert_eq(f, [Leaf("id"), Group("n", [Leaf("x"), Leaf("y")])])
  let leaves : Array[Json] = []
  guard rows[1] is Object(row1) else { @test.fail("expected object") }
  @encode.collect_row_leaves(row1, f, leaves)
  @test.assert_eq(leaves, [
    Json::number(2.0),
    Json::string("b"),
    Json::boolean(false),
  ])
  @test.assert_eq(@encode.extract_tabular_fields([]), None)
}

///|
test "keyed tabular objects: root, nested groups, delimiters, fallbacks, list-item first field" {
  let root_keyed : Json = {
    "alice": { "age": 30, "city": "Berlin" },
    "bob": { "age": 25, "city": "Oslo" },
  }
  @test.assert_eq(
    @encode.encode(root_keyed),
    "[2:]{age,city}:\n  alice: 30,Berlin\n  bob: 25,Oslo",
  )
  let nested_keyed : Json = {
    "regions": {
      "eu": { "name": "Europe", "geo": { "lat": 50, "lon": 10 } },
      "us": { "name": "America", "geo": { "lat": 40, "lon": -100 } },
    },
  }
  @test.assert_eq(
    @encode.encode(nested_keyed),
    "regions[2:]{name,geo{lat,lon}}:\n  eu: Europe,50,10\n  us: America,40,-100",
  )
  let pipe_keyed : Json = {
    "servers": {
      "alpha": { "host": "a.example.com", "port": 8080, "note": "x|y" },
      "beta": { "host": "b.example.com", "port": 9090, "note": "p,q" },
    },
  }
  @test.assert_eq(
    @encode.encode(
      pipe_keyed,
      options=@types.EncodeOptions::new(delimiter=Pipe),
    ),
    "servers[2:|]{host|port|note}:\n  alpha: a.example.com|8080|\"x|y\"\n  beta: b.example.com|9090|p,q",
  )
  @test.assert_eq(
    @encode.encode(pipe_keyed, options=@types.EncodeOptions::new(delimiter=Tab)),
    "servers[2:\t]{host\tport\tnote}:\n  alpha: a.example.com\t8080\tx|y\n  beta: b.example.com\t9090\tp,q",
  )
  let quoted_entry_keys : Json = {
    "ids": { "42": { "v": 1 }, "my key": { "v": 2 } },
  }
  @test.assert_eq(
    @encode.encode(quoted_entry_keys),
    "ids[2:]{v}:\n  \"42\": 1\n  \"my key\": 2",
  )
  // Fallbacks
  let single_entry : Json = { "config": { "only": { "a": 1, "b": 2 } } }
  @test.assert_eq(
    @encode.encode(single_entry),
    "config:\n  only:\n    a: 1\n    b: 2",
  )
  let empty_entries : Json = { "m": { "a": {}, "b": {} } }
  @test.assert_eq(@encode.encode(empty_entries), "m:\n  a:\n  b:")
  let arr_in_entry : Json = {
    "m": { "a": { "tags": ["x"] }, "b": { "tags": ["y"] } },
  }
  @test.assert_eq(
    @encode.encode(arr_in_entry),
    "m:\n  a:\n    tags[1]: x\n  b:\n    tags[1]: y",
  )
  // Anonymous array element is never keyed tabular
  let anon_elem : Json = { "items": [{ "a": { "x": 1 }, "b": { "x": 2 } }, 5] }
  @test.assert_eq(
    @encode.encode(anon_elem),
    "items[2]:\n  - a:\n      x: 1\n    b:\n      x: 2\n  - 5",
  )
  // List-item first field keyed tabular
  let list_first_keyed : Json = {
    "items": [
      { "config": { "a": { "x": 1 }, "b": { "x": 2 } }, "status": "ok" },
      { "status": "down" },
    ],
  }
  @test.assert_eq(
    @encode.encode(list_first_keyed),
    "items[2]:\n  - config[2:]{x}:\n      a: 1\n      b: 2\n    status: ok\n  - status: down",
  )
  @test.assert_eq(
    @encode.extract_keyed_tabular_fields({ "only": { "a": Json::number(1.0) } }),
    None,
  )
}

///|
test "objects as list items, custom indentSize, delimiters, and streaming" {
  let list_items : Json = {
    "items": [
      {
        "users": [{ "id": 1, "name": "Ada" }, { "id": 2, "name": "Bob" }],
        "status": "active",
      },
      { "data": [], "name": "Ada" },
      { "a": {}, "b": 1 },
      {
        "id": 1,
        "users": [{ "id": 3, "name": "Cy" }, { "id": 4, "name": "Dee" }],
      },
    ],
  }
  @test.assert_eq(
    @encode.encode(list_items),
    "items[4]:\n  - users[2]{id,name}:\n      1,Ada\n      2,Bob\n    status: active\n  - data: []\n    name: Ada\n  - a:\n    b: 1\n  - id: 1\n    users[2]{id,name}:\n      3,Cy\n      4,Dee",
  )
  let indent4_obj : Json = { "a": [{ "b": 1, "c": 2 }, 1] }
  @test.assert_eq(
    @encode.encode(
      indent4_obj,
      options=@types.EncodeOptions::new(indent_size=4),
    ),
    "a[2]:\n    - b: 1\n        c: 2\n    - 1",
  )
  let pipe_mixed : Json = {
    "pairs": [["a", "b"], ["c", "d"]],
    "items": [{ "k": [[1, { "x": 1 }]] }],
  }
  @test.assert_eq(
    @encode.encode(
      pipe_mixed,
      options=@types.EncodeOptions::new(delimiter=Pipe),
    ),
    "pairs[2|]:\n  - [2|]: a|b\n  - [2|]: c|d\nitems[1|]:\n  - k[1|]:\n      - [2|]:\n        - 1\n        - x: 1",
  )
  @test.assert_eq(
    @encode.encode(
      Json::string("a,b"),
      options=@types.EncodeOptions::new(delimiter=Pipe),
    ),
    "a,b",
  )
  @test.assert_eq(
    @encode.encode(
      { "a": ["x|y", "p,q", { "b": 1 }] },
      options=@types.EncodeOptions::new(delimiter=Pipe),
    ),
    "a[3|]:\n  - \"x|y\"\n  - p,q\n  - b: 1",
  )
  let streamed : Array[String] = []
  @encode.encode_to_lines({ "k": [1, 2] }, line => streamed.push(line))
  @test.assert_eq(streamed, ["k[2]: 1,2"])
  @test.assert_eq(@encode.encode_lines({ "a": 1, "b": { "c": 2 } }), [
    "a: 1", "b:", "  c: 2",
  ])
  // Empty array inside mixed array must use `- [0<delim?>]:`, never `- []`
  @test.assert_eq(
    @encode.encode(
      [Json::array([]), { "a": 1 }],
      options=@types.EncodeOptions::new(delimiter=Pipe),
    ),
    "[2|]:\n  - [0|]:\n  - a: 1",
  )
  // List item with nested non-empty object first field, and later keyed tabular field
  let complex_list : Json = {
    "items": [
      { "a": { "b": 1 }, "c": 2 },
      { "id": 1, "cfg": { "k1": { "x": 1 }, "k2": { "x": 2 } } },
    ],
  }
  @test.assert_eq(
    @encode.encode(complex_list),
    "items[2]:\n  - a:\n      b: 1\n    c: 2\n  - id: 1\n    cfg[2:]{x}:\n      k1: 1\n      k2: 2",
  )
}

///|
test "errors: invalid options and unpaired UTF-16 surrogates" {
  @test.assert_raise(() => {
    @encode.encode(
      Json::null(),
      options=@types.EncodeOptions::new(indent_size=0),
    )
    |> ignore
  })
  let high = make_utf16_string([0xD800])
  let low = make_utf16_string([0xDC00])
  let swapped = make_utf16_string([0xDC00, 0xD800])
  let valid_pair = make_utf16_string([0xD83D, 0xDE80])
  @test.assert_eq(@encode.encode_string_literal(valid_pair, Comma), "🚀")
  @test.assert_eq(
    @encode.encode_string_literal("\u{feff}x", Comma, is_root=false),
    "\u{feff}x",
  )
  @test.assert_eq(
    @encode.encode_string_literal("\u{feff}x", Comma, is_root=true),
    "\"\u{feff}x\"",
  )
  @test.assert_raise(() => @encode.encode_string_literal(high, Comma) |> ignore)
  @test.assert_raise(() => @encode.encode_string_literal(low, Comma) |> ignore)
  @test.assert_raise(() => @encode.encode_key(swapped) |> ignore)
  @test.assert_raise(() => @encode.encode(Json::string(high)) |> ignore)
  let mut caught_path : String? = None
  try @encode.encode({ "nested": [Json::string(low)] }) |> ignore catch {
    @types.EncodeError(path~, ..) => caught_path = path
  }
  @test.assert_eq(caught_path, Some("nested[0]"))
  @test.assert_raise(() => {
    let bad_obj : Map[String, Json] = Map([])
    bad_obj[high] = Json::number(1.0)
    @encode.encode(Json::object(bad_obj)) |> ignore
  })
  @test.assert_raise(() => {
    let r1 : Map[String, Json] = Map([])
    r1[high] = Json::number(1.0)
    @encode.encode(Json::array([Json::object(r1)])) |> ignore
  })
  @test.assert_raise(() => {
    @encode.encode({ "rows": [{ "a": Json::string(low) }] }) |> ignore
  })
  @test.assert_raise(() => {
    let bad_keyed : Map[String, Json] = Map([])
    bad_keyed[high] = { "x": Json::number(1.0) }
    bad_keyed["ok"] = { "x": Json::number(2.0) }
    @encode.encode(Json::object(bad_keyed)) |> ignore
  })
}
