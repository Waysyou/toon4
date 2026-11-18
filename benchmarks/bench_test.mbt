///|
fn build_inventory_payload(count : Int32) -> Json {
  let items : Array[Json] = []
  let warehouses = ["SH-East", "SZ-South", "BJ-North", "CD-West"]
  let categories = ["sensor", "actuator", "cable", "controller"]
  for i in 0..<count {
    items.push(
      Json::object(
        Map([
          ("sku", Json::string("SKU-\{1000 + i}")),
          ("name", Json::string("Industrial Module \{i}")),
          ("category", Json::string(categories[i % categories.length()])),
          ("stock", Json::number((i * 7 % 120).to_double())),
          ("reorderPoint", Json::number(25.0)),
          ("warehouse", Json::string(warehouses[i % warehouses.length()])),
          ("unitPrice", Json::number(12.5 + (i % 15).to_double())),
          ("active", Json::boolean(i % 9 != 0)),
        ]),
      ),
    )
  }
  Json::object(Map([("inventory", Json::array(items))]))
}

///|
fn build_keyed_flags_payload(count : Int32) -> Json {
  let flags : Map[String, Json] = Map([])
  let owners = ["platform", "search", "billing", "agent-core"]
  let tiers = ["free", "pro", "enterprise"]
  for i in 0..<count {
    flags["flag_rollout_\{i}"] = Json::object(
      Map([
        ("enabled", Json::boolean(i % 2 == 0)),
        ("rollout", Json::number((i * 5 % 100).to_double())),
        ("owner", Json::string(owners[i % owners.length()])),
        ("tier", Json::string(tiers[i % tiers.length()])),
      ]),
    )
  }
  Json::object(Map([("flags", Json::object(flags))]))
}

///|
fn build_nested_orders_payload(count : Int32) -> Json {
  let orders : Array[Json] = []
  for i in 0..<count {
    let order : Map[String, Json] = Map([
      ("orderId", Json::string("ORD-\{5000 + i}")),
      (
        "customer",
        Json::object(
          Map([
            ("id", Json::number((i + 1).to_double())),
            ("name", Json::string("Customer \{i}")),
            ("region", Json::string("apac")),
          ]),
        ),
      ),
      (
        "items",
        Json::array([
          Json::object(
            Map([
              ("sku", Json::string("SKU-\{100 + i % 10}")),
              ("qty", Json::number((1 + i % 4).to_double())),
              ("price", Json::number(29.5)),
            ]),
          ),
        ]),
      ),
      ("total", Json::number(88.5)),
    ])
    if i % 2 == 1 {
      order["shippingNote"] = Json::string("deliver before 18:00")
    }
    orders.push(Json::object(order))
  }
  Json::object(Map([("orders", Json::array(orders))]))
}

///|
test "benchmark datasets round-trip and match advisor verdicts" {
  let inv = build_inventory_payload(60)
  let flags = build_keyed_flags_payload(40)
  let orders = build_nested_orders_payload(20)
  @test.assert_eq(@toon4.decode(@toon4.encode(inv)), inv)
  @test.assert_eq(@toon4.decode(@toon4.encode(flags)), flags)
  @test.assert_eq(@toon4.decode(@toon4.encode(orders)), orders)
  @test.assert_eq(@toon4.analyze(inv).verdict, RecommendToon)
  @test.assert_eq(@toon4.analyze(flags).verdict, RecommendToon)
  @test.assert_eq(@toon4.analyze(orders).verdict, KeepCompactJson)
}

///|
test "bench encode inventory_200" (it : @bench.T) {
  let payload = build_inventory_payload(200)
  it.bench(name="encode_inventory_200", () => {
    let out = @toon4.encode(payload) catch { _ => abort("bench encode") }
    it.keep(out)
  })
}

///|
test "bench decode inventory_200" (it : @bench.T) {
  let encoded = @toon4.encode(build_inventory_payload(200))
  it.bench(name="decode_inventory_200", () => {
    let doc = @toon4.decode(encoded) catch { _ => abort("bench decode") }
    it.keep(doc)
  })
}

///|
test "bench encode keyed_flags_80" (it : @bench.T) {
  let payload = build_keyed_flags_payload(80)
  it.bench(name="encode_keyed_flags_80", () => {
    let out = @toon4.encode(payload) catch { _ => abort("bench encode") }
    it.keep(out)
  })
}

///|
test "bench decode keyed_flags_80" (it : @bench.T) {
  let encoded = @toon4.encode(build_keyed_flags_payload(80))
  it.bench(name="decode_keyed_flags_80", () => {
    let doc = @toon4.decode(encoded) catch { _ => abort("bench decode") }
    it.keep(doc)
  })
}

///|
test "bench advisor inventory_200 and nested_orders_50" (it : @bench.T) {
  let inv = build_inventory_payload(200)
  let orders = build_nested_orders_payload(50)
  it.bench(name="analyze_inventory_200", () => {
    let rep = @toon4.analyze(inv) catch { _ => abort("bench analyze") }
    it.keep(rep)
  })
  it.bench(name="analyze_nested_orders_50", () => {
    let rep = @toon4.analyze(orders) catch { _ => abort("bench analyze") }
    it.keep(rep)
  })
}
