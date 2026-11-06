///|
test "configuration functions produce deterministic JSON" {
  let source =
    #|let service = \(port : Natural) ->
    #|  { host = "127.0.0.1", port = port }
    #|in { api = service 8080, admin = service 9090 }
  assert_eq(
    @MoonDhall.to_json(source),
    "{\"admin\":{\"host\":\"127.0.0.1\",\"port\":9090},\"api\":{\"host\":\"127.0.0.1\",\"port\":8080}}",
  )
}

///|
test "closures capture the definition environment" {
  assert_eq(
    @MoonDhall.to_json(
      "let x = 1 let f = \\(y : Natural) -> x + y let x = 100 in f 2",
    ),
    "3",
  )
}

///|
test "shadowed variables can be referenced by name index" {
  assert_eq(@MoonDhall.to_json("let x = 7 in let x = 9 in x@1"), "7")
  assert_eq(
    @MoonDhall.to_json("(\\(x : Natural) -> \\(x : Natural) -> x@1) 7 9"),
    "7",
  )
}

///|
test "higher order functions preserve lexical binding" {
  assert_eq(
    @MoonDhall.to_json(
      "let apply = \\(f : Natural -> Natural) -> f 4 in apply (\\(x : Natural) -> x * 3)",
    ),
    "12",
  )
}

///|
test "record selection and right biased record preference" {
  assert_eq(
    @MoonDhall.to_json("({ a = 1, b = True } // { a = \"override\" }).a"),
    "\"override\"",
  )
  assert_eq(
    @MoonDhall.check("{ b = True, a = 1 }").display(),
    "{ a : Natural, b : Bool }",
  )
  assert_eq(@MoonDhall.to_json("{=}"), "{}")
}

///|
test "type equality ignores record field order" {
  assert_eq(
    @MoonDhall.to_json(
      "(\\(r : { a : Natural, b : Bool }) -> r.a) { b = True, a = 8 }",
    ),
    "8",
  )
}

///|
test "lists can contain records and typed empty lists" {
  assert_eq(
    @MoonDhall.to_json("[{ x = 1 }, { x = 2 }]"),
    "[{\"x\":1},{\"x\":2}]",
  )
  assert_eq(@MoonDhall.to_json("[] : List Natural"), "[]")
  assert_eq(
    @MoonDhall.check("[] : List (Natural -> Natural)").display(),
    "List ((Natural -> Natural))",
  )
}

///|
test "Natural values serialize exactly and arithmetic respects precedence" {
  assert_eq(@MoonDhall.to_json("9007199254740993"), "9007199254740993")
  assert_eq(@MoonDhall.to_json("9223372036854775807"), "9223372036854775807")
  assert_eq(@MoonDhall.to_json("2 + 3 * 4"), "14")
  assert_eq(@MoonDhall.to_json("(2 + 3) * 4"), "20")
}

///|
test "Boolean operators and conditional evaluation" {
  assert_eq(@MoonDhall.to_json("True && False || True"), "true")
  assert_eq(@MoonDhall.to_json("True == False"), "false")
  assert_eq(@MoonDhall.to_json("True != False"), "true")
  assert_eq(
    @MoonDhall.to_json("if True then 1 else 9223372036854775807 + 1"),
    "1",
  )
}

///|
test "Natural builtins" {
  assert_eq(
    @MoonDhall.to_json("[Natural/isZero 0, Natural/even 6, Natural/odd 3]"),
    "[true,true,true]",
  )
  assert_eq(@MoonDhall.to_json("Natural/show 123"), "\"123\"")
}

///|
test "text escaping Unicode and concatenation" {
  assert_eq(@MoonDhall.to_json("\"hello\" ++ \" world\""), "\"hello world\"")
  assert_eq(@MoonDhall.to_json("\"你好😀\""), "\"你好😀\"")
  assert_eq(@MoonDhall.to_json("\"a\\nb\\t\\\"c\""), "\"a\\nb\\t\\\"c\"")
}

///|
test "nested block and end of line comments" {
  assert_eq(
    @MoonDhall.to_json("{- outer {- inner -} -} 1 -- trailing\n + 2"),
    "3",
  )
}

///|
test "Unicode lambda and arrow" {
  assert_eq(@MoonDhall.to_json("(λ(x : Natural) → x + 1) 9"), "10")
}

///|
test "check exposes function types without JSON conversion" {
  assert_eq(
    @MoonDhall.check("\\(x : Natural) -> x").display(),
    "(Natural -> Natural)",
  )
  assert_eq(@MoonDhall.check("let x : Natural = 2 in x").display(), "Natural")
}

///|
test "ill typed programs fail before evaluation" {
  for
    source in [
      "1 + True", "if True then 1 else False", "if True then 1 else unknown", "(\\(x : Natural) -> x) \"wrong\"",
      "[1, True]", "let x : Bool = 1 in x", "{ a = 1 }.missing", "1.a", "1 2", "[]",
      "[] : Natural", "1 == 1", "let x = 1 in x@1",
    ] {
    let rejected = try {
      let _ = @MoonDhall.to_json(source)
      false
    } catch {
      @MoonDhall.TypeError(_) => true
      _ => false
    }
    assert_true(rejected, msg=source)
  }
}

///|
test "invalid syntax and unsupported features are rejected" {
  for
    source in [
      "", "1 )", "\"unterminated", "{- unterminated", "{ a = 1, a = 2 }", "let x = 1",
      "[1,]", "{ }", "9223372036854775808", "./other.dhall", "https://example.invalid/config",
      "\"bad\\q\"",
    ] {
    let rejected = try {
      let _ = @MoonDhall.to_json(source)
      false
    } catch {
      @MoonDhall.Syntax(_, _) => true
      _ => false
    }
    assert_true(rejected, msg=source)
  }
}

///|
test "overflow is explicit rather than wrapped" {
  for source in ["9223372036854775807 + 1", "4611686018427387904 * 2"] {
    let rejected = try {
      let _ = @MoonDhall.to_json(source)
      false
    } catch {
      @MoonDhall.Evaluation(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "functions cannot silently become JSON strings" {
  let rejected = try {
    let _ = @MoonDhall.to_json("\\(x : Natural) -> x")
    false
  } catch {
    @MoonDhall.JsonError(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "public AST rejects negative Naturals" {
  let rejected = try {
    let _ = @MoonDhall.type_of(@MoonDhall.Natural(-1L))
    false
  } catch {
    @MoonDhall.TypeError(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "nested inputs fail with a resource diagnostic" {
  let mut source = "1"
  for _ in 0..<150 {
    source = "(" + source + ")"
  }
  let rejected = try {
    let _ = @MoonDhall.to_json(source)
    false
  } catch {
    @MoonDhall.Syntax(_, _) => true
    _ => false
  }
  assert_true(rejected)
}
