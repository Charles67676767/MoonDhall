///|
fn complete_record(schema : Expr, value : Expr) -> Expr {
  Annotate(Binary("//", Field(schema, "default"), value), Field(schema, "Type"))
}

///|
fn replace_field(
  fields : Array[(String, Expr)],
  key : String,
  value : Expr,
) -> Array[(String, Expr)] {
  let result = fields.filter(p => p.0 != key)
  result.push((key, value))
  sorted_expr(result)
}

///|
fn update_type(
  subject : Expr,
  path : ArrayView[String?],
  value : Expr,
  depth : Int32,
) -> Expr raise DhallError {
  if depth > 128 {
    raise TypeError("with path exceeds the nesting limit")
  }
  if path.is_empty() {
    return value
  }
  match (path[0], subject) {
    (Some(key), RecordType(fields)) => {
      let child = get_field(fields, key).unwrap_or(RecordType([]))
      RecordType(
        replace_field(
          fields,
          key,
          update_type(child, path[1:], value, depth + 1),
        ),
      )
    }
    (None, Apply(Builtin("Optional"), inner)) => {
      require_same(
        update_type(inner, path[1:], value, depth + 1),
        inner,
        "Optional update",
      )
      subject
    }
    _ => raise TypeError("with requires a record field or an Optional path")
  }
}

///|
fn normalize_update(
  subject : Expr,
  path : ArrayView[String?],
  value : Expr,
  budget : Budget,
  depth : Int32,
) -> Expr raise DhallError {
  budget.step(depth)
  if path.is_empty() {
    return value
  }
  match (path[0], subject) {
    (Some(key), Record(fields)) => {
      let child = get_field(fields, key).unwrap_or(Record([]))
      Record(
        replace_field(
          fields,
          key,
          normalize_update(child, path[1:], value, budget, depth + 1),
        ),
      )
    }
    (None, Apply(Builtin("Some"), inner)) =>
      Apply(
        Builtin("Some"),
        normalize_update(inner, path[1:], value, budget, depth + 1),
      )
    (None, Apply(Builtin("None"), _)) => subject
    _ => With(subject, path.to_owned(), value)
  }
}
