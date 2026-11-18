///|
fn build_warehouse_snapshot() -> Json {
  let skus : Array[Json] = []
  let warehouses = ["WH-SH", "WH-SZ", "WH-BJ"]
  for i in 0..<80 {
    let stock = (i * 11 + 3) % 60
    let reorder = 20
    skus.push(
      Json::object(
        Map([
          ("sku", Json::string("SKU-\{2000 + i}")),
          ("name", Json::string("Barcode Scanner Gen\{1 + i % 3}")),
          ("warehouse", Json::string(warehouses[i % warehouses.length()])),
          ("stock", Json::number(stock.to_double())),
          ("reorderPoint", Json::number(reorder.to_double())),
          ("lowStock", Json::boolean(stock <= reorder)),
        ]),
      ),
    )
  }
  // TOON 4.4 §9.5 keyed tabular warehouse metadata alongside uniform SKU array
  let wh_meta = Json::object(
    Map([
      (
        "WH-SH",
        Json::object(
          Map([
            ("city", Json::string("Shanghai")),
            ("leadDays", Json::number(2.0)),
            ("active", Json::boolean(true)),
          ]),
        ),
      ),
      (
        "WH-SZ",
        Json::object(
          Map([
            ("city", Json::string("Shenzhen")),
            ("leadDays", Json::number(1.0)),
            ("active", Json::boolean(true)),
          ]),
        ),
      ),
      (
        "WH-BJ",
        Json::object(
          Map([
            ("city", Json::string("Beijing")),
            ("leadDays", Json::number(3.0)),
            ("active", Json::boolean(true)),
          ]),
        ),
      ),
    ]),
  )
  Json::object(Map([("warehouses", wh_meta), ("inventory", Json::array(skus))]))
}

///|
fn main {
  let snapshot = build_warehouse_snapshot()
  println("=== 1. Cost & Token-Efficiency Pre-Check ===")
  let report = @toon4.analyze(snapshot) catch {
    err => {
      println(@toon4.format_encode_error(err))
      return
    }
  }
  println(report.render_report())

  println("\n=== 2. Encoded TOON v4.4 Payload (first 12 lines) ===")
  let lines = @toon4.encode_lines(snapshot) catch {
    err => {
      println(@toon4.format_encode_error(err))
      return
    }
  }
  let preview = if lines.length() > 12 { 12 } else { lines.length() }
  for i in 0..<preview {
    println(lines[i])
  }
  println("... (\{lines.length()} total lines)")

  println("\n=== 3. Round-Trip Verification ===")
  let toon_doc = lines.join("\n")
  let decoded = @toon4.decode(toon_doc) catch {
    err => {
      println(@toon4.format_decode_error(err))
      return
    }
  }
  println("Lossless round-trip equal: \{decoded == snapshot}")

  println("\n=== 4. Malformed Payload Pinpoint Diagnostic Demo ===")
  let broken_llm_reply =
    #|warehouses[3:]{city,leadDays,active}:
    #|  WH-SH: Shanghai,2,true
    #|  WH-SZ: Shenzhen,1
    #|  WH-BJ: Beijing,3,true
  ignore(@toon4.decode(broken_llm_reply)) catch {
    err => println(@toon4.format_decode_error(err))
  }
}
