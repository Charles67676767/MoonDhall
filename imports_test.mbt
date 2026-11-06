///|
test "local import chains text and repeated dependencies" {
  let sources = [
    @MoonDhall.ImportSource::{
      key: "root\n./a",
      location: "a",
      source: Some("{ x = ./b, y = ./b }"),
    },
    @MoonDhall.ImportSource::{
      key: "a\n./b",
      location: "b",
      source: Some("let T = Natural in 7 : T"),
    },
    @MoonDhall.ImportSource::{
      key: "root\n./message",
      location: "message",
      source: Some("raw\ntext"),
    },
  ]
  assert_eq(
    @MoonDhall.json_expr(@MoonDhall.resolve("./a", "root", sources)),
    "{\"x\":7,\"y\":7}",
  )
  assert_eq(
    @MoonDhall.json_expr(
      @MoonDhall.resolve("./message as Text", "root", sources),
    ),
    "\"raw\\ntext\"",
  )
}

///|
test "import fallback only handles unavailable resources" {
  let sources = [
    @MoonDhall.ImportSource::{
      key: "root\n./missing",
      location: "missing",
      source: None,
    },
    @MoonDhall.ImportSource::{
      key: "root\n./bad",
      location: "bad",
      source: Some("1 + True"),
    },
  ]
  assert_eq(
    @MoonDhall.json_expr(@MoonDhall.resolve("./missing ? 42", "root", sources)),
    "42",
  )
  assert_eq(
    @MoonDhall.json_expr(@MoonDhall.resolve("missing ? 1", "root", [])),
    "1",
  )
  let rejected = try {
    let _ = @MoonDhall.resolve("./bad ? 42", "root", sources)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "cycles remote access and semantic integrity" {
  let sources = [
    @MoonDhall.ImportSource::{
      key: "root\n./a",
      location: "a",
      source: Some("./b"),
    },
    @MoonDhall.ImportSource::{
      key: "a\n./b",
      location: "root",
      source: Some("./a"),
    },
  ]
  let cycle = try {
    let _ = @MoonDhall.resolve("./a", "root", sources)
    false
  } catch {
    _ => true
  }
  assert_true(cycle)
  let sources = [
    @MoonDhall.ImportSource::{
      key: "root\n./value",
      location: "value",
      source: Some("1 + 1"),
    },
  ]
  let hash = @MoonDhall.semantic_hash("2")
  assert_eq(
    @MoonDhall.json_expr(
      @MoonDhall.resolve("./value sha256:" + hash, "root", sources),
    ),
    "2",
  )
  let rejected = try {
    let _ = @MoonDhall.resolve(
      "./value sha256:" + @MoonDhall.semantic_hash("3"),
      "root",
      sources,
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let remote = [
    @MoonDhall.ImportSource::{
      key: "https://example.com/a\n./secret",
      location: "file:///secret",
      source: Some("1"),
    },
  ]
  let rejected = try {
    let _ = @MoonDhall.resolve("./secret", "https://example.com/a", remote)
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "diagnostics include file line column and excerpt" {
  let source = "{ port =\n  True + 1 }"
  let message = try {
    let _ = @MoonDhall.check(source)
    ""
  } catch {
    e => @MoonDhall.diagnostic(e, source, "config.dhall")
  }
  assert_true(message.contains("config.dhall:2:3"))
  assert_true(message.contains("True + 1"))
  assert_true(message.contains("^"))
}
