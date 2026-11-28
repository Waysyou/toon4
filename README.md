# toon4 — TOON v4.4 Codec, Pinpoint Diagnostics & Token-Efficiency Advisor

[![mooncakes.io](https://img.shields.io/badge/mooncakes.io-Waysyou%2Ftoon4-blue)](https://mooncakes.io/docs/Waysyou/toon4)
[![CI](https://github.com/Waysyou/toon4/actions/workflows/ci.yml/badge.svg)](https://github.com/Waysyou/toon4/actions/workflows/ci.yml)
[![TOON Spec](https://img.shields.io/badge/TOON%20v4.4-564%2F564%20fixtures-brightgreen)](conformance/README.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Pure MoonBit implementation of **TOON (Token-Oriented Object Notation) v4.4**, built to:

1. **Close TOON v4.4 compatibility gaps** in existing MoonBit tooling (including keyed tabular form `users[2:]{name,score}:`, nested field groups `geo{lat,lon}`, comment pre-pass `#`, canonical `[]` empty arrays, strict UTF-8 & number parsing, and exact §14.4 non-strict recoveries) — **564 / 564** official `toon-format/spec` fixtures passing.
2. **Pinpoint errors with actionable diagnostics** — structured `DecodeError` values carry an `ErrorKind` code, 1-based line/column `Span`, tab visualization (`→`), and `^` caret underline pointing directly at the offending token.
3. **Measure whether converting to TOON actually pays off** — compares `Pretty JSON`, `Compact JSON`, and `TOON` (`comma`, `tab`, `pipe`), reports exact UTF-8 byte sizes, tabular eligibility coverage, path-level fallback reasons, and an explicit `RECOMMEND_TOON` / `MARGINAL` / `KEEP_COMPACT_JSON` verdict.

---

## Why `toon4`? (Compatibility Gap vs `oliveagle/toon-mbit`)

Auditing [`oliveagle/toon-mbit`](https://github.com/oliveagle/toon-mbit) against TOON Spec v4.4 and MoonBit `0.10.21` (`moon 0.1.20261117`) identified the following verified gaps:

| Capability / Spec Clause | `oliveagle/toon-mbit` (audited) | `Waysyou/toon4` |
| :--- | :--- | :--- |
| Toolchain manifest (`moon.mod` / `moon.pkg`) | Uses legacy `moon.mod` + `moon.pkg.json` (rejected by `moon 0.1.20261117`) | Modern `moon.mod` + `moon.pkg` DSL; zero warnings (`--deny-warn`) across `wasm`, `wasm-gc`, `js`, `native` |
| **TOON 4.4 §9.5 Keyed Tabular** (`users[2:]{name,score}:`) | Fails at `src/decoder.mbt:273-295, 360-369` (`:` inside `[2:]` treated as key-value colon / illegal symbol) | Full encode, decode, nested field groups, `[0:]`, delimiter support, and strict/non-strict rules |
| **§9.3 Nested Field Groups** (`regions[2:]{name,geo{lat,lon}}:`) | Not supported | Recursive `FieldNode` ADT (`Leaf` / `Group`) in both encoder and decoder |
| **§11 Tab Delimiter Header** (`items[2\t]:`) | `src/decoder.mbt:299` `.trim()` strips trailing `\t` before parsing bracket delimiter | Preserves exact `HTAB` and `|` header delimiters; validates `{fields}` delimiter consistency |
| **§5.1 Full-line Comments** (`# ...`) | Not stripped | Pre-pass strips space-indented `#` lines before blank-line, quote, and indent checks |
| **§9.1 / §9.2 Empty Arrays** | Encodes deprecated `[0]:` / `key[0]:` (`src/encoder.mbt:194-209`); decodes `[]` as string | Emits `[]` / `key: []` / `- [0]:`; decodes `[]` as array in root/field/list-item positions and `"[]"` inside cells |
| **§4 Strict Numbers** (`1e5`, `05`, `+1`, `1.`) | `05` parsed as integer `5`; `1e5` fails `parse_double` | Exact §4 DFA (`1e5 -> 100000`, `05` / `+1` / `1.` / `0x10` stay strings, `-0.0 -> 0`) |
| **§7.1 Escapes & Quotes** (`\uXXXX`, `"a" "b"`) | Rejects `\uXXXX`; `unquote_string` skips interior quote check (`"a" "b"` passes) | Full `\uXXXX` + surrogate rejection; strict closing-quote boundary check |
| **§14 Strict vs 5 Non-Strict Recoveries** | Checks `strict` only on inline array counts (`src/decoder.mbt:401`) | Full strict enforcement + all 5 §14.4 non-strict recoveries (preserving key insertion order via `Map`) |
| **UTF-16 Emoji Index Safety** | Mixes `Char` iterator offsets with UTF-16 slices (`src/decoder.mbt:593-612`) | Scans UTF-16 code units consistently; maps offsets to 1-based Unicode scalar columns for carets |
| **Error Diagnostics** | `ParseError { line, message }` hardcodes `line: 0` in all 6 header errors | `DecodeError` with `ErrorKind`, `Span(line, column, length)`, source line, and caret formatting |

---

## Official Conformance & Verification

Version 0.2.1 was verified with `moonc v1.0.0-rc1+3c0520448` (`moon 0.1.20261126`). Checks, builds, and tests passed across `wasm`, `wasm-gc`, `js`, and `native`, along with the native example and CLI smoke checks.

Vendored all 23 official fixture files from [`toon-format/spec`](https://github.com/toon-format/spec) (`v4.4.0`, MIT License) under [`conformance/fixtures/`](conformance/fixtures):

- **Encode fixtures**: **160 / 160** passing (9 files)
- **Decode fixtures**: **404 / 404** passing (14 files, including 158 `shouldError: true` cases, strict object key insertion-order check, and valid `span.line >= 1` check)
- **Total official fixtures**: **564 / 564 (100%)** passing on both `native` and `wasm`
- **Additional suites**: Raw ill-formed UTF-8 byte sequence rejection, TOON 4.4 differential tests, caret golden snapshots, CLI integration tests, and advisor decision tests — all running with zero warnings under `moon check --deny-warn`.

---

## Pinpoint Diagnostics Example

```text
DecodeError[E_WIDTH] at line 3, column 10: expected 3 keyed entry cells, but got 2
  3 |   WH-SZ: Shenzhen,1
    |          ^^^^^^^^^^
```

```text
DecodeError[E_INDENT] at line 2, column 1: tabs are not allowed in indentation in strict mode
  2 | →b: 1
    | ^
```

---

## Cost & Token-Efficiency Advisor (Real Output)

Running `moon run examples/inventory_agent --target native` on an 80-SKU inventory list + 3 keyed warehouses (`warehouses[3:]{city,leadDays,active}:`):

```text
TOON v4.4 Cost & Token-Efficiency Analysis
------------------------------------------------------------------------
  JSON (pretty)   ████████████████████  ~4835 tok (14113 B, 7388 syntax B, +79.3% vs compact)
  JSON (compact)  ███████████░░░░░░░░░  ~2696 tok (9353 B, 2628 syntax B, 0.0% vs compact)
* TOON (comma)    ███████░░░░░░░░░░░░░  ~1584 tok (4139 B, 686 syntax B, -41.2% vs compact)
  TOON (tab)      ███████░░░░░░░░░░░░░  ~1587 tok (4141 B, 688 syntax B, -41.1% vs compact)
  TOON (pipe)     ███████░░░░░░░░░░░░░  ~1587 tok (4141 B, 688 syntax B, -41.1% vs compact)
------------------------------------------------------------------------
Tabular coverage: 100.0% (tabular_items=83, fallback_items=0, array_blocks=1, keyed_blocks=1)
Verdict [RECOMMEND_TOON]: Recommend TOON (comma): -41.2% estimated tokens vs compact JSON (-67.2% vs pretty JSON), tabular coverage 100.0%.
```

Conversely, running `moon run --target native cmd/toon4 -- analyze conformance/fixtures/encode/objects-keyed.json` on semi-uniform nested fixture data accurately warns against converting:

```text
Tabular coverage: 43.2% (tabular_items=16, fallback_items=21, array_blocks=0, keyed_blocks=8)
Fallback paths:
  - tests (14 items): element [1] adds extra key 'note' absent in [0]; falls back to list form
  - tests[7].input.config (1 items): object has only 1 entry (< 2 minimum for TOON 4.4 keyed tabular '[N:]')
  - tests[11].input.items (2 items): element [1] is missing key 'config' present in [0]; falls back to list form
  - tests[12].input.items (2 items): contains non-object, empty-object, or nested-array elements; uses list form ('- ')
  - tests[12].input.items[0] (2 items): an anonymous list object must write its fields individually
Verdict [KEEP_COMPACT_JSON]: Keep compact JSON: TOON (comma) adds +19.1% estimated tokens vs compact JSON (tabular coverage 43.2%; 5 non-tabular path(s)).
```

---

## Performance Benchmarks (`moon bench`)

Measured directly with `moon bench -p Waysyou/toon4/benchmarks` (`moonc v0.10.21+06da1ed44`):

| Benchmark | `native` (mean ± σ) | `wasm` / `moonrun` (mean ± σ) |
| :--- | :--- | :--- |
| `encode_inventory_200` (200 SKU rows, 8 cols) | `411.67 µs ± 10.37 µs` | `479.54 µs ± 16.71 µs` |
| `decode_inventory_200` (200 SKU rows, 8 cols) | `1.07 ms ± 78.63 µs` | `1.09 ms ± 28.40 µs` |
| `encode_keyed_flags_80` (80 keyed entries, `[80:]`) | `145.00 µs ± 2.32 µs` | `144.37 µs ± 2.86 µs` |
| `decode_keyed_flags_80` (80 keyed entries, `[80:]`) | `274.56 µs ± 10.65 µs` | `281.96 µs ± 6.96 µs` |
| `analyze_inventory_200` (3 TOON + 2 JSON + audit) | `2.94 ms ± 129.90 µs` | `4.25 ms ± 295.95 µs` |
| `analyze_nested_orders_50` (50 nested orders) | `1.59 ms ± 42.72 µs` | `2.30 ms ± 80.30 µs` |

---

## Architecture & Scope Boundaries

### Package Layout
- `types`: Core ADTs (`Delimiter`, `FieldNode`, `ArrayHeader`, `StreamEvent`), options, `Span`, `ErrorKind`, `DecodeError::format`, `EncodeError`.
- `lex`: UTF-16-safe lexical scanner, §1.2/§12 whitespace & comment stripping, §4 number DFA, §7 escaping/quoting, §6/§9.5 header parser.
- `encode`: Canonical number normalization (§2/§3), recursive `FieldNode` tabular & keyed-tabular eligibility, streaming `encode_to_lines`.
- `decode`: Pull-based lookahead `LineReader`, streaming `decode_stream` emitting `StreamEvent`, `EventBuilder`, strict UTF-8 `decode_bytes`.
- `advisor`: BPE-aware offline token estimator, recursive structural eligibility auditor, multi-format `analyze` & Markdown/JSON reporting.
- `toon4` (root): Unified public API facade re-exporting core & advisor types and entrypoints.
- `cli` + `cmd/toon4`: Testable CLI command logic (`cli`) + `async` file/stdio executable (`cmd/toon4`).
- `conformance`, `benchmarks`, `examples/inventory_agent`: Official 564-case spec runner, differential diagnostics, `@bench.T` suite, and warehouse agent walkthrough.

### Explicit Scope Boundaries & Design Trade-offs

**Numeric precision (§2 and §4).** The CLI preserves source number text through JSON → TOON → JSON and normalizes its decimal spelling without rounding digits. The decoder stores that text in `Json::Number.repr`; reading just its host `Double` value can still round or underflow. JSON or TOON literals that overflow the supported finite `Double` range fail with a diagnostic. For library JSON input, parse with `preserve_number_repr=true` to retain the original digits.

1. **Offline BPE-Aware Token Estimator**: `advisor` uses a deterministic, zero-dependency BPE-style heuristic (modeling `o200k`/`cl100k` 3-digit chunking, identifier splitting, JSON punctuation clusters, and newline+indent merging) rather than embedding multi-megabyte external `.tiktoken` BPE tables. UTF-8 byte counts, syntax byte counts, and tabular coverage percentages are exact; token counts are labeled `estimated_tokens` and may vary slightly across specific model tokenizers.
2. **TOON v4.0+ Literal Dotted Keys**: Per `toon-format/spec` v4.0–v4.4, `keyFolding` / `expandPaths` are intentionally absent; dotted keys like `a.b` are unconditionally treated as literal keys.
3. **Target Compatibility**: All core packages (`types`, `lex`, `encode`, `decode`, `advisor`, `cli`, root `toon4`, `examples/inventory_agent`, `benchmarks`) compile and pass on **all 4 backends** (`wasm`, `wasm-gc`, `js`, `native`). File-system I/O packages (`cmd/toon4` and `conformance/spec_conformance_test.mbt`) use `moonbitlang/core/async/fs` and target `native` + `wasm`.
4. **Small-Payload Prompt Tax**: Even when TOON reduces raw payload characters on tiny 2–3 row snippets, `advisor` marks payloads `< 45` compact tokens (or `< 12` tokens saved) as `MARGINAL` because LLM format instructions carry a fixed prompt overhead.

---

## Quick Start

[中文快速上手与三个可运行示例](examples/cli_walkthrough/README.md)

### Library Usage (`moon add` & `moon.pkg`)
```sh
moon add Waysyou/toon4
```

```text
import {
  "Waysyou/toon4",
}
```

```moonbit
let doc = Json::object(Map([
  ("users", Json::object(Map([
    ("alice", Json::object(Map([("name", Json::string("Alice")), ("score", Json::number(95.0))]))),
    ("bob", Json::object(Map([("name", Json::string("Bob")), ("score", Json::number(88.0))]))),
  ]))),
]))

let toon_text = @toon4.encode(doc)
let round_trip = @toon4.decode(toon_text)
let report = @toon4.analyze(doc)
println(report.render_report())
```

### CLI Usage
```sh
# Compare JSON vs TOON efficiency and inspect non-tabular fallback paths
moon run --target native cmd/toon4 -- analyze data.json
moon run --target native cmd/toon4 -- analyze --json data.json

# Encode JSON to TOON v4.4 (comma | tab | pipe) with stats to stderr
moon run --target native cmd/toon4 -- encode -d pipe --stats data.json

# Validate TOON with pinpoint line/column caret diagnostics
moon run --target native cmd/toon4 -- check payload.toon

# Decode TOON (strict by default, or --no-strict for §14.4 recoveries)
moon run --target native cmd/toon4 -- decode payload.toon
```

Run these examples from the repository root to try the CLI features introduced in 0.2.0.

```sh
# Encode inventory.json with an automatically selected delimiter (also -d auto)
moon run --target native cmd/toon4 -- encode --auto --stats examples/cli_walkthrough/inventory.json

# Compare formats for the JSON files in the walkthrough directory
moon run --target native cmd/toon4 -- analyze examples/cli_walkthrough

# Validate the TOON files in the directory. The sample inventory-invalid.toon
# deliberately triggers E_WIDTH and a nonzero exit status.
moon run --target native cmd/toon4 -- check examples/cli_walkthrough
```

### Running All Tests & Benchmarks
```sh
moon fmt --check
moon check --deny-warn --target all
moon build --target all
moon test --target native
moon test --target wasm
moon test --target wasm-gc
moon test --target js
moon bench -p Waysyou/toon4/benchmarks --target native
```

---

## License

MIT — see [`LICENSE`](LICENSE). Official conformance fixtures in [`conformance/fixtures/`](conformance/fixtures) are MIT-licensed from [`toon-format/spec`](https://github.com/toon-format/spec).
