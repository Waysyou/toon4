# Inventory Agent Example

Demonstrates a realistic warehouse stock-alert AI agent workflow using `waysyou/toon4`:

1. Evaluates a 80-SKU inventory + 3-warehouse TOON 4.4 keyed metadata payload (`warehouses[3:]{city,leadDays,active}:`) with `@toon4.analyze` before calling an LLM.
2. Encodes the payload into compact TOON v4.4 and previews the generated tabular + keyed-tabular headers.
3. Verifies lossless round-trip decoding back to `Json`.
4. Shows how a truncated LLM/streamed response is pinpointed with line, column, error code, and caret underline.

Run on any target:

```sh
moon run examples/inventory_agent --target native
moon run examples/inventory_agent --target wasm
```
