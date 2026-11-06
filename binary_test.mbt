///|
test "SHA256 known vectors" {
  assert_eq(
    @MoonDhall.sha256(b""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    @MoonDhall.sha256(b"abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
test "CBOR exact standard representations" {
  for
    (source, hex) in [
      ("True", "f5"),
      ("False", "f4"),
      ("1", "820f01"),
      ("-2", "821021"),
      ("\"abc\"", "821263616263"),
      ("[] : List Natural", "8204674e61747572616c"),
      ("[1,2]", "8404f6820f01820f02"),
      ("Some 1", "8305f6820f01"),
      ("1.5", "f93e00"),
      ("-0.0", "f98000"),
      ("NaN", "f97e00"),
      ("65504.0", "f97bff"),
      ("100000.0", "fa47c35000"),
      ("1.1", "fb3ff199999999999a"),
      ("18446744073709551616", "820fc249010000000000000000"),
    ] {
    assert_eq(
      @MoonDhall.bytes_to_hex(@MoonDhall.encode(source)),
      hex,
      msg=source,
    )
    assert_eq(
      @MoonDhall.bytes_to_hex(
        @MoonDhall.encode_expr(@MoonDhall.decode(@MoonDhall.hex_to_bytes(hex))),
      ),
      hex,
      msg=source,
    )
  }
}

///|
test "CBOR preserves binding and syntax" {
  for
    source in [
      "let x = 1 let y = 2 in x + y", "\\(a : Type) -> \\(x : a) -> x", "{ x = [1], f = \\(y : Natural) -> y }",
      "< A : Natural | B >", "{a=1}.{a}",
    ] {
    let decoded = @MoonDhall.decode(@MoonDhall.encode(source))
    assert_true(
      @MoonDhall.equivalent(source, @MoonDhall.format_expr(decoded)),
      msg=source,
    )
  }
}

///|
test "semantic hashes ignore bound names and reducible syntax" {
  assert_eq(
    @MoonDhall.semantic_hash("\\(x : Natural) -> x + 0"),
    @MoonDhall.semantic_hash("\\(z : Natural) -> z"),
  )
  assert_eq(
    @MoonDhall.semantic_hash("{b=2,a=1}"),
    @MoonDhall.semantic_hash("{a=1,b=2}"),
  )
  assert_false(@MoonDhall.semantic_hash("1") == @MoonDhall.semantic_hash("2"))
}

///|
test "binary decoder rejects malformed or trailing input" {
  for
    hex in [
      "", "ff", "f5f4", "820f20", "820f", "9f", "821800", "8207a26161f56161f4", "8304664e61747572616c00",
    ] {
    let rejected = try {
      let _ = @MoonDhall.decode(@MoonDhall.hex_to_bytes(hex))
      false
    } catch {
      _ => true
    }
    assert_true(rejected, msg=hex)
  }
}
