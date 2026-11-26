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
async fn is_input_directory(path : String) -> Bool {
  if path == "-" {
    return false
  }
  let kind = @fs.kind(path) catch { _ => return false }
  kind is Directory
}

///|
async fn read_batch_files(
  root : String,
  suffix : String,
) -> Array[(String, Bytes)] {
  let pending = [root]
  let paths : Array[String] = []
  while pending.pop() is Some(dir) {
    let prefix = if dir.has_suffix("/") { dir } else { dir + "/" }
    for name in @fs.readdir(dir) {
      let path = prefix + name
      match @fs.kind(path, follow_symlink=false) {
        Directory => pending.push(path)
        Regular if name.has_suffix(suffix) => paths.push(path)
        _ => ()
      }
    }
  }
  paths.sort_by(String::lexical_compare)
  let files : Array[(String, Bytes)] = []
  for path in paths {
    files.push((path, @fs.read_binary(path)))
  }
  files
}

///|
async fn run_action_on_path(
  action : @cli.CliAction,
  path : String,
) -> @cli.ExecOutput {
  match action {
    Check(indent_size~, strict~, ..) =>
      if is_input_directory(path) {
        let files = read_batch_files(path, ".toon")
        return @cli.run_batch_check(files, indent_size~, strict~)
      }
    Analyze(output_path~, indent_size~, as_json~, ..) =>
      if is_input_directory(path) {
        let files = read_batch_files(path, ".json")
        let result = @cli.run_batch_analyze(files, indent_size~, as_json~)
        return { ..result, output_path, }
      }
    _ => ()
  }
  let bytes = read_input_bytes(path)
  @cli.run_action_on_bytes(action, bytes[:])
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
      let res = run_action_on_path(action, path) catch {
        err => {
          @stdio.stderr.write(@utf8.encode("error reading '\{path}': \{err}\n"))
          @env.exit(1)
        }
      }
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
