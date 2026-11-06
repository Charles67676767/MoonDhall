///|
/// SHA-256 as specified by FIPS 180-4; arithmetic wraps modulo 2^32.
fn rotate(x : UInt32, n : Int32) -> UInt32 {
  (x >> n) | (x << (32 - n))
}

///|
pub fn sha256(bytes : Bytes) -> String {
  let constants : Array[UInt32] = [
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U,
    0x923f82a4U, 0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U,
    0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U,
    0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
    0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU,
    0x5b9cca4fU, 0x682e6ff3U, 0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U,
  ]
  let h : Array[UInt32] = [
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
    0x1f83d9abU, 0x5be0cd19U,
  ]
  let padded : Array[Byte] = []
  for b in bytes {
    padded.push(b)
  }
  padded.push(0x80)
  while padded.length() % 64 != 56 {
    padded.push(0)
  }
  write_uint(padded, bytes.length().to_uint64() * 8UL, 8)
  for block = 0; block < padded.length(); block = block + 64 {
    let w : Array[UInt32] = Array::make(64, 0U)
    for i in 0..<16 {
      let j = block + i * 4
      w[i] = (padded[j].to_uint() << 24) |
        (padded[j + 1].to_uint() << 16) |
        (padded[j + 2].to_uint() << 8) |
        padded[j + 3].to_uint()
    }
    for i in 16..<64 {
      let x = w[i - 15]
      let y = w[i - 2]
      w[i] = w[i - 16] +
        (rotate(x, 7) ^ rotate(x, 18) ^ (x >> 3)) +
        w[i - 7] +
        (rotate(y, 17) ^ rotate(y, 19) ^ (y >> 10))
    }
    let mut a = h[0]
    let mut b = h[1]
    let mut c = h[2]
    let mut d = h[3]
    let mut e = h[4]
    let mut f = h[5]
    let mut g = h[6]
    let mut k = h[7]
    for i in 0..<64 {
      let choose = (e & f) ^ ((e ^ 0xffffffffU) & g)
      let t1 = k +
        (rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)) +
        choose +
        constants[i] +
        w[i]
      let t2 = (rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)) +
        ((a & b) ^ (a & c) ^ (b & c))
      k = g
      g = f
      f = e
      e = d + t1
      d = c
      c = b
      b = a
      a = t1 + t2
    }
    h[0] += a
    h[1] += b
    h[2] += c
    h[3] += d
    h[4] += e
    h[5] += f
    h[6] += g
    h[7] += k
  }
  let out : Array[Byte] = []
  for x in h {
    write_uint(out, x.to_uint64(), 4)
  }
  bytes_to_hex(Bytes::from_array(out[:]))
}

///|
/// Dhall semantic hash: SHA-256 of alpha-normalized normal-form CBOR.
pub fn semantic_hash(source : String) -> String raise DhallError {
  sha256(encode_expr(normalize(source)))
}
