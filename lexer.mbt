///|
priv enum TokenKind {
  Word(String)
  Digits(String)
  Quoted(String)
  Symbol(String)
  End
} derive(Debug, Eq)

///|
priv struct Token {
  kind : TokenKind
  offset : Int32
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
fn lex(source : String) -> Array[Token] raise DhallError {
  let chars = source.to_array()
  let tokens : Array[Token] = []
  let mut i = 0
  while i < chars.length() {
    if tokens.length() >= 20000 {
      raise Syntax("Token limit exceeded", i)
    }
    let c = chars[i]
    if c == ' ' || c == '\n' || c == '\r' || c == '\t' {
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
    if c == '"' {
      let raw = StringBuilder()
      raw.write_char(c)
      i += 1
      let mut closed = false
      while i < chars.length() {
        let ch = chars[i]
        raw.write_char(ch)
        i += 1
        if ch == '"' {
          closed = true
          break
        }
        if ch == '\\' {
          if i == chars.length() {
            break
          }
          raw.write_char(chars[i])
          i += 1
        } else if ch == '$' && i < chars.length() && chars[i] == '{' {
          raise Syntax("Text interpolation is not supported yet", start)
        }
      }
      if !closed {
        raise Syntax("Unterminated text literal", start)
      }
      let value = @json.parse(raw.to_string()) catch {
        _ => raise Syntax("Invalid text escape or control character", start)
      }
      guard value is String(text) else { raise Syntax("Invalid text", start) }
      tokens.push({ kind: Quoted(text), offset: start, })
      continue
    }
    if c >= '0' && c <= '9' {
      let digits = StringBuilder()
      while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
        digits.write_char(chars[i])
        i += 1
      }
      tokens.push({ kind: Digits(digits.to_string()), offset: start, })
      continue
    }
    if identifier_start(c) {
      let word = StringBuilder()
      while i < chars.length() && identifier_part(chars[i]) {
        word.write_char(chars[i])
        i += 1
      }
      tokens.push({ kind: Word(word.to_string()), offset: start, })
      continue
    }
    let single = c.to_string()
    if i + 1 < chars.length() {
      let pair = single + chars[i + 1].to_string()
      if pair == "->" ||
        pair == "&&" ||
        pair == "||" ||
        pair == "==" ||
        pair == "!=" ||
        pair == "++" ||
        pair == "//" {
        tokens.push({ kind: Symbol(pair), offset: start, })
        i += 2
        continue
      }
    }
    let symbol = match c {
      'λ' => "\\"
      '→' => "->"
      _ => single
    }
    if ["(", ")", "{", "}", "[", "]", ",", ":", "=", ".", "\\", "+", "*", "@"].contains(
        symbol,
      ) ||
      c == 'λ' ||
      c == '→' {
      tokens.push({ kind: Symbol(symbol), offset: start, })
      i += 1
    } else {
      raise Syntax("Unsupported character: " + single, start)
    }
    if tokens.length() > 20000 {
      raise Syntax("Token limit exceeded", start)
    }
  }
  tokens.push({ kind: End, offset: chars.length(), })
  tokens
}
