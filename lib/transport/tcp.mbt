// TCP Transport - raw socket FFI for connect + S7 protocol
// connect() handles: TCP connect → COTP CR/CC → PDU setup → ready

///|
#borrow(data)
extern "C" fn platform_send(
  fd : Int,
  data : FixedArray[Byte],
  len : Int,
  flags : Int,
) -> Int = "send"

///|
#owned(buf)
extern "C" fn platform_recv(
  fd : Int,
  buf : FixedArray[Byte],
  len : Int,
  flags : Int,
) -> Int = "recv"

///|
extern "C" fn platform_close(fd : Int) -> Int = "close"

///|
extern "C" fn socket_connect(
  ip : Int,
  port : Int,
) -> Int = "moon_s7_connect"

///|
/// Parse IPv4 string like "172.16.152.1" to u32 integer
fn parse_ip4(host : String) -> Int {
  let mut result = 0
  let mut octet = 0
  let mut dots = 0
  for i in 0..<host.length() {
    let ch = host[i]
    if ch == '.' {
      result = (result << 8) | octet
      octet = 0
      dots = dots + 1
    } else if ch >= '0' && ch <= '9' {
      octet = octet * 10 + (ch.to_int() - 48)
    }
  }
  result = (result << 8) | octet
  result
}

///|
pub struct TcpConfig {
  host : String
  port : Int
  connect_timeout : Int
  read_timeout : Int
  write_timeout : Int
  use_tls : Bool
  local_tsap : Array[Byte]
  remote_tsap : Array[Byte]
  rack : Int
  slot : Int
  conn_type : Int
}

///|
pub fn TcpConfig::new(
  host? : String = "192.168.0.1",
  port? : Int = 102,
  connect_timeout? : Int = 5000,
  read_timeout? : Int = 5000,
  write_timeout? : Int = 5000,
  rack? : Int = 0,
  slot? : Int = 1,
  conn_type? : Int = 1,
) -> TcpConfig {
  {
    host,
    port,
    connect_timeout,
    read_timeout,
    write_timeout,
    use_tls: false,
    local_tsap: [0x01, 0x00],
    remote_tsap: [0x03, slot.to_byte()],
    rack,
    slot,
    conn_type,
  }
}

///|
pub struct TcpConnection {
  config : TcpConfig
  connected : Bool
  fd : Int
  pdu_ref : Int
  pdu_size : Int
  local_tsap : Array[Byte]
  remote_tsap : Array[Byte]
}

///|
pub fn TcpConnection::new(c : TcpConfig) -> TcpConnection {
  {
    config: c,
    connected: false,
    fd: -1,
    pdu_ref: 0,
    pdu_size: 480,
    local_tsap: c.local_tsap,
    remote_tsap: c.remote_tsap,
  }
}

///|
/// TCP connect → COTP CR/CC → S7 PDU setup (sync, native only)
pub fn TcpConnection::connect(self : Self) -> S7Result[TcpConnection] {
  if self.connected {
    return Err(S7Error::already_connected())
  }

  // 1. Parse IP and connect via C FFI
  let ip = parse_ip4(self.config.host)
  println("  parsed IP=\{ip} port=\{self.config.port}")
  let raw_fd = socket_connect(ip, self.config.port)
  if raw_fd < 0 {
    return Err(S7Error::connection_failed(
      "connect to \{self.config.host}:\{self.config.port} failed (code=\{raw_fd})",
    ))
  }
  println("  connected, fd=\{raw_fd}")

  // 2. COTP Connection Request / Confirm
  let cr = @protocol.build_cotp_cr(self.local_tsap, self.remote_tsap)
  println("  COTP CR: \{hex_dump(cr)}")
  if platform_send(raw_fd, to_fa(cr), cr.length(), 0) < 0 {
    let _ = platform_close(raw_fd)
    return Err(S7Error::transport("COTP CR send failed"))
  }
  println("  COTP CR sent, waiting for CC...")
  let cc_buf : FixedArray[Byte] = FixedArray::make(1024, 0x00)
  let cc_n = platform_recv(raw_fd, cc_buf, 1024, 0)
  println("  COTP recv returned \{cc_n} bytes")
  if cc_n < 4 {
    let _ = platform_close(raw_fd)
    return Err(S7Error::transport("COTP CC too short: \{cc_n} bytes"))
  }
  let cc_data : Array[Byte] = []
  for i in 0..<cc_n {
    cc_data.push(cc_buf[i])
  }
  println("  COTP CC data: \{hex_dump(cc_data)}")
  let _cotp = match @protocol.parse_cotp_cc(cc_data) {
    Err(e) => {
      let _ = platform_close(raw_fd)
      return Err(e)
    }
    Ok(tpdu) => tpdu
  }

  // 4. S7 Setup Communication (PDU negotiation)
  let spdu = @protocol.build_setup_pdu(1, 1, 1)
  if platform_send(raw_fd, to_fa(spdu), spdu.length(), 0) < 0 {
    let _ = platform_close(raw_fd)
    return Err(S7Error::transport("Setup PDU send failed"))
  }
  let st_buf : FixedArray[Byte] = FixedArray::make(1024, 0x00)
  let st_n = platform_recv(raw_fd, st_buf, 1024, 0)
  if st_n < 4 {
    let _ = platform_close(raw_fd)
    return Err(S7Error::transport("Setup resp too short"))
  }
  let st_data : Array[Byte] = []
  for i in 0..<st_n {
    st_data.push(st_buf[i])
  }
  let pdu_size = match @protocol.parse_setup_resp(st_data) {
    Err(e) => {
      let _ = platform_close(raw_fd)
      return Err(e)
    }
    Ok(ps) => ps
  }

  Ok({
    config: self.config,
    connected: true,
    fd: raw_fd,
    pdu_ref: 2,
    pdu_size,
    local_tsap: self.local_tsap,
    remote_tsap: self.remote_tsap,
  })
}

///|
pub fn TcpConnection::disconnect(self : Self) -> Unit {
  if self.connected {
    let _ = platform_close(self.fd)
  }
}

///|
fn to_fa(arr : Array[Byte]) -> FixedArray[Byte] {
  let n = arr.length()
  let fa : FixedArray[Byte] = FixedArray::make(n, 0x00)
  for i in 0..<n {
    fa[i] = arr[i]
  }
  fa
}

///|
fn hex_char(v : Int) -> Char {
  if v < 10 { Char::from_int(48 + v) } else { Char::from_int(55 + v) }
}

///|
fn hex_dump(data : Array[Byte]) -> String {
  let mut s = ""
  for i in 0..<data.length() {
    let v = data[i].to_int()
    s = s + hex_char((v >> 4) & 0xF).to_string() + hex_char(v & 0xF).to_string()
    if i < data.length() - 1 { s = s + " " }
  }
  s
}

///|
pub fn TcpConnection::send(
  self : Self,
  data : Array[Byte],
) -> S7Result[Array[Byte]] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  let sb = to_fa(data)
  if platform_send(self.fd, sb, data.length(), 0) < 0 {
    return Err(S7Error::transport("Send failed"))
  }
  let hb : FixedArray[Byte] = FixedArray::make(4, 0x00)
  if platform_recv(self.fd, hb, 4, 0) < 4 {
    return Err(S7Error::transport("Response too short"))
  }
  let rl = (hb[2].to_int() << 8) | hb[3].to_int()
  if rl < 4 {
    return Err(S7Error::invalid_pdu("Invalid TPKT"))
  }
  let bb : FixedArray[Byte] = FixedArray::make(rl - 4, 0x00)
  let bn = platform_recv(self.fd, bb, rl - 4, 0)
  let result : Array[Byte] = []
  for i in 0..<4 {
    result.push(hb[i])
  }
  let cnt = if bn < 0 { 0 } else { bn }
  for i in 0..<cnt {
    result.push(bb[i])
  }
  Ok(result)
}

///|
pub fn TcpConnection::send_raw(
  self : Self,
  data : Array[Byte],
) -> S7Result[Int] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  Ok(platform_send(self.fd, to_fa(data), data.length(), 0))
}

///|
pub fn TcpConnection::receive(
  self : Self,
  len : Int,
) -> S7Result[Array[Byte]] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  let buf : FixedArray[Byte] = FixedArray::make(len, 0x00)
  let n = platform_recv(self.fd, buf, len, 0)
  let result : Array[Byte] = []
  let cnt = if n < 0 { 0 } else { n }
  for i in 0..<cnt {
    result.push(buf[i])
  }
  Ok(result)
}

///|
pub fn TcpConnection::pdu_length(self : Self) -> Int {
  self.pdu_size
}

///|
pub fn TcpConnection::is_connected(self : Self) -> Bool {
  self.connected
}

///|
impl Transport for TcpConnection with fn send(self, data) {
  self.send(data)
}

///|
impl Transport for TcpConnection with fn pdu_length(self) {
  self.pdu_length()
}

///|
impl Transport for TcpConnection with fn is_connected(self) {
  self.is_connected()
}

///|
impl Transport for TcpConnection with fn disconnect(self) {
  self.disconnect()
}

///|
impl Transport for TcpConnection with fn connection_type(_self) {
  ConnType::basic()
}
