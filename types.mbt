///|
pub suberror DhallError {
  Syntax(String, Int32)
  TypeError(String)
  Evaluation(String)
  JsonError(String)
} derive(Debug)

///|
/// Types supported by the initial self-contained configuration core.
pub(all) enum Type {
  BoolType
  NaturalType
  TextType
  ListType(Type)
  RecordType(Array[(String, Type)])
  FunctionType(Type, Type)
} derive(Debug, Eq)

///|
pub(all) enum Expr {
  Boolean(Bool)
  Natural(Int64)
  Text(String)
  Variable(String, Int32)
  Let(String, Type?, Expr, Expr)
  Lambda(String, Type, Expr)
  Apply(Expr, Expr)
  Record(Array[(String, Expr)])
  Field(Expr, String)
  List(Array[Expr])
  Annotate(Expr, Type)
  If(Expr, Expr, Expr)
  Binary(String, Expr, Expr)
} derive(Debug)

///|
pub fn Type::display(self : Type) -> String {
  match self {
    BoolType => "Bool"
    NaturalType => "Natural"
    TextType => "Text"
    ListType(t) => "List (\{t.display()})"
    RecordType(fields) => {
      let items = fields.map(fn(f) { "\{f.0} : \{f.1.display()}" })
      "{ " + items.join(", ") + " }"
    }
    FunctionType(a, b) => "(\{a.display()} -> \{b.display()})"
  }
}

///|
fn sorted_types(fields : Array[(String, Type)]) -> Array[(String, Type)] {
  let result = fields.copy()
  result.sort_by(fn(a, b) { a.0[:].lexical_compare(b.0[:]) })
  result
}

///|
pub extend Type with Eq::{equal, not_equal}

///|
pub extend Type with @debug.Debug::{to_repr}

///|
pub extend Expr with @debug.Debug::{to_repr}

///|
pub extend DhallError with @debug.Debug::{to_repr}
