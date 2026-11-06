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
/// Resolve dependencies using supplied sources, without performing I/O.
/// MissingImport contains the exact key the host must load before retrying.
pub fn resolve(
  source : String,
  origin : String,
  sources : Array[ImportSource],
) -> Expr raise DhallError {
  let cache : Map[String, Expr] = Map([])
  resolve_tree(parse(source), origin, sources, [origin], cache, 0)
}

///|
fn resolve_tree(
  e : Expr,
  origin : String,
  sources : Array[ImportSource],
  stack : Array[String],
  cache : Map[String, Expr],
  depth : Int32,
) -> Expr raise DhallError {
  if depth > 128 || stack.length() > 64 {
    raise ImportError("Import nesting limit exceeded")
  }
  match e {
    Import(spec) => {
      if spec.path == "missing" {
        raise UnavailableImport("missing")
      }
      if spec.mode == "Location" {
        raise ImportError("Location imports are not supported")
      }
      let key = import_key(origin, spec.path)
      let mut entry : ImportSource? = None
      for s in sources {
        if s.key == key {
          entry = Some(s)
          break
        }
      }
      guard entry is Some(entry) else { raise MissingImport(key) }
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
      let cache_key = entry.location + "\n" + spec.mode
      let value = match cache.get(cache_key) {
        Some(value) => value
        None => {
          let value = if spec.mode == "Text" {
            Text(text)
          } else {
            let scope = stack.copy()
            scope.push(entry.location)
            try {
              let resolved = resolve_tree(
                parse(text),
                entry.location,
                sources,
                scope,
                cache,
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
          cache[cache_key] = value
          value
        }
      }
      if spec.hash is Some(expected) {
        let actual = sha256(encode_expr(value))
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
      }
      value
    }
    Binary("?", a, b) =>
      resolve_tree(a, origin, sources, stack, cache, depth + 1) catch {
        UnavailableImport(_) =>
          resolve_tree(b, origin, sources, stack, cache, depth + 1)
        error => raise error
      }
    _ =>
      children(e, (child, _) => {
        resolve_tree(child, origin, sources, stack, cache, depth + 1)
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
