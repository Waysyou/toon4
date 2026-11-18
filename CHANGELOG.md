# Changelog

## Unreleased

### Fixed
- Preserve decimal number text through JSON ⇄ TOON round trips and reject numeric overflow with a diagnostic.
- Report anonymous list items according to the encoder’s actual layout when counting tabular coverage.

## 0.1.0 (2026-11-18)

### Added
- **Core Types & Pinpoint Diagnostics (`types`)**: `Delimiter`, recursive `FieldNode` (`Leaf` / `Group`), `ArrayHeader` with `@bigint.BigInt` lengths, `StreamEvent`, `Span`, `ErrorKind` (19 error codes), and `DecodeError::format` with tab visualization and caret alignment.
- **UTF-16-Safe Lexer & TOON 4.4 Header Parser (`lex`)**: §1.2/§12 whitespace & `#` comment pre-pass, §4 strict number DFA, §7 `\uXXXX` escaping/surrogate checks, and §6/§9.5 bracket/keyed header parser.
- **Streaming Encoder (`encode`)**: Canonical number normalization (§2/§3), recursive `FieldNode` tabular & keyed-tabular (`>= 2` uniform entries) detection, and line-streaming emitter across `,`, `\t`, and `|` delimiters.
- **Streaming Decoder (`decode`)**: Pull-based lookahead `LineReader`, recursive-descent `decode_stream`, `EventBuilder`, strict UTF-8 `decode_bytes`, §9.5 keyed tabular decoding, and all 5 §14.4 non-strict recoveries.
- **Conformance & Differential Verification (`conformance`)**: Full 564/564 pass rate against vendored `toon-format/spec` v4.4.0 fixtures (160 encode + 404 decode), raw malformed UTF-8 byte suite, and caret diagnostic golden tests.
- **Cost & Token-Efficiency Advisor (`advisor`)**: Multi-format comparison (`Pretty JSON`, `Compact JSON`, `TOON` comma/tab/pipe), structural tabular coverage auditor, path-level fallback diagnostics, and `RECOMMEND_TOON` / `MARGINAL` / `KEEP_COMPACT_JSON` verdicts.
- **Public Facade, CLI, Benchmarks & Example (`toon4`, `cli`, `cmd/toon4`, `benchmarks`, `examples/inventory_agent`)**: Unified root package exports, `encode`/`decode`/`check`/`analyze` CLI commands, `@bench.T` throughput suite, and 80-SKU warehouse inventory agent demo.
