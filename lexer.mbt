///|
priv enum TokenKind {
  Word(String)
  Number(String)
  Quoted(String, Bool)
  Path(String)
  Label(String)
  Symbol(String)
  End
} derive(Debug, Eq)

///|
priv struct Token {
  kind : TokenKind
  offset : Int32
  end : Int32
}

///|
fn identifier_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn identifier_part(c : Char) -> Bool {
  identifier_start(c) || (c >= '0' && c <= '9') || c == '-' || c == '/'
}

///|
fn chars_text(chars : Array[Char], start : Int32, end : Int32) -> String {
  let b = StringBuilder()
  for i in start..<end {
    b.write_char(chars[i])
  }
  b.to_string()
}

///|
fn lex(source : String) -> Array[Token] raise DhallError {
  let chars = source.to_array()
  let tokens : Array[Token] = []
  let mut i = 0
  while i < chars.length() {
    if tokens.length() >= 20000 {
      raise Syntax("Token limit exceeded", i)
    }
    let c = chars[i]
    if [' ', '\n', '\r', '\t'].contains(c) {
      i += 1
      continue
    }
    if c == '-' && i + 1 < chars.length() && chars[i + 1] == '-' {
      while i < chars.length() && chars[i] != '\n' {
        i += 1
      }
      continue
    }
    if c == '{' && i + 1 < chars.length() && chars[i + 1] == '-' {
      let start = i
      i += 2
      let mut depth = 1
      while i < chars.length() && depth > 0 {
        if i + 1 < chars.length() && chars[i] == '{' && chars[i + 1] == '-' {
          depth += 1
          i += 2
        } else if i + 1 < chars.length() &&
          chars[i] == '-' &&
          chars[i + 1] == '}' {
          depth -= 1
          i += 2
        } else {
          i += 1
        }
      }
      if depth != 0 {
        raise Syntax("Unterminated block comment", start)
      }
      continue
    }
    let start = i
    let rest = chars_text(chars, i, min_int(i + 8, chars.length()))
    if rest.has_prefix("./") ||
      rest.has_prefix("../") ||
      rest.has_prefix("~/") ||
      rest.has_prefix("https://") ||
      rest.has_prefix("http://") ||
      rest.has_prefix("env:") ||
      (
        c == '/' &&
        i + 1 < chars.length() &&
        chars[i + 1] != '/' &&
        chars[i + 1] != '\\'
      ) {
      while i < chars.length() &&
            ![' ', '\n', '\r', '\t', ')', ']', '}', ','].contains(chars[i]) {
        i += 1
      }
      tokens.push({
        kind: Path(chars_text(chars, start, i)),
        offset: start,
        end: i,
      })
      continue
    }
    if c.to_int() == 96 {
      i += 1
      let begin = i
      while i < chars.length() && chars[i].to_int() != 96 {
        i += 1
      }
      if i == chars.length() {
        raise Syntax("Unterminated quoted label", start)
      }
      let name = chars_text(chars, begin, i)
      i += 1
      tokens.push({ kind: Label(name), offset: start, end: i, })
      continue
    }
    let multiline = c == '\'' && i + 1 < chars.length() && chars[i + 1] == '\''
    if c == '"' || multiline {
      i += if multiline { 2 } else { 1 }
      let begin = i
      let mut nesting = 0
      let mut closed = false
      while i < chars.length() {
        if multiline &&
          i + 2 < chars.length() &&
          chars[i] == '\'' &&
          chars[i + 1] == '\'' &&
          (chars[i + 2] == '\'' || chars[i + 2] == '$') {
          i += 3
          continue
        }
        if !multiline && chars[i] == '\\' {
          i += 2
          continue
        }
        if chars[i] == '$' && i + 1 < chars.length() && chars[i + 1] == '{' {
          nesting += 1
          i += 2
          continue
        }
        if nesting > 0 {
          if chars[i] == '{' {
            nesting += 1
          } else if chars[i] == '}' {
            nesting -= 1
          } else if chars[i] == '"' {
            i += 1
            while i < chars.length() && chars[i] != '"' {
              if chars[i] == '\\' {
                i += 1
              }
              i += 1
            }
          }
          i += 1
          continue
        }
        if (!multiline && chars[i] == '"') ||
          (
            multiline &&
            i + 1 < chars.length() &&
            chars[i] == '\'' &&
            chars[i + 1] == '\''
          ) {
          let text = chars_text(chars, begin, i)
          i += if multiline { 2 } else { 1 }
          tokens.push({ kind: Quoted(text, multiline), offset: start, end: i, })
          closed = true
          break
        }
        i += 1
      }
      if !closed {
        raise Syntax("Unterminated text literal", start)
      }
      continue
    }
    if (c >= '0' && c <= '9') ||
      (
        (c == '+' || c == '-') &&
        i + 1 < chars.length() &&
        chars[i + 1] >= '0' &&
        chars[i + 1] <= '9'
      ) {
      i += 1
      while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
        i += 1
      }
      if i + 1 < chars.length() &&
        chars[i] == '.' &&
        chars[i + 1] >= '0' &&
        chars[i + 1] <= '9' {
        i += 1
        while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
          i += 1
        }
      }
      if i < chars.length() && (chars[i] == 'e' || chars[i] == 'E') {
        i += 1
        if i < chars.length() && (chars[i] == '+' || chars[i] == '-') {
          i += 1
        }
        let exponent = i
        while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
          i += 1
        }
        if i == exponent {
          raise Syntax("Missing exponent digits", i)
        }
      }
      tokens.push({
        kind: Number(chars_text(chars, start, i)),
        offset: start,
        end: i,
      })
      continue
    }
    if identifier_start(c) {
      i += 1
      while i < chars.length() && identifier_part(chars[i]) {
        i += 1
      }
      let name = chars_text(chars, start, i)
      if name == "sha256" && i < chars.length() && chars[i] == ':' {
        i += 1
        while i < chars.length() &&
              (
                (chars[i] >= '0' && chars[i] <= '9') ||
                (chars[i] >= 'a' && chars[i] <= 'f')
              ) {
          i += 1
        }
      }
      tokens.push({
        kind: Word(chars_text(chars, start, i)),
        offset: start,
        end: i,
      })
      continue
    }
    let mut symbol = c.to_string()
    let remaining = chars_text(chars, i, min_int(i + 3, chars.length()))
    if remaining == "===" {
      symbol = "==="
      i += 3
    } else {
      let pair = chars_text(chars, i, min_int(i + 2, chars.length()))
      if ["->", "&&", "||", "==", "!=", "++", "//", "/\\", "::"].contains(pair) {
        symbol = pair
        i += 2
      } else {
        i += 1
      }
    }
    symbol = match symbol {
      "λ" => "\\"
      "→" => "->"
      "∀" => "forall"
      "∧" => "/\\"
      "⫽" => "//"
      "≡" => "==="
      _ => symbol
    }
    if [
        "(", ")", "{", "}", "[", "]", ",", ":", "=", ".", "\\", "+", "*", "@", "#",
        "<", ">", "|", "?", "->", "&&", "||", "==", "!=", "++", "//", "/\\", "::",
        "===", "forall",
      ].contains(symbol) {
      tokens.push({ kind: Symbol(symbol), offset: start, end: i, })
    } else {
      raise Syntax("Unsupported character: " + symbol, start)
    }
  }
  tokens.push({ kind: End, offset: chars.length(), end: chars.length(), })
  tokens
}
