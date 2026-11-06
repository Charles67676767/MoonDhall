///|
/// Small bounded CBOR model used by the Dhall binary format.
priv enum Cbor {
  CInt(@bigint.BigInt)
  CText(String)
  CBytes(Bytes)
  CArray(Array[Cbor])
  CMap(Array[(String, Cbor)])
  CBool(Bool)
  CNull
  CDouble(Double)
}

///|
fn ci(n : Int32) -> Cbor {
  CInt(@bigint.BigInt::from_int(n))
}

///|
fn cbor_expr(e : Expr, depth : Int32) -> Cbor raise DhallError {
  if depth > 256 {
    raise BinaryError("Binary nesting limit exceeded")
  }
  let enc = x => cbor_expr(bare(x), depth + 1)
  match bare(e) {
    Variable("_", k) => ci(k)
    Variable(n, k) => CArray([CText(n), ci(k)])
    Boolean(b) => CBool(b)
    Natural(n) => CArray([ci(15), CInt(@bigint.BigInt::from_int64(n))])
    BigNatural(s) => CArray([ci(15), CInt(@bigint.BigInt::from_string(s))])
    Integer(s) => CArray([ci(16), CInt(@bigint.BigInt::from_string(s))])
    Real(d) => CDouble(d)
    Text(s) => CArray([ci(18), CText(s)])
    Interpolate(ps, tail) => {
      let a = [ci(18)]
      for (p, x) in ps {
        a.push(CText(p))
        a.push(enc(x))
      }
      a.push(CText(tail))
      CArray(a)
    }
    Builtin(s) => CText(s)
    Universe(n) =>
      CText(
        match n {
          0 => "Type"
          1 => "Kind"
          _ => "Sort"
        },
      )
    Apply(f, x) => {
      if bare(f) == Builtin("Some") {
        return CArray([ci(5), CNull, enc(x)])
      }
      let (f, args) = applications(strip_positions(e))
      let a = [ci(0), enc(f)]
      for x in args {
        a.push(enc(x))
      }
      CArray(a)
    }
    Lambda(n, t, b) | Pi(n, t, b) => {
      let a = [ci(if bare(e) is Lambda(_, _, _) { 1 } else { 2 })]
      if n != "_" {
        a.push(CText(n))
      }
      a.push(enc(t))
      a.push(enc(b))
      CArray(a)
    }
    Record(fs) | RecordType(fs) => {
      let m = sorted_expr(fs).map(p => (p.0, enc(p.1)))
      CArray([ci(if bare(e) is Record(_) { 8 } else { 7 }), CMap(m)])
    }
    UnionType(fs) => {
      let m = fs.map(p => (p.0, p.1.map(enc).unwrap_or(CNull)))
      m.sort_by((a, b) => lexical(a.0, b.0))
      CArray([ci(11), CMap(m)])
    }
    Field(r, k) => CArray([ci(9), enc(r), CText(k)])
    Project(r, ks) => {
      let a = [ci(10), enc(r)]
      let ks = ks.copy()
      ks.sort_by(lexical)
      for k in ks {
        a.push(CText(k))
      }
      CArray(a)
    }
    Annotate(x, t) if bare(x) is List(xs) && xs.is_empty() =>
      match bare(t) {
        Apply(Builtin("List"), a) => CArray([ci(4), enc(a)])
        _ => CArray([ci(28), enc(t)])
      }
    List(xs) => {
      if xs.is_empty() {
        raise BinaryError("Untyped empty list has no binary representation")
      }
      let a = [ci(4), CNull]
      for x in xs {
        a.push(enc(x))
      }
      CArray(a)
    }
    Annotate(x, t) => CArray([ci(26), enc(x), enc(t)])
    If(c, a, b) => CArray([ci(14), enc(c), enc(a), enc(b)])
    Binary(op, a, b) => {
      let ops = [
        "||", "&&", "==", "!=", "+", "*", "++", "#", "/\\", "//", "//\\", "?", "===",
        "::",
      ]
      let mut code = -1
      for i in 0..<ops.length() {
        if ops[i] == op {
          code = i
        }
      }
      if code < 0 {
        raise BinaryError("Unsupported binary operator: " + op)
      }
      CArray([ci(3), ci(code), enc(a), enc(b)])
    }
    Assert(x) => CArray([ci(19), enc(x)])
    Merge(h, u, t) => {
      let a = [ci(6), enc(h), enc(u)]
      if t is Some(t) {
        a.push(enc(t))
      }
      CArray(a)
    }
    Let(_, _, _, _) => {
      let a = [ci(25)]
      let mut tail = bare(e)
      while tail is Let(n, t, v, b) {
        a.push(CText(n))
        a.push(t.map(enc).unwrap_or(CNull))
        a.push(enc(v))
        tail = bare(b)
      }
      a.push(enc(tail))
      CArray(a)
    }
    Import(spec) =>
      raise BinaryError("Encode imports after resolution: " + spec.path)
    At(_, _, _) => abort("unreachable")
  }
}

///|
fn strip_positions(e : Expr) -> Expr raise DhallError {
  match e {
    At(_, _, x) => strip_positions(x)
    _ => children(e, (x, _) => strip_positions(x))
  }
}

///|
fn write_uint(out : Array[Byte], n : UInt64, size : Int32) -> Unit {
  for i = size - 1; i >= 0; i = i - 1 {
    out.push(((n >> (i * 8)) & 255UL).to_byte())
  }
}

///|
fn header(out : Array[Byte], major : Int32, n : UInt64) -> Unit {
  if n < 24UL {
    out.push(((major << 5) | n.to_int()).to_byte())
  } else {
    let (code, size) = if n <= 255UL {
      (24, 1)
    } else if n <= 65535UL {
      (25, 2)
    } else if n <= 4294967295UL {
      (26, 4)
    } else {
      (27, 8)
    }
    out.push(((major << 5) | code).to_byte())
    write_uint(out, n, size)
  }
}

///|
fn half_value(bits : UInt32) -> Double {
  let sign = if (bits & 0x8000U) != 0U { -1.0 } else { 1.0 }
  let exponent = ((bits >> 10) & 31U).reinterpret_as_int()
  let fraction = (bits & 1023U).to_double()
  if exponent == 31 {
    return if fraction == 0.0 { sign * (1.0 / 0.0) } else { 0.0 / 0.0 }
  }
  let mut v = if exponent == 0 { fraction } else { 1024.0 + fraction }
  let power = if exponent == 0 { -24 } else { exponent - 25 }
  if power < 0 {
    for _ in 0..<-power {
      v = v / 2.0
    }
  } else {
    for _ in 0..<power {
      v = v * 2.0
    }
  }
  sign * v
}

///|
fn half_bits(d : Double) -> UInt32? {
  if d.is_nan() {
    return Some(0x7e00U)
  }
  let f = @float.Float::from_double(d)
  if f.to_double() != d {
    return None
  }
  let bits = f.reinterpret_as_uint()
  let sign = (bits >> 16) & 0x8000U
  let exponent = ((bits >> 23) & 255U).reinterpret_as_int() - 127
  let fraction = bits & 0x7fffffU
  if d.is_inf() {
    return Some(sign | 0x7c00U)
  }
  if d == 0.0 {
    return Some(sign)
  }
  if exponent >= -14 && exponent <= 15 && (fraction & 8191U) == 0U {
    return Some(
      sign | ((exponent + 15).reinterpret_as_uint() << 10) | (fraction >> 13),
    )
  }
  if exponent >= -24 && exponent < -14 {
    let significand = fraction | 0x800000U
    let shift = -exponent - 1
    if (significand & ((1U << shift) - 1U)) == 0U {
      return Some(sign | (significand >> shift))
    }
  }
  None
}

///|
fn write_cbor(c : Cbor, out : Array[Byte]) -> Unit {
  match c {
    CInt(n) => {
      let negative = n < 0
      let magnitude = if negative { -n - 1 } else { n }
      if magnitude.bit_length() <= 64 {
        header(out, if negative { 1 } else { 0 }, magnitude.to_uint64())
      } else {
        header(out, 6, if negative { 3UL } else { 2UL })
        let bytes = magnitude.to_octets()
        header(out, 2, bytes.length().to_uint64())
        for b in bytes {
          out.push(b)
        }
      }
    }
    CText(s) => {
      let bytes = @utf8.encode(s[:])
      header(out, 3, bytes.length().to_uint64())
      for b in bytes {
        out.push(b)
      }
    }
    CBytes(bytes) => {
      header(out, 2, bytes.length().to_uint64())
      for b in bytes {
        out.push(b)
      }
    }
    CArray(a) => {
      header(out, 4, a.length().to_uint64())
      for x in a {
        write_cbor(x, out)
      }
    }
    CMap(fs) => {
      header(out, 5, fs.length().to_uint64())
      for (k, v) in fs {
        write_cbor(CText(k), out)
        write_cbor(v, out)
      }
    }
    CBool(b) => out.push(if b { 0xf5 } else { 0xf4 })
    CNull => out.push(0xf6)
    CDouble(d) =>
      match half_bits(d) {
        Some(h) => {
          out.push(0xf9)
          write_uint(out, h.to_uint64(), 2)
        }
        None => {
          let f = @float.Float::from_double(d)
          if f.to_double() == d {
            out.push(0xfa)
            write_uint(out, f.reinterpret_as_uint().to_uint64(), 4)
          } else {
            out.push(0xfb)
            write_uint(out, d.reinterpret_as_uint64(), 8)
          }
        }
      }
  }
}

///|
/// Encode the source syntax, without normalization or alpha-renaming.
pub fn encode(source : String) -> Bytes raise DhallError {
  encode_expr(parse(source))
}

///|
pub fn encode_expr(expr : Expr) -> Bytes raise DhallError {
  let out : Array[Byte] = []
  write_cbor(cbor_expr(strip_positions(expr), 0), out)
  Bytes::from_array(out[:])
}

///|
priv struct BinaryReader {
  bytes : Bytes
  mut index : Int32
  mut fuel : Int32
}

///|
fn BinaryReader::byte(self : BinaryReader) -> Byte raise DhallError {
  if self.index >= self.bytes.length() {
    raise BinaryError("Truncated CBOR")
  }
  let b = self.bytes[self.index]
  self.index += 1
  b
}

///|
fn BinaryReader::uint(
  self : BinaryReader,
  size : Int32,
) -> UInt64 raise DhallError {
  let mut n = 0UL
  for _ in 0..<size {
    n = (n << 8) | self.byte().to_uint64()
  }
  n
}

///|
fn BinaryReader::read(
  self : BinaryReader,
  depth : Int32,
) -> Cbor raise DhallError {
  self.fuel -= 1
  if depth > 256 || self.fuel < 0 {
    raise BinaryError("CBOR resource limit exceeded")
  }
  let first = self.byte().to_int()
  let major = first >> 5
  let info = first & 31
  if major == 7 {
    return match info {
      20 => CBool(false)
      21 => CBool(true)
      22 => CNull
      25 => CDouble(half_value(self.uint(2).to_uint()))
      26 =>
        CDouble(
          @float.Float::reinterpret_from_uint(self.uint(4).to_uint()).to_double(),
        )
      27 => CDouble(self.uint(8).reinterpret_as_double())
      _ => raise BinaryError("Unsupported CBOR simple value")
    }
  }
  let n = if info < 24 {
    info.to_uint64()
  } else {
    self.uint(
      match info {
        24 => 1
        25 => 2
        26 => 4
        27 => 8
        _ => raise BinaryError("Indefinite CBOR is not supported")
      },
    )
  }
  if major == 0 || major == 1 {
    let b = @bigint.BigInt::from_uint64(n)
    return CInt(if major == 0 { b } else { -b - 1 })
  }
  if major == 6 {
    if n != 2UL && n != 3UL {
      raise BinaryError("Unsupported CBOR tag")
    }
    guard self.read(depth + 1) is CBytes(bs) else {
      raise BinaryError("Bignum tag requires bytes")
    }
    let b = @bigint.BigInt::from_octets(bs[:])
    return CInt(if n == 2UL { b } else { -b - 1 })
  }
  if n > 262144UL {
    raise BinaryError("CBOR collection limit exceeded")
  }
  let size = n.to_int()
  match major {
    2 | 3 => {
      if size > self.bytes.length() - self.index {
        raise BinaryError("Truncated CBOR string")
      }
      let bs = self.bytes[self.index:self.index + size].to_owned()
      self.index += size
      if major == 2 {
        CBytes(bs)
      } else {
        CText(
          @utf8.decode(bs[:], ignore_bom=true) catch {
            _ => raise BinaryError("Invalid UTF-8")
          },
        )
      }
    }
    4 => {
      let a = []
      for _ in 0..<size {
        a.push(self.read(depth + 1))
      }
      CArray(a)
    }
    5 => {
      let fs : Array[(String, Cbor)] = []
      for _ in 0..<size {
        guard self.read(depth + 1) is CText(k) else {
          raise BinaryError("Dhall map keys must be text")
        }
        if fs.any(p => p.0 == k) {
          raise BinaryError("Duplicate CBOR map key")
        }
        fs.push((k, self.read(depth + 1)))
      }
      CMap(fs)
    }
    _ => raise BinaryError("Unsupported CBOR major type")
  }
}

///|
fn decode_expr(c : Cbor, depth : Int32) -> Expr raise DhallError {
  if depth > 256 {
    raise BinaryError("Dhall binary nesting limit exceeded")
  }
  let dec = x => decode_expr(x, depth + 1)
  match c {
    CBool(b) => Boolean(b)
    CDouble(d) => Real(d)
    CInt(n) if n >= 0 && n <= 20000 => Variable("_", n.to_int())
    CText("Type") => Universe(0)
    CText("Kind") => Universe(1)
    CText("Sort") => Universe(2)
    CText(s) if builtin_signature(s) is Some(_) => Builtin(s)
    CArray([CText(n), CInt(k)]) if n != "_" && k >= 0 && k <= 20000 =>
      Variable(n, k.to_int())
    CArray([CInt(tag), .. rest]) => {
      if tag < 0 || tag > 28 {
        raise BinaryError("Unknown Dhall binary tag")
      }
      let a = rest.to_owned()
      match (tag.to_int(), a) {
        (0, [f, .. args]) if args.length() > 0 =>
          apply_many(dec(f), args.map(dec))
        (1, [t, b]) => Lambda("_", dec(t), dec(b))
        (1, [CText(n), t, b]) if n != "_" => Lambda(n, dec(t), dec(b))
        (2, [t, b]) => Pi("_", dec(t), dec(b))
        (2, [CText(n), t, b]) if n != "_" => Pi(n, dec(t), dec(b))
        (3, [CInt(op), a, b]) if op >= 0 && op <= 13 => {
          let ops = [
            "||", "&&", "==", "!=", "+", "*", "++", "#", "/\\", "//", "//\\", "?",
            "===", "::",
          ]
          Binary(ops[op.to_int()], dec(a), dec(b))
        }
        (4, [CNull, .. xs]) if xs.length() > 0 => List(xs.map(dec))
        (4, [t]) => Annotate(List([]), Apply(Builtin("List"), dec(t)))
        (5, [CNull, x]) => Apply(Builtin("Some"), dec(x))
        (6, [h, u]) => Merge(dec(h), dec(u), None)
        (6, [h, u, t]) => Merge(dec(h), dec(u), Some(dec(t)))
        (7, [CMap(fs)]) => RecordType(fs.map(p => (p.0, dec(p.1))))
        (8, [CMap(fs)]) => Record(fs.map(p => (p.0, dec(p.1))))
        (9, [r, CText(k)]) => Field(dec(r), k)
        (10, [r, .. ks]) => {
          let labels : Array[String] = []
          for k in ks {
            guard k is CText(s) else { raise BinaryError("Invalid projection") }
            if labels.contains(s) {
              raise BinaryError("Duplicate projection")
            }
            labels.push(s)
          }
          Project(dec(r), labels)
        }
        (11, [CMap(fs)]) =>
          UnionType(
            fs.map(p => {
              (
                p.0,
                match p.1 {
                  CNull => None
                  x => Some(dec(x))
                },
              )
            }),
          )
        (14, [c, a, b]) => If(dec(c), dec(a), dec(b))
        (15, [CInt(n)]) if n >= 0 => nat(n)
        (16, [CInt(n)]) => Integer(n.to_string())
        (18, _) if a.length() % 2 == 1 => {
          let ps : Array[(String, Expr)] = []
          for i = 0; i < a.length() - 1; i = i + 2 {
            guard a[i] is CText(s) else {
              raise BinaryError("Invalid text chunk")
            }
            ps.push((s, dec(a[i + 1])))
          }
          guard a[a.length() - 1] is CText(tail) else {
            raise BinaryError("Invalid text tail")
          }
          if ps.is_empty() {
            Text(tail)
          } else {
            Interpolate(ps, tail)
          }
        }
        (19, [x]) => Assert(dec(x))
        (25, _) if a.length() >= 4 && a.length() % 3 == 1 => {
          let mut body = dec(a[a.length() - 1])
          for i = a.length() - 4; i >= 0; i = i - 3 {
            guard a[i] is CText(n) else {
              raise BinaryError("Invalid let binder")
            }
            body = Let(
              n,
              match a[i + 1] {
                CNull => None
                x => Some(dec(x))
              },
              dec(a[i + 2]),
              body,
            )
          }
          body
        }
        (26, [x, t]) => Annotate(dec(x), dec(t))
        (28, [t]) => Annotate(List([]), dec(t))
        _ => raise BinaryError("Malformed or unsupported Dhall binary form")
      }
    }
    _ => raise BinaryError("Invalid Dhall binary value")
  }
}

///|
/// Strict, bounded decoding: rejects trailing bytes and malformed structures.
pub fn decode(bytes : Bytes) -> Expr raise DhallError {
  if bytes.length() > 1048576 {
    raise BinaryError("CBOR input size limit exceeded")
  }
  let reader = BinaryReader::{ bytes, index: 0, fuel: 100000, }
  let c = reader.read(0)
  if reader.index != bytes.length() {
    raise BinaryError("Trailing CBOR bytes")
  }
  decode_expr(c, 0)
}

///|
pub fn bytes_to_hex(bytes : Bytes) -> String {
  let hex = "0123456789abcdef".to_array()
  let out = StringBuilder()
  for b in bytes {
    out.write_char(hex[b.to_int() >> 4])
    out.write_char(hex[b.to_int() & 15])
  }
  out.to_string()
}

///|
pub fn hex_to_bytes(hex : String) -> Bytes raise DhallError {
  let chars = hex.to_array()
  if chars.length() % 2 != 0 {
    raise BinaryError("Odd hexadecimal length")
  }
  let out : Array[Byte] = []
  let mut n = 0
  for i in 0..<chars.length() {
    let c = chars[i]
    let digit = if c >= '0' && c <= '9' {
      c.to_int() - 48
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 87
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 55
    } else {
      raise BinaryError("Invalid hexadecimal digit")
    }
    n = (n << 4) | digit
    if i % 2 == 1 {
      out.push(n.to_byte())
      n = 0
    }
  }
  Bytes::from_array(out[:])
}
