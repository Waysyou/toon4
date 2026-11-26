///|
pub(all) enum CliAction {
  Encode(
    input_path~ : String,
    output_path~ : String?,
    delimiter~ : @toon4.Delimiter,
    auto_delimiter~ : Bool,
    indent_size~ : Int32,
    stats~ : Bool,
  )
  Decode(
    input_path~ : String,
    output_path~ : String?,
    indent_size~ : Int32,
    strict~ : Bool,
  )
  Check(input_path~ : String, indent_size~ : Int32, strict~ : Bool)
  Analyze(
    input_path~ : String,
    output_path~ : String?,
    indent_size~ : Int32,
    as_json~ : Bool,
  )
}

///|
pub(all) enum CliOutcome {
  Action(CliAction)
  PrintAndExit(text~ : String, exit_code~ : Int32)
}

///|
pub(all) struct ExecOutput {
  stdout : String
  stderr : String
  exit_code : Int32
  output_path : String?
}

///|
fn io_opts() -> Array[@argparse.OptionArg] {
  [
    @argparse.OptionArg(
      "out",
      short='o',
      about="Write output to file instead of stdout",
    ),
    @argparse.OptionArg(
      "indent",
      about="Indentation spaces per level (default: 2)",
      default_values=["2"],
    ),
  ]
}

///|
fn strict_flags() -> Array[@argparse.FlagArg] {
  [
    @argparse.FlagArg(
      "no-strict",
      about="Disable strict count, duplicate-key, indent, and blank-line checks (§14.4)",
    ),
  ]
}

///|
/// Builds the `@argparse.Command` definition for `toon4`.
pub fn build_command() -> @argparse.Command {
  let encode_cmd = @argparse.Command(
    "encode",
    about="Encode JSON input into TOON v4.4",
    flags=[
      @argparse.FlagArg("auto", about="Choose the lowest-cost TOON delimiter"),
      @argparse.FlagArg(
        "stats",
        about="Print byte and estimated token savings vs compact JSON to stderr",
      ),
    ],
    options=[
      @argparse.OptionArg(
        "delimiter",
        short='d',
        about="Array/tabular delimiter: comma, tab, pipe, or auto (default: comma)",
        default_values=["comma"],
      ),
      ..io_opts(),
    ],
    positionals=[
      @argparse.PositionArg(
        "input",
        about="Input JSON file path, or '-' for stdin (default: '-')",
        default_values=["-"],
      ),
    ],
  )
  let decode_cmd = @argparse.Command(
    "decode",
    about="Decode TOON v4.4 input into JSON",
    flags=strict_flags(),
    options=io_opts(),
    positionals=[
      @argparse.PositionArg(
        "input",
        about="Input TOON file path, or '-' for stdin (default: '-')",
        default_values=["-"],
      ),
    ],
  )
  let check_cmd = @argparse.Command(
    "check",
    about="Validate TOON v4.4 documents with pinpoint line/column diagnostics",
    flags=strict_flags(),
    options=[
      @argparse.OptionArg(
        "indent",
        about="Indentation spaces per level (default: 2)",
        default_values=["2"],
      ),
    ],
    positionals=[
      @argparse.PositionArg(
        "input",
        about="Input TOON file, directory of .toon files, or '-' for stdin",
        default_values=["-"],
      ),
    ],
  )
  let analyze_cmd = @argparse.Command(
    "analyze",
    about="Compare Pretty JSON, Compact JSON, and TOON (comma/tab/pipe) efficiency",
    flags=[@argparse.FlagArg("json", about="Emit machine-readable JSON report")],
    options=io_opts(),
    positionals=[
      @argparse.PositionArg(
        "input",
        about="Input JSON file, directory of .json files, or '-' for stdin",
        default_values=["-"],
      ),
    ],
  )
  @argparse.Command(
    "toon4",
    about="TOON v4.4 codec, pinpoint diagnostics, and JSON vs TOON cost advisor",
    version="0.2.0",
    subcommand_required=true,
    arg_required_else_help=true,
    subcommands=[encode_cmd, decode_cmd, check_cmd, analyze_cmd],
  )
}

///|
fn parse_delimiter_name(raw : String) -> @toon4.Delimiter? {
  match raw {
    "comma" | "," => Some(Comma)
    "tab" | "\t" | "\\t" => Some(Tab)
    "pipe" | "|" => Some(Pipe)
    _ => None
  }
}

///|
fn first_value(matches : @argparse.Matches, key : String) -> String? {
  match matches.values.get(key) {
    Some(arr) => if arr.is_empty() { None } else { Some(arr[0]) }
    None => None
  }
}

///|
fn parse_indent(matches : @argparse.Matches) -> Result[Int32, String] {
  match first_value(matches, "indent") {
    None => Ok(2)
    Some(raw) => {
      let n = @string.parse_int(raw) catch {
        _ => return Err("invalid --indent value '\{raw}': expected integer")
      }
      if n < 1 {
        Err("invalid --indent value '\{raw}': must be >= 1")
      } else {
        Ok(n)
      }
    }
  }
}

///|
/// Parses CLI arguments into a strongly typed `CliOutcome`.
pub fn parse_cli_args(argv : Array[String]) -> CliOutcome {
  let cmd = build_command()
  match cmd.parse_outcome(argv~) {
    Help(text) => PrintAndExit(text~, exit_code=0)
    Version(text) => PrintAndExit(text~, exit_code=0)
    Failed(err) => PrintAndExit(text="\{err}", exit_code=2)
    Parsed(root_matches) =>
      match root_matches.subcommand {
        None => PrintAndExit(text=cmd.render_help(), exit_code=2)
        Some((sub_name, sub_matches)) => {
          let input_path = match first_value(sub_matches, "input") {
            Some(p) => p
            None => "-"
          }
          let output_path = first_value(sub_matches, "out")
          let indent_size = match parse_indent(sub_matches) {
            Ok(n) => n
            Err(msg) => return PrintAndExit(text="error: \{msg}", exit_code=2)
          }
          match sub_name {
            "encode" => {
              let raw_delim = match first_value(sub_matches, "delimiter") {
                Some(d) => d
                None => "comma"
              }
              let delimiter = match parse_delimiter_name(raw_delim) {
                Some(d) => d
                None if raw_delim == "auto" => @toon4.Delimiter::Comma
                None =>
                  return PrintAndExit(
                    text="error: unsupported --delimiter '\{raw_delim}' (expected comma, tab, pipe, or auto)",
                    exit_code=2,
                  )
              }
              let auto_delimiter = raw_delim == "auto" ||
                sub_matches.flags.get("auto") is Some(true)
              let stats = sub_matches.flags.get("stats") is Some(true)
              Action(
                Encode(
                  input_path~,
                  output_path~,
                  delimiter~,
                  auto_delimiter~,
                  indent_size~,
                  stats~,
                ),
              )
            }
            "decode" => {
              let strict = !(sub_matches.flags.get("no-strict") is Some(true))
              Action(Decode(input_path~, output_path~, indent_size~, strict~))
            }
            "check" => {
              let strict = !(sub_matches.flags.get("no-strict") is Some(true))
              Action(Check(input_path~, indent_size~, strict~))
            }
            "analyze" => {
              let as_json = sub_matches.flags.get("json") is Some(true)
              Action(Analyze(input_path~, output_path~, indent_size~, as_json~))
            }
            _ => PrintAndExit(text=cmd.render_help(), exit_code=2)
          }
        }
      }
  }
}

///|
fn parse_json_bytes(raw_bytes : BytesView) -> Result[Json, String] {
  let json_text = @utf8.decode(raw_bytes) catch {
    _ => return Err("error: input is not valid UTF-8")
  }
  let json_val = @json.parse(json_text, preserve_number_repr=true) catch {
    err => return Err("JSON parse error: \{err}")
  }
  Ok(json_val)
}

///|
fn analyze_json(
  json_val : Json,
  indent_size~ : Int32,
) -> Result[@toon4.CostReport, String] {
  let report = @toon4.analyze(json_val, indent_size~) catch {
    err => return Err(@toon4.format_encode_error(err))
  }
  Ok(report)
}

///|
fn analyze_bytes(
  raw_bytes : BytesView,
  indent_size~ : Int32,
) -> Result[@toon4.CostReport, String] {
  match parse_json_bytes(raw_bytes) {
    Ok(json_val) => analyze_json(json_val, indent_size~)
    Err(error) => Err(error)
  }
}

///|
fn execution_error(message : String) -> ExecOutput {
  { stdout: "", stderr: "\{message}\n", exit_code: 1, output_path: None, }
}

///|
/// Pure execution core operating on raw input bytes so tests can exercise
/// encode/decode/check/analyze end-to-end without process I/O.
pub fn run_action_on_bytes(
  action : CliAction,
  raw_bytes : BytesView,
) -> ExecOutput {
  match action {
    Encode(output_path~, delimiter~, auto_delimiter~, indent_size~, stats~, ..) => {
      let json_val = match parse_json_bytes(raw_bytes) {
        Ok(value) => value
        Err(error) => return execution_error(error)
      }
      let auto_report = if auto_delimiter {
        match analyze_json(json_val, indent_size~) {
          Ok(report) => Some(report)
          Err(error) => return execution_error(error)
        }
      } else {
        None
      }
      let delimiter = match auto_report {
        Some(report) => report.best_toon.delimiter.unwrap_or(delimiter)
        None => delimiter
      }
      let encoded = @toon4.encode(
        json_val,
        options=@toon4.EncodeOptions::new(indent_size~, delimiter~),
      ) catch {
        err => return execution_error(@toon4.format_encode_error(err))
      }
      let stderr = if stats {
        let report = match auto_report {
          Some(report) => report
          None =>
            match analyze_json(json_val, indent_size~) {
              Ok(report) => report
              Err(error) => return execution_error(error)
            }
        }
        "\{report.render_report()}\n"
      } else {
        ""
      }
      let body = if encoded.is_empty() { "" } else { "\{encoded}\n" }
      { stdout: body, stderr, exit_code: 0, output_path, }
    }
    Decode(output_path~, indent_size~, strict~, ..) => {
      let decoded = @toon4.decode_bytes(
        raw_bytes,
        options=@toon4.DecodeOptions::new(indent_size~, strict~),
      ) catch {
        err =>
          return {
            stdout: "",
            stderr: "\{@toon4.format_decode_error(err)}\n",
            exit_code: 1,
            output_path: None,
          }
      }
      let json_out = "\{decoded.stringify(indent=indent_size)}\n"
      { stdout: json_out, stderr: "", exit_code: 0, output_path, }
    }
    Check(indent_size~, strict~, ..) => {
      let _ = @toon4.decode_bytes(
        raw_bytes,
        options=@toon4.DecodeOptions::new(indent_size~, strict~),
      ) catch {
        err =>
          return {
            stdout: "",
            stderr: "\{@toon4.format_decode_error(err)}\n",
            exit_code: 1,
            output_path: None,
          }
      }
      let mode_label = if strict { "strict" } else { "non-strict" }
      {
        stdout: "OK: valid TOON v4.4 document (\{mode_label}, indent=\{indent_size})\n",
        stderr: "",
        exit_code: 0,
        output_path: None,
      }
    }
    Analyze(output_path~, indent_size~, as_json~, ..) => {
      let report = match analyze_bytes(raw_bytes, indent_size~) {
        Ok(report) => report
        Err(error) => return execution_error(error)
      }
      let text = if as_json {
        "\{report.to_json().stringify(indent=2)}\n"
      } else {
        "\{report.render_report()}\n"
      }
      { stdout: text, stderr: "", exit_code: 0, output_path, }
    }
  }
}

///|
/// Validates the supplied files in order and reports each result.
pub fn run_batch_check(
  files : Array[(String, Bytes)],
  indent_size~ : Int32,
  strict~ : Bool,
) -> ExecOutput {
  let stdout = StringBuilder()
  let mut passed = 0
  for file in files {
    let (path, bytes) = file
    let result = run_action_on_bytes(
      Check(input_path=path, indent_size~, strict~),
      bytes[:],
    )
    if result.exit_code == 0 {
      passed += 1
      stdout.write_string("PASS \{path}\n")
    } else {
      stdout.write_string("FAIL \{path}: \{result.stderr}")
    }
  }
  let total = files.length()
  let failed = total - passed
  if total == 0 {
    stdout.write_string("No matching .toon files.\n")
  }
  stdout.write_string(
    "Summary: \{passed} passed, \{failed} failed (total \{total} files)\n",
  )
  let exit_code = if total == 0 || failed > 0 { 1 } else { 0 }
  { stdout: stdout.to_string(), stderr: "", exit_code, output_path: None, }
}

///|
/// Analyzes the supplied files in order and returns a table or JSON report.
pub fn run_batch_analyze(
  files : Array[(String, Bytes)],
  indent_size~ : Int32,
  as_json~ : Bool,
) -> ExecOutput {
  let rows : Array[Json] = []
  let table = StringBuilder()
  if !as_json {
    table.write_string(
      "File | Compact JSON tokens | Best TOON tokens | Delta % | Recommendation\n",
    )
  }
  let mut analyzed = 0
  for file in files {
    let (path, bytes) = file
    match analyze_bytes(bytes[:], indent_size~) {
      Ok(report) => {
        analyzed += 1
        if as_json {
          rows.push({ "path": Json::string(path), "report": report.to_json() })
        } else {
          let compact = report.compact_json.estimated_tokens
          let best = report.best_toon
          let delta = (best.delta_vs_compact_pct * 10.0).round() / 10.0
          table.write_string(
            "\{path} | \{compact} | \{best.estimated_tokens} | \{delta}% | \{report.verdict.label()}\n",
          )
        }
      }
      Err(error) =>
        if as_json {
          rows.push({ "path": Json::string(path), "error": Json::string(error) })
        } else {
          table.write_string("\{path} | - | - | - | FAIL: \{error}\n")
        }
    }
  }
  let total = files.length()
  let failed = total - analyzed
  let stdout = if as_json {
    let report : Json = {
      "files": Json::array(rows),
      "summary": {
        "analyzed": Json::number(analyzed.to_double()),
        "failed": Json::number(failed.to_double()),
        "total": Json::number(total.to_double()),
      },
    }
    "\{report.stringify(indent=2)}\n"
  } else {
    if total == 0 {
      table.write_string("No matching .json files.\n")
    }
    table.write_string(
      "Summary: \{analyzed} analyzed, \{failed} failed (total \{total} files)\n",
    )
    table.to_string()
  }
  let exit_code = if total == 0 || failed > 0 { 1 } else { 0 }
  { stdout, stderr: "", exit_code, output_path: None, }
}
