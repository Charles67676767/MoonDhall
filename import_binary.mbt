///|
fn split_first(s : String, separator : Char) -> (String, String?) {
  let chars = s.to_array()
  for i in 0..<chars.length() {
    if chars[i] == separator {
      return (
        chars_text(chars, 0, i),
        Some(chars_text(chars, i + 1, chars.length())),
      )
    }
  }
  (s, None)
}

///|
fn import_cbor(
  spec : ImportSpec,
  enc : (Expr) -> Cbor raise DhallError,
) -> Array[Cbor] raise DhallError {
  let digest = match spec.hash {
    None => CNull
    Some(hash) => {
      if hash.length() != 64 {
        raise BinaryError("Invalid SHA-256 digest length")
      }
      CBytes(hex_to_bytes("1220" + hash))
    }
  }
  let mode = match spec.mode {
    "Code" => 0
    "Text" => 1
    "Location" => 2
    "Bytes" => 3
    _ => raise BinaryError("Unknown import mode")
  }
  let out = [ci(24), digest, ci(mode)]
  let path = spec.path
  if path == "missing" {
    out.push(ci(7))
  } else if path.has_prefix("env:") {
    out.push(ci(6))
    out.push(CText(unquote_import_component(path[4:].to_owned())))
  } else if path.has_prefix("http://") || path.has_prefix("https://") {
    let https = path.has_prefix("https://")
    let start = if https { 8 } else { 7 }
    let (url, query) = split_first(path[start:].to_owned(), '?')
    let (authority, tail) = split_first(url, '/')
    if authority == "" {
      raise BinaryError("Missing URL authority")
    }
    out.push(ci(if https { 1 } else { 0 }))
    out.push(spec.headers.map(enc).unwrap_or(CNull))
    out.push(CText(authority))
    for component in tail.unwrap_or("").split("/") {
      out.push(CText(component.to_owned()))
    }
    out.push(query.map(q => CText(q)).unwrap_or(CNull))
  } else {
    let (prefix, start) = if path.has_prefix("../") {
      (4, 3)
    } else if path.has_prefix("./") {
      (3, 2)
    } else if path.has_prefix("~/") {
      (5, 2)
    } else if path.has_prefix("/") {
      (2, 1)
    } else {
      raise BinaryError("Unknown import path prefix")
    }
    out.push(ci(prefix))
    for component in path[start:].to_owned().split("/") {
      out.push(CText(unquote_import_component(component.to_owned())))
    }
  }
  out
}

///|
fn unquote_import_component(s : String) -> String {
  if s.length() >= 2 && s.has_prefix("\"") && s.has_suffix("\"") {
    s[1:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
fn render_path_component(s : String) -> String {
  if s == "" ||
    s
    .to_array()
    .any(c => {
      [' ', '\t', '\r', '\n', '(', ')', '[', ']', '{', '}', '<', '>', ',', '"'].contains(
        c,
      )
    }) {
    "\"" + s + "\""
  } else {
    s
  }
}

///|
fn cbor_path_component(value : Cbor) -> String raise DhallError {
  guard value is CText(s) else {
    raise BinaryError("Import path component must be text")
  }
  s
}

///|
fn decode_import_cbor(
  parts : Array[Cbor],
  dec : (Cbor) -> Expr raise DhallError,
) -> Expr raise DhallError {
  guard parts is [hash, CInt(mode), CInt(scheme), .. payload] &&
    mode >= 0 &&
    mode <= 3 &&
    scheme >= 0 &&
    scheme <= 7 else {
    raise BinaryError("Invalid binary import")
  }
  let hash = match hash {
    CNull => None
    CBytes(bytes) if bytes.length() == 34 &&
      bytes[0] == 0x12 &&
      bytes[1] == 0x20 => Some(bytes_to_hex(bytes[2:].to_owned()))
    _ => raise BinaryError("Invalid import multihash")
  }
  let mode = ["Code", "Text", "Location", "Bytes"][mode.to_int()]
  let (path, headers) = match scheme.to_int() {
    0 | 1 => {
      guard payload.length() >= 4 else {
        raise BinaryError("Invalid remote import")
      }
      let headers = match payload[0] {
        CNull => None
        x => Some(dec(x))
      }
      let authority = cbor_path_component(payload[1])
      let query = match payload[payload.length() - 1] {
        CNull => ""
        CText(query) => "?" + query
        _ => raise BinaryError("Invalid import query")
      }
      let components = payload[2:payload.length() - 1].map(cbor_path_component)
      let prefix = if scheme == 0 { "http://" } else { "https://" }
      (prefix + authority + "/" + components.join("/") + query, headers)
    }
    2 | 3 | 4 | 5 => {
      if payload.is_empty() {
        raise BinaryError("Missing file path")
      }
      let prefix = ["/", "./", "../", "~/"][scheme.to_int() - 2]
      let components = payload.map(x => {
        render_path_component(cbor_path_component(x))
      })
      (prefix + components.join("/"), None)
    }
    6 => {
      guard payload is [CText(name)] else {
        raise BinaryError("Invalid environment import")
      }
      let rendered = if name != "" &&
        identifier_start(name.to_array()[0]) &&
        name.to_array().all(c => identifier_start(c) || digit(c)) {
        name
      } else {
        quote_json(name)
      }
      ("env:" + rendered, None)
    }
    _ => {
      if !payload.is_empty() {
        raise BinaryError("Invalid missing import")
      }
      ("missing", None)
    }
  }
  Import({ path, mode, hash, headers, })
}
