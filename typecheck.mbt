///|
fn lookup_type(
  env : Array[(String, Type)],
  name : String,
  index : Int32,
) -> Type raise DhallError {
  let mut skip = index
  for i = env.length() - 1; i >= 0; i = i - 1 {
    if env[i].0 == name {
      if skip == 0 {
        return env[i].1
      }
      skip -= 1
    }
  }
  if index == 0 {
    match name {
      "Natural/isZero" | "Natural/even" | "Natural/odd" =>
        return FunctionType(NaturalType, BoolType)
      "Natural/show" => return FunctionType(NaturalType, TextType)
      _ => ()
    }
  }
  raise TypeError("Unbound variable: \{name}@\{index}")
}

///|
fn require_type(
  actual : Type,
  expected : Type,
  context : String,
) -> Unit raise DhallError {
  if actual != expected {
    raise TypeError(
      context + ": expected " + expected.display() + ", got " + actual.display(),
    )
  }
}

///|
fn infer(
  expr : Expr,
  env : Array[(String, Type)],
  depth : Int32,
) -> Type raise DhallError {
  if depth > 128 {
    raise TypeError("Expression depth limit exceeded")
  }
  let next = depth + 1
  match expr {
    Boolean(_) => BoolType
    Natural(n) => {
      if n < 0L {
        raise TypeError("Natural literals must be nonnegative")
      }
      NaturalType
    }
    Text(_) => TextType
    Variable(name, index) => {
      if index < 0 {
        raise TypeError("Variable index must be nonnegative")
      }
      lookup_type(env, name, index)
    }
    Let(name, annotation, value, body) => {
      let t = infer(value, env, next)
      if annotation is Some(expected) {
        require_type(t, expected, "let " + name)
      }
      let scope = env.copy()
      scope.push((name, t))
      infer(body, scope, next)
    }
    Lambda(name, input, body) => {
      let scope = env.copy()
      scope.push((name, input))
      FunctionType(input, infer(body, scope, next))
    }
    Apply(function, argument) => {
      guard infer(function, env, next) is FunctionType(input, output) else {
        raise TypeError("Cannot apply a non-function")
      }
      require_type(infer(argument, env, next), input, "Function argument")
      output
    }
    Record(fields) => {
      let result : Array[(String, Type)] = []
      for (name, value) in fields {
        if result.any(fn(f) { f.0 == name }) {
          raise TypeError("Duplicate record field: " + name)
        }
        result.push((name, infer(value, env, next)))
      }
      RecordType(sorted_types(result))
    }
    Field(record, name) => {
      guard infer(record, env, next) is RecordType(fields) else {
        raise TypeError("Field selection requires a record")
      }
      for field in fields {
        if field.0 == name {
          return field.1
        }
      }
      raise TypeError("Missing record field: " + name)
    }
    List(items) => {
      if items.is_empty() {
        raise TypeError("Empty lists require a List type annotation")
      }
      let element = infer(items[0], env, next)
      for item in items {
        require_type(infer(item, env, next), element, "List element")
      }
      ListType(element)
    }
    Annotate(List(items), ListType(element)) if items.is_empty() =>
      ListType(element)
    Annotate(value, expected) => {
      require_type(infer(value, env, next), expected, "Annotation")
      expected
    }
    If(condition, yes, no) => {
      require_type(infer(condition, env, next), BoolType, "if condition")
      let t = infer(yes, env, next)
      require_type(infer(no, env, next), t, "if branches")
      t
    }
    Binary(op, left, right) => {
      let a = infer(left, env, next)
      let b = infer(right, env, next)
      match op {
        "+" | "*" => {
          require_type(a, NaturalType, op)
          require_type(b, NaturalType, op)
          NaturalType
        }
        "++" => {
          require_type(a, TextType, op)
          require_type(b, TextType, op)
          TextType
        }
        "&&" | "||" | "==" | "!=" => {
          require_type(a, BoolType, op)
          require_type(b, BoolType, op)
          BoolType
        }
        "//" => {
          guard a is RecordType(af) && b is RecordType(bf) else {
            raise TypeError("// requires two records")
          }
          let merged = af.filter(fn(f) { !bf.any(fn(g) { g.0 == f.0 }) })
          for field in bf {
            merged.push(field)
          }
          RecordType(sorted_types(merged))
        }
        _ => raise TypeError("Unsupported operator: " + op)
      }
    }
  }
}

///|
/// Infer the type of a closed expression in the supported core.
pub fn type_of(expr : Expr) -> Type raise DhallError {
  infer(expr, [], 0)
}

///|
/// Parse and type-check source, including both branches of conditionals.
pub fn check(source : String) -> Type raise DhallError {
  type_of(parse(source))
}
