///|
test "CLI parses encode, decode, check, and analyze arguments" {
  guard @cli.parse_cli_args(["encode", "-d", "pipe", "--stats", "in.json"])
    is Action(
      Encode(
        input_path="in.json",
        output_path=None,
        delimiter=Pipe,
        indent_size=2,
        stats=true,
      ),
    ) else {
    @test.fail("expected Encode action")
  }
  guard @cli.parse_cli_args([
      "decode", "--no-strict", "--indent", "4", "-o", "out.json", "in.toon",
    ])
    is Action(
      Decode(
        input_path="in.toon",
        output_path=Some("out.json"),
        indent_size=4,
        strict=false,
      ),
    ) else {
    @test.fail("expected Decode action")
  }
  guard @cli.parse_cli_args(["check", "bad.toon"])
    is Action(Check(input_path="bad.toon", indent_size=2, strict=true)) else {
    @test.fail("expected Check action")
  }
  guard @cli.parse_cli_args(["analyze", "--json", "payload.json"])
    is Action(
      Analyze(
        input_path="payload.json",
        output_path=None,
        indent_size=2,
        as_json=true,
      ),
    ) else {
    @test.fail("expected Analyze action")
  }
  guard @cli.parse_cli_args(["--help"]) is PrintAndExit(exit_code=0, ..) else {
    @test.fail("expected PrintAndExit help")
  }
}

///|
test "CLI execution handles TOON 4.4 round-trip, check diagnostics, and analyze" {
  let json_bytes = b"{\"users\":{\"alice\":{\"name\":\"Alice\",\"score\":95},\"bob\":{\"name\":\"Bob\",\"score\":88}}}"
  guard @cli.parse_cli_args(["encode", "--stats", "-"]) is Action(enc_act) else {
    @test.fail("expected encode action")
  }
  let enc_res = @cli.run_action_on_bytes(enc_act, json_bytes[:])
  @test.assert_eq(enc_res.exit_code, 0)
  assert_true(enc_res.stdout.contains("users[2:]{name,score}:"))
  assert_true(enc_res.stderr.contains("Tabular coverage: 100.0%"))

  guard @cli.parse_cli_args(["check", "-"]) is Action(chk_ok) else {
    @test.fail("expected check action")
  }
  let ok_res = @cli.run_action_on_bytes(chk_ok, @utf8.encode(enc_res.stdout)[:])
  @test.assert_eq(ok_res.exit_code, 0)
  assert_true(ok_res.stdout.contains("OK: valid TOON v4.4 document"))

  let bad_toon = b"users[2:]:\n  alice: 1"
  let bad_res = @cli.run_action_on_bytes(chk_ok, bad_toon[:])
  @test.assert_eq(bad_res.exit_code, 1)
  assert_true(bad_res.stderr.contains("DecodeError[E_HEADER]"))

  guard @cli.parse_cli_args(["decode", "-"]) is Action(dec_act) else {
    @test.fail("expected decode action")
  }
  let dec_res = @cli.run_action_on_bytes(
    dec_act,
    @utf8.encode(enc_res.stdout)[:],
  )
  @test.assert_eq(dec_res.exit_code, 0)
  assert_true(dec_res.stdout.contains("\"score\": 95"))

  guard @cli.parse_cli_args(["analyze", "--json", "-"]) is Action(ana_act) else {
    @test.fail("expected analyze action")
  }
  let ana_res = @cli.run_action_on_bytes(ana_act, json_bytes[:])
  @test.assert_eq(ana_res.exit_code, 0)
  assert_true(ana_res.stdout.contains("\"verdict\""))
}
