// Field types for structured PLC data access

// ===== BoolField =====

///|
pub struct BoolField {
  db_num : Int
  byte_offset : Int
  bit_offset : Int
  byte_val : Int
  bit_val : Bool
}

///|
pub fn BoolField::new(db : Int, byte_off : Int, bit_off : Int) -> BoolField {
  {
    db_num: db,
    byte_offset: byte_off,
    bit_offset: bit_off,
    byte_val: 0,
    bit_val: false,
  }
}

///|
pub fn BoolField::from_byte(
  db : Int,
  byte_off : Int,
  bit_off : Int,
  b : Byte,
) -> BoolField {
  let v = b.to_int()
  let bit = (v >> bit_off) & 1
  {
    db_num: db,
    byte_offset: byte_off,
    bit_offset: bit_off,
    byte_val: v,
    bit_val: bit != 0,
  }
}

///|
pub fn BoolField::set_value(self : BoolField, v : Bool) -> BoolField {
  let mask = 1 << self.bit_offset
  let nb = if v { self.byte_val | mask } else { self.byte_val & (0xFF ^ mask) }
  {
    db_num: self.db_num,
    byte_offset: self.byte_offset,
    bit_offset: self.bit_offset,
    byte_val: nb,
    bit_val: v,
  }
}

///|
pub fn BoolField::value(self : BoolField) -> Bool {
  self.bit_val
}

///|
pub fn BoolField::db_number(self : BoolField) -> Int {
  self.db_num
}

///|
pub fn BoolField::offset(self : BoolField) -> Int {
  self.byte_offset
}

///|
pub fn BoolField::to_bytes(self : BoolField) -> Array[Byte] {
  [self.byte_val.to_byte()]
}

///|
pub fn BoolField::size() -> Int {
  1
}

// ===== WordField (u16) =====

///|
pub struct WordField {
  db_num : Int
  offset_val : Int
  value_val : Int
}

///|
pub fn WordField::new(db : Int, offset : Int, bytes : Array[Byte]) -> WordField {
  let val = if bytes.length() >= 2 {
    (bytes[0].to_int() << 8) | bytes[1].to_int()
  } else {
    0
  }
  { db_num: db, offset_val: offset, value_val: val }
}

///|
pub fn WordField::value(self : WordField) -> Int {
  self.value_val
}

///|
pub fn WordField::db_number(self : WordField) -> Int {
  self.db_num
}

///|
pub fn WordField::offset(self : WordField) -> Int {
  self.offset_val
}

///|
pub fn WordField::to_bytes(self : WordField) -> Array[Byte] {
  let hi = ((self.value_val >> 8) & 0xFF).to_byte()
  let lo = (self.value_val & 0xFF).to_byte()
  [hi, lo]
}

///|
pub fn WordField::size() -> Int {
  2
}

// ===== DIntField (signed 32-bit) =====

///|
/// Signed 32-bit integer field (S7 DInt). MoonBit `Int` is 32-bit signed,
/// so this covers the full signed range -2^31 .. 2^31-1.
pub struct DIntField {
  db_num : Int
  offset_val : Int
  value_val : Int
}

///|
pub fn DIntField::new(db : Int, offset : Int, bytes : Array[Byte]) -> DIntField {
  let val = if bytes.length() >= 4 { dint_from_bytes(bytes) } else { 0 }
  { db_num: db, offset_val: offset, value_val: val }
}

///|
pub fn DIntField::value(self : DIntField) -> Int {
  self.value_val
}

///|
pub fn DIntField::db_number(self : DIntField) -> Int {
  self.db_num
}

///|
pub fn DIntField::offset(self : DIntField) -> Int {
  self.offset_val
}

///|
pub fn DIntField::to_bytes(self : DIntField) -> Array[Byte] {
  dint_to_bytes(self.value_val)
}

///|
pub fn DIntField::size() -> Int {
  4
}

// ===== DWordField (unsigned 32-bit, Int64) =====

///|
/// Unsigned 32-bit integer field (S7 DWord). The value is stored as `Int64`
/// so it covers the full unsigned range 0 .. 2^32-1 (MoonBit `Int` is only
/// 32-bit signed and would wrap values > 2^31).
pub struct DWordField {
  db_num : Int
  offset_val : Int
  value_val : Int64
}

///|
pub fn DWordField::new(db : Int, offset : Int, bytes : Array[Byte]) -> DWordField {
  let val = if bytes.length() >= 4 { dword_from_bytes(bytes) } else { 0L }
  { db_num: db, offset_val: offset, value_val: val }
}

///|
pub fn DWordField::value(self : DWordField) -> Int64 {
  self.value_val
}

///|
pub fn DWordField::db_number(self : DWordField) -> Int {
  self.db_num
}

///|
pub fn DWordField::offset(self : DWordField) -> Int {
  self.offset_val
}

///|
pub fn DWordField::to_bytes(self : DWordField) -> Array[Byte] {
  dword_to_bytes(self.value_val)
}

///|
pub fn DWordField::size() -> Int {
  4
}

// ===== 32-bit encode/decode helpers =====

///|
/// Decode 4 big-endian bytes into an unsigned 32-bit value (Int64).
fn dword_from_bytes(b : Array[Byte]) -> Int64 {
  let b0 = b[0].to_int().to_int64()
  let b1 = b[1].to_int().to_int64()
  let b2 = b[2].to_int().to_int64()
  let b3 = b[3].to_int().to_int64()
  (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}

///|
/// Encode an unsigned 32-bit value (Int64) as 4 big-endian bytes.
pub fn dword_to_bytes(val : Int64) -> Array[Byte] {
  [
    ((val >> 24) & 0xFF).to_byte(),
    ((val >> 16) & 0xFF).to_byte(),
    ((val >> 8) & 0xFF).to_byte(),
    (val & 0xFF).to_byte(),
  ]
}

///|
/// Decode 4 big-endian bytes into a signed 32-bit value (Int).
fn dint_from_bytes(b : Array[Byte]) -> Int {
  let u = dword_from_bytes(b)
  let s = if u >= 0x80000000L { u - 0x100000000L } else { u }
  s.to_int()
}

///|
/// Encode a signed 32-bit value (Int) as 4 big-endian bytes.
pub fn dint_to_bytes(val : Int) -> Array[Byte] {
  dword_to_bytes(val.to_int64() & 0xFFFFFFFFL)
}

// ===== FloatField (IEEE 754 f32) =====

///|
pub struct FloatField {
  db_num : Int
  offset_val : Int
  value_val : Double
}

///|
pub fn FloatField::new(
  db : Int,
  offset : Int,
  bytes : Array[Byte],
) -> FloatField {
  let val = if bytes.length() >= 4 { f32_from_bytes(bytes) } else { 0.0 }
  { db_num: db, offset_val: offset, value_val: val }
}

///|
pub fn FloatField::value(self : FloatField) -> Double {
  self.value_val
}

///|
pub fn FloatField::db_number(self : FloatField) -> Int {
  self.db_num
}

///|
pub fn FloatField::offset(self : FloatField) -> Int {
  self.offset_val
}

///|
pub fn FloatField::to_bytes(self : FloatField) -> Array[Byte] {
  f32_to_bytes(self.value_val)
}

///|
pub fn FloatField::size() -> Int {
  4
}

// ===== DoubleField (IEEE 754 f64) =====

///|
pub struct DoubleField {
  db_num : Int
  offset_val : Int
  value_val : Double
}

///|
pub fn DoubleField::new(
  db : Int,
  offset : Int,
  bytes : Array[Byte],
) -> DoubleField {
  let val = if bytes.length() >= 8 { f64_from_bytes(bytes) } else { 0.0 }
  { db_num: db, offset_val: offset, value_val: val }
}

///|
pub fn DoubleField::value(self : DoubleField) -> Double {
  self.value_val
}

///|
pub fn DoubleField::db_number(self : DoubleField) -> Int {
  self.db_num
}

///|
pub fn DoubleField::offset(self : DoubleField) -> Int {
  self.offset_val
}

///|
pub fn DoubleField::to_bytes(self : DoubleField) -> Array[Byte] {
  f64_to_bytes(self.value_val)
}

///|
pub fn DoubleField::size() -> Int {
  8
}

// ===== IEEE 754 Helpers =====

///|
fn f32_from_bytes(b : Array[Byte]) -> Double {
  let b0 = b[0].to_int()
  let b1 = b[1].to_int()
  let b2 = b[2].to_int()
  let b3 = b[3].to_int()
  let bits = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
  let sign = if (bits & 0x80000000) != 0 { -1.0 } else { 1.0 }
  let exp = ((bits >> 23) & 0xFF) - 127
  let mant = (bits & 0x7FFFFF).to_double()
  if exp == -127 && mant == 0.0 {
    return 0.0
  }
  if exp == 128 {
    return if sign > 0.0 { 1.0 / 0.0 } else { -1.0 / 0.0 }
  }
  let mv = 1.0 + mant / 8388608.0
  sign * mv * pow2(exp)
}

///|
pub fn f32_to_bytes(val : Double) -> Array[Byte] {
  if val == 0.0 {
    return [0x00, 0x00, 0x00, 0x00]
  }
  let sb = if val < 0.0 { 1 } else { 0 }
  let av = if val < 0.0 { -val } else { val }
  let ev = ilog2_floor(av)
  let eb = ev + 127
  let mn = av / pow2(ev)
  let mi = ((mn - 1.0) * 8388608.0).round().to_int()
  let bits = (sb << 31) | (eb << 23) | (mi & 0x7FFFFF)
  [
    ((bits >> 24) & 0xFF).to_byte(),
    ((bits >> 16) & 0xFF).to_byte(),
    ((bits >> 8) & 0xFF).to_byte(),
    (bits & 0xFF).to_byte(),
  ]
}

///|
fn f64_from_bytes(b : Array[Byte]) -> Double {
  let b0 = b[0].to_int()
  let b1 = b[1].to_int()
  let b2 = b[2].to_int()
  let b3 = b[3].to_int()
  let b4 = b[4].to_int()
  let b5 = b[5].to_int()
  let b6 = b[6].to_int()
  let b7 = b[7].to_int()
  let hi = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
  let lo = (b4 << 24) | (b5 << 16) | (b6 << 8) | b7
  let sign = if (hi & 0x80000000) != 0 { -1.0 } else { 1.0 }
  let exp = ((hi >> 20) & 0x7FF) - 1023
  let mh = (hi & 0xFFFFF).to_double()
  let ml = lo.to_double()
  if exp == -1023 && mh == 0.0 && ml == 0.0 {
    return 0.0
  }
  if exp == 1024 {
    return if sign > 0.0 { 1.0 / 0.0 } else { -1.0 / 0.0 }
  }
  let mv = 1.0 + (mh * 4294967296.0 + ml) / 4503599627370496.0
  sign * mv * pow2(exp)
}

///|
pub fn f64_to_bytes(val : Double) -> Array[Byte] {
  if val == 0.0 {
    return Array::make(8, 0x00)
  }
  let sb = if val < 0.0 { 1 } else { 0 }
  let av = if val < 0.0 { -val } else { val }
  let ev = ilog2_floor(av)
  let eb = ev + 1023
  let mn = av / pow2(ev)
  let mi64 : Int64 = ((mn - 1.0) * 4503599627370496.0).round().to_int64()
  let hm = ((mi64 >> 32) & 0xFFFFFL).to_int()
  let lm = (mi64 & 0xFFFFFFFFL).to_int()
  let hi = (sb << 31) | (eb << 20) | hm
  let lo = lm
  [
    ((hi >> 24) & 0xFF).to_byte(),
    ((hi >> 16) & 0xFF).to_byte(),
    ((hi >> 8) & 0xFF).to_byte(),
    (hi & 0xFF).to_byte(),
    ((lo >> 24) & 0xFF).to_byte(),
    ((lo >> 16) & 0xFF).to_byte(),
    ((lo >> 8) & 0xFF).to_byte(),
    (lo & 0xFF).to_byte(),
  ]
}

///|
fn pow2(e : Int) -> Double {
  let mut r = 1.0
  let n = if e < 0 { -e } else { e }
  for _ in 0..<n {
    r = r * 2.0
  }
  if e < 0 {
    1.0 / r
  } else {
    r
  }
}

///|
fn ilog2_floor(x : Double) -> Int {
  let mut n = 0
  let mut v = x
  while v >= 2.0 {
    v = v / 2.0
    n = n + 1
  }
  while v < 1.0 {
    v = v * 2.0
    n = n - 1
  }
  n
}

// ===== StringField =====

///|
/// Structured access to an S7 STRING field: `[max_len, cur_len, chars...]`.
pub struct StringField {
  db_num : Int
  byte_offset : Int
  max_len : Int
  value : String
}

///|
pub fn StringField::new(db : Int, byte_off : Int, max_len : Int, value : String) -> StringField {
  { db_num: db, byte_offset: byte_off, max_len, value }
}

///|
pub fn StringField::value(self : StringField) -> String {
  self.value
}

///|
pub fn StringField::db_number(self : StringField) -> Int {
  self.db_num
}

///|
pub fn StringField::offset(self : StringField) -> Int {
  self.byte_offset
}

///|
pub fn StringField::max_length(self : StringField) -> Int {
  self.max_len
}

///|
/// Encode to the full S7 STRING field bytes `[max_len, cur_len, chars..., 0x00...]`
/// padded to `max_len + 2` bytes, ready to write to the PLC.
pub fn StringField::to_bytes(self : StringField) -> Array[Byte] {
  let b = encode_s7_string(self.max_len, self.value)
  while b.length() < self.max_len + 2 {
    b.push(0x00)
  }
  b
}

///|
/// Decode raw S7 STRING field bytes into a StringField.
pub fn StringField::from_bytes(
  db : Int,
  byte_off : Int,
  max_len : Int,
  data : Array[Byte],
) -> StringField {
  { db_num: db, byte_offset: byte_off, max_len, value: decode_s7_string(data) }
}

// ===== Field Trait =====

///|
/// Trait for structured PLC field access (matching Rust s7 Field trait)
pub trait Field {
  fn data_block(Self) -> Int
  fn offset(Self) -> Int
  fn to_bytes(Self) -> Array[Byte]
}

///|
impl Field for BoolField with fn data_block(self) {
  self.db_num
}

///|
impl Field for BoolField with fn offset(self) {
  self.byte_offset
}

///|
impl Field for BoolField with fn to_bytes(self) {
  self.to_bytes()
}

///|
impl Field for WordField with fn data_block(self) {
  self.db_num
}

///|
impl Field for WordField with fn offset(self) {
  self.offset_val
}

///|
impl Field for WordField with fn to_bytes(self) {
  self.to_bytes()
}

///|
impl Field for FloatField with fn data_block(self) {
  self.db_num
}

///|
impl Field for FloatField with fn offset(self) {
  self.offset_val
}

///|
impl Field for FloatField with fn to_bytes(self) {
  self.to_bytes()
}

///|
impl Field for DoubleField with fn data_block(self) {
  self.db_num
}

///|
impl Field for DoubleField with fn offset(self) {
  self.offset_val
}

///|
impl Field for DoubleField with fn to_bytes(self) {
  self.to_bytes()
}

// ===== FieldValue — heterogeneous field collection =====

///|
/// Enum wrapping all field types for heterogeneous collections (replaces Rust's `Fields = Vec<Box<dyn Field>>`)
pub enum FieldValue {
  FBool(BoolField)
  FWord(WordField)
  FFloat(FloatField)
  FDouble(DoubleField)
}

///|
pub fn FieldValue::data_block(self : Self) -> Int {
  match self {
    FBool(f) => f.db_num
    FWord(f) => f.db_num
    FFloat(f) => f.db_num
    FDouble(f) => f.db_num
  }
}

///|
pub fn FieldValue::offset(self : Self) -> Int {
  match self {
    FBool(f) => f.byte_offset
    FWord(f) => f.offset_val
    FFloat(f) => f.offset_val
    FDouble(f) => f.offset_val
  }
}

///|
pub fn FieldValue::to_bytes(self : Self) -> Array[Byte] {
  match self {
    FBool(f) => f.to_bytes()
    FWord(f) => f.to_bytes()
    FFloat(f) => f.to_bytes()
    FDouble(f) => f.to_bytes()
  }
}

///|
pub fn FieldValue::size(self : Self) -> Int {
  match self {
    FBool(_) => 1
    FWord(_) => 2
    FFloat(_) => 4
    FDouble(_) => 8
  }
}

///|
pub fn FieldValue::value_bool(self : Self) -> Bool? {
  match self {
    FBool(f) => Some(f.bit_val)
    _ => None
  }
}

///|
pub fn FieldValue::value_int(self : Self) -> Int? {
  match self {
    FWord(f) => Some(f.value_val)
    _ => None
  }
}

///|
pub fn FieldValue::value_double(self : Self) -> Double? {
  match self {
    FFloat(f) => Some(f.value_val)
    FDouble(f) => Some(f.value_val)
    _ => None
  }
}

///|
/// Construct a FieldValue from a BoolField
pub fn FieldValue::from_bool(f : BoolField) -> FieldValue {
  FBool(f)
}

///|
/// Construct a FieldValue from a WordField
pub fn FieldValue::from_word(f : WordField) -> FieldValue {
  FWord(f)
}

///|
/// Construct a FieldValue from a FloatField
pub fn FieldValue::from_float(f : FloatField) -> FieldValue {
  FFloat(f)
}

///|
/// Construct a FieldValue from a DoubleField
pub fn FieldValue::from_double(f : DoubleField) -> FieldValue {
  FDouble(f)
}
