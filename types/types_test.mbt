///|
test "Delimiter round-trip and suffixes" {
  @test.assert_eq(@types.Delimiter::Comma.to_char(), ',')
  @test.assert_eq(@types.Delimiter::Tab.to_char(), '\t')
  @test.assert_eq(@types.Delimiter::Pipe.to_char(), '|')
  @test.assert_eq(@types.Delimiter::from_char(','), Some(Comma))
  @test.assert_eq(@types.Delimiter::from_char('\t'), Some(Tab))
  @test.assert_eq(@types.Delimiter::from_char('|'), Some(Pipe))
  @test.assert_eq(@types.Delimiter::from_char(';'), None)
  @test.assert_eq(@types.Delimiter::Comma.header_suffix(), "")
  @test.assert_eq(@types.Delimiter::Tab.header_suffix(), "\t")
  @test.assert_eq(@types.Delimiter::Pipe.header_suffix(), "|")
}

///|
test "FieldNode nested leaves and same-level duplicate detection" {
  let fields : Array[@types.FieldNode] = [
    Leaf("id"),
    Group("customer", [Leaf("name"), Group("geo", [Leaf("lat"), Leaf("lon")])]),
    Leaf("total"),
  ]
  @test.assert_eq(@types.count_leaf_fields(fields), 5)
  let names : Array[String] = []
  for f in fields {
    f.collect_leaves(names)
  }
  @test.assert_eq(names, ["id", "name", "lat", "lon", "total"])
  @test.assert_eq(@types.find_duplicate_field(fields), None)

  // Duplicate at different nesting levels `{x,n{x}}` is allowed per §9.3
  let cross_level : Array[@types.FieldNode] = [
    Leaf("x"),
    Group("n", [Leaf("x")]),
  ]
  @test.assert_eq(@types.find_duplicate_field(cross_level), None)

  // Duplicate at same brace level `{a,a}` or `{n{x,x}}` is detected
  let same_level : Array[@types.FieldNode] = [Leaf("a"), Leaf("a")]
  @test.assert_eq(@types.find_duplicate_field(same_level), Some("a"))
  let nested_dup : Array[@types.FieldNode] = [
    Group("n", [Leaf("x"), Leaf("x")]),
  ]
  @test.assert_eq(@types.find_duplicate_field(nested_dup), Some("x"))
}

///|
test "Options validation" {
  let bad_enc = @types.EncodeOptions::new(indent_size=0)
  @test.assert_raise(() => bad_enc.validate())
  let bad_dec = @types.DecodeOptions::new(indent_size=-1)
  @test.assert_raise(() => bad_dec.validate())
  @types.EncodeOptions::default().validate()
  @types.DecodeOptions::default().validate()
}

///|
test "DecodeError diagnostic caret formatting with tabs" {
  let err = @types.DecodeError::new(
    kind=@types.ErrorKind::MalformedHeader,
    message="expected '{fields}' after keyed bracket segment",
    span=@types.Span::at(4, 9, length=4),
    source_line=Some("\tusers[2:]:"),
  )
  let rendered = err.format()
  let expected =
    #|DecodeError[E_HEADER] at line 4, column 9: expected '{fields}' after keyed bracket segment
    #|  4 | →users[2:]:
    #|    |         ^^^^
  @test.assert_eq(rendered, expected)
}
