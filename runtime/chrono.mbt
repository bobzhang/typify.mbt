// `chrono::NaiveDate` and `chrono::DateTime<Utc>` (chrono 0.4.45): a port of
// the `FromStr` parsers used by their serde impls (including chrono's error
// classification and messages) and of their RFC 3339 / ISO 8601 output.

///|
priv enum ChronoErr {
  OutOfRange
  Impossible
  NotEnough
  Invalid
  TooShort
  TooLong
}

///|
priv suberror ChronoError {
  ChronoError(ChronoErr)
}

///|
/// chrono's `ParseError` display text.
fn ChronoErr::message(self : ChronoErr) -> String {
  match self {
    OutOfRange => "input is out of range"
    Impossible => "no possible date and time matching input"
    NotEnough => "input is not enough for unique date and time"
    Invalid => "input contains invalid characters"
    TooShort => "premature end of input"
    TooLong => "trailing input"
  }
}

///|
/// The smallest and largest years of `NaiveDate` (`MIN_YEAR`, `MAX_YEAR`).
const MIN_YEAR : Int = -262143

///|
const MAX_YEAR : Int = 262142

///|
/// A byte cursor over UTF-8 input, mirroring chrono's `&str` slicing.
priv struct Scan {
  b : Bytes
  mut pos : Int
}

///|
fn Scan::new(s : String) -> Scan {
  { b: @utf8.encode(s), pos: 0, }
}

///|
fn Scan::len(self : Scan) -> Int {
  self.b.length() - self.pos
}

///|
fn Scan::at(self : Scan, i : Int) -> Int {
  self.b[self.pos + i].to_int()
}

///|
/// Byte length of the Unicode `White_Space` character at `pos`, or 0
/// (Rust's `char::is_whitespace`).
fn Scan::space_len(self : Scan) -> Int {
  let n = self.len()
  if n == 0 {
    return 0
  }
  let c0 = self.at(0)
  if c0 == 0x20 || (c0 >= 0x09 && c0 <= 0x0D) {
    return 1
  }
  if n >= 2 && c0 == 0xC2 && self.at(1) is (0x85 | 0xA0) {
    return 2
  }
  if n >= 3 {
    let (c1, c2) = (self.at(1), self.at(2))
    match (c0, c1, c2) {
      (0xE1, 0x9A, 0x80) => return 3 // U+1680
      (0xE2, 0x80, 0x80..=0x8A) => return 3 // U+2000..U+200A
      (0xE2, 0x80, 0xA8 | 0xA9 | 0xAF) => return 3 // U+2028, U+2029, U+202F
      (0xE2, 0x81, 0x9F) => return 3 // U+205F
      (0xE3, 0x80, 0x80) => return 3 // U+3000
      _ => ()
    }
  }
  0
}

///|
/// `str::trim_start`.
fn Scan::trim_start(self : Scan) -> Unit {
  while self.space_len() is n && n > 0 {
    self.pos += n
  }
}

///|
/// `scan::number`: `min..=max` ASCII digits as an `i64`.
fn Scan::number(self : Scan, min : Int, max : Int) -> Int64 raise ChronoError {
  if self.len() < min {
    raise ChronoError(TooShort)
  }
  let mut n = 0L
  let limit = if max < self.len() { max } else { self.len() }
  for i in 0..<limit {
    let c = self.at(i)
    if c < 0x30 || c > 0x39 {
      if i < min {
        raise ChronoError(Invalid)
      }
      self.pos += i
      return n
    }
    let d = (c - 0x30).to_int64()
    if n > (@int64.max_value - d) / 10L {
      raise ChronoError(OutOfRange)
    }
    n = n * 10L + d
  }
  self.pos += limit
  n
}

///|
/// `Item::Numeric` with the given width; signed numbers (years) accept an
/// explicit sign followed by any number of digits.
fn Scan::numeric(
  self : Scan,
  width : Int,
  signed : Bool,
) -> Int64 raise ChronoError {
  self.trim_start()
  let unlimited = 0x7FFFFFFF
  if signed && self.len() > 0 && self.at(0) == 0x2D {
    self.pos += 1
    -self.number(1, unlimited)
  } else if signed && self.len() > 0 && self.at(0) == 0x2B {
    self.pos += 1
    self.number(1, unlimited)
  } else {
    self.number(1, width)
  }
}

///|
/// `Item::Literal` of one ASCII byte.
fn Scan::literal(self : Scan, c : Int) -> Unit raise ChronoError {
  if self.len() < 1 {
    raise ChronoError(TooShort)
  }
  if self.at(0) != c {
    raise ChronoError(Invalid)
  }
  self.pos += 1
}

///|
fn in_range(v : Int64, lo : Int, hi : Int) -> Int raise ChronoError {
  if v < lo.to_int64() || v > hi.to_int64() {
    raise ChronoError(OutOfRange)
  }
  v.to_int()
}

///|
/// `Year - Month - Day` with optional whitespace around the dashes
/// (`Parsed::set_year`, `set_month`, `set_day` range checks).
fn Scan::date_items(self : Scan) -> (Int, Int, Int) raise ChronoError {
  let year = in_range(self.numeric(4, true), -0x80000000, 0x7FFFFFFF)
  self.trim_start()
  self.literal(0x2D)
  let month = in_range(self.numeric(2, false), 1, 12)
  self.trim_start()
  self.literal(0x2D)
  let day = in_range(self.numeric(2, false), 1, 31)
  (year, month, day)
}

///|
fn is_leap_year(y : Int) -> Bool {
  y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
}

///|
fn month_days(y : Int, m : Int) -> Int {
  match m {
    2 => if is_leap_year(y) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
/// A calendar date (`chrono::NaiveDate`), serialized as `%Y-%m-%d` (years
/// outside 0..=9999 carry an explicit sign).
pub struct NaiveDate {
  year : Int
  month : Int
  day : Int
} derive(Eq, Compare, Hash, Debug)

///|
/// `NaiveDate::from_ymd_opt`.
pub fn NaiveDate::from_ymd(year : Int, month : Int, day : Int) -> NaiveDate? {
  if year < MIN_YEAR ||
    year > MAX_YEAR ||
    month < 1 ||
    month > 12 ||
    day < 1 ||
    day > month_days(year, month) {
    None
  } else {
    Some({ year, month, day, })
  }
}

///|
pub fn NaiveDate::year(self : NaiveDate) -> Int {
  self.year
}

///|
pub fn NaiveDate::month(self : NaiveDate) -> Int {
  self.month
}

///|
pub fn NaiveDate::day(self : NaiveDate) -> Int {
  self.day
}

///|
/// `NaiveDate::succ_opt`.
fn NaiveDate::succ(self : NaiveDate) -> NaiveDate? {
  if self.day < month_days(self.year, self.month) {
    Some({ ..self, day: self.day + 1, })
  } else if self.month < 12 {
    Some({ ..self, month: self.month + 1, day: 1, })
  } else {
    NaiveDate::from_ymd(self.year + 1, 1, 1)
  }
}

///|
/// `NaiveDate::pred_opt`.
fn NaiveDate::pred(self : NaiveDate) -> NaiveDate? {
  if self.day > 1 {
    Some({ ..self, day: self.day - 1, })
  } else if self.month > 1 {
    Some({
      ..self,
      month: self.month - 1,
      day: month_days(self.year, self.month - 1),
    })
  } else {
    NaiveDate::from_ymd(self.year - 1, 12, 31)
  }
}

///|
fn write2(buf : StringBuilder, n : Int) -> Unit {
  buf.write_char(Int::unsafe_to_char(0x30 + n / 10))
  buf.write_char(Int::unsafe_to_char(0x30 + n % 10))
}

///|
fn write_date(buf : StringBuilder, d : NaiveDate) -> Unit {
  if d.year >= 0 && d.year <= 9999 {
    write2(buf, d.year / 100)
    write2(buf, d.year % 100)
  } else {
    // `{year:+05}`
    buf.write_char(if d.year < 0 { '-' } else { '+' })
    let digits = d.year.abs().to_string()
    for _ in digits.length()..<4 {
      buf.write_char('0')
    }
    buf.write_string(digits)
  }
  buf.write_char('-')
  write2(buf, d.month)
  buf.write_char('-')
  write2(buf, d.day)
}

///|
fn parse_naive_date(s : String) -> NaiveDate raise ChronoError {
  let sc = Scan::new(s)
  let (year, month, day) = sc.date_items()
  sc.trim_start()
  if sc.len() > 0 {
    raise ChronoError(TooLong)
  }
  match NaiveDate::from_ymd(year, month, day) {
    Some(d) => d
    None => raise ChronoError(OutOfRange)
  }
}

///|
/// `NaiveDate::from_str` (`%Y-%m-%d`, relaxed as chrono's parser is).
pub fn NaiveDate::parse(s : String) -> NaiveDate raise ConversionError {
  parse_naive_date(s) catch {
    ChronoError(e) => raise ConversionError(e.message())
  }
}

///|
pub fn NaiveDate::to_string(self : NaiveDate) -> String {
  let buf = StringBuilder()
  write_date(buf, self)
  buf.to_string()
}

///|
pub impl Show for NaiveDate with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn NaiveDate::deserialize(d : De) -> NaiveDate raise DeError {
  let s = de_string_expecting(d, "a formatted date string")
  parse_naive_date(s) catch {
    ChronoError(e) => raise DeError(e.message())
  }
}

///|
pub fn NaiveDate::serialize(self : NaiveDate) -> Content raise SerError {
  String(self.to_string())
}

///|
/// A UTC timestamp (`chrono::DateTime<Utc>`), serialized as RFC 3339 with
/// chrono's `SecondsFormat::AutoSi` and `Z`.
pub struct DateTimeUtc {
  date : NaiveDate
  /// Seconds since midnight (0..86400).
  secs : Int
  /// Nanoseconds; 10^9 and above denote a leap second.
  frac : Int
} derive(Eq, Compare, Hash, Debug)

///|
pub fn DateTimeUtc::date(self : DateTimeUtc) -> NaiveDate {
  self.date
}

///|
/// Seconds since the Unix epoch (a leap second counts as the second before).
pub fn DateTimeUtc::timestamp(self : DateTimeUtc) -> Int64 {
  let d = self.date
  let y = if d.month <= 2 { d.year - 1 } else { d.year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = (d.month + 9) % 12
  let doy = (153 * mp + 2) / 5 + d.day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  let days = era.to_int64() * 146097L + doe.to_int64() - 719468L
  days * 86400L + self.secs.to_int64()
}

///|
/// The nanosecond part (at least 10^9 during a leap second).
pub fn DateTimeUtc::nanosecond(self : DateTimeUtc) -> Int {
  self.frac
}

///|
/// `DateTime<FixedOffset>::from_str` (chrono's relaxed RFC 3339), converted
/// to UTC.
fn parse_datetime(s : String) -> DateTimeUtc raise ChronoError {
  let sc = Scan::new(s)
  let (year, month, day) = sc.date_items()
  if sc.len() == 0 {
    raise ChronoError(TooShort)
  }
  if !(sc.at(0) is (0x74 | 0x54 | 0x20)) {
    raise ChronoError(Invalid)
  }
  sc.pos += 1
  let hour = in_range(sc.numeric(2, false), 0, 23)
  sc.trim_start()
  sc.literal(0x3A)
  let minute = in_range(sc.numeric(2, false), 0, 59)
  sc.trim_start()
  sc.literal(0x3A)
  let second = in_range(sc.numeric(2, false), 0, 60)
  let mut nano = 0
  if sc.len() > 0 && sc.at(0) == 0x2E {
    sc.pos += 1
    // `scan::nanosecond`: up to 9 digits scaled, further digits skipped.
    let start = sc.pos
    let v = sc.number(1, 9).to_int()
    let scale = [
      0, 100000000, 10000000, 1000000, 100000, 10000, 1000, 100, 10, 1,
    ]
    nano = v * scale[sc.pos - start]
    while sc.len() > 0 && sc.at(0) >= 0x30 && sc.at(0) <= 0x39 {
      sc.pos += 1
    }
  }
  sc.trim_start()
  sc.trim_start()
  let offset = if sc.len() >= 3 &&
    (sc.at(0) | 32) == 0x75 &&
    (sc.at(1) | 32) == 0x74 &&
    (sc.at(2) | 32) == 0x63 {
    sc.pos += 3
    0
  } else {
    sc.timezone_offset()
  }
  sc.trim_start()
  if sc.len() > 0 {
    raise ChronoError(TooLong)
  }
  // `Parsed::to_datetime`
  let date = match NaiveDate::from_ymd(year, month, day) {
    Some(d) => d
    None => raise ChronoError(OutOfRange)
  }
  let (second, frac) = if second == 60 {
    (59, 1000000000 + nano)
  } else {
    (second, nano)
  }
  if offset <= -86400 || offset >= 86400 {
    raise ChronoError(OutOfRange)
  }
  // `checked_sub_offset`
  let local = hour * 3600 + minute * 60 + second
  let utc = local - offset
  let date = if utc < 0 {
    date.pred()
  } else if utc >= 86400 {
    date.succ()
  } else {
    Some(date)
  }
  match date {
    Some(date) => { date, secs: (utc % 86400 + 86400) % 86400, frac, }
    None => raise ChronoError(Impossible)
  }
}

///|
/// `scan::timezone_offset(s, colon_or_space, allow_zulu=true,
/// allow_missing_minutes=false, allow_tz_minus_sign=true)`, in seconds.
fn Scan::timezone_offset(self : Scan) -> Int raise ChronoError {
  if self.len() > 0 && self.at(0) is (0x5A | 0x7A) {
    self.pos += 1
    return 0
  }
  if self.len() == 0 {
    raise ChronoError(TooShort)
  }
  let negative = match self.at(0) {
    0x2B => {
      self.pos += 1
      false
    }
    0x2D => {
      self.pos += 1
      true
    }
    0xE2 if self.len() >= 3 && self.at(1) == 0x88 && self.at(2) == 0x92 => {
      // U+2212 MINUS SIGN
      self.pos += 3
      true
    }
    _ => raise ChronoError(Invalid)
  }
  if self.len() < 2 {
    raise ChronoError(TooShort)
  }
  let (h1, h2) = (self.at(0), self.at(1))
  if !(h1 >= 0x30 && h1 <= 0x39 && h2 >= 0x30 && h2 <= 0x39) {
    raise ChronoError(Invalid)
  }
  let hours = (h1 - 0x30) * 10 + (h2 - 0x30)
  self.pos += 2
  // `colon_or_space`
  while self.len() > 0 {
    if self.at(0) == 0x3A {
      self.pos += 1
    } else if self.space_len() is n && n > 0 {
      self.pos += n
    } else {
      break
    }
  }
  if self.len() < 2 {
    raise ChronoError(TooShort)
  }
  let (m1, m2) = (self.at(0), self.at(1))
  let minutes = if m1 >= 0x30 && m1 <= 0x35 && m2 >= 0x30 && m2 <= 0x39 {
    (m1 - 0x30) * 10 + (m2 - 0x30)
  } else if m1 >= 0x36 && m1 <= 0x39 && m2 >= 0x30 && m2 <= 0x39 {
    raise ChronoError(OutOfRange)
  } else {
    raise ChronoError(Invalid)
  }
  self.pos += 2
  let seconds = hours * 3600 + minutes * 60
  if negative {
    -seconds
  } else {
    seconds
  }
}

///|
/// `DateTime<Utc>::from_str`: chrono's relaxed RFC 3339 (`T`, `t` or a space
/// between date and time, optional fractional seconds, an offset, `Z` or
/// `UTC`), normalised to UTC.
pub fn DateTimeUtc::parse(s : String) -> DateTimeUtc raise ConversionError {
  parse_datetime(s) catch {
    ChronoError(e) => raise ConversionError(e.message())
  }
}

///|
/// RFC 3339 with `SecondsFormat::AutoSi` (0, 3, 6 or 9 fraction digits)
/// and `Z`.
pub fn DateTimeUtc::to_string(self : DateTimeUtc) -> String {
  let buf = StringBuilder()
  write_date(buf, self.date)
  buf.write_char('T')
  let (sec, nano) = if self.frac >= 1000000000 {
    (self.secs % 60 + 1, self.frac - 1000000000)
  } else {
    (self.secs % 60, self.frac)
  }
  write2(buf, self.secs / 3600)
  buf.write_char(':')
  write2(buf, self.secs / 60 % 60)
  buf.write_char(':')
  write2(buf, sec)
  let pad = (n : Int, width : Int) => {
    let digits = n.to_string()
    for _ in digits.length()..<width {
      buf.write_char('0')
    }
    buf.write_string(digits)
  }
  if nano == 0 {
    ()
  } else if nano % 1000000 == 0 {
    buf.write_char('.')
    pad(nano / 1000000, 3)
  } else if nano % 1000 == 0 {
    buf.write_char('.')
    pad(nano / 1000, 6)
  } else {
    buf.write_char('.')
    pad(nano, 9)
  }
  buf.write_char('Z')
  buf.to_string()
}

///|
pub impl Show for DateTimeUtc with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn DateTimeUtc::deserialize(d : De) -> DateTimeUtc raise DeError {
  let s = de_string_expecting(d, "an RFC 3339 formatted date and time string")
  parse_datetime(s) catch {
    ChronoError(e) => raise DeError(e.message())
  }
}

///|
pub fn DateTimeUtc::serialize(self : DateTimeUtc) -> Content raise SerError {
  String(self.to_string())
}
