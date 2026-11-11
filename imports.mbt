///|
/// Host-provided import data. Keys are origin + newline + written import path.
/// A missing source records an unavailable resource, enabling import alternatives.
pub(all) struct ImportSource {
  key : String
  location : String
  source : String?
} derive(Debug)

///|
pub extend ImportSource with @debug.Debug::{to_repr}

///|
fn import_key(origin : String, path : String) -> String {
  origin + "\n" + path
}

///|
priv struct ImportContext {
  sources : Array[ImportSource]
  cache : Map[String, Expr]
  semantic_cache : Map[String, Bytes]
  origin_headers : Map[String, Array[(String, String)]]
  legacy_keys : Bool
  mut loading_headers : Bool
}

///|
/// Resolve dependencies using supplied sources, without performing I/O.
/// MissingImport contains the exact key the host must load before retrying.
pub fn resolve(
  source : String,
  origin : String,
  sources : Array[ImportSource],
  legacy_keys~ : Bool = true,
  header_source~ : String = "",
  header_origin~ : String = "",
  semantic_cache~ : Map[String, Bytes] = Map([]),
) -> Expr raise DhallError {
  let context = ImportContext::{
    sources,
    cache: Map([]),
    semantic_cache,
    origin_headers: Map([]),
    legacy_keys,
    loading_headers: header_source != "",
  }
  if context.loading_headers {
    let headers = resolve_tree(
      parse(header_source),
      header_origin,
      [header_origin],
      context,
      [],
      0,
    )
    let expected = parse(
      "List { mapKey : Text, mapValue : List { mapKey : Text, mapValue : Text } }",
    )
    require_same(
      type_of(headers).expression,
      expected,
      "Origin header configuration",
    )
    match normalize_expr(headers) {
      List(items) =>
        for item in items {
          guard item is Record(fields) &&
            get_field(fields, "mapKey") is Some(Text(key)) &&
            get_field(fields, "mapValue") is Some(value) else {
            raise ImportError("Invalid origin header entry")
          }
          if context.origin_headers.get(key) is None {
            context.origin_headers[key] = request_headers(value)
          }
        }
      Annotate(List(items), _) if items.is_empty() => ()
      _ => raise ImportError("Origin headers must normalize to a list")
    }
    context.loading_headers = false
  }
  resolve_tree(parse(source), origin, [origin], context, [], 0)
}

///|
fn resolve_tree(
  e : Expr,
  origin : String,
  stack : Array[String],
  context : ImportContext,
  inherited_headers : Array[(String, String)],
  depth : Int32,
) -> Expr raise DhallError {
  if depth > 128 || stack.length() > 64 {
    raise ImportError("Import nesting limit exceeded")
  }
  match e {
    Import(spec) => {
      if spec.mode != "Location" &&
        spec.hash is Some(digest) &&
        context.cache.get("sha256:" + digest) is Some(value) {
        return value
      }
      if spec.path == "missing" {
        if spec.mode == "Location" {
          return location_value("Missing", "")
        }
        if spec.hash is None {
          raise UnavailableImport("missing")
        }
      }
      let explicit = if spec.mode == "Location" {
        []
      } else if spec.headers is Some(headers) {
        let resolved = resolve_tree(
          headers,
          origin,
          stack,
          context,
          inherited_headers,
          depth + 1,
        )
        request_headers(resolved)
      } else if spec.path.has_prefix("./") || spec.path.has_prefix("../") {
        inherited_headers
      } else {
        []
      }
      let remote_authority = import_authority(spec.path, origin)
      if context.loading_headers &&
        remote_authority is Some(_) &&
        spec.mode != "Location" {
        raise ImportError(
          "Origin header configuration cannot import remote resources",
        )
      }
      let headers = match remote_authority {
        Some(authority) if spec.mode != "Location" => {
          let configured = context.origin_headers.get(authority).unwrap_or([])
          explicit.filter(p => {
            !configured.any(q => p.0.to_lower() == q.0.to_lower())
          }) +
          configured
        }
        _ => explicit
      }
      let key = import_key(origin, spec.path) +
        (if spec.mode != "Bytes" &&
          spec.mode != "Location" &&
          headers.is_empty() &&
          spec.hash is None {
          ""
        } else {
          "\n[" +
          quote_json(spec.mode) +
          ",[" +
          headers
          .map(p => "[" + quote_json(p.0) + "," + quote_json(p.1) + "]")
          .join(",") +
          "]," +
          spec.hash.map(quote_json).unwrap_or("null") +
          "]"
        })
      let mut entry : ImportSource? = None
      for s in context.sources {
        if s.key == key ||
          (
            context.legacy_keys &&
            spec.mode == "Code" &&
            headers.is_empty() &&
            s.key == import_key(origin, spec.path)
          ) {
          entry = Some(s)
          break
        }
      }
      guard entry is Some(entry) else { raise MissingImport(key) }
      if spec.mode == "Location" {
        if spec.path.has_prefix("env:") {
          return location_value("Environment", entry.location)
        }
        if entry.location.has_prefix("http://") ||
          entry.location.has_prefix("https://") {
          return location_value("Remote", entry.location)
        }
        return location_value("Local", entry.location)
      }
      if entry.location == "semantic-cache" &&
        spec.hash is Some(expected) &&
        entry.source is Some(hex) {
        let bytes = hex_to_bytes(hex)
        if sha256(bytes) != expected {
          raise ImportError("Invalid semantic cache entry")
        }
        let value = decode(bytes)
        let _ = type_of(value)
        context.cache["sha256:" + expected] = value
        return value
      }
      if spec.path == "missing" {
        raise UnavailableImport("missing")
      }
      if (origin.has_prefix("http://") || origin.has_prefix("https://")) &&
        !(entry.location.has_prefix("http://") ||
        entry.location.has_prefix("https://")) {
        raise ImportError(
          "Remote imports cannot access local files or environment variables",
        )
      }
      guard entry.source is Some(text) else {
        raise UnavailableImport("Unavailable import: " + entry.location)
      }
      if stack.contains(entry.location) {
        raise ImportError(
          "Import cycle: " + (stack + [entry.location]).join(" -> "),
        )
      }
      let cache_key = entry.location +
        "\n" +
        spec.mode +
        "\n" +
        headers.map(p => quote_json(p.0) + ":" + quote_json(p.1)).join(",")
      let value = match context.cache.get(cache_key) {
        Some(value) => value
        None => {
          let value = if spec.mode == "Text" {
            Text(text)
          } else if spec.mode == "Bytes" {
            ByteLiteral(hex_to_bytes(text))
          } else {
            let scope = stack.copy()
            scope.push(entry.location)
            try {
              let resolved = resolve_tree(
                parse(text),
                entry.location,
                scope,
                context,
                headers,
                depth + 1,
              )
              let _ = type_of(resolved)
              normal(canonical(resolved, [], 0), { fuel: 200000, }, 0)
            } catch {
              MissingImport(k) => raise MissingImport(k)
              UnavailableImport(message) => raise UnavailableImport(message)
              error =>
                raise ImportError(
                  diagnostic(error, text, entry.location) +
                  "\nImported from " +
                  stack.join(" -> "),
                )
            }
          }
          context.cache[cache_key] = value
          value
        }
      }
      if spec.hash is Some(expected) {
        let encoded = encode_expr(value)
        let actual = sha256(encoded)
        if actual != expected {
          raise ImportError(
            "Integrity mismatch for " +
            entry.location +
            "\nExpected sha256:" +
            expected +
            "\nActual   sha256:" +
            actual,
          )
        }
        context.cache["sha256:" + expected] = value
        context.semantic_cache[expected] = encoded
      }
      value
    }
    Binary("?", a, b) =>
      resolve_tree(a, origin, stack, context, inherited_headers, depth + 1) catch {
        UnavailableImport(_) =>
          resolve_tree(b, origin, stack, context, inherited_headers, depth + 1)
        error => raise error
      }
    _ =>
      children(e, (child, _) => {
        resolve_tree(
          child,
          origin,
          stack,
          context,
          inherited_headers,
          depth + 1,
        )
      })
  }
}

///|
/// Check and normalize an already resolved AST.
pub fn normalize_expr(expr : Expr) -> Expr raise DhallError {
  let e = canonical(expr, [], 0)
  let _ = infer(e, [], 0)
  normal(e, { fuel: 200000, }, 0)
}

///|
pub fn json_expr(expr : Expr) -> String raise DhallError {
  render_json(normalize_expr(expr), 0)
}

///|
fn location_value(kind : String, value : String) -> Expr {
  let location = UnionType([
    ("Local", Some(Builtin("Text"))),
    ("Remote", Some(Builtin("Text"))),
    ("Environment", Some(Builtin("Text"))),
    ("Missing", None),
  ])
  let selected = Field(location, kind)
  if kind == "Missing" {
    selected
  } else {
    Apply(selected, Text(value))
  }
}

///|
fn request_headers(expr : Expr) -> Array[(String, String)] raise DhallError {
  let kind = type_of(expr).expression
  let mapping = Apply(
    Builtin("List"),
    RecordType([("mapKey", Builtin("Text")), ("mapValue", Builtin("Text"))]),
  )
  let legacy = Apply(
    Builtin("List"),
    RecordType([("header", Builtin("Text")), ("value", Builtin("Text"))]),
  )
  let (key_name, value_name) = if same(kind, mapping) {
    ("mapKey", "mapValue")
  } else if same(kind, legacy) {
    ("header", "value")
  } else {
    raise ImportError("Invalid HTTP request headers type")
  }
  match normalize_expr(expr) {
    Annotate(List(items), _) if items.is_empty() => []
    List(items) =>
      items.map(item => {
        guard item is Record(fields) &&
          get_field(fields, key_name) is Some(Text(key)) &&
          get_field(fields, value_name) is Some(Text(value)) else {
          raise ImportError("Invalid HTTP header")
        }
        (key, value)
      })
    _ => raise ImportError("HTTP request headers must normalize to a list")
  }
}

///|
fn import_authority(path : String, origin : String) -> String? {
  let url = if path.has_prefix("./") || path.has_prefix("../") {
    origin
  } else {
    path
  }
  let start = if url.has_prefix("https://") {
    8
  } else if url.has_prefix("http://") {
    7
  } else {
    return None
  }
  let (authority, _) = split_first(url[start:].to_owned(), '/')
  let (authority, _) = split_first(authority, '?')
  Some(authority)
}
