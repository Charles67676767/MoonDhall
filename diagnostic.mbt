///|
/// Human-readable diagnostics use Unicode scalar columns (one-based).
pub fn diagnostic(
  error : DhallError,
  source : String,
  filename : String,
) -> String {
  let (message, offset) = match error {
    Syntax(s, p) | TypeAt(s, p) => (s, Some(p))
    TypeError(s)
    | Evaluation(s)
    | JsonError(s)
    | ImportError(s)
    | UnavailableImport(s)
    | BinaryError(s) => (s, None)
    MissingImport(s) => ("Import source required: " + s, None)
  }
  match offset {
    None => filename + ": " + message
    Some(pos) => {
      let chars = source.to_array()
      let stop = min_int(pos, chars.length())
      let mut line = 1
      let mut begin = 0
      for i in 0..<stop {
        if chars[i] == '\n' {
          line += 1
          begin = i + 1
        }
      }
      let column = stop - begin + 1
      let mut end = stop
      while end < chars.length() && chars[end] != '\n' {
        end += 1
      }
      let excerpt = chars_text(chars, begin, end)
      let caret = StringBuilder()
      for i in begin..<stop {
        caret.write_char(if chars[i] == '\t' { '\t' } else { ' ' })
      }
      filename +
      ":" +
      line.to_string() +
      ":" +
      column.to_string() +
      ": " +
      message +
      "\n" +
      excerpt +
      "\n" +
      caret.to_string() +
      "^"
    }
  }
}
