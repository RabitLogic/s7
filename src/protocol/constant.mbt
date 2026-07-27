// S7 Protocol Constants - matching Rust s7 library

// ===== Word Length (WL) constants =====
///|
pub const WL_BIT : Int = 0x01

///|
pub const WL_BYTE : Int = 0x02

///|
pub const WL_CHAR : Int = 0x03

///|
pub const WL_WORD : Int = 0x04

///|
pub const WL_INT : Int = 0x05

///|
pub const WL_DWORD : Int = 0x06

///|
pub const WL_DINT : Int = 0x07

///|
pub const WL_REAL : Int = 0x08

///|
pub const WL_COUNTER : Int = 0x1C

///|
pub const WL_TIMER : Int = 0x1D

// ===== Transport Size (TS) constants =====

///|
pub const TS_RES_BIT : Int = 3

///|
pub const TS_RES_BYTE : Int = 4

///|
pub const TS_RES_INT : Int = 5

///|
pub const TS_RES_REAL : Int = 7

///|
pub const TS_RES_OCTET : Int = 9

// ===== Area hex codes (matching Rust Area enum) =====

///|
pub const AREA_PI : Byte = 0x81 // ProcessInput

///|
pub const AREA_PQ : Byte = 0x82 // ProcessOutput

///|
pub const AREA_MK : Byte = 0x83 // Merker (Flags)

///|
pub const AREA_DB : Byte = 0x84 // DataBausteine (DataBlock)

///|
pub const AREA_CT : Byte = 0x1C // Counter

///|
pub const AREA_TM : Byte = 0x1D // Timer

// ===== Header sizes =====

///|
pub const SIZE_HEADER_READ : Int = 31

///|
pub const SIZE_HEADER_WRITE : Int = 35

// ===== Connection type numeric values =====

///|
pub const CONN_PG : Int = 1

///|
pub const CONN_OP : Int = 2

///|
pub const CONN_BASIC : Int = 3

// ===== CpuStatus byte values =====

///|
pub const CPU_UNKNOWN : Int = 0

///|
pub const CPU_STOP : Int = 4

///|
pub const CPU_RUN : Int = 8

// ===== Data size lookup =====

///|
/// Convert word_length to number of bytes per element
pub fn data_size_byte(word_len : Int) -> Int {
  match word_len {
    WL_BIT => 1
    WL_BYTE => 1
    WL_CHAR => 1
    WL_WORD => 2
    WL_INT => 2
    WL_COUNTER => 2
    WL_TIMER => 2
    WL_DWORD => 4
    WL_DINT => 4
    WL_REAL => 4
    _ => 0
  }
}

///|
/// Convert DataType to word length constant
pub fn dt_to_word_len(dt : DataType) -> Int {
  match dt {
    Bool => WL_BIT
    Byte | Char | String | ByteArray(_) => WL_BYTE
    Word | Counter | S5Time => WL_WORD
    Int => WL_INT
    DWord | Time | TimeOfDay | Date => WL_DWORD
    DInt => WL_DINT
    Real => WL_REAL
    Timer => WL_TIMER
    IecTimer | DateAndTime => WL_DWORD
  }
}
