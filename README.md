# toon4

Pure MoonBit **TOON v4.4** (Token-Oriented Object Notation) codec, pinpoint diagnostic engine, and JSON vs TOON cost/token efficiency advisor.

## Project Goals

1. **Full TOON v4.4 Conformance**: Closes specification gaps in earlier MoonBit implementations—including keyed tabular headers (`users[2:]{name,score}:`), nested field groups (`geo{lat,lon}`), comment lines (`#`), canonical `[]` empty arrays, strict UTF-8 & number parsing, and exact §14.4 non-strict recoveries—verified against all 564 official `toon-format/spec` fixtures.
2. **Pinpoint Error Diagnostics**: Structured `DecodeError` with line/column/length spans, error codes, and caret source snippets so malformed LLM or user payloads can be located immediately.
3. **Cost & Token Efficiency Advisor**: Compares `Pretty JSON`, `Compact JSON`, and `TOON` (comma / tab / pipe) on real payloads, measuring byte sizes, tabular eligibility coverage, and estimated token savings to answer whether converting to TOON actually pays off.

## Architecture (Planned)

- `types`: Core ADTs (`Delimiter`, `FieldNode`, `StreamEvent`, `Span`, `ErrorKind`, `DecodeError`, `EncodeError`, `EncodeOptions`, `DecodeOptions`)
- `lex`: UTF-16-safe lexical scanner, §4 number DFA, §6 header parser, §7 quoting/escaping
- `encode`: Canonical number normalization, recursive `FieldNode` tabular/keyed-tabular detector, streaming line encoder
- `decode`: Lookahead `LineReader`, streaming recursive-descent decoder, `EventBuilder`, UTF-8 byte decoder
- `advisor`: Multi-format comparison, tabular coverage breakdown, BPE-aware token estimator & recommendation engine
- `cmd/toon4`: Standalone CLI (`encode`, `decode`, `check`, `analyze`)

## License

MIT
