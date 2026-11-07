///|
test "types are first class and aliases normalize" {
  assert_eq(
    @MoonDhall.to_json(
      "let Port = Natural in (\\(p : Port) -> { port = p }) 8080",
    ),
    "{\"port\":8080}",
  )
  assert_eq(
    @MoonDhall.to_json("(\\(a : Type) -> \\(x : a) -> x) Natural 9"),
    "9",
  )
  assert_true(
    @MoonDhall.equivalent(
      "\\(a : Type) -> \\(x : a) -> x", "\\(b : Type) -> \\(y : b) -> y",
    ),
  )
  assert_eq(@MoonDhall.check("List").display(), "(Type -> Type)")
}

///|
test "capture avoidance through nested polymorphic functions" {
  assert_eq(
    @MoonDhall.to_json(
      "(\\(a : Type) -> \\(x : a) -> (\\(b : Type) -> \\(y : b) -> x) Bool True) Natural 5",
    ),
    "5",
  )
  assert_true(
    @MoonDhall.equivalent(
      "\\(x : Natural) -> (\\(y : Natural) -> x) 2", "\\(z : Natural) -> z",
    ),
  )
}

///|
test "text interpolation multiline dedent and escapes" {
  let source =
    #|let name = "Moon" in "hello ${name}!"
  assert_eq(@MoonDhall.to_json(source), "\"hello Moon!\"")
  let multiline =
    #|''
    #|  first
    #|    second
    #|  ''
  assert_eq(@MoonDhall.to_json(multiline), "\"first\\n  second\\n\"")
  let escaped =
    #|"\${literal}"
  assert_eq(@MoonDhall.to_json(escaped), "\"${literal}\"")
}

///|
test "dotted records projection recursive merge and list concat" {
  assert_eq(
    @MoonDhall.to_json(
      "{ server.port = 80, server.host = \"localhost\", debug = True }.{ server }",
    ),
    "{\"server\":{\"host\":\"localhost\",\"port\":80}}",
  )
  assert_eq(@MoonDhall.to_json("[1,2] # [3] # ([] : List Natural)"), "[1,2,3]")
  assert_eq(
    @MoonDhall.to_json("({ a = { x = 1 } } /\\ { a = { y = 2 } }).a"),
    "{\"x\":1,\"y\":2}",
  )
}

///|
test "numeric conversions preserve exact signed values" {
  assert_eq(
    @MoonDhall.to_json("-999999999999999999999999999999"),
    "-999999999999999999999999999999",
  )
  assert_eq(@MoonDhall.to_json("Integer/abs -99"), "99")
  assert_eq(@MoonDhall.to_json("Integer/negate +12"), "-12")
  assert_eq(@MoonDhall.to_json("Natural/subtract 9 4"), "0")
  assert_eq(@MoonDhall.to_json("Integer/toDouble +4"), "4.0")
  assert_eq(@MoonDhall.to_json("1.25e2"), "125.0")
}

///|
test "list folds builders indexing and optional values" {
  assert_eq(
    @MoonDhall.to_json(
      "List/fold Natural [1,2,3] Natural (\\(x : Natural) -> \\(y : Natural) -> x + y) 0",
    ),
    "6",
  )
  assert_eq(
    @MoonDhall.to_json("Natural/fold 4 Natural (\\(x : Natural) -> x * 2) 1"),
    "16",
  )
  assert_eq(
    @MoonDhall.to_json("List/indexed Text [\"a\",\"b\"]"),
    "[{\"index\":0,\"value\":\"a\"},{\"index\":1,\"value\":\"b\"}]",
  )
  assert_eq(@MoonDhall.to_json("List/head Natural ([] : List Natural)"), "null")
  assert_eq(@MoonDhall.to_json("List/last Natural [1,2]"), "2")
  assert_eq(@MoonDhall.to_json("Some True"), "true")
}

///|
test "union constructors and exhaustive merge" {
  assert_eq(
    @MoonDhall.to_json(
      "merge { Yes = \\(n : Natural) -> n + 1, No = 0 } (< Yes : Natural | No >.Yes 4)",
    ),
    "5",
  )
  assert_eq(
    @MoonDhall.to_json(
      "merge { Yes = \\(n : Natural) -> n, No = 0 } < Yes : Natural | No >.No",
    ),
    "0",
  )
  assert_eq(
    @MoonDhall.to_json(
      "merge { Some = \\(n : Natural) -> n, None = 0 } (None Natural)",
    ),
    "0",
  )
}

///|
test "equivalence assertions and rejected mismatches" {
  let _ = @MoonDhall.check(
    "assert : (\\(x : Natural) -> x + 0) === (\\(y : Natural) -> y)",
  )
  assert_false(@MoonDhall.equivalent("1", "2"))
  for
    source in [
      "assert : 1 === 2", "Some Natural", "[Natural]", "merge { A = 1 } < A | B >.A",
      "{ a = 1, a = 2 }",
    ] {
    let rejected = try {
      let _ = @MoonDhall.check(source)
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=source)
  }
}

///|
test "formatting round trips normalized values" {
  for
    source in [
      "{ x = 1, ys = [True,False] }", "\\(a : Type) -> \\(x : a) -> x", "let X = Natural in \\(x : X) -> x",
    ] {
    assert_true(
      @MoonDhall.equivalent(source, @MoonDhall.format(source)),
      msg=source,
    )
    assert_true(
      @MoonDhall.equivalent(
        source,
        @MoonDhall.format_expr(@MoonDhall.normalize(source)),
      ),
      msg=source,
    )
  }
}

///|
test "Integer to Double uses round to nearest ties to even" {
  assert_eq(
    @MoonDhall.to_json("Integer/toDouble +9007199254740993"),
    "9007199254740992.0",
  )
  assert_eq(
    @MoonDhall.to_json("Integer/toDouble +9007199254740995"),
    "9007199254740996.0",
  )
  assert_true(@MoonDhall.equivalent("NaN", "NaN"))
}

///|
test "builders text replacement and list reversal" {
  assert_eq(
    @MoonDhall.to_json(
      "Natural/build (\\(natural : Type) -> \\(succ : natural -> natural) -> \\(zero : natural) -> succ (succ zero))",
    ),
    "2",
  )
  assert_eq(
    @MoonDhall.to_json(
      "List/build Natural (\\(list : Type) -> \\(cons : Natural -> list -> list) -> \\(nil : list) -> cons 1 (cons 2 nil))",
    ),
    "[1,2]",
  )
  assert_eq(@MoonDhall.to_json("List/reverse Natural [1,2,3]"), "[3,2,1]")
  assert_eq(
    @MoonDhall.to_json("Text/replace \"aa\" \"b\" \"aaaaa\""),
    "\"bba\"",
  )
}
