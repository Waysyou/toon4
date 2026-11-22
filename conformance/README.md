# Official TOON v4.4 Conformance Fixtures

The JSON test fixtures under `conformance/fixtures/` are vendored from the
official TOON specification repository ([toon-format/spec](https://github.com/toon-format/spec),
version `4.4.0`, MIT License — see `conformance/fixtures/LICENSE`).

- `encode/`: 9 files, 160 test cases
- `decode/`: 14 files, 404 test cases (including 158 error cases)
- Total: 23 fixture files, **564** test cases

Run the full conformance harness in MoonBit via:

```sh
moon test -p Waysyou/toon4/conformance --target native
moon test -p Waysyou/toon4/conformance --target wasm
```
