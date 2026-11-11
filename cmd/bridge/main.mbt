///|
/// The only host-specific primitive: all language operations remain in MoonBit.
extern "js" fn read_stdin() -> String =
  #|() => require("node:fs").readFileSync(0, "utf8")

///|
fn text_field(j : Json, key : String, default : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => s
        _ => default
      }
    _ => default
  }
}

///|
fn response(j : Json) -> String {
  let source = text_field(j, "source", "")
  let origin = text_field(j, "origin", "<stdin>")
  let op = text_field(j, "op", "json")
  let semantic_cache : Map[String, Bytes] = Map([])
  let result = try {
    if op == "format" {
      @dhall.format(source)
    } else if op == "syntax" {
      @dhall.format_expr(@dhall.parse(source))
    } else if op == "decode" {
      @dhall.format_expr(@dhall.decode(@dhall.hex_to_bytes(source)))
    } else if op == "parse" {
      @dhall.bytes_to_hex(@dhall.encode(source))
    } else if op == "alpha" {
      @dhall.bytes_to_hex(
        @dhall.encode_expr(@dhall.alpha_normalize(@dhall.parse(source))),
      )
    } else if op == "beta" {
      @dhall.bytes_to_hex(
        @dhall.encode_expr(@dhall.beta_normalize(@dhall.parse(source))),
      )
    } else if op == "equivalent" {
      @dhall.equivalent(source, text_field(j, "right", "")).to_string()
    } else {
      let sources : Array[@dhall.ImportSource] = []
      match j {
        Object(m) =>
          match m.get("sources") {
            Some(Array(xs)) =>
              for x in xs {
                let text = match x {
                  Object(m) =>
                    match m.get("source") {
                      Some(String(s)) => Some(s)
                      _ => None
                    }
                  _ => None
                }
                sources.push({
                  key: text_field(x, "key", ""),
                  location: text_field(x, "location", ""),
                  source: text,
                })
              }
            _ => ()
          }
        _ => ()
      }
      let expr = @dhall.resolve(
        source,
        origin,
        sources,
        legacy_keys=false,
        header_source=text_field(j, "headerSource", ""),
        header_origin=text_field(j, "headerOrigin", origin),
        semantic_cache~,
      )
      match op {
        "beta-resolved" =>
          @dhall.bytes_to_hex(@dhall.encode_expr(@dhall.beta_normalize(expr)))
        "json" => @dhall.json_expr(expr)
        "check" => @dhall.type_of(expr).display()
        "type-binary" =>
          @dhall.bytes_to_hex(
            @dhall.encode_expr(@dhall.type_of(expr).expression),
          )
        "normalize" => @dhall.format_expr(@dhall.normalize_expr(expr))
        "hash" => @dhall.sha256(@dhall.encode_expr(@dhall.normalize_expr(expr)))
        "encode" => @dhall.bytes_to_hex(@dhall.encode_expr(expr))
        _ => return "{\"error\":\"Unknown operation\"}"
      }
    }
  } catch {
    @dhall.MissingImport(key) =>
      return "{\"need\":" + Json::string(key).stringify() + "}"
    error =>
      return "{\"error\":" +
        Json::string(@dhall.diagnostic(error, source, origin)).stringify() +
        "}"
  }
  let cache : Array[String] = []
  for key, bytes in semantic_cache {
    cache.push(
      Json::string(key).stringify() +
      ":" +
      Json::string(@dhall.bytes_to_hex(bytes)).stringify(),
    )
  }
  "{\"result\":" +
  Json::string(result).stringify() +
  ",\"cache\":{" +
  cache.join(",") +
  "}}"
}

///|
fn main {
  let input = @json.parse(read_stdin()) catch {
    _ => {
      println("{\"error\":\"Invalid protocol JSON\"}")
      return
    }
  }
  match input {
    Array(xs) => println("[" + xs.map(response).join(",") + "]")
    _ => println(response(input))
  }
}
