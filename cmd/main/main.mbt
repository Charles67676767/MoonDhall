///|
fn main raise {
  let raw = @env.args()
  let start = if raw.length() > 1 &&
    (raw[0].has_suffix("node") || raw[0].has_suffix("node.exe")) {
    2
  } else {
    1
  }
  let args = if raw.length() >= start { raw[start:].to_owned() } else { [] }
  if args.is_empty() || (args.length() == 1 && args[0] == "--help") {
    println("MoonDhall 0.1.0-dev")
    println("Usage: moondhall <json|check> '<Dhall expression>'")
    return
  }
  if args.length() == 1 && args[0] == "--version" {
    println("MoonDhall 0.1.0-dev")
    return
  }
  if args.length() != 2 {
    fail("Expected json or check followed by one source argument")
  }
  match args[0] {
    "json" => println(@dhall.to_json(args[1]))
    "check" => println(@dhall.check(args[1]).display())
    _ => fail("Unknown command: " + args[0])
  }
}
