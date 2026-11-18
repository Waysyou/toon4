///|
test "spec_version targets TOON 4.4" {
  @test.assert_eq(@toon4.spec_version(), "4.4")
}

///|
test "top-level facade end-to-end encode, decode, stream, and analyze" {
  let records : Array[Json] = []
  for i in 0..<25 {
    records.push(
      Json::object(
        Map([
          ("sku", Json::string("ITEM-\{100 + i}")),
          ("stock", Json::number((30 - i).to_double())),
          ("reorder", Json::number(10.0)),
        ]),
      ),
    )
  }
  let doc = Json::object(Map([("inventory", Json::array(records))]))
  let encoded = @toon4.encode(doc)
  let decoded = @toon4.decode(encoded)
  @test.assert_eq(decoded, doc)

  let events : Array[@toon4.StreamEvent] = []
  @toon4.decode_stream(encoded, ev => events.push(ev))
  assert_true(events.length() > 10)

  let report = @toon4.analyze(doc)
  @test.assert_eq(report.verdict, @toon4.VerdictKind::RecommendToon)
  assert_true(@toon4.measure_text(encoded).utf8_bytes > 0)
}

///|
test "top-level facade surfaces pinpoint diagnostics" {
  let err_msg = try {
    ignore(@toon4.decode("users[2:]:\n  a: 1"))
    ""
  } catch {
    err => @toon4.format_decode_error(err)
  }
  assert_true(err_msg.contains("DecodeError[E_HEADER]"))
  assert_true(err_msg.contains("users[2:]:"))
}
