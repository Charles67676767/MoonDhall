///|
fn label(s : String) -> String {
  let valid = s
    .to_array()
    .all(c => {
      (
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9')
      ) ||
      c == '_' ||
      c == '-' ||
      c == '/'
    })
  if valid &&
    ![
      "let", "in", "if", "then", "else", "True", "False", "Type", "Kind", "Sort",
    ].contains(s) {
    s
  } else {
    (96).unsafe_to_char().to_string() + s + (96).unsafe_to_char().to_string()
  }
}

///|
fn pretty_type(e : Expr) -> String {
  let p = pretty_type
  match e {
    At(_, _, x) => p(x)
    Boolean(b) => if b { "True" } else { "False" }
    Natural(n) => n.to_string()
    BigNatural(s) => s
    Integer(s) => if s.has_prefix("-") { s } else { "+" + s }
    Real(d) => double_text(d)
    Text(s) =>
      quote_json(s).replace_all(
        old=interpolation_start()[:],
        new=("\\$" + "{")[:],
      )
    Variable(n, k) => label(n) + (if k == 0 { "" } else { "@" + k.to_string() })
    Builtin(n) => n
    Universe(n) =>
      match n {
        0 => "Type"
        1 => "Kind"
        _ => "Sort"
      }
    Let(n, t, v, b) =>
      "let " +
      label(n) +
      t.map(x => " : " + p(x)).unwrap_or("") +
      " = " +
      p(v) +
      " in " +
      p(b)
    Lambda(n, t, b) => "(\\(" + label(n) + " : " + p(t) + ") -> " + p(b) + ")"
    Pi(n, t, b) =>
      if n == "_" && !uses_zero(b, 0) {
        "(" + p(t) + " -> " + p(b) + ")"
      } else {
        "(forall (" + label(n) + " : " + p(t) + ") -> " + p(b) + ")"
      }
    Apply(Builtin("List"), t) => "List (" + p(t) + ")"
    Apply(f, x) => "(" + p(f) + " " + p(x) + ")"
    Record(fs) =>
      if fs.is_empty() {
        "{=}"
      } else {
        "{ " +
        fs.map(p => label(p.0) + " = " + pretty_type(p.1)).join(", ") +
        " }"
      }
    RecordType(fs) =>
      if fs.is_empty() {
        "{}"
      } else {
        "{ " +
        fs.map(p => label(p.0) + " : " + pretty_type(p.1)).join(", ") +
        " }"
      }
    UnionType(fs) =>
      "< " +
      fs
      .map(p => label(p.0) + p.1.map(x => " : " + pretty_type(x)).unwrap_or(""))
      .join(" | ") +
      " >"
    Field(r, k) => "(" + p(r) + ")." + label(k)
    Project(r, ks) => "(" + p(r) + ").{ " + ks.map(label).join(", ") + " }"
    List(xs) => "[" + xs.map(p).join(", ") + "]"
    Annotate(x, t) => "(" + p(x) + " : " + p(t) + ")"
    If(c, a, b) => "(if " + p(c) + " then " + p(a) + " else " + p(b) + ")"
    Binary(op, a, b) => "(" + p(a) + " " + op + " " + p(b) + ")"
    Assert(x) => "assert : " + p(x)
    Merge(h, u, t) =>
      "(merge " +
      p(h) +
      " " +
      p(u) +
      t.map(x => " : " + p(x)).unwrap_or("") +
      ")"
    Interpolate(ps, tail) => {
      let mut s = "\""
      for (prefix, x) in ps {
        let quoted = quote_json(prefix).to_array()
        s += chars_text(quoted, 1, quoted.length() - 1) +
          interpolation_start() +
          p(x) +
          "}"
      }
      let quoted = quote_json(tail).to_array()
      s + chars_text(quoted, 1, quoted.length() - 1) + "\""
    }
    Import(spec) =>
      spec.path +
      spec.hash.map(h => " sha256:" + h).unwrap_or("") +
      (if spec.mode == "Code" { "" } else { " as " + spec.mode })
  }
}

///|
fn uses_zero(e : Expr, depth : Int32) -> Bool {
  match e {
    Variable("_", k) => k == depth
    _ => {
      let mut found = false
      let _ = children(e, (x, b) => {
        if uses_zero(x, depth + b) {
          found = true
        }
        x
      }) catch {
        _ => e
      }
      found
    }
  }
}

///|
/// Render an expression as parseable Dhall.
pub fn format_expr(expr : Expr) -> String {
  pretty_type(expr)
}

///|
pub fn format(source : String) -> String raise DhallError {
  pretty_type(parse(source))
}

///|
fn interpolation_start() -> String {
  let s = StringBuilder()
  s.write_char('$')
  s.write_char('{')
  s.to_string()
}
