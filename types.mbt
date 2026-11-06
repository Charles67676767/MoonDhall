///|
pub suberror DhallError {
  Syntax(String, Int32)
  TypeError(String)
  TypeAt(String, Int32)
  Evaluation(String)
  JsonError(String)
  ImportError(String)
  MissingImport(String)
  BinaryError(String)
} derive(Debug)

///|
/// One syntax tree represents terms and types.
pub(all) enum Expr {
  At(Int32, Int32, Expr)
  Boolean(Bool)
  Natural(Int64)
  BigNatural(String)
  Integer(String)
  Real(Double)
  Text(String)
  Interpolate(Array[(String, Expr)], String)
  Variable(String, Int32)
  Builtin(String)
  Universe(Int32)
  Let(String, Expr?, Expr, Expr)
  Lambda(String, Expr, Expr)
  Pi(String, Expr, Expr)
  Apply(Expr, Expr)
  Record(Array[(String, Expr)])
  RecordType(Array[(String, Expr)])
  UnionType(Array[(String, Expr?)])
  Field(Expr, String)
  Project(Expr, Array[String])
  List(Array[Expr])
  Annotate(Expr, Expr)
  If(Expr, Expr, Expr)
  Binary(String, Expr, Expr)
  Merge(Expr, Expr, Expr?)
  Assert(Expr)
  Import(ImportSpec)
} derive(Debug, Eq)

///|
pub(all) struct ImportSpec {
  path : String
  mode : String
  hash : String?
} derive(Debug, Eq)

///|
/// A normalized inferred type.
pub(all) struct Type {
  expression : Expr
} derive(Debug, Eq)

///|
pub fn Type::display(self : Type) -> String {
  pretty_type(self.expression)
}

///|
fn bare(expr : Expr) -> Expr {
  match expr {
    At(_, _, child) => bare(child)
    _ => expr
  }
}

///|
fn lexical(a : String, b : String) -> Int32 {
  a.lexical_compare(b)
}

///|
pub extend Type with Eq::{equal, not_equal}

///|
pub extend Type with @debug.Debug::{to_repr}

///|
pub extend Expr with Eq::{equal, not_equal}

///|
pub extend Expr with @debug.Debug::{to_repr}

///|
pub extend ImportSpec with Eq::{equal, not_equal}

///|
pub extend ImportSpec with @debug.Debug::{to_repr}

///|
pub extend DhallError with @debug.Debug::{to_repr}

///|
fn min_int(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}
