///|
fn builtin_signature(name : String) -> String? {
  match name {
    "Bool" | "Natural" | "Integer" | "Double" | "Text" => Some("Type")
    "Bytes" | "Date" | "Time" | "TimeZone" => Some("Type")
    "Date/show" => Some("Date -> Text")
    "Time/show" => Some("Time -> Text")
    "TimeZone/show" => Some("TimeZone -> Text")
    "List" | "Optional" => Some("Type -> Type")
    "None" => Some("forall (a : Type) -> Optional a")
    "Natural/isZero" | "Natural/even" | "Natural/odd" => Some("Natural -> Bool")
    "Natural/show" => Some("Natural -> Text")
    "Natural/toInteger" => Some("Natural -> Integer")
    "Natural/subtract" => Some("Natural -> Natural -> Natural")
    "Natural/fold" =>
      Some(
        "Natural -> forall (natural : Type) -> (natural -> natural) -> natural -> natural",
      )
    "Natural/build" =>
      Some(
        "(forall (natural : Type) -> (natural -> natural) -> natural -> natural) -> Natural",
      )
    "Integer/show" => Some("Integer -> Text")
    "Integer/toDouble" => Some("Integer -> Double")
    "Integer/negate" => Some("Integer -> Integer")
    "Integer/clamp" | "Integer/abs" => Some("Integer -> Natural")
    "Double/show" => Some("Double -> Text")
    "Text/show" => Some("Text -> Text")
    "Text/replace" => Some("Text -> Text -> Text -> Text")
    "List/length" => Some("forall (a : Type) -> List a -> Natural")
    "List/head" | "List/last" =>
      Some("forall (a : Type) -> List a -> Optional a")
    "List/reverse" => Some("forall (a : Type) -> List a -> List a")
    "List/indexed" =>
      Some("forall (a : Type) -> List a -> List { index : Natural, value : a }")
    "List/fold" =>
      Some(
        "forall (a : Type) -> List a -> forall (list : Type) -> (a -> list -> list) -> list -> list",
      )
    "List/build" =>
      Some(
        "forall (a : Type) -> (forall (list : Type) -> (a -> list -> list) -> list -> list) -> List a",
      )
    _ => None
  }
}

///|
fn require_same(
  actual : Expr,
  expected : Expr,
  context : String,
) -> Unit raise DhallError {
  if !same(actual, expected) {
    raise TypeError(
      context +
      ": expected " +
      pretty_type(expected) +
      ", got " +
      pretty_type(actual),
    )
  }
}

///|
fn kind_of(
  e : Expr,
  ctx : Array[Expr],
  depth : Int32,
) -> Int32 raise DhallError {
  let k = normal(infer(e, ctx, depth + 1), { fuel: 200000, }, 0)
  guard k is Universe(n) else {
    raise TypeError("Expected a type, got " + pretty_type(k))
  }
  n
}

///|
fn infer(e : Expr, ctx : Array[Expr], depth : Int32) -> Expr raise DhallError {
  if depth > 128 {
    raise TypeError("Type checking depth limit exceeded")
  }
  let infer_child = x => infer(x, ctx, depth + 1)
  let norm = x => normal(x, { fuel: 200000, }, 0)
  match e {
    At(pos, _, x) =>
      infer_child(x) catch {
        TypeError(message) => raise TypeAt(message, pos)
        err => raise err
      }
    Boolean(_) => Builtin("Bool")
    Natural(n) => {
      if n < 0L {
        raise TypeError("Natural literals must be nonnegative")
      }
      Builtin("Natural")
    }
    BigNatural(s) => {
      if @bigint.BigInt::from_string(s) < 0 {
        raise TypeError("Negative Natural")
      }
      Builtin("Natural")
    }
    Integer(_) => Builtin("Integer")
    Real(_) => Builtin("Double")
    Text(_) => Builtin("Text")
    ByteLiteral(_) => Builtin("Bytes")
    DateLiteral(_, _, _) => Builtin("Date")
    TimeLiteral(_, _, _, _) => Builtin("Time")
    TimeZoneLiteral(_) => Builtin("TimeZone")
    Interpolate(ps, _) => {
      for (_, x) in ps {
        require_same(infer_child(x), Builtin("Text"), "Text interpolation")
      }
      Builtin("Text")
    }
    Universe(n) if n < 2 => Universe(n + 1)
    Universe(_) => raise TypeError("Sort has no type")
    Builtin(name) => {
      guard builtin_signature(name) is Some(signature) else {
        raise TypeError("Unknown builtin: " + name)
      }
      canonical(parse(signature), [], 0)
    }
    Variable("_", i) if i >= 0 && i < ctx.length() =>
      shift(ctx[ctx.length() - 1 - i], i + 1, 0)
    Variable(name, i) =>
      raise TypeError("Unbound variable: " + name + "@" + i.to_string())
    Let(_, annotation, v, b) => {
      let t = infer_child(v)
      if annotation is Some(expected) {
        let _ = kind_of(expected, ctx, depth + 1)
        require_same(t, expected, "let annotation")
      }
      infer_child(substitute(b, norm(v), 0))
    }
    Lambda(_, t, b) => {
      let _ = kind_of(t, ctx, depth + 1)
      let scope = ctx.copy()
      scope.push(norm(t))
      let result = infer(b, scope, depth + 1)
      let out = Pi("_", norm(t), result)
      let _ = kind_of(out, ctx, depth + 1)
      out
    }
    Pi(_, a, b) => {
      let input_kind = kind_of(a, ctx, depth + 1)
      let scope = ctx.copy()
      scope.push(norm(a))
      let output_kind = kind_of(b, scope, depth + 1)
      if output_kind == 0 {
        Universe(0)
      } else {
        Universe(
          if input_kind > output_kind {
            input_kind
          } else {
            output_kind
          },
        )
      }
    }
    Apply(f, x) => {
      if bare(f) == Builtin("Some") {
        let t = infer_child(x)
        require_same(infer_child(t), Universe(0), "Some element type")
        return Apply(Builtin("Optional"), t)
      }
      guard norm(infer_child(f)) is Pi(_, input, output) else {
        raise TypeError("Cannot apply a non-function")
      }
      require_same(infer_child(x), input, "Function argument")
      norm(substitute(output, norm(x), 0))
    }
    Record(fs) => {
      let fields : Array[(String, Expr)] = []
      for (k, v) in fs {
        if fields.any(p => p.0 == k) {
          raise TypeError("Duplicate field: " + k)
        }
        fields.push((k, infer_child(v)))
      }
      let out = RecordType(sorted_expr(fields))
      let _ = kind_of(out, ctx, depth + 1)
      out
    }
    RecordType(fs) => {
      let mut universe = 0
      for (_, t) in fs {
        let n = kind_of(t, ctx, depth + 1)
        if n > universe {
          universe = n
        }
      }
      Universe(universe)
    }
    UnionType(fs) => {
      let mut universe = 0
      for (_, t) in fs {
        if t is Some(t) {
          let n = kind_of(t, ctx, depth + 1)
          if n > universe {
            universe = n
          }
        }
      }
      Universe(universe)
    }
    Field(r, k) => {
      let rt = norm(infer_child(r))
      if rt is RecordType(fs) {
        guard get_field(fs, k) is Some(t) else {
          raise TypeError("Missing record field: " + k)
        }
        return t
      }
      if norm(r) is UnionType(fs) {
        for (name, t) in fs {
          if name == k {
            return match t {
              None => norm(r)
              Some(t) => Pi("_", t, shift(norm(r), 1, 0))
            }
          }
        }
        raise TypeError("Missing union alternative: " + k)
      }
      raise TypeError("Field selection requires a record or union type")
    }
    ProjectType(r, t) => {
      guard norm(infer_child(r)) is RecordType(fields) &&
        norm(t) is RecordType(selected) else {
        raise TypeError(
          "Projection by type requires a record and a record type",
        )
      }
      let _ = kind_of(t, ctx, depth + 1)
      for (key, expected) in selected {
        guard get_field(fields, key) is Some(actual) else {
          raise TypeError("Missing projection field: " + key)
        }
        require_same(actual, expected, "Projection field " + key)
      }
      RecordType(selected)
    }
    Project(r, ks) => {
      guard norm(infer_child(r)) is RecordType(fs) else {
        raise TypeError("Projection requires a record")
      }
      for k in ks {
        if get_field(fs, k) is None {
          raise TypeError("Missing projection field: " + k)
        }
      }
      RecordType(fs.filter(p => ks.contains(p.0)))
    }
    List(xs) => {
      if xs.is_empty() {
        raise TypeError("Empty lists require a List type annotation")
      }
      let t = infer_child(xs[0])
      require_same(infer_child(t), Universe(0), "List element type")
      for x in xs {
        require_same(infer_child(x), t, "List element")
      }
      Apply(Builtin("List"), t)
    }
    Annotate(x, t) => {
      let _ = kind_of(t, ctx, depth + 1)
      let t = norm(t)
      if bare(x) is List(xs) && xs.is_empty() {
        guard t is Apply(Builtin("List"), _) else {
          raise TypeError("Empty list annotation must be List")
        }
      } else {
        require_same(infer_child(x), t, "Annotation")
      }
      t
    }
    If(c, a, b) => {
      require_same(infer_child(c), Builtin("Bool"), "if condition")
      let t = infer_child(a)
      require_same(infer_child(b), t, "if branches")
      require_same(infer_child(t), Universe(0), "if result type")
      t
    }
    ToMap(r, annotation) => {
      guard norm(infer_child(r)) is RecordType(fields) else {
        raise TypeError("toMap requires a record")
      }
      let expected = annotation.map(x => {
        require_same(infer_child(x), Universe(0), "toMap annotation")
        norm(x)
      })
      let value_type = if fields.is_empty() {
        guard expected is Some(Apply(Builtin("List"), RecordType(fields))) &&
          fields is [("mapKey", Builtin("Text")), ("mapValue", value_type)] else {
          raise TypeError(
            "Empty toMap requires List { mapKey : Text, mapValue : T }",
          )
        }
        value_type
      } else {
        fields[0].1
      }
      require_same(infer_child(value_type), Universe(0), "toMap field kind")
      for (_, t) in fields {
        require_same(t, value_type, "toMap field")
      }
      let result = Apply(
        Builtin("List"),
        RecordType([("mapKey", Builtin("Text")), ("mapValue", value_type)]),
      )
      if expected is Some(expected) {
        require_same(result, expected, "toMap annotation")
      }
      result
    }
    With(r, path, value) => {
      let t = update_type(
        norm(infer_child(r)),
        path[:],
        norm(infer_child(value)),
        depth + 1,
      )
      require_same(infer_child(t), Universe(0), "with result kind")
      t
    }
    Binary("::", schema, value) => infer_child(complete_record(schema, value))
    Binary("//\\", a, b) => {
      let _ = kind_of(a, ctx, depth + 1)
      let _ = kind_of(b, ctx, depth + 1)
      guard norm(a) is RecordType(left) && norm(b) is RecordType(right) else {
        raise TypeError("Record type merge requires record types")
      }
      kind_of(
        RecordType(
          combine_records(left, right, true, true, { fuel: 200000, }, 0),
        ),
        ctx,
        depth + 1,
      )
      |> Universe
    }
    Binary(op, a, b) => {
      let ta = norm(infer_child(a))
      let tb = norm(infer_child(b))
      match op {
        "+" | "*" => {
          require_same(ta, Builtin("Natural"), op)
          require_same(tb, ta, op)
          ta
        }
        "++" => {
          require_same(ta, Builtin("Text"), op)
          require_same(tb, ta, op)
          ta
        }
        "&&" | "||" | "==" | "!=" => {
          require_same(ta, Builtin("Bool"), op)
          require_same(tb, ta, op)
          ta
        }
        "#" => {
          guard ta is Apply(Builtin("List"), _) else {
            raise TypeError("# requires lists")
          }
          require_same(tb, ta, op)
          ta
        }
        "//" | "/\\" => {
          guard ta is RecordType(af) && tb is RecordType(bf) else {
            raise TypeError("Record operator requires records")
          }
          RecordType(
            combine_records(af, bf, op == "/\\", true, { fuel: 200000, }, 0),
          )
        }
        "===" => {
          require_same(ta, tb, "Equivalence operands")
          Universe(0)
        }
        "?" =>
          raise ImportError(
            "Import alternatives must be resolved before checking",
          )
        _ => raise TypeError("Unsupported operator: " + op)
      }
    }
    Assert(x) => {
      let _ = infer_child(x)
      guard norm(x) is Binary("===", a, b) else {
        raise TypeError("assert requires an equivalence")
      }
      if !same(a, b) {
        raise TypeError("Assertion failed: expressions are not equivalent")
      }
      norm(x)
    }
    Merge(h, u, annotation) => {
      guard norm(infer_child(h)) is RecordType(handlers) else {
        raise TypeError("merge handlers must be a record")
      }
      let ut = norm(infer_child(u))
      let alternatives = match ut {
        UnionType(fs) => fs
        Apply(Builtin("Optional"), t) => [("None", None), ("Some", Some(t))]
        _ => raise TypeError("merge requires a union or Optional")
      }
      if handlers.length() != alternatives.length() {
        raise TypeError("merge handlers must cover exactly the alternatives")
      }
      let mut result = annotation.map(norm)
      for (k, t) in alternatives {
        guard get_field(handlers, k) is Some(handler) else {
          raise TypeError("Missing merge handler: " + k)
        }
        let output = match t {
          None => handler
          Some(t) => {
            guard norm(handler) is Pi(_, input, out) else {
              raise TypeError("merge handler must be a function: " + k)
            }
            require_same(input, t, "merge handler " + k)
            // Reject result types depending on the constructor payload.
            if uses_zero(out, 0) {
              raise TypeError("Dependent merge result is not allowed")
            }
            let output = shift(out, -1, 0)
            require_same(shift(output, 1, 0), out, "Non-dependent merge result")
            output
          }
        }
        match result {
          None => result = Some(output)
          Some(expected) => require_same(output, expected, "merge result")
        }
      }
      guard result is Some(t) else {
        raise TypeError("Empty merge needs a result annotation")
      }
      t
    }
    Import(spec) => raise MissingImport(spec.path)
  }
}

///|
pub fn type_of(expr : Expr) -> Type raise DhallError {
  let e = canonical(expr, [], 0)
  { expression: normal(infer(e, [], 0), { fuel: 200000, }, 0), }
}

///|
pub fn check(source : String) -> Type raise DhallError {
  type_of(parse(source))
}
