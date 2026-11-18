///|
test "advisor recommends TOON on uniform inventory records" {
  let items : Array[Json] = []
  for i in 0..<40 {
    items.push(
      Json::object(
        Map([
          ("sku", Json::string("SKU-00\{i}")),
          ("name", Json::string("Warehouse Sensor \{i}")),
          ("stock", Json::number((100 - i).to_double())),
          ("reorderPoint", Json::number(25.0)),
          ("warehouse", Json::string("SH-East")),
          ("active", Json::boolean(true)),
        ]),
      ),
    )
  }
  let payload = Json::object(Map([("inventory", Json::array(items))]))
  let report = @advisor.analyze(payload)
  @test.assert_eq(report.verdict, RecommendToon)
  @test.assert_eq(report.audit.tabular_coverage_pct, 100.0)
  @test.assert_eq(report.audit.array_tabular_blocks, 1)
  assert_true(report.best_toon.delta_vs_compact_pct <= -20.0)
  assert_true(report.best_toon.utf8_bytes < report.compact_json.utf8_bytes)
  assert_true(report.render_report().contains("RECOMMEND_TOON"))
}

///|
test "advisor recommends TOON on TOON 4.4 keyed feature flags" {
  let flags : Map[String, Json] = Map([])
  for i in 0..<25 {
    flags["feature_flag_\{i}"] = Json::object(
      Map([
        ("enabled", Json::boolean(i % 2 == 0)),
        ("rollout", Json::number((i * 4 % 100).to_double())),
        ("owner", Json::string("platform")),
        ("tier", Json::string("enterprise")),
      ]),
    )
  }
  let payload = Json::object(Map([("flags", Json::object(flags))]))
  let report = @advisor.analyze(payload)
  @test.assert_eq(report.verdict, RecommendToon)
  @test.assert_eq(report.audit.keyed_tabular_blocks, 1)
  @test.assert_eq(report.audit.tabular_coverage_pct, 100.0)
  assert_true(report.best_toon.delta_vs_compact_pct <= -15.0)
}

///|
test "advisor detects non-uniform nested e-commerce orders and advises KeepCompactJson" {
  let orders : Array[Json] = []
  for i in 0..<20 {
    let order : Map[String, Json] = Map([
      ("orderId", Json::string("ORD-\{1000 + i}")),
      (
        "customer",
        Json::object(
          Map([
            ("id", Json::number(i.to_double())),
            ("name", Json::string("Buyer \{i}")),
            ("tier", Json::string("vip")),
          ]),
        ),
      ),
      (
        "items",
        Json::array([
          Json::object(
            Map([
              ("sku", Json::string("A1")),
              ("qty", Json::number(2.0)),
              ("price", Json::number(19.5)),
            ]),
          ),
        ]),
      ),
      ("total", Json::number(39.0)),
    ])
    // Half the orders carry an optional field, breaking top-level tabular eligibility
    if i % 2 == 1 {
      order["shippingNote"] = Json::string("leave at reception desk")
    }
    orders.push(Json::object(order))
  }
  let payload = Json::object(Map([("orders", Json::array(orders))]))
  let report = @advisor.analyze(payload)
  @test.assert_eq(report.verdict, KeepCompactJson)
  assert_true(report.best_toon.delta_vs_compact_pct > 2.0)
  assert_true(report.audit.fallbacks.length() >= 1)
  assert_true(report.render_report().contains("KEEP_COMPACT_JSON"))
}

///|
test "advisor flags tiny payload as Marginal due to prompt-tax threshold" {
  let tiny = Json::object(
    Map([
      (
        "users",
        Json::array([
          Json::object(
            Map([("id", Json::number(1.0)), ("name", Json::string("Ada"))]),
          ),
          Json::object(
            Map([("id", Json::number(2.0)), ("name", Json::string("Bob"))]),
          ),
        ]),
      ),
    ]),
  )
  let report = @advisor.analyze(tiny)
  @test.assert_eq(report.verdict, Marginal)
  let json_summary = report.to_json()
  guard json_summary is Object(m) else { @test.fail("expected json object") }
  @test.assert_eq(m.get("verdict"), Some(Json::string("MARGINAL")))
}
