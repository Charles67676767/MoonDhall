///|
priv enum Value {
  VBool(Bool)
  VNatural(Int64)
  VText(String)
  VList(Array[Value])
  VRecord(Array[(String, Value)])
  Closure(String, Expr, Array[(String, Value)])
  Builtin(String)
}

///|
priv struct Budget {
  mut fuel : Int32
}

///|
fn Budget::step(self : Budget, depth : Int32) -> Unit raise DhallError {
  self.fuel -= 1
  if self.fuel < 0 || depth > 128 {
    raise Evaluation("Evaluation resource limit exceeded")
  }
}

///|
fn lookup_value(
  env : Array[(String, Value)],
  name : String,
  index : Int32,
) -> Value raise DhallError {
  let mut skip = index
  for i = env.length() - 1; i >= 0; i = i - 1 {
    if env[i].0 == name {
      if skip == 0 {
        return env[i].1
      }
      skip -= 1
    }
  }
  if index == 0 &&
    ["Natural/isZero", "Natural/even", "Natural/odd", "Natural/show"].contains(
      name,
    ) {
    return Builtin(name)
  }
  raise Evaluation("Unbound variable: \{name}@\{index}")
}

///|
fn eval(
  expr : Expr,
  env : Array[(String, Value)],
  budget : Budget,
  depth : Int32,
) -> Value raise DhallError {
  budget.step(depth)
  let next = depth + 1
  match expr {
    Boolean(b) => VBool(b)
    Natural(n) => VNatural(n)
    Text(s) => VText(s)
    Variable(name, index) => lookup_value(env, name, index)
    Lambda(name, _, body) => Closure(name, body, env.copy())
    Let(name, _, expr, body) => {
      let value = eval(expr, env, budget, next)
      let scope = env.copy()
      scope.push((name, value))
      eval(body, scope, budget, next)
    }
    Apply(function, argument) => {
      let f = eval(function, env, budget, next)
      let arg = eval(argument, env, budget, next)
      match f {
        Closure(name, body, captured) => {
          let scope = captured.copy()
          scope.push((name, arg))
          eval(body, scope, budget, next)
        }
        Builtin(name) => {
          guard arg is VNatural(n) else {
            raise Evaluation("Builtin expected a Natural")
          }
          match name {
            "Natural/isZero" => VBool(n == 0L)
            "Natural/even" => VBool(n % 2L == 0L)
            "Natural/odd" => VBool(n % 2L != 0L)
            "Natural/show" => VText(n.to_string())
            _ => raise Evaluation("Unknown builtin")
          }
        }
        _ => raise Evaluation("Cannot apply a non-function")
      }
    }
    Record(fields) => {
      let values : Array[(String, Value)] = []
      for (name, expr) in fields {
        values.push((name, eval(expr, env, budget, next)))
      }
      values.sort_by(fn(a, b) { a.0[:].lexical_compare(b.0[:]) })
      VRecord(values)
    }
    Field(record, name) => {
      guard eval(record, env, budget, next) is VRecord(fields) else {
        raise Evaluation("Expected a record")
      }
      for field in fields {
        if field.0 == name {
          return field.1
        }
      }
      raise Evaluation("Missing field: " + name)
    }
    List(items) => {
      let values : Array[Value] = []
      for item in items {
        values.push(eval(item, env, budget, next))
      }
      VList(values)
    }
    Annotate(expr, _) => eval(expr, env, budget, next)
    If(condition, yes, no) => {
      guard eval(condition, env, budget, next) is VBool(b) else {
        raise Evaluation("Expected a Bool")
      }
      eval(if b { yes } else { no }, env, budget, next)
    }
    Binary(op, left, right) => {
      let a = eval(left, env, budget, next)
      if op == "&&" && a is VBool(false) {
        return VBool(false)
      }
      if op == "||" && a is VBool(true) {
        return VBool(true)
      }
      let b = eval(right, env, budget, next)
      match (op, a, b) {
        ("+", VNatural(x), VNatural(y)) => {
          if x > 9223372036854775807L - y {
            raise Evaluation("Natural addition overflow")
          }
          VNatural(x + y)
        }
        ("*", VNatural(x), VNatural(y)) => {
          if y != 0L && x > 9223372036854775807L / y {
            raise Evaluation("Natural multiplication overflow")
          }
          VNatural(x * y)
        }
        ("++", VText(x), VText(y)) => {
          if x.length() + y.length() > 1048576 {
            raise Evaluation("Text size limit exceeded")
          }
          VText(x + y)
        }
        ("&&", VBool(x), VBool(y)) => VBool(x && y)
        ("||", VBool(x), VBool(y)) => VBool(x || y)
        ("==", VBool(x), VBool(y)) => VBool(x == y)
        ("!=", VBool(x), VBool(y)) => VBool(x != y)
        ("//", VRecord(x), VRecord(y)) => {
          let merged = x.filter(fn(f) { !y.any(fn(g) { f.0 == g.0 }) })
          for field in y {
            merged.push(field)
          }
          merged.sort_by(fn(a, b) { a.0[:].lexical_compare(b.0[:]) })
          VRecord(merged)
        }
        _ => raise Evaluation("Invalid operator arguments")
      }
    }
  }
}

///|
fn quote_json(text : String) -> String {
  Json::string(text).stringify()
}

///|
fn render_json(
  value : Value,
  budget : Budget,
  depth : Int32,
) -> String raise DhallError {
  budget.step(depth)
  let output = match value {
    VBool(b) => if b { "true" } else { "false" }
    VNatural(n) => n.to_string()
    VText(s) => quote_json(s)
    VList(items) => {
      let parts : Array[String] = []
      for item in items {
        parts.push(render_json(item, budget, depth + 1))
      }
      "[" + parts.join(",") + "]"
    }
    VRecord(fields) => {
      let parts : Array[String] = []
      for (name, item) in fields {
        parts.push(
          quote_json(name) + ":" + render_json(item, budget, depth + 1),
        )
      }
      "{" + parts.join(",") + "}"
    }
    Closure(_, _, _) | Builtin(_) =>
      raise JsonError(
        "Functions cannot be represented as JSON; apply the function first",
      )
  }
  if output.length() > 1048576 {
    raise Evaluation("JSON output size limit exceeded")
  }
  output
}

///| Parse, check, and evaluate a closed expression to deterministic JSON.

///|
/// Naturals retain exact decimal digits, including values above 2^53.
pub fn to_json(source : String) -> String raise DhallError {
  let expr = parse(source)
  let _ = type_of(expr)
  let budget = { fuel: 100000, }
  render_json(eval(expr, [], budget, 0), budget, 0)
}
