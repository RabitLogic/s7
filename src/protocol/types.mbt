///|
pub enum DataType {
  Bool
  Byte
  Word
  DWord
  Int
  DInt
  Real
  S5Time
  Time
  Date
  TimeOfDay
  String
  ByteArray(Int)
  Char
  Counter
  Timer
  IecTimer
  DateAndTime
}

///|
pub fn DataType::bool_dt() -> DataType {
  Bool
}

///|
pub fn DataType::byte() -> DataType {
  Byte
}

///|
pub fn DataType::word() -> DataType {
  Word
}

///|
pub fn DataType::dword() -> DataType {
  DWord
}

///|
pub fn DataType::int_type() -> DataType {
  Int
}

///|
pub fn DataType::dint() -> DataType {
  DInt
}

///|
pub fn DataType::real() -> DataType {
  Real
}

///|
pub fn DataType::s5time() -> DataType {
  S5Time
}

///|
pub fn DataType::time_type() -> DataType {
  Time
}

///|
pub fn DataType::date() -> DataType {
  Date
}

///|
pub fn DataType::time_of_day() -> DataType {
  TimeOfDay
}

///|
pub fn DataType::string_type() -> DataType {
  String
}

///|
pub fn DataType::byte_array(len : Int) -> DataType {
  ByteArray(len)
}

///|
pub fn DataType::char_type() -> DataType {
  Char
}

///|
pub fn DataType::counter() -> DataType {
  Counter
}

///|
pub fn DataType::timer() -> DataType {
  Timer
}

///|
pub fn DataType::iec_timer() -> DataType {
  IecTimer
}

///|
pub fn DataType::date_and_time() -> DataType {
  DateAndTime
}

///|
pub enum Area {
  ProcessInputs
  ProcessOutputs
  Flags
  DataBlock(Int)
  SystemInfo
  Timer
  Counter
  Vendor(Int)
}

///|
pub enum CpuStatus {
  Unknown
  Stop
  Run
}

///|
pub fn CpuStatus::from_u8(v : Byte) -> CpuStatus {
  match v.to_int() {
    // 4 => Stop
    4 => Stop
    // 8 => Run
    8 => Run
    _ => Unknown
  }
}

///|
pub enum ConnectionType {
  PG
  OP
  Basic
}

///|
pub struct CpuInfo {
  module_type_name : String
  serial_number : String
  as_name : String
  copyright : String
  module_name : String
}

///|
pub struct CPInfo {
  max_pdu_length : Int
  max_connections : Int
  max_mpi_rate : Int
  max_bus_rate : Int
}

///|
pub struct SZLData {
  header_len : Int
  data_count : Int
  data : Array[Byte]
}

///|
pub fn Area::inputs() -> Area {
  ProcessInputs
}

///|
pub fn Area::outputs() -> Area {
  ProcessOutputs
}

///|
pub fn Area::flags() -> Area {
  Flags
}

///|
pub fn Area::db(n : Int) -> Area {
  DataBlock(n)
}

///|
pub fn Area::system_info() -> Area {
  SystemInfo
}

///|
pub fn Area::timer() -> Area {
  Timer
}

///|
pub fn Area::counter() -> Area {
  Counter
}

///|
pub fn Area::vendor(n : Int) -> Area {
  Vendor(n)
}

///|
pub fn ConnectionType::pg() -> ConnectionType {
  PG
}

///|
pub fn ConnectionType::op() -> ConnectionType {
  OP
}

///|
pub fn ConnectionType::basic() -> ConnectionType {
  Basic
}

///|
pub fn ConnectionType::numeric(self : Self) -> Int {
  match self {
    PG => 1
    OP => 2
    Basic => 3
  }
}
