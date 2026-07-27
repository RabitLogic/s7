///|
/// DB200 field definitions (from TIA Portal):
///   signal : Bool   @ 0.0
///   index  : Int    @ 2.0
///   code   : String @ 4.0
///
/// Connect to Siemens S7 PLC at 172.16.152.1 and read DB200 with structured parsing.

/// Parse a Bool at a specific byte offset and bit position
fn parse_bool(data : Array[Byte], byte_off : Int, bit_off : Int) -> Bool {
  if byte_off >= data.length() { return false }
  ((data[byte_off].to_int() >> bit_off) & 1) == 1
}

/// Parse a big-endian 16-bit signed Int starting at byte_off
fn parse_int(data : Array[Byte], byte_off : Int) -> Int {
  if byte_off + 1 >= data.length() {
    abort("parse_int: out of range")
  }
  let hi = data[byte_off].to_int()
  let lo = data[byte_off + 1].to_int()
  (hi << 8) | lo
}

/// Parse an S7 String at byte_off.
/// S7 string layout: [max_len: Byte][actual_len: Byte][data...]
fn parse_s7_string(data : Array[Byte], byte_off : Int) -> String {
  if byte_off + 1 >= data.length() {
    abort("parse_s7_string: header out of range")
  }
  let act_len = data[byte_off + 1].to_int()
  if byte_off + 1 + act_len > data.length() {
    abort("parse_s7_string: string data out of range")
  }
  let mut result = ""
  for i in 0..<act_len {
    let b = data[byte_off + 2 + i]
    result = result + b.to_string()
  }
  result
}

/// Format bytes as hex string (e.g. "DE AD BE EF")
fn hex_dump(data : Array[Byte]) -> String {
  let hex_chars = "0123456789ABCDEF"
  let mut s = ""
  for i in 0..<data.length() {
    let v = data[i].to_int()
    let hi = (v >> 4) & 0xF
    let lo = v & 0xF
    s = s + hex_chars[hi].to_string()
    s = s + hex_chars[lo].to_string()
    if i < data.length() - 1 { s = s + " " }
  }
  s
}

async fn main {
  println("=== S7 DB200 Structured Read Test ===")
  println("Connecting to 127.0.0.1:102...")

  let cfg = @transport.TcpConfig::new(
    host="127.0.0.1",
    port=102,
    connect_timeout=10000,
    read_timeout=10000,
    rack=0,
    slot=2,
    conn_type=1,
  )

  let client = @client.S7Client::new_with_config(cfg)

  match client.connect() {
    Err(e) => println("Connection failed: \{e}")
    Ok(cl) => {
      println("Connected successfully! PDU size: \{cl.pdu_size}")

      // Read DB200 — enough bytes to cover all fields (~260 bytes for a typical string)
      println("\nReading DB200 (256 bytes from offset 0)...")
      match cl.ag_read(200, 0, 256) {
        Err(e) => println("DB200 read failed: \{e}")
        Ok(data) => {
          println("Received \{data.length()} bytes")
          println("Raw hex: \{hex_dump(data)}")

          // --- Parse fields ---
          // 1. signal (Bool at 0.0)
          let signal = parse_bool(data, 0, 0)
          println("\n--- DB200 Fields ---")
          println("signal (Bool  @ 0.0) = \{signal}")

          // 2. index (Int at 2.0)
          let index = parse_int(data, 2)
          println("index  (Int   @ 2.0) = \{index}")

          // 3. code (String at 4.0)
          let code = parse_s7_string(data, 4)
          println("code   (String @ 4.0) = \"\{code}\"")
        }
      }

      println("\nDisconnecting...")
      cl.disconnect()
      println("Done.")
    }
  }
}
