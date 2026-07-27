// TCP Transport - full async negotiation via moonbitlang/async/socket
// connect() handles: TCP connect → COTP CR/CC → PDU setup → ready

#borrow(data)
extern "C" fn platform_send(fd : Int, data : FixedArray[Byte], len : Int, flags : Int) -> Int = "send"
#owned(buf)
extern "C" fn platform_recv(fd : Int, buf : FixedArray[Byte], len : Int, flags : Int) -> Int = "recv"
extern "C" fn platform_close(fd : Int) -> Int = "close"

pub struct TcpConfig {
  host : String; port : Int
  connect_timeout : Int; read_timeout : Int; write_timeout : Int
  use_tls : Bool
  local_tsap : Array[Byte]; remote_tsap : Array[Byte]
  rack : Int; slot : Int; conn_type : Int
}

pub fn TcpConfig::new(
  host? : String = "192.168.0.1", port? : Int = 102,
  connect_timeout? : Int = 5000, read_timeout? : Int = 5000,
  write_timeout? : Int = 5000,
  rack? : Int = 0, slot? : Int = 1, conn_type? : Int = 1,
) -> TcpConfig {
  { host: host, port: port, connect_timeout: connect_timeout,
    read_timeout: read_timeout, write_timeout: write_timeout,
    use_tls: false, local_tsap: [0x01, 0x00], remote_tsap: [0x01, 0x01],
    rack: rack, slot: slot, conn_type: conn_type }
}

pub struct TcpConnection {
  config : TcpConfig
  connected : Bool
  fd : Int
  pdu_ref : Int; pdu_size : Int
  local_tsap : Array[Byte]; remote_tsap : Array[Byte]
}

pub fn TcpConnection::new(c : TcpConfig) -> TcpConnection {
  { config: c, connected: false, fd: -1, pdu_ref: 0, pdu_size: 480,
    local_tsap: c.local_tsap, remote_tsap: c.remote_tsap }
}

/// Full async negotiation: TCP connect → COTP CR/CC → S7 PDU setup
pub async fn TcpConnection::connect(self : Self) -> S7Result[TcpConnection] {
  if self.connected { return Err(S7Error::already_connected()) }
  // 1. TCP connect via official async library
  let sock = try {
    @socket.Tcp::connect_to_host(self.config.host, port=self.config.port)
  } catch {
    err => return Err(S7Error::connection_failed("connect to \{self.config.host}:\{self.config.port}: \{err.to_string()}"))
  }
  let fd = sock.fd()

  // 2. COTP Connection Request / Confirm
  let cr = @protocol.build_cotp_cr(self.local_tsap, self.remote_tsap)
  if platform_send(fd, to_fa(cr), cr.length(), 0) < 0 {
    let _ = platform_close(fd); return Err(S7Error::transport("COTP CR send failed"))
  }
  let cc_buf : FixedArray[Byte] = FixedArray::make(1024, 0x00)
  let cc_n = platform_recv(fd, cc_buf, 1024, 0)
  if cc_n < 4 { let _ = platform_close(fd); return Err(S7Error::transport("COTP CC too short")) }
  let cc_data : Array[Byte] = []
  for i in 0..<cc_n { cc_data.push(cc_buf[i]) }
  let _cotp = match @protocol.parse_cotp_cc(cc_data) {
    Err(e) => { let _ = platform_close(fd); return Err(e) }
    Ok(tpdu) => tpdu
  }

  // 3. S7 Setup Communication (PDU negotiation)
  let spdu = @protocol.build_setup_pdu(1, 1, 1)
  if platform_send(fd, to_fa(spdu), spdu.length(), 0) < 0 {
    let _ = platform_close(fd); return Err(S7Error::transport("Setup PDU send failed"))
  }
  let st_buf : FixedArray[Byte] = FixedArray::make(1024, 0x00)
  let st_n = platform_recv(fd, st_buf, 1024, 0)
  if st_n < 4 { let _ = platform_close(fd); return Err(S7Error::transport("Setup resp too short")) }
  let st_data : Array[Byte] = []
  for i in 0..<st_n { st_data.push(st_buf[i]) }
  let pdu_size = match @protocol.parse_setup_resp(st_data) {
    Err(e) => { let _ = platform_close(fd); return Err(e) }
    Ok(ps) => ps
  }

  Ok({ config: self.config, connected: true, fd: fd, pdu_ref: 2, pdu_size: pdu_size,
    local_tsap: self.local_tsap, remote_tsap: self.remote_tsap })
}

pub fn TcpConnection::disconnect(self : Self) -> Unit {
  if self.connected { let _ = platform_close(self.fd) }
}

fn to_fa(arr : Array[Byte]) -> FixedArray[Byte] {
  let n = arr.length()
  let fa : FixedArray[Byte] = FixedArray::make(n, 0x00)
  for i in 0..<n { fa[i] = arr[i] }
  fa
}

pub async fn TcpConnection::send(self : Self, data : Array[Byte]) -> S7Result[Array[Byte]] {
  if !self.connected { return Err(S7Error::not_connected()) }
  let sb = to_fa(data)
  if platform_send(self.fd, sb, data.length(), 0) < 0 { return Err(S7Error::transport("Send failed")) }
  let hb : FixedArray[Byte] = FixedArray::make(4, 0x00)
  if platform_recv(self.fd, hb, 4, 0) < 4 { return Err(S7Error::transport("Response too short")) }
  let rl = (hb[2].to_int() << 8) | hb[3].to_int()
  if rl < 4 { return Err(S7Error::invalid_pdu("Invalid TPKT")) }
  let bb : FixedArray[Byte] = FixedArray::make(rl - 4, 0x00)
  let bn = platform_recv(self.fd, bb, rl - 4, 0)
  let result : Array[Byte] = []
  for i in 0..<4 { result.push(hb[i]) }
  let cnt = if bn < 0 { 0 } else { bn }
  for i in 0..<cnt { result.push(bb[i]) }
  Ok(result)
}

pub async fn TcpConnection::send_raw(self : Self, data : Array[Byte]) -> S7Result[Int] {
  if !self.connected { return Err(S7Error::not_connected()) }
  Ok(platform_send(self.fd, to_fa(data), data.length(), 0))
}

pub async fn TcpConnection::receive(self : Self, len : Int) -> S7Result[Array[Byte]] {
  if !self.connected { return Err(S7Error::not_connected()) }
  let buf : FixedArray[Byte] = FixedArray::make(len, 0x00)
  let n = platform_recv(self.fd, buf, len, 0)
  let result : Array[Byte] = []
  let cnt = if n < 0 { 0 } else { n }
  for i in 0..<cnt { result.push(buf[i]) }
  Ok(result)
}

pub fn TcpConnection::pdu_length(self : Self) -> Int { self.pdu_size }
pub fn TcpConnection::is_connected(self : Self) -> Bool { self.connected }

impl Transport for TcpConnection with fn send(self, data) { self.send(data) }
impl Transport for TcpConnection with fn pdu_length(self) { self.pdu_length() }
impl Transport for TcpConnection with fn is_connected(self) { self.is_connected() }
impl Transport for TcpConnection with fn disconnect(self) { self.disconnect() }
impl Transport for TcpConnection with fn connection_type(_self) { ConnType::basic() }
