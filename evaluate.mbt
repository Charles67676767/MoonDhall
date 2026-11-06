///|
/// Resource limits apply to public ASTs as well as parsed source.
priv struct Budget {
  mut fuel : Int32
}

///|
fn Budget::step(self : Budget, depth : Int32) -> Unit raise DhallError {
  self.fuel -= 1
  if self.fuel < 0 || depth > 256 {
    raise Evaluation("Evaluation resource limit exceeded")
  }
}

///|
/// Map immediate children, reporting binder depth.
fn children(
  e : Expr,
  f : (Expr, Int32) -> Expr raise DhallError,
) -> Expr raise DhallError {
  match e {
    At(a, b, x) => At(a, b, f(x, 0))
    Let(n, t, v, b) => Let(n, t.map(x => f(x, 0)), f(v, 0), f(b, 1))
    Lambda(n, t, b) => Lambda(n, f(t, 0), f(b, 1))
    Pi(n, t, b) => Pi(n, f(t, 0), f(b, 1))
    Apply(a, b) => Apply(f(a, 0), f(b, 0))
    Record(fs) => Record(fs.map(p => (p.0, f(p.1, 0))))
    RecordType(fs) => RecordType(fs.map(p => (p.0, f(p.1, 0))))
    UnionType(fs) => UnionType(fs.map(p => (p.0, p.1.map(x => f(x, 0)))))
    Field(x, n) => Field(f(x, 0), n)
    Project(x, ns) => Project(f(x, 0), ns)
    List(xs) => List(xs.map(x => f(x, 0)))
    Annotate(x, t) => Annotate(f(x, 0), f(t, 0))
    If(c, a, b) => If(f(c, 0), f(a, 0), f(b, 0))
    Binary(op, a, b) => Binary(op, f(a, 0), f(b, 0))
    Interpolate(ps, s) => Interpolate(ps.map(p => (p.0, f(p.1, 0))), s)
    Merge(h, u, t) => Merge(f(h, 0), f(u, 0), t.map(x => f(x, 0)))
    Assert(x) => Assert(f(x, 0))
    _ => e
  }
}

///|
fn canonical(
  e : Expr,
  names : Array[String],
  depth : Int32,
) -> Expr raise DhallError {
  if depth > 256 {
    raise Evaluation("Expression depth limit exceeded")
  }
  match e {
    Variable(n, k) => {
      let mut skip = k
      for i = names.length() - 1; i >= 0; i = i - 1 {
        if names[i] == n {
          if skip == 0 {
            return Variable("_", names.length() - 1 - i)
          }
          skip -= 1
        }
      }
      // Keep free variables distinguishable from bound de Bruijn indices.
      if n == "_" {
        Variable(n, skip + names.length())
      } else {
        Variable(n, skip)
      }
    }
    Lambda(n, t, b) | Pi(n, t, b) => {
      let input = canonical(t, names, depth + 1)
      let scope = names.copy()
      scope.push(n)
      let body = canonical(b, scope, depth + 1)
      if e is Lambda(_, _, _) {
        Lambda("_", input, body)
      } else {
        Pi("_", input, body)
      }
    }
    Let(n, t, v, b) => {
      let annotation = t.map(x => canonical(x, names, depth + 1))
      let value = canonical(v, names, depth + 1)
      let scope = names.copy()
      scope.push(n)
      Let("_", annotation, value, canonical(b, scope, depth + 1))
    }
    _ => children(e, (x, _) => canonical(x, names, depth + 1))
  }
}

///|
fn shift(e : Expr, amount : Int32, cutoff : Int32) -> Expr raise DhallError {
  match e {
    Variable("_", k) if k >= cutoff => Variable("_", k + amount)
    _ => children(e, (x, bound) => shift(x, amount, cutoff + bound))
  }
}

///|
/// Capture-avoiding substitution, removing the substituted binder.
fn substitute(e : Expr, value : Expr, depth : Int32) -> Expr raise DhallError {
  match e {
    Variable("_", k) if k == depth => shift(value, depth, 0)
    Variable("_", k) if k > depth => Variable("_", k - 1)
    _ => children(e, (x, bound) => substitute(x, value, depth + bound))
  }
}

///|
fn nat(n : @bigint.BigInt) -> Expr {
  if n.compare_int64(9223372036854775807L) <= 0 {
    Natural(n.to_int64())
  } else {
    BigNatural(n.to_string())
  }
}

///|
fn number(e : Expr) -> @bigint.BigInt? {
  match e {
    Natural(n) => Some(@bigint.BigInt::from_int64(n))
    BigNatural(s) | Integer(s) => Some(@bigint.BigInt::from_string(s))
    _ => None
  }
}

///|
fn sorted_expr(fs : Array[(String, Expr)]) -> Array[(String, Expr)] {
  let out = fs.copy()
  out.sort_by((a, b) => lexical(a.0, b.0))
  out
}

///|
fn get_field(fs : Array[(String, Expr)], n : String) -> Expr? {
  for (k, v) in fs {
    if k == n {
      return Some(v)
    }
  }
  None
}

///|
fn combine_records(
  a : Array[(String, Expr)],
  b : Array[(String, Expr)],
  infer_childsive : Bool,
  types : Bool,
  budget : Budget,
  depth : Int32,
) -> Array[(String, Expr)] raise DhallError {
  let out = a.filter(p => !b.any(q => p.0 == q.0))
  for (k, v) in b {
    let v = if infer_childsive && get_field(a, k) is Some(old) {
      match (old, v) {
        (Record(x), Record(y)) if !types =>
          Record(combine_records(x, y, true, false, budget, depth + 1))
        (RecordType(x), RecordType(y)) =>
          RecordType(combine_records(x, y, true, true, budget, depth + 1))
        _ =>
          raise TypeError(
            "Recursive record merge has a non-record collision: " + k,
          )
      }
    } else {
      v
    }
    out.push((k, v))
  }
  sorted_expr(out)
}

///|
fn applications(e : Expr) -> (Expr, Array[Expr]) {
  let args : Array[Expr] = []
  let mut head = e
  while head is Apply(f, x) {
    args.push(x)
    head = f
  }
  args.rev_in_place()
  (head, args)
}

///|
fn apply_many(f : Expr, args : Array[Expr]) -> Expr {
  let mut result = f
  for x in args {
    result = Apply(result, x)
  }
  result
}

///|
fn reduce_builtin(
  name : String,
  a : Array[Expr],
  budget : Budget,
  depth : Int32,
) -> Expr? raise DhallError {
  let norm = e => normal(e, budget, depth + 1)
  let optional = (t, x) => {
    Annotate(Apply(Builtin("Some"), x), Apply(Builtin("Optional"), t))
  }
  match (name, a) {
    ("Natural/isZero", [x]) if number(x) is Some(n) => Some(Boolean(n == 0))
    ("Natural/even", [x]) if number(x) is Some(n) => Some(Boolean(n % 2 == 0))
    ("Natural/odd", [x]) if number(x) is Some(n) => Some(Boolean(n % 2 != 0))
    ("Natural/show", [x]) if number(x) is Some(n) => Some(Text(n.to_string()))
    ("Natural/toInteger", [x]) if number(x) is Some(n) =>
      Some(Integer(n.to_string()))
    ("Natural/subtract", [x, y]) if number(x) is Some(n) && number(y) is Some(m) =>
      Some(nat(if m >= n { m - n } else { @bigint.BigInt::from_int(0) }))
    ("Integer/show", [Integer(s)]) =>
      Some(Text(if s.has_prefix("-") { s } else { "+" + s }))
    ("Integer/toDouble", [Integer(s)]) =>
      Some(
        Real(
          @string.parse_double(s[:]) catch {
            _ => raise Evaluation("Integer is too large for Double")
          },
        ),
      )
    ("Integer/negate", [Integer(s)]) =>
      Some(Integer((-@bigint.BigInt::from_string(s)).to_string()))
    ("Integer/clamp", [Integer(s)]) => {
      let n = @bigint.BigInt::from_string(s)
      Some(nat(if n < 0 { @bigint.BigInt::from_int(0) } else { n }))
    }
    ("Integer/abs", [Integer(s)]) => {
      let n = @bigint.BigInt::from_string(s)
      Some(nat(if n < 0 { -n } else { n }))
    }
    ("Double/show", [Real(d)]) => Some(Text(double_text(d)))
    ("Text/show", [Text(s)]) => Some(Text(quote_json(s)))
    ("Text/replace", [Text(needle), Text(replacement), Text(haystack)]) =>
      Some(
        Text(
          if needle == "" {
            haystack
          } else {
            haystack.split(needle).map(s => s.to_owned()).join(replacement)
          },
        ),
      )
    ("List/length", [_, List(xs)])
    | ("List/length", [_, Annotate(List(xs), _)]) =>
      Some(Natural(xs.length().to_int64()))
    ("List/reverse", [_, List(xs)])
    | ("List/reverse", [_, Annotate(List(xs), _)]) => {
      let ys = xs.copy()
      ys.rev_in_place()
      Some(List(ys))
    }
    ("List/head", [t, List(xs)]) | ("List/head", [t, Annotate(List(xs), _)]) =>
      Some(
        if xs.is_empty() {
          Apply(Builtin("None"), t)
        } else {
          optional(t, xs[0])
        },
      )
    ("List/last", [t, List(xs)]) | ("List/last", [t, Annotate(List(xs), _)]) =>
      Some(
        if xs.is_empty() {
          Apply(Builtin("None"), t)
        } else {
          optional(t, xs[xs.length() - 1])
        },
      )
    ("List/indexed", [_, List(xs)])
    | ("List/indexed", [_, Annotate(List(xs), _)]) => {
      let out : Array[Expr] = []
      for i in 0..<xs.length() {
        out.push(Record([("index", Natural(i.to_int64())), ("value", xs[i])]))
      }
      Some(List(out))
    }
    ("Natural/fold", [x, _, succ, zero]) if number(x) is Some(n) => {
      if n > 10000 {
        raise Evaluation("Natural/fold iteration limit exceeded")
      }
      let mut out = zero
      for _ in 0..<n.to_int() {
        out = norm(Apply(succ, out))
      }
      Some(out)
    }
    ("Natural/build", [builder]) =>
      Some(
        norm(
          apply_many(builder, [
            Builtin("Natural"),
            Lambda(
              "_",
              Builtin("Natural"),
              Binary("+", Variable("_", 0), Natural(1L)),
            ),
            Natural(0L),
          ]),
        ),
      )
    ("List/fold", [_, List(xs), _, cons, nil])
    | ("List/fold", [_, Annotate(List(xs), _), _, cons, nil]) => {
      let mut out = nil
      for i = xs.length() - 1; i >= 0; i = i - 1 {
        out = norm(apply_many(cons, [xs[i], out]))
      }
      Some(out)
    }
    ("List/build", [t, builder]) =>
      Some(
        norm(
          apply_many(builder, [
            Apply(Builtin("List"), t),
            Lambda(
              "_",
              t,
              Lambda(
                "_",
                Apply(Builtin("List"), shift(t, 1, 0)),
                Binary("#", List([Variable("_", 1)]), Variable("_", 0)),
              ),
            ),
            Annotate(List([]), Apply(Builtin("List"), t)),
          ]),
        ),
      )
    _ => None
  }
}

///|
fn normal(e : Expr, budget : Budget, depth : Int32) -> Expr raise DhallError {
  budget.step(depth)
  let norm = x => normal(x, budget, depth + 1)
  match e {
    At(_, _, x) => norm(x)
    Let(_, _, v, b) => norm(substitute(b, norm(v), 0))
    Annotate(x, t) => {
      let v = norm(x)
      if v is List(xs) && xs.is_empty() {
        Annotate(v, norm(t))
      } else {
        v
      }
    }
    Apply(f, x) => {
      let function = norm(f)
      let arg = norm(x)
      if function is Lambda(_, _, body) {
        return norm(substitute(body, arg, 0))
      }
      let e = Apply(function, arg)
      let (head, args) = applications(e)
      if head is Builtin(name) &&
        reduce_builtin(name, args, budget, depth + 1) is Some(result) {
        return result
      }
      e
    }
    Lambda(n, t, b) => Lambda(n, norm(t), norm(b))
    Pi(n, t, b) => Pi(n, norm(t), norm(b))
    Integer(s) => Integer(@bigint.BigInt::from_string(s).to_string())
    Record(fs) => Record(sorted_expr(fs.map(p => (p.0, norm(p.1)))))
    RecordType(fs) => RecordType(sorted_expr(fs.map(p => (p.0, norm(p.1)))))
    UnionType(fs) => {
      let fs = fs.map(p => (p.0, p.1.map(norm)))
      fs.sort_by((a, b) => lexical(a.0, b.0))
      UnionType(fs)
    }
    Field(x, k) => {
      let x = norm(x)
      if x is Record(fs) && get_field(fs, k) is Some(v) {
        v
      } else {
        Field(x, k)
      }
    }
    Project(x, ks) => {
      let x = norm(x)
      if x is Record(fs) {
        Record(fs.filter(p => ks.contains(p.0)))
      } else {
        let ks = ks.copy()
        ks.sort_by(lexical)
        Project(x, ks)
      }
    }
    List(xs) => List(xs.map(norm))
    If(c, a, b) => {
      let c = norm(c)
      match c {
        Boolean(true) => norm(a)
        Boolean(false) => norm(b)
        _ => {
          let a = norm(a)
          let b = norm(b)
          if a == b {
            a
          } else if a == Boolean(true) && b == Boolean(false) {
            c
          } else {
            If(c, a, b)
          }
        }
      }
    }
    Interpolate(ps, tail) => {
      let mut text = ""
      let out : Array[(String, Expr)] = []
      for (prefix, x) in ps {
        text += prefix
        match norm(x) {
          Text(s) => text += s
          Interpolate(inner, last) => {
            for (p, v) in inner {
              out.push((text + p, v))
              text = ""
            }
            text += last
          }
          v => {
            out.push((text, v))
            text = ""
          }
        }
      }
      text += tail
      if out.is_empty() {
        Text(text)
      } else {
        Interpolate(out, text)
      }
    }
    Binary(op, a, b) => {
      let a = norm(a)
      let b = norm(b)
      match (op, a, b) {
        ("+", x, y) if number(x) is Some(n) && number(y) is Some(m) =>
          nat(n + m)
        ("*", x, y) if number(x) is Some(n) && number(y) is Some(m) =>
          nat(n * m)
        ("+", Natural(0L), x) | ("+", x, Natural(0L)) => x
        ("*", Natural(0L), _) | ("*", _, Natural(0L)) => Natural(0L)
        ("*", Natural(1L), x) | ("*", x, Natural(1L)) => x
        ("++", Text(x), Text(y)) => Text(x + y)
        ("++", Text(""), x) | ("++", x, Text("")) => x
        ("++", x, y) => norm(Interpolate([("", x), ("", y)], ""))
        ("#", List(x), List(y)) => {
          let out = x.copy()
          out.append(y)
          List(out)
        }
        ("#", Annotate(List(x), _), y) if x.is_empty() => y
        ("#", x, Annotate(List(y), _)) if y.is_empty() => x
        ("&&", Boolean(false), _) | ("&&", _, Boolean(false)) => Boolean(false)
        ("&&", Boolean(true), x) | ("&&", x, Boolean(true)) => x
        ("||", Boolean(true), _) | ("||", _, Boolean(true)) => Boolean(true)
        ("||", Boolean(false), x) | ("||", x, Boolean(false)) => x
        ("==", Boolean(x), Boolean(y)) => Boolean(x == y)
        ("!=", Boolean(x), Boolean(y)) => Boolean(x != y)
        ("==", Boolean(true), x) | ("==", x, Boolean(true)) => x
        ("!=", Boolean(false), x) | ("!=", x, Boolean(false)) => x
        ("==", x, y) if x == y => Boolean(true)
        ("!=", x, y) if x == y => Boolean(false)
        ("//", Record(x), Record(y)) =>
          Record(combine_records(x, y, false, false, budget, depth + 1))
        ("/\\", Record(x), Record(y)) =>
          Record(combine_records(x, y, true, false, budget, depth + 1))
        ("/\\", RecordType(x), RecordType(y)) =>
          RecordType(combine_records(x, y, true, true, budget, depth + 1))
        _ => Binary(op, a, b)
      }
    }
    Merge(h, u, t) => {
      let h = norm(h)
      let u = norm(u)
      match (h, u) {
        (Record(fs), Field(UnionType(_), k)) if get_field(fs, k)
          is Some(handler) => norm(handler)
        (Record(fs), Apply(Field(UnionType(_), k), v)) if get_field(fs, k)
          is Some(handler) => norm(Apply(handler, v))
        (Record(fs), Apply(Builtin("Some"), v)) if get_field(fs, "Some")
          is Some(handler) => norm(Apply(handler, v))
        (Record(fs), Apply(Builtin("None"), _)) if get_field(fs, "None")
          is Some(handler) => norm(handler)
        _ => Merge(h, u, t.map(norm))
      }
    }
    Assert(x) => Assert(norm(x))
    Import(spec) => raise MissingImport(spec.path)
    _ => e
  }
}

///|
/// Alpha- and beta-normalize a well-typed, closed expression.
pub fn normalize(source : String) -> Expr raise DhallError {
  let e = canonical(parse(source), [], 0)
  let _ = infer(e, [], 0)
  normal(e, { fuel: 200000, }, 0)
}

///|
/// Compare closed expressions by inferred type and normalized form.
pub fn equivalent(left : String, right : String) -> Bool raise DhallError {
  let a = canonical(parse(left), [], 0)
  let b = canonical(parse(right), [], 0)
  let ta = infer(a, [], 0)
  let tb = infer(b, [], 0)
  same(ta, tb) && same(a, b)
}

///|
fn same(a : Expr, b : Expr) -> Bool raise DhallError {
  normal(a, { fuel: 200000, }, 0) == normal(b, { fuel: 200000, }, 0)
}

///|
fn quote_json(s : String) -> String {
  Json::string(s).stringify()
}

///|
fn double_text(d : Double) -> String {
  if d.is_nan() {
    "NaN"
  } else if d.is_inf() {
    if d < 0.0 {
      "-Infinity"
    } else {
      "Infinity"
    }
  } else {
    let s = d.to_string()
    if s.contains(".") || s.contains("e") || s.contains("E") {
      s
    } else {
      s + ".0"
    }
  }
}

///|
fn render_json(e : Expr, depth : Int32) -> String raise DhallError {
  if depth > 256 {
    raise Evaluation("JSON depth limit exceeded")
  }
  let render = x => render_json(x, depth + 1)
  let output = match e {
    Boolean(b) => if b { "true" } else { "false" }
    Natural(n) => n.to_string()
    BigNatural(s) | Integer(s) => s
    Real(d) =>
      if d.is_nan() || d.is_inf() {
        raise JsonError("Non-finite Double cannot be JSON")
      } else {
        double_text(d)
      }
    Text(s) => quote_json(s)
    List(xs) | Annotate(List(xs), _) => "[" + xs.map(render).join(",") + "]"
    Record(fs) =>
      "{" + fs.map(p => quote_json(p.0) + ":" + render(p.1)).join(",") + "}"
    Apply(Builtin("Some"), x) => render(x)
    Annotate(Apply(Builtin("Some"), x), _) => render(x)
    Apply(Builtin("None"), _) => "null"
    Field(UnionType(_), k) => quote_json(k)
    Apply(Field(UnionType(_), _), x) => render(x)
    _ =>
      raise JsonError(
        "This value cannot be represented as JSON; apply functions first",
      )
  }
  if output.length() > 1048576 {
    raise Evaluation("JSON output size limit exceeded")
  }
  output
}

///|
/// Exact decimal serialization for arbitrary-precision integers.
pub fn to_json(source : String) -> String raise DhallError {
  render_json(normalize(source), 0)
}
