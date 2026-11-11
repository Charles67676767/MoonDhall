///|
priv struct Parser {
  tokens : Array[Token]
  mut index : Int32
  mut depth : Int32
}

///|
fn Parser::peek(self : Parser) -> TokenKind {
  self.tokens[self.index].kind
}

///|
fn Parser::offset(self : Parser) -> Int32 {
  self.tokens[self.index].offset
}

///|
fn Parser::accept(self : Parser, kind : TokenKind) -> Bool {
  if self.peek() == kind {
    self.index += 1
    true
  } else {
    false
  }
}

///|
fn Parser::expect(self : Parser, kind : TokenKind) -> Unit raise DhallError {
  if !self.accept(kind) {
    raise Syntax(
      "Expected \{@debug.repr(kind)}, found \{@debug.repr(self.peek())}",
      self.offset(),
    )
  }
}

///|
fn Parser::name(self : Parser) -> String raise DhallError {
  match self.peek() {
    Word(s) if ![
        "let", "in", "if", "then", "else", "as", "assert", "forall", "merge", "True",
        "False",
      ].contains(s) => {
      self.index += 1
      s
    }
    Label(s) => {
      self.index += 1
      s
    }
    _ => raise Syntax("Expected a label", self.offset())
  }
}

///|
fn Parser::expression(self : Parser) -> Expr raise DhallError {
  self.depth += 1
  if self.depth > 128 {
    raise Syntax("Nesting limit exceeded", self.offset())
  }
  let start = self.offset()
  let mut updated = false
  let expr = if self.accept(Word("let")) {
    let name = self.name()
    let annotation = if self.accept(Symbol(":")) {
      Some(self.expression())
    } else {
      None
    }
    self.expect(Symbol("="))
    let value = self.expression()
    if self.peek() != Word("let") {
      self.expect(Word("in"))
    }
    Let(name, annotation, value, self.expression())
  } else if self.accept(Symbol("\\")) {
    self.expect(Symbol("("))
    let name = self.name()
    self.expect(Symbol(":"))
    let t = self.expression()
    self.expect(Symbol(")"))
    self.expect(Symbol("->"))
    Lambda(name, t, self.expression())
  } else if self.accept(Word("forall")) || self.accept(Symbol("forall")) {
    self.expect(Symbol("("))
    let name = self.name()
    self.expect(Symbol(":"))
    let t = self.expression()
    self.expect(Symbol(")"))
    self.expect(Symbol("->"))
    Pi(name, t, self.expression())
  } else if self.accept(Word("if")) {
    let condition = self.expression()
    self.expect(Word("then"))
    let yes = self.expression()
    self.expect(Word("else"))
    If(condition, yes, self.expression())
  } else if self.accept(Word("assert")) {
    self.expect(Symbol(":"))
    Assert(self.expression())
  } else {
    let mut subject = self.binary(0)
    while self.peek() == Word("with") {
      let keyword = self.tokens[self.index]
      if self.tokens[self.index - 1].end == keyword.offset ||
        self.tokens[self.index + 1].offset == keyword.end {
        raise Syntax("with requires surrounding whitespace", keyword.offset)
      }
      self.index += 1
      if subject is Apply(_, _) ||
        subject is ToMap(_, _) ||
        subject is Merge(_, _, _) ||
        (subject is Binary(op, _, _) && op != "::") {
        raise Syntax("Parenthesize the subject of with", start)
      }
      updated = true
      let path = [self.update_component()]
      while self.accept(Symbol(".")) {
        path.push(self.update_component())
      }
      self.expect(Symbol("="))
      subject = With(subject, path, self.binary(0))
    }
    subject
  }
  let expr = if self.accept(Symbol("->")) {
    Pi("_", expr, self.expression())
  } else {
    expr
  }
  let expr = if self.accept(Symbol(":")) {
    if updated {
      raise Syntax("Parenthesize the with expression before annotating", start)
    }
    match bare(expr) {
      Merge(h, u, None) => Merge(h, u, Some(self.expression()))
      ToMap(r, None) => ToMap(r, Some(self.expression()))
      _ => Annotate(expr, self.expression())
    }
  } else {
    expr
  }
  self.depth -= 1
  At(start, self.tokens[self.index - 1].end, expr)
}

///|
fn precedence(op : String) -> Int32 {
  match op {
    "===" => 0
    "?" => 1
    "||" => 2
    "++" => 3
    "+" => 4
    "#" => 5
    "&&" => 6
    "/\\" => 7
    "//" => 8
    "*" => 9
    "==" => 10
    "!=" => 11
    _ => -1
  }
}

///|
fn Parser::binary(self : Parser, minimum : Int32) -> Expr raise DhallError {
  let mut left = self.application()
  while self.peek() is Symbol(op) && precedence(op) >= minimum {
    self.index += 1
    left = Binary(op, left, self.binary(precedence(op) + 1))
  }
  left
}

///|
fn starts_atom(kind : TokenKind) -> Bool {
  match kind {
    Number(_)
    | Quoted(_, _)
    | Path(_)
    | Label(_)
    | Symbol("(")
    | Symbol("{")
    | Symbol("[")
    | Symbol("<") => true
    Word(s) =>
      !["let", "in", "then", "else", "if", "as", "forall", "with", "assert"].contains(
        s,
      )
    _ => false
  }
}

///|
fn Parser::application(self : Parser) -> Expr raise DhallError {
  let mut expr = self.completion()
  while starts_atom(self.peek()) {
    expr = Apply(expr, self.completion())
  }
  expr
}

///|
fn Parser::completion(self : Parser) -> Expr raise DhallError {
  let left = self.project()
  if self.accept(Symbol("::")) {
    Binary("::", left, self.project())
  } else {
    left
  }
}

///|
fn Parser::update_component(self : Parser) -> String? raise DhallError {
  if self.accept(Symbol("?")) {
    None
  } else {
    Some(self.name())
  }
}

///|
fn Parser::project(self : Parser) -> Expr raise DhallError {
  let mut expr = self.atom()
  while self.accept(Symbol(".")) {
    if self.accept(Symbol("{")) {
      let names : Array[String] = []
      if !self.accept(Symbol("}")) {
        while true {
          let name = self.name()
          if names.contains(name) {
            raise Syntax("Duplicate projection label", self.offset())
          }
          names.push(name)
          if self.accept(Symbol("}")) {
            break
          }
          self.expect(Symbol(","))
          if self.accept(Symbol("}")) {
            break
          }
        }
      }
      expr = Project(expr, names)
    } else {
      expr = Field(expr, self.name())
    }
  }
  expr
}

///|
fn number_expr(s : String, offset : Int32) -> Expr raise DhallError {
  if s.contains(".") || s.contains("e") || s.contains("E") {
    let value = @string.parse_double(s[:]) catch {
      _ => raise Syntax("Invalid Double", offset)
    }
    Real(value)
  } else if s.has_prefix("+") || s.has_prefix("-") {
    Integer(if s.has_prefix("+") { s[1:].to_owned() } else { s })
  } else {
    let n = @bigint.BigInt::from_string(s)
    if n.compare_int64(9223372036854775807L) <= 0 {
      Natural(n.to_int64())
    } else {
      BigNatural(n.to_string())
    }
  }
}

///|
fn dotted_record(names : Array[String], value : Expr) -> Expr {
  let mut expr = value
  for i = names.length() - 1; i >= 0; i = i - 1 {
    expr = Record([(names[i], expr)])
  }
  expr
}

///|
fn Parser::atom(self : Parser) -> Expr raise DhallError {
  let start = self.offset()
  let expr = match self.peek() {
    Number(s) => {
      self.index += 1
      number_expr(s, start)
    }
    Quoted(text, multiline) => {
      self.index += 1
      parse_text(text, multiline, start, self.depth)
    }
    Word("True") => {
      self.index += 1
      Boolean(true)
    }
    Word("False") => {
      self.index += 1
      Boolean(false)
    }
    Word("Type") => {
      self.index += 1
      Universe(0)
    }
    Word("Kind") => {
      self.index += 1
      Universe(1)
    }
    Word("Sort") => {
      self.index += 1
      Universe(2)
    }
    Word("NaN") => {
      self.index += 1
      Real(0.0 / 0.0)
    }
    Word("-Infinity") => {
      self.index += 1
      Real(-1.0 / 0.0)
    }
    Word("Infinity") => {
      self.index += 1
      Real(1.0 / 0.0)
    }
    Word("toMap") => {
      self.index += 1
      ToMap(self.completion(), None)
    }
    Word("merge") => {
      self.index += 1
      let handlers = self.project()
      let union = self.project()
      Merge(handlers, union, None)
    }
    Word("missing") => {
      self.index += 1
      Import({ path: "missing", mode: "Code", hash: None, })
    }
    Path(path) => {
      self.index += 1
      let hash = match self.peek() {
        Word(s) if s.has_prefix("sha256:") => {
          self.index += 1
          if s.length() != 71 {
            raise Syntax("Expected 64 hexadecimal hash digits", self.offset())
          }
          Some(s[7:].to_owned())
        }
        _ => None
      }
      let mode = if self.accept(Word("as")) {
        let name = self.name()
        if !["Text", "Location"].contains(name) {
          raise Syntax("Expected Text or Location import mode", self.offset())
        }
        name
      } else {
        "Code"
      }
      Import({ path, mode, hash, })
    }
    Word(s) | Label(s) => {
      self.index += 1
      if builtin_signature(s) is Some(_) ||
        [
          "Bool", "Natural", "Integer", "Double", "Text", "List", "Optional", "Some",
          "None",
        ].contains(s) {
        Builtin(s)
      } else {
        let index = if self.accept(Symbol("@")) {
          match self.peek() {
            Number(n) => {
              self.index += 1
              let value = number_expr(n, start)
              guard value is Natural(v) && v <= 20000L else {
                raise Syntax("Invalid variable index", start)
              }
              v.to_int()
            }
            _ => raise Syntax("Expected variable index", self.offset())
          }
        } else {
          0
        }
        Variable(s, index)
      }
    }
    Symbol("(") => {
      self.index += 1
      let expr = self.expression()
      self.expect(Symbol(")"))
      expr
    }
    Symbol("{") => {
      self.index += 1
      if self.accept(Symbol("=")) {
        self.expect(Symbol("}"))
        Record([])
      } else if self.accept(Symbol("}")) {
        RecordType([])
      } else {
        let fields : Array[(String, Expr)] = []
        let mut is_type : Bool? = None
        while true {
          let names : Array[String] = [self.name()]
          while self.accept(Symbol(".")) {
            names.push(self.name())
          }
          let t = if self.accept(Symbol(":")) {
            true
          } else {
            self.expect(Symbol("="))
            false
          }
          if is_type is Some(old) && old != t {
            raise Syntax("Cannot mix record types and values", self.offset())
          }
          is_type = Some(t)
          let value = self.expression()
          if t {
            if names.length() != 1 || fields.any(f => f.0 == names[0]) {
              raise Syntax("Invalid record type field", start)
            }
            fields.push((names[0], value))
          } else {
            let value = if names.length() > 1 {
              dotted_record(names[1:].to_owned(), value)
            } else {
              value
            }
            let mut existing = -1
            for i in 0..<fields.length() {
              if fields[i].0 == names[0] {
                existing = i
              }
            }
            if existing >= 0 {
              fields[existing] = (
                names[0],
                Binary("/\\", fields[existing].1, value),
              )
            } else {
              fields.push((names[0], value))
            }
          }
          if self.accept(Symbol("}")) {
            break
          }
          self.expect(Symbol(","))
          if self.accept(Symbol("}")) {
            break
          }
        }
        if is_type == Some(true) {
          RecordType(fields)
        } else {
          Record(fields)
        }
      }
    }
    Symbol("[") => {
      self.index += 1
      let items : Array[Expr] = []
      if !self.accept(Symbol("]")) {
        while true {
          items.push(self.expression())
          if self.accept(Symbol("]")) {
            break
          }
          self.expect(Symbol(","))
          if self.accept(Symbol("]")) {
            break
          }
        }
      }
      List(items)
    }
    Symbol("<") => {
      self.index += 1
      let fields : Array[(String, Expr?)] = []
      if !self.accept(Symbol(">")) {
        while true {
          let name = self.name()
          if fields.any(f => f.0 == name) {
            raise Syntax("Duplicate union alternative", start)
          }
          let t = if self.accept(Symbol(":")) {
            Some(self.expression())
          } else {
            None
          }
          fields.push((name, t))
          if self.accept(Symbol(">")) {
            break
          }
          self.expect(Symbol("|"))
        }
      }
      UnionType(fields)
    }
    _ =>
      raise Syntax(
        "Expected an expression, found \{@debug.repr(self.peek())}",
        start,
      )
  }
  At(start, self.tokens[self.index - 1].end, expr)
}

///|
fn dedent_text(raw : String) -> String {
  let raw = if raw.has_prefix("\r\n") {
    raw[2:].to_owned()
  } else if raw.has_prefix("\n") {
    raw[1:].to_owned()
  } else {
    raw
  }
  let lines = raw.split("\n").to_array()
  let mut indent = 2147483647
  for line in lines {
    let chars = line.to_array()
    let mut count = 0
    while count < chars.length() &&
          (chars[count] == ' ' || chars[count] == '\t') {
      count += 1
    }
    if count < chars.length() || line == lines[lines.length() - 1] {
      indent = min_int(indent, count)
    }
  }
  if indent == 2147483647 {
    indent = 0
  }
  lines
  .map(line => {
    let c = line.to_array()
    chars_text(c, min_int(indent, c.length()), c.length())
  })
  .join("\n")
}

///|
fn decode_text(raw : String, offset : Int32) -> String raise DhallError {
  let json = @json.parse("\"" + raw + "\"") catch {
    _ => raise Syntax("Invalid text escape or control character", offset)
  }
  guard json is String(text) else { raise Syntax("Invalid Text", offset) }
  text
}

///|
fn parse_text(
  input : String,
  multiline : Bool,
  offset : Int32,
  depth : Int32,
) -> Expr raise DhallError {
  let raw = if multiline { dedent_text(input) } else { input }
  let chars = raw.to_array()
  let parts : Array[(String, Expr)] = []
  let mut literal = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    if !multiline && chars[i] == '\\' {
      if i + 2 < chars.length() && chars[i + 1] == '$' && chars[i + 2] == '{' {
        literal.write_string(interpolation_start())
        i += 3
        continue
      }
      if i + 1 >= chars.length() {
        raise Syntax("Unterminated escape", offset + i)
      }
      literal.write_char(chars[i])
      literal.write_char(chars[i + 1])
      i += 2
      continue
    }
    if multiline &&
      i + 2 < chars.length() &&
      chars[i] == '\'' &&
      chars[i + 1] == '\'' {
      if chars[i + 2] == '\'' {
        literal.write_string("''")
        i += 3
        continue
      }
      if chars[i + 2] == '$' && i + 3 < chars.length() && chars[i + 3] == '{' {
        literal.write_string(interpolation_start())
        i += 4
        continue
      }
    }
    if chars[i] == '$' && i + 1 < chars.length() && chars[i + 1] == '{' {
      let begin = i + 2
      i = begin
      let mut nesting = 1
      while i < chars.length() && nesting > 0 {
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
        if nesting > 0 {
          i += 1
        }
      }
      if nesting != 0 {
        raise Syntax("Unterminated interpolation", offset + begin)
      }
      let source = chars_text(chars, begin, i)
      let expr = parse_internal(source, offset + begin + 1, depth + 1)
      let text = literal.to_string()
      literal = StringBuilder()
      parts.push(
        (if multiline { text } else { decode_text(text, offset) }, expr),
      )
      i += 1
    } else {
      literal.write_char(chars[i])
      i += 1
    }
  }
  let tail = if multiline {
    literal.to_string()
  } else {
    decode_text(literal.to_string(), offset)
  }
  if parts.is_empty() {
    Text(tail)
  } else {
    Interpolate(parts, tail)
  }
}

///|
fn parse_internal(
  source : String,
  base : Int32,
  depth : Int32,
) -> Expr raise DhallError {
  if source.length() > 262144 || depth > 128 {
    raise Syntax("Source or nesting limit exceeded", base)
  }
  let tokens = lex(source)
  let shifted = tokens.map(t => Token::{
    kind: t.kind,
    offset: t.offset + base,
    end: t.end + base,
  })
  let parser = Parser::{ tokens: shifted, index: 0, depth, }
  let expr = parser.expression()
  parser.expect(End)
  expr
}

///|
pub fn parse(source : String) -> Expr raise DhallError {
  parse_internal(source, 0, 0)
}
