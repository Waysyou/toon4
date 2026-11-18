///|
/// Byte, structural syntax overhead, and BPE-aware heuristic token metrics for
/// a serialized text payload.
#derive(Eq, @debug.Debug)
pub(all) struct TextMetrics {
  utf8_bytes : Int32
  chars : Int32
  structural_bytes : Int32
  estimated_tokens : Int32
}

///|
fn is_ascii_letter(code : Int32) -> Bool {
  (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A)
}

///|
fn is_ascii_digit(code : Int32) -> Bool {
  code >= 0x30 && code <= 0x39
}

///|
fn is_ident_char(code : Int32) -> Bool {
  is_ascii_letter(code) || is_ascii_digit(code) || code == 0x5F
}

///|
fn is_structural_ascii(code : Int32) -> Bool {
  code == 0x22 || // '"'
  code == 0x7B || // '{'
  code == 0x7D || // '}'
  code == 0x5B || // '['
  code == 0x5D || // ']'
  code == 0x3A || // ':'
  code == 0x2C || // ','
  code == 0x7C || // '|'
  code == 0x0A || // '\n'
  code == 0x09 // '\t'
}

///|
fn is_json_punct_cluster(code : Int32) -> Bool {
  code == 0x22 || // '"'
  code == 0x7B || // '{'
  code == 0x7D || // '}'
  code == 0x5B || // '['
  code == 0x5D || // ']'
  code == 0x3A || // ':'
  code == 0x2C // ','
}

///|
/// Computes exact UTF-8 byte count, Unicode scalar count, syntax overhead
/// bytes, and a deterministic BPE-aware token estimate (modeled on o200k/cl100k
/// chunking: <=8-char words with optional leading space, <=3-digit number
/// chunks, merged JSON punctuation clusters like `{"`, `":"`, `","`, `"},{"`,
/// newline+indent runs, and per-scalar CJK/emoji).
pub fn measure_text(text : String) -> TextMetrics {
  let utf8_bytes = @utf8.encode(text).length()
  let scalars : Array[Int32] = []
  for ch in text {
    scalars.push(ch.to_int())
  }
  let n = scalars.length()
  let mut structural = 0
  for i in 0..<n {
    let c = scalars[i]
    if is_structural_ascii(c) {
      structural += 1
    } else if c == 0x20 {
      let at_line_start = i == 0 ||
        scalars[i - 1] == 0x0A ||
        scalars[i - 1] == 0x20
      let after_colon_or_comma = i > 0 &&
        (scalars[i - 1] == 0x3A || scalars[i - 1] == 0x2C)
      if at_line_start || after_colon_or_comma {
        structural += 1
      }
    }
  }
  let mut tokens = 0
  let mut i = 0
  while i < n {
    let c = scalars[i]
    // Optional leading single space merged into word/number token (standard BPE)
    if c == 0x20 && i + 1 < n {
      let next = scalars[i + 1]
      if is_ascii_letter(next) {
        i += 1
        let start = i
        while i < n && is_ident_char(scalars[i]) && i - start < 8 {
          i += 1
        }
        tokens += 1
        continue
      }
      if is_ascii_digit(next) {
        i += 1
        let start = i
        while i < n && is_ascii_digit(scalars[i]) && i - start < 3 {
          i += 1
        }
        tokens += 1
        continue
      }
    }
    if is_ascii_letter(c) || c == 0x5F {
      let start = i
      while i < n && is_ident_char(scalars[i]) && i - start < 8 {
        i += 1
      }
      tokens += 1
    } else if is_ascii_digit(c) {
      let start = i
      while i < n && is_ascii_digit(scalars[i]) && i - start < 3 {
        i += 1
      }
      tokens += 1
    } else if c == 0x20 || c == 0x09 {
      let start = i
      while i < n && (scalars[i] == 0x20 || scalars[i] == 0x09) && i - start < 4 {
        i += 1
      }
      tokens += 1
    } else if c == 0x0A {
      // '\n' + up to 2 spaces merges in typical BPE; deeper indentation costs extra tokens
      i += 1
      let sp_start = i
      while i < n && scalars[i] == 0x20 && i - sp_start < 2 {
        i += 1
      }
      tokens += 1
    } else if is_json_punct_cluster(c) {
      // Modern tokenizers (o200k/cl100k) merge common JSON delimiter sequences
      // such as `{"`, `":"`, `","`, `"},{"`, `":[`, `"]` into single tokens (up to 3-4 chars).
      let start = i
      while i < n && is_json_punct_cluster(scalars[i]) && i - start < 4 {
        i += 1
      }
      if i < n && scalars[i] == 0x20 && i - start <= 2 {
        i += 1
      }
      tokens += 1
    } else if c < 0x80 {
      if (c == 0x7C || c == 0x2D) && i + 1 < n && scalars[i + 1] == 0x20 {
        i += 2
      } else {
        i += 1
      }
      tokens += 1
    } else if c >= 0x4E00 && c <= 0x9FFF {
      let mut cjk_run = 0
      while i < n && scalars[i] >= 0x4E00 && scalars[i] <= 0x9FFF {
        cjk_run += 1
        i += 1
      }
      tokens += cjk_run + cjk_run / 4
    } else {
      i += 1
      tokens += if c > 0xFFFF { 2 } else { 1 }
    }
  }
  {
    utf8_bytes,
    chars: n,
    structural_bytes: structural,
    estimated_tokens: tokens,
  }
}
