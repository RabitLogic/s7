// TCP Transport - async I/O via moonbitlang/async/socket + @io
// connect() handles: TCP connect → COTP CR/CC → PDU setup → ready

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
    remote_tsap: [0x01, 0x01],
    rack,
    slot,
    conn_type,
  }
}

///|
pub struct TcpConnection {
  config : TcpConfig
  connected : Bool
  tcp : @socket.Tcp?
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
    tcp: None,
    pdu_ref: 0,
    pdu_size: 480,
    local_tsap: c.local_tsap,
    remote_tsap: c.remote_tsap,
  }
}

///|
/// Write all bytes (async), converting any raised error to an S7 error.
async fn write_all(tcp : @socket.Tcp, data : Array[Byte]) -> S7Result[Unit] {
  try {
    tcp.write(to_bytes(data))
    Ok(())
  } catch {
    err => Err(S7Error::transport("Write failed: \{err.to_string()}"))
  }
}

///|
/// Read one complete ISO-on-TCP frame: the 4-byte TPKT header, then the rest
/// of the payload. Uses `read_exactly` so partial TCP segments are handled
/// correctly (no data loss on real networks or large responses).
async fn read_tpkt(tcp : @socket.Tcp) -> S7Result[Array[Byte]] {
  try {
    let hdr = tcp.read_exactly(4)
    if hdr[0] != 0x03 {
      return Err(S7Error::invalid_pdu("Bad TPKT"))
    }
    let total = (hdr[2].to_int() << 8) | hdr[3].to_int()
    if total < 4 {
      return Err(S7Error::invalid_pdu("Invalid TPKT length"))
    }
    let body = tcp.read_exactly(total - 4)
    let result : Array[Byte] = []
    for i in 0..<4 {
      result.push(hdr[i])
    }
    for i in 0..<body.length() {
      result.push(body[i])
    }
    Ok(result)
  } catch {
    _ => Err(S7Error::connection_closed())
  }
}

///|
/// COTP Connection Request/Confirm + S7 Setup Communication negotiation.
async fn negotiate(
  local_tsap : Array[Byte],
  remote_tsap : Array[Byte],
  sock : @socket.Tcp,
) -> S7Result[Int] {
  // COTP Connection Request / Confirm
  let cr = @protocol.build_cotp_cr(local_tsap, remote_tsap)
  match write_all(sock, cr) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let cc = match read_tpkt(sock) {
    Err(e) => return Err(e)
    Ok(d) => d
  }
  let _cotp = match @protocol.parse_cotp_cc(cc) {
    Err(e) => return Err(e)
    Ok(tpdu) => tpdu
  }

  // S7 Setup Communication (PDU negotiation)
  let spdu = @protocol.build_setup_pdu(1, 1, 1)
  match write_all(sock, spdu) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let st = match read_tpkt(sock) {
    Err(e) => return Err(e)
    Ok(d) => d
  }
  @protocol.parse_setup_resp(st)
}

///|
/// Full async negotiation: TCP connect → COTP CR/CC → S7 PDU setup
pub async fn TcpConnection::connect(self : Self) -> S7Result[TcpConnection] {
  if self.connected {
    return Err(S7Error::already_connected())
  }
  // 1. TCP connect via official async library, bounded by the connect timeout
  let c_res = @async.with_timeout_opt(
    self.config.connect_timeout,
    () => { @socket.Tcp::connect_to_host(self.config.host, port=self.config.port) },
  ) catch {
    err =>
      return Err(
        S7Error::connection_failed(
          "connect to \{self.config.host}:\{self.config.port}: \{err.to_string()}",
        ),
      )
  }
  let sock = match c_res {
    None => return Err(S7Error::connection_timeout())
    Some(s) => s
  }

  // 2/3. COTP CR/CC + S7 PDU negotiation, bounded by the connect timeout.
  // Reads use read_exactly so partial TCP segments are handled correctly.
  let neg_res = @async.with_timeout_opt(self.config.connect_timeout) <| () => {
    negotiate(self.local_tsap, self.remote_tsap, sock)
  }
  let pdu_size = match neg_res {
    None => {
      sock.close()
      return Err(S7Error::connection_timeout())
    }
    Some(Ok(ps)) => ps
    Some(Err(e)) => {
      sock.close()
      return Err(e)
    }
  }

  Ok({
    config: self.config,
    connected: true,
    tcp: Some(sock),
    pdu_ref: 2,
    pdu_size,
    local_tsap: self.local_tsap,
    remote_tsap: self.remote_tsap,
  })
}

///|
pub fn TcpConnection::disconnect(self : Self) -> Unit {
  match self.tcp {
    Some(tcp) => tcp.close()
    None => ()
  }
}

///|
fn to_bytes(arr : Array[Byte]) -> Bytes {
  let n = arr.length()
  let fa : FixedArray[Byte] = FixedArray::make(n, 0x00)
  for i in 0..<n {
    fa[i] = arr[i]
  }
  fa.unsafe_reinterpret_as_bytes()
}

///|
pub async fn TcpConnection::send(
  self : Self,
  data : Array[Byte],
) -> S7Result[Array[Byte]] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  match self.tcp {
    None => Err(S7Error::not_connected())
    Some(tcp) => {
      // Write the request with a timeout
      let wres = @async.with_timeout_opt(self.config.write_timeout) <| () => {
        write_all(tcp, data)
      }
      match wres {
        None => return Err(S7Error::timeout("write timeout"))
        Some(Ok(_)) => ()
        Some(Err(e)) => return Err(e)
      }
      // Read the full TPKT-framed response with a timeout
      let rres = @async.with_timeout_opt(self.config.read_timeout) <| () => {
        read_tpkt(tcp)
      }
      match rres {
        None => Err(S7Error::timeout("read timeout"))
        Some(Ok(d)) => Ok(d)
        Some(Err(e)) => Err(e)
      }
    }
  }
}

///|
pub async fn TcpConnection::send_raw(
  self : Self,
  data : Array[Byte],
) -> S7Result[Int] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  match self.tcp {
    None => Err(S7Error::not_connected())
    Some(tcp) => {
      let wres = @async.with_timeout_opt(self.config.write_timeout) <| () => {
        write_all(tcp, data)
      }
      match wres {
        None => Err(S7Error::timeout("write timeout"))
        Some(Ok(_)) => Ok(data.length())
        Some(Err(e)) => Err(e)
      }
    }
  }
}

///|
pub async fn TcpConnection::receive(
  self : Self,
  _len : Int,
) -> S7Result[Array[Byte]] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  match self.tcp {
    None => Err(S7Error::not_connected())
    Some(tcp) => {
      // Read the complete TPKT-framed response (handles partial segments)
      let rres = @async.with_timeout_opt(self.config.read_timeout) <| () => {
        read_tpkt(tcp)
      }
      match rres {
        None => Err(S7Error::timeout("read timeout"))
        Some(Ok(d)) => Ok(d)
        Some(Err(e)) => Err(e)
      }
    }
  }
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
