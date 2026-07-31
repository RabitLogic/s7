///|
/// Convert S7Error to a human-readable string
pub fn err_to_string(e : @core.S7Error) -> String {
  match e {
    @core.ConnectionFailed(m) => "Connection failed: \{m}"
    @core.ConnectionTimeout => "Connection timeout"
    @core.ConnectionClosed => "Connection closed"
    @core.InvalidPDU(m) => "Invalid PDU: \{m}"
    @core.InvalidParameter(m) => "Invalid parameter: \{m}"
    @core.PlcError(c, m) => "PLC error (\{c.to_string()}): \{m}"
    @core.Timeout(m) => "Timeout: \{m}"
    @core.TransportError(m) => "Transport error: \{m}"
    @core.TlsError(m) => "TLS error: \{m}"
    @core.VersionMismatch(v1, v2) => "Version mismatch: \{v1.to_string()} vs \{v2.to_string()}"
    @core.BufferOverflow => "Buffer overflow"
    @core.ItemNotFound(m) => "Item not found: \{m}"
    @core.NotConnected => "Not connected"
    @core.AlreadyConnected => "Already connected"
    @core.DataConversionError(m) => "Data conversion error: \{m}"
    @core.Unsupported(m) => "Unsupported: \{m}"
    @core.ResourceExhausted(m) => "Resource exhausted: \{m}"
    @core.JobPending => "Job pending"
    @core.InvalidDataSize => "Invalid data size"
    @core.InvalidPassword => "Invalid password"
    @core.NeedPassword => "Password required"
    @core.FunNotAvailable => "Function not available"
    @core.DataOverPdu => "Data exceeds PDU size"
    @core.CpuError(c) => "CPU error: \{c.to_string()}"
    @core.InvalidResponse(m) => "Invalid response: \{m}"
  }
}

///|
/// Convert CpuStatus to a human-readable string
pub fn cpu_status_to_string(s : @protocol.CpuStatus) -> String {
  match s {
    @protocol.Run => "RUN"
    @protocol.Stop => "STOP"
    @protocol.Unknown => "UNKNOWN"
  }
}

///|
/// Convert a byte array to a hex dump string (e.g. "AB CD EF")
pub fn hex_dump(data : Array[Byte]) -> String {
  let mut s = ""
  let n = data.length()
  for i in 0..<n {
    if i > 0 {
      s = s + " "
    }
    let b = data[i].to_int()
    let hi = (b >> 4) & 0xF
    let lo = b & 0xF
    s = s + hex_char(hi) + hex_char(lo)
  }
  s
}

///|
fn hex_char(v : Int) -> String {
  match v {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "A"
    11 => "B"
    12 => "C"
    13 => "D"
    14 => "E"
    15 => "F"
    _ => "?"
  }
}
