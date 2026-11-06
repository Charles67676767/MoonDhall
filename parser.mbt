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
    Word(name) => {
      if [
          "let", "in", "if", "then", "else", "True", "False", "Bool", "Natural",
          "Text", "List",
        ].contains(name) {
        raise Syntax(
          "Reserved word cannot be used as a label: " + name,
          self.offset(),
        )
      }
      self.index += 1
      name
    }
    _ => raise Syntax("Expected an identifier", self.offset())
  }
}

///|
fn Parser::enter(self : Parser) -> Unit raise DhallError {
  self.depth += 1
  if self.depth > 128 {
    raise Syntax("Nesting limit exceeded", self.offset())
  }
}

///|
fn Parser::read_type(self : Parser) -> Type raise DhallError {
  self.enter()
  let t = if self.accept(Word("Bool")) {
    BoolType
  } else if self.accept(Word("Natural")) {
    NaturalType
  } else if self.accept(Word("Text")) {
    TextType
  } else if self.accept(Word("List")) {
    ListType(self.type_atom())
  } else if self.accept(Symbol("(")) {
    let t = self.read_type()
    self.expect(Symbol(")"))
    t
  } else if self.accept(Symbol("{")) {
    let fields : Array[(String, Type)] = []
    if !self.accept(Symbol("}")) {
      while true {
        let name = self.name()
        if fields.any(fn(f) { f.0 == name }) {
          raise Syntax("Duplicate type field: " + name, self.offset())
        }
        self.expect(Symbol(":"))
        fields.push((name, self.read_type()))
        if self.accept(Symbol("}")) {
          break
        }
        self.expect(Symbol(","))
      }
    }
    RecordType(sorted_types(fields))
  } else {
    raise Syntax("Expected a supported type", self.offset())
  }
  let result = if self.accept(Symbol("->")) {
    FunctionType(t, self.read_type())
  } else {
    t
  }
  self.depth -= 1
  result
}

///|
fn Parser::type_atom(self : Parser) -> Type raise DhallError {
  self.enter()
  let result = if self.accept(Symbol("(")) {
    let t = self.read_type()
    self.expect(Symbol(")"))
    t
  } else if self.accept(Word("Bool")) {
    BoolType
  } else if self.accept(Word("Natural")) {
    NaturalType
  } else if self.accept(Word("Text")) {
    TextType
  } else if self.accept(Word("List")) {
    ListType(self.type_atom())
  } else {
    raise Syntax(
      "Expected an atomic type; parenthesize record or function types",
      self.offset(),
    )
  }
  self.depth -= 1
  result
}

///|
fn Parser::expression(self : Parser) -> Expr raise DhallError {
  self.enter()
  let expr = if self.accept(Word("let")) {
    let name = self.name()
    let annotation = if self.accept(Symbol(":")) {
      Some(self.read_type())
    } else {
      None
    }
    self.expect(Symbol("="))
    let value = self.expression()
    if self.accept(Word("let")) {
      self.index -= 1
    } else {
      self.expect(Word("in"))
    }
    Let(name, annotation, value, self.expression())
  } else if self.accept(Symbol("\\")) {
    self.expect(Symbol("("))
    let name = self.name()
    self.expect(Symbol(":"))
    let t = self.read_type()
    self.expect(Symbol(")"))
    self.expect(Symbol("->"))
    Lambda(name, t, self.expression())
  } else if self.accept(Word("if")) {
    let condition = self.expression()
    self.expect(Word("then"))
    let yes = self.expression()
    self.expect(Word("else"))
    If(condition, yes, self.expression())
  } else {
    self.binary(0)
  }
  let result = if self.accept(Symbol(":")) {
    Annotate(expr, self.read_type())
  } else {
    expr
  }
  self.depth -= 1
  result
}

///|
fn precedence(op : String) -> Int32 {
  match op {
    "||" => 1
    "++" => 2
    "+" => 3
    "&&" => 4
    "//" => 5
    "*" => 6
    "==" | "!=" => 7
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
    Digits(_) | Quoted(_) | Symbol("(") | Symbol("{") | Symbol("[") => true
    Word(s) => !["let", "in", "then", "else", "if"].contains(s)
    _ => false
  }
}

///|
fn Parser::application(self : Parser) -> Expr raise DhallError {
  let mut expr = self.project()
  while starts_atom(self.peek()) {
    expr = Apply(expr, self.project())
  }
  expr
}

///|
fn Parser::project(self : Parser) -> Expr raise DhallError {
  let mut expr = self.atom()
  while self.accept(Symbol(".")) {
    expr = Field(expr, self.name())
  }
  expr
}

///|
fn natural_literal(s : String, offset : Int32) -> Int64 raise DhallError {
  let mut value = 0L
  for c in s.to_array() {
    let digit = (c.to_int() - 48).to_int64()
    if value > (9223372036854775807L - digit) / 10L {
      raise Syntax(
        "Natural exceeds this implementation's signed 64-bit range", offset,
      )
    }
    value = value * 10L + digit
  }
  value
}

///|
fn Parser::atom(self : Parser) -> Expr raise DhallError {
  let offset = self.offset()
  match self.peek() {
    Digits(s) => {
      self.index += 1
      Natural(natural_literal(s, offset))
    }
    Quoted(s) => {
      self.index += 1
      Text(s)
    }
    Word("True") => {
      self.index += 1
      Boolean(true)
    }
    Word("False") => {
      self.index += 1
      Boolean(false)
    }
    Word(_) => {
      let name = self.name()
      let index = if self.accept(Symbol("@")) {
        match self.peek() {
          Digits(s) => {
            self.index += 1
            let n = natural_literal(s, offset)
            if n > 20000L {
              raise Syntax("Variable index limit exceeded", offset)
            }
            n.to_int()
          }
          _ => raise Syntax("Expected a variable index", self.offset())
        }
      } else {
        0
      }
      Variable(name, index)
    }
    Symbol("(") => {
      self.index += 1
      let expr = self.expression()
      self.expect(Symbol(")"))
      expr
    }
    Symbol("{") => {
      self.index += 1
      let fields : Array[(String, Expr)] = []
      if self.accept(Symbol("=")) {
        self.expect(Symbol("}"))
        return Record(fields)
      }
      if self.peek() == Symbol("}") {
        raise Syntax("An empty record value is written {=}", offset)
      }
      while true {
        let name = self.name()
        if fields.any(fn(f) { f.0 == name }) {
          raise Syntax(
            "Duplicate record fields are not supported yet: " + name,
            offset,
          )
        }
        self.expect(Symbol("="))
        fields.push((name, self.expression()))
        if self.accept(Symbol("}")) {
          break
        }
        self.expect(Symbol(","))
      }
      Record(fields)
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
        }
      }
      List(items)
    }
    _ =>
      raise Syntax(
        "Expected an expression, found \{@debug.repr(self.peek())}",
        offset,
      )
  }
}

///|
/// Parse a supported Dhall expression. Offsets count Unicode scalar values.
pub fn parse(source : String) -> Expr raise DhallError {
  if source.length() > 262144 {
    raise Syntax("Source exceeds 256 Ki UTF-16 code units", 0)
  }
  let parser = { tokens: lex(source), index: 0, depth: 0, }
  let expr = parser.expression()
  parser.expect(End)
  expr
}
