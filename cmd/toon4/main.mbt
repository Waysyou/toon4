///|
async fn read_input_bytes(input_path : String) -> Bytes {
  if input_path == "-" {
    @stdio.stdin.read_all()
  } else {
    @fs.read_binary(input_path)
  }
}

///|
fn action_input_path(action : @cli.CliAction) -> String {
  match action {
    Encode(input_path~, ..) => input_path
    Decode(input_path~, ..) => input_path
    Check(input_path~, ..) => input_path
    Analyze(input_path~, ..) => input_path
  }
}

///|
async fn main {
  let raw_args = @env.args()
  let argv : Array[String] = if raw_args.length() > 1 {
    let slice : Array[String] = []
    for i in 1..<raw_args.length() {
      slice.push(raw_args[i])
    }
    slice
  } else {
    []
  }
  match @cli.parse_cli_args(argv) {
    PrintAndExit(text~, exit_code~) => {
      let msg = "\{text}\n"
      if exit_code == 0 {
        @stdio.stdout.write(@utf8.encode(msg))
      } else {
        @stdio.stderr.write(@utf8.encode(msg))
        @env.exit(exit_code)
      }
    }
    Action(action) => {
      let path = action_input_path(action)
      let bytes = read_input_bytes(path) catch {
        err => {
          @stdio.stderr.write(@utf8.encode("error reading '\{path}': \{err}\n"))
          @env.exit(1)
        }
      }
      let res = @cli.run_action_on_bytes(action, bytes[:])
      if !res.stderr.is_empty() {
        @stdio.stderr.write(@utf8.encode(res.stderr))
      }
      match res.output_path {
        Some(out_file) =>
          @fs.write_text(out_file, res.stdout) catch {
            err => {
              @stdio.stderr.write(
                @utf8.encode("error writing '\{out_file}': \{err}\n"),
              )
              @env.exit(1)
            }
          }
        None =>
          if !res.stdout.is_empty() {
            @stdio.stdout.write(@utf8.encode(res.stdout))
          }
      }
      if res.exit_code != 0 {
        @env.exit(res.exit_code)
      }
    }
  }
}
