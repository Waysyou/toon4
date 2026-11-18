///|
/// High-level actionable recommendation from comparing TOON vs Compact JSON.
#derive(Eq, @debug.Debug)
pub(all) enum VerdictKind {
  RecommendToon
  Marginal
  KeepCompactJson
}

///|
/// Returns a stable uppercase tag for CLI/JSON reporting.
pub fn VerdictKind::label(self : VerdictKind) -> String {
  match self {
    RecommendToon => "RECOMMEND_TOON"
    Marginal => "MARGINAL"
    KeepCompactJson => "KEEP_COMPACT_JSON"
  }
}

///|
/// Per-format serialization and efficiency measurement.
#derive(Eq, @debug.Debug)
pub(all) struct FormatStats {
  name : String
  delimiter : @types.Delimiter?
  text : String
  utf8_bytes : Int32
  chars : Int32
  structural_bytes : Int32
  estimated_tokens : Int32
  delta_vs_compact_pct : Double
  delta_vs_pretty_pct : Double
}

///|
/// Complete cost-efficiency and tabular diagnostic report for a JSON document.
#derive(Eq, @debug.Debug)
pub(all) struct CostReport {
  pretty_json : FormatStats
  compact_json : FormatStats
  toon_comma : FormatStats
  toon_tab : FormatStats
  toon_pipe : FormatStats
  best_toon : FormatStats
  audit : StructuralAudit
  verdict : VerdictKind
  reason : String
}

///|
fn round1(x : Double) -> Double {
  (x * 10.0).round() / 10.0
}

///|
fn format_pct1(pct : Double) -> String {
  let r = round1(pct)
  let tenths = (r.abs() * 10.0).round().to_int()
  let whole = tenths / 10
  let frac = tenths % 10
  let neg = if r < 0.0 && tenths > 0 { "-" } else { "" }
  "\{neg}\{whole}.\{frac}%"
}

///|
fn format_signed_pct1(pct : Double) -> String {
  let r = round1(pct)
  let tenths = (r.abs() * 10.0).round().to_int()
  let whole = tenths / 10
  let frac = tenths % 10
  let sign = if r > 0.0 && tenths > 0 {
    "+"
  } else if r < 0.0 && tenths > 0 {
    "-"
  } else {
    ""
  }
  "\{sign}\{whole}.\{frac}%"
}

///|
fn pct_delta(target : Int32, baseline : Int32) -> Double {
  if baseline <= 0 {
    0.0
  } else {
    (target - baseline).to_double() * 100.0 / baseline.to_double()
  }
}

///|
fn make_format_stats(
  name : String,
  delimiter : @types.Delimiter?,
  text : String,
  compact_tokens : Int32,
  pretty_tokens : Int32,
) -> FormatStats {
  let m = measure_text(text)
  {
    name,
    delimiter,
    text,
    utf8_bytes: m.utf8_bytes,
    chars: m.chars,
    structural_bytes: m.structural_bytes,
    estimated_tokens: m.estimated_tokens,
    delta_vs_compact_pct: pct_delta(m.estimated_tokens, compact_tokens),
    delta_vs_pretty_pct: pct_delta(m.estimated_tokens, pretty_tokens),
  }
}

///|
fn pick_better(a : FormatStats, b : FormatStats) -> FormatStats {
  if b.estimated_tokens < a.estimated_tokens {
    b
  } else if b.estimated_tokens == a.estimated_tokens &&
    b.utf8_bytes < a.utf8_bytes {
    b
  } else {
    a
  }
}

///|
/// Evaluates `value` across Pretty JSON, Compact JSON, and TOON (comma, tab,
/// pipe), returning byte/token measurements, tabular coverage audit, and an
/// explicit recommendation on whether TOON is worthwhile.
pub fn analyze(
  value : Json,
  indent_size~ : Int32 = 2,
) -> CostReport raise @types.EncodeError {
  let pretty_text = value.stringify(indent=indent_size)
  let compact_text = value.stringify(indent=0)
  let pretty_m = measure_text(pretty_text)
  let compact_m = measure_text(compact_text)

  let toon_comma_text = @encode.encode(
    value,
    options=@types.EncodeOptions::new(indent_size~, delimiter=Comma),
  )
  let toon_tab_text = @encode.encode(
    value,
    options=@types.EncodeOptions::new(indent_size~, delimiter=Tab),
  )
  let toon_pipe_text = @encode.encode(
    value,
    options=@types.EncodeOptions::new(indent_size~, delimiter=Pipe),
  )

  let pretty_json = {
    name: "JSON (pretty)",
    delimiter: None,
    text: pretty_text,
    utf8_bytes: pretty_m.utf8_bytes,
    chars: pretty_m.chars,
    structural_bytes: pretty_m.structural_bytes,
    estimated_tokens: pretty_m.estimated_tokens,
    delta_vs_compact_pct: pct_delta(
      pretty_m.estimated_tokens,
      compact_m.estimated_tokens,
    ),
    delta_vs_pretty_pct: 0.0,
  }
  let compact_json = {
    name: "JSON (compact)",
    delimiter: None,
    text: compact_text,
    utf8_bytes: compact_m.utf8_bytes,
    chars: compact_m.chars,
    structural_bytes: compact_m.structural_bytes,
    estimated_tokens: compact_m.estimated_tokens,
    delta_vs_compact_pct: 0.0,
    delta_vs_pretty_pct: pct_delta(
      compact_m.estimated_tokens,
      pretty_m.estimated_tokens,
    ),
  }
  let toon_comma = make_format_stats(
    "TOON (comma)",
    Some(Comma),
    toon_comma_text,
    compact_m.estimated_tokens,
    pretty_m.estimated_tokens,
  )
  let toon_tab = make_format_stats(
    "TOON (tab)",
    Some(Tab),
    toon_tab_text,
    compact_m.estimated_tokens,
    pretty_m.estimated_tokens,
  )
  let toon_pipe = make_format_stats(
    "TOON (pipe)",
    Some(Pipe),
    toon_pipe_text,
    compact_m.estimated_tokens,
    pretty_m.estimated_tokens,
  )

  let best_toon = pick_better(pick_better(toon_comma, toon_tab), toon_pipe)
  let audit = audit_structure(value)

  let delta_compact = best_toon.delta_vs_compact_pct
  let delta_pretty = best_toon.delta_vs_pretty_pct
  let delim_label = match best_toon.delimiter {
    Some(d) => d.label()
    None => "comma"
  }
  let cov_str = format_pct1(audit.tabular_coverage_pct)
  let delta_c_str = format_signed_pct1(delta_compact)
  let delta_p_str = format_signed_pct1(delta_pretty)

  let saved_tokens = compact_m.estimated_tokens - best_toon.estimated_tokens
  let (verdict, reason) = if delta_compact > 2.0 {
    (
      KeepCompactJson,
      "Keep compact JSON: TOON (\{delim_label}) adds \{delta_c_str} estimated tokens vs compact JSON (tabular coverage \{cov_str}; \{audit.fallbacks.length()} non-tabular path(s)).",
    )
  } else if compact_m.estimated_tokens < 45 ||
    (saved_tokens >= 0 && saved_tokens < 12) {
    (
      Marginal,
      "Small payload (~\{compact_m.estimated_tokens} compact tokens, saving ~\{saved_tokens} tok): TOON (\{delim_label}) is \{delta_c_str} vs compact JSON, where prompt format instructions may offset raw savings.",
    )
  } else if delta_compact <= -8.0 {
    (
      RecommendToon,
      "Recommend TOON (\{delim_label}): \{delta_c_str} estimated tokens vs compact JSON (\{delta_p_str} vs pretty JSON), tabular coverage \{cov_str}.",
    )
  } else {
    (
      Marginal,
      "Marginal difference (\{delta_c_str} vs compact JSON, tabular coverage \{cov_str}); keep compact JSON unless TOON is already in use.",
    )
  }

  {
    pretty_json,
    compact_json,
    toon_comma,
    toon_tab,
    toon_pipe,
    best_toon,
    audit,
    verdict,
    reason,
  }
}

///|
fn render_bar(tokens : Int32, max_tokens : Int32, width : Int32) -> String {
  if max_tokens <= 0 {
    return String::make(width, '░')
  }
  let filled = (tokens * width + max_tokens / 2) / max_tokens
  let clamped = if filled < 0 {
    0
  } else if filled > width {
    width
  } else {
    filled
  }
  String::make(clamped, '█') + String::make(width - clamped, '░')
}

///|
fn pad_right(s : String, width : Int32) -> String {
  if s.length() >= width {
    s
  } else {
    s + String::make(width - s.length(), ' ')
  }
}

///|
/// Renders a human-readable CLI / Markdown comparison table with ASCII bars,
/// tabular coverage breakdown, fallback diagnostics, and final verdict.
pub fn CostReport::render_report(self : CostReport) -> String {
  let rows : Array[FormatStats] = [
    self.pretty_json,
    self.compact_json,
    self.toon_comma,
    self.toon_tab,
    self.toon_pipe,
  ]
  let mut max_tokens = 1
  for r in rows {
    if r.estimated_tokens > max_tokens {
      max_tokens = r.estimated_tokens
    }
  }
  let sb = StringBuilder()
  sb.write_string("TOON v4.4 Cost & Token-Efficiency Analysis\n")
  sb.write_string(
    "------------------------------------------------------------------------\n",
  )
  for r in rows {
    let bar = render_bar(r.estimated_tokens, max_tokens, 20)
    let mark = if r.name == self.best_toon.name { "*" } else { " " }
    let label = pad_right("\{mark} \{r.name}", 17)
    let delta = format_signed_pct1(r.delta_vs_compact_pct)
    sb.write_string(
      "\{label} \{bar}  ~\{r.estimated_tokens} tok (\{r.utf8_bytes} B, \{r.structural_bytes} syntax B, \{delta} vs compact)\n",
    )
  }
  sb.write_string(
    "------------------------------------------------------------------------\n",
  )
  let cov = format_pct1(self.audit.tabular_coverage_pct)
  sb.write_string(
    "Tabular coverage: \{cov} (tabular_items=\{self.audit.tabular_items}, fallback_items=\{self.audit.non_tabular_items}, array_blocks=\{self.audit.array_tabular_blocks}, keyed_blocks=\{self.audit.keyed_tabular_blocks})\n",
  )
  if !self.audit.fallbacks.is_empty() {
    sb.write_string("Fallback paths:\n")
    let limit = if self.audit.fallbacks.length() > 5 {
      5
    } else {
      self.audit.fallbacks.length()
    }
    for i in 0..<limit {
      let fb = self.audit.fallbacks[i]
      sb.write_string(
        "  - \{fb.path} (\{fb.item_count} items): \{fb.explanation}\n",
      )
    }
  }
  sb.write_string("Verdict [\{self.verdict.label()}]: \{self.reason}")
  sb.to_string()
}

///|
fn format_stats_to_json(s : FormatStats) -> Json {
  let delim_json : Json = match s.delimiter {
    Some(d) => Json::string(d.label())
    None => Json::null()
  }
  Json::object(
    Map([
      ("name", Json::string(s.name)),
      ("delimiter", delim_json),
      ("utf8Bytes", Json::number(s.utf8_bytes.to_double())),
      ("chars", Json::number(s.chars.to_double())),
      ("structuralBytes", Json::number(s.structural_bytes.to_double())),
      ("estimatedTokens", Json::number(s.estimated_tokens.to_double())),
      ("deltaVsCompactPct", Json::number(round1(s.delta_vs_compact_pct))),
      ("deltaVsPrettyPct", Json::number(round1(s.delta_vs_pretty_pct))),
    ]),
  )
}

///|
/// Serializes `CostReport` as a JSON summary (omitting full rendered payload
/// strings so report size stays compact for automation/CLI `--json`).
pub fn CostReport::to_json(self : CostReport) -> Json {
  let fb_json : Array[Json] = []
  for fb in self.audit.fallbacks {
    fb_json.push(
      Json::object(
        Map([
          ("path", Json::string(fb.path)),
          ("itemCount", Json::number(fb.item_count.to_double())),
          ("explanation", Json::string(fb.explanation)),
        ]),
      ),
    )
  }
  Json::object(
    Map([
      ("verdict", Json::string(self.verdict.label())),
      ("reason", Json::string(self.reason)),
      ("bestDelimiter", Json::string(self.best_toon.name)),
      (
        "tabularCoveragePct",
        Json::number(round1(self.audit.tabular_coverage_pct)),
      ),
      ("tabularItems", Json::number(self.audit.tabular_items.to_double())),
      (
        "nonTabularItems",
        Json::number(self.audit.non_tabular_items.to_double()),
      ),
      (
        "arrayTabularBlocks",
        Json::number(self.audit.array_tabular_blocks.to_double()),
      ),
      (
        "keyedTabularBlocks",
        Json::number(self.audit.keyed_tabular_blocks.to_double()),
      ),
      ("fallbacks", Json::array(fb_json)),
      (
        "formats",
        Json::object(
          Map([
            ("prettyJson", format_stats_to_json(self.pretty_json)),
            ("compactJson", format_stats_to_json(self.compact_json)),
            ("toonComma", format_stats_to_json(self.toon_comma)),
            ("toonTab", format_stats_to_json(self.toon_tab)),
            ("toonPipe", format_stats_to_json(self.toon_pipe)),
          ]),
        ),
      ),
    ]),
  )
}
