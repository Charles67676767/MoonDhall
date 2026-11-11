///|
fn digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn decimal_at(chars : Array[Char], start : Int32, count : Int32) -> Int32 {
  if start + count > chars.length() {
    return -1
  }
  let mut value = 0
  for i in start..<(start + count) {
    if !digit(chars[i]) {
      return -1
    }
    value = value * 10 + chars[i].to_int() - '0'.to_int()
  }
  value
}

///|
fn char_at(chars : Array[Char], i : Int32, c : Char) -> Bool {
  i < chars.length() && chars[i] == c
}

///|
fn valid_date(year : Int32, month : Int32, day : Int32) -> Bool {
  if month < 1 || month > 12 || day < 1 {
    return false
  }
  let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  let days = match month {
    2 => if leap { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
  day <= days
}

///|
fn zone_at(
  chars : Array[Char],
  start : Int32,
) -> (Expr, Int32)? raise DhallError {
  let negative = char_at(chars, start, '-')
  if !(negative || char_at(chars, start, '+')) ||
    !char_at(chars, start + 3, ':') ||
    decimal_at(chars, start + 1, 2) < 0 {
    return None
  }
  let h = decimal_at(chars, start + 1, 2)
  let m = decimal_at(chars, start + 4, 2)
  if h > 23 || m < 0 || m > 59 {
    raise Syntax("Invalid TimeZone", start)
  }
  Some(
    (TimeZoneLiteral((if negative { -1 } else { 1 }) * (h * 60 + m)), start + 6),
  )
}

///|
fn temporal_at(
  chars : Array[Char],
  start : Int32,
) -> (Expr, Int32)? raise DhallError {
  if char_at(chars, start, '+') || char_at(chars, start, '-') {
    return zone_at(chars, start)
  }
  let fields : Array[(String, Expr)] = []
  let mut cursor = start
  if char_at(chars, start + 4, '-') &&
    char_at(chars, start + 7, '-') &&
    decimal_at(chars, start, 4) >= 0 {
    let y = decimal_at(chars, start, 4)
    let m = decimal_at(chars, start + 5, 2)
    let d = decimal_at(chars, start + 8, 2)
    if !valid_date(y, m, d) {
      raise Syntax("Invalid Date", start)
    }
    cursor = start + 10
    if !char_at(chars, cursor, 'T') && !char_at(chars, cursor, 't') {
      return Some((DateLiteral(y, m, d), cursor))
    }
    fields.push(("date", DateLiteral(y, m, d)))
    cursor += 1
  }
  if !char_at(chars, cursor + 2, ':') ||
    !char_at(chars, cursor + 5, ':') ||
    decimal_at(chars, cursor, 2) < 0 ||
    decimal_at(chars, cursor + 3, 2) < 0 {
    if fields.is_empty() {
      return None
    }
    raise Syntax("Expected a Time after T", cursor)
  }
  let h = decimal_at(chars, cursor, 2)
  let m = decimal_at(chars, cursor + 3, 2)
  let s = decimal_at(chars, cursor + 6, 2)
  if h > 23 || m > 59 || s < 0 || s > 59 {
    raise Syntax("Invalid Time", cursor)
  }
  cursor += 8
  let fraction = if char_at(chars, cursor, '.') {
    cursor += 1
    let begin = cursor
    while cursor < chars.length() && digit(chars[cursor]) {
      cursor += 1
    }
    if cursor == begin {
      raise Syntax("Expected fractional seconds", begin)
    }
    chars_text(chars, begin, cursor)
  } else {
    ""
  }
  let time = TimeLiteral(h, m, s, fraction)
  let zone = if char_at(chars, cursor, 'Z') {
    Some((TimeZoneLiteral(0), cursor + 1))
  } else {
    zone_at(chars, cursor)
  }
  if fields.is_empty() && zone is None {
    return Some((time, cursor))
  }
  fields.push(("time", time))
  if zone is Some((value, end)) {
    fields.push(("timeZone", value))
    cursor = end
  }
  Some((Record(fields), cursor))
}

///|
fn pad_digits(digits : String, width : Int32) -> String {
  let out = StringBuilder()
  for _ in digits.length()..<width {
    out.write_char('0')
  }
  out.write_string(digits)
  out.to_string()
}

///|
fn pad_decimal(value : Int32, width : Int32) -> String {
  pad_digits(value.to_string(), width)
}
