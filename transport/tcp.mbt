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
/// Full async negotiation: TCP connect → COTP CR/CC → S7 PDU setup
pub async fn TcpConnection::connect(self : Self) -> S7Result[TcpConnection] {
  if self.connected {
    return Err(S7Error::already_connected())
  }
  // 1. TCP connect via official async library
  let sock = @socket.Tcp::connect_to_host(
    self.config.host,
    port=self.config.port,
  ) catch {
    err =>
      return Err(
        S7Error::connection_failed(
          "connect to \{self.config.host}:\{self.config.port}: \{err.to_string()}",
        ),
      )
  }

  // 2. COTP Connection Request / Confirm
  let cr = @protocol.build_cotp_cr(self.local_tsap, self.remote_tsap)
  try {
    sock.write(to_bytes(cr))
  } catch {
    err => {
      sock.close()
      return Err(S7Error::transport("COTP CR send failed: \{err.to_string()}"))
    }
  }
  let cc_buf : FixedArray[Byte] = FixedArray::make(1024, 0x00)
  let cc_n = try {
    sock.read(cc_buf, max_len=1024)
  } catch {
    err => {
      sock.close()
      return Err(S7Error::transport("COTP CC recv failed: \{err.to_string()}"))
    }
  }
  if cc_n < 4 {
    sock.close()
    return Err(S7Error::transport("COTP CC too short"))
  }
  let cc_data : Array[Byte] = []
  for i in 0..<cc_n {
    cc_data.push(cc_buf[i])
  }
  let _cotp = match @protocol.parse_cotp_cc(cc_data) {
    Err(e) => {
      sock.close()
      return Err(e)
    }
    Ok(tpdu) => tpdu
  }

  // 3. S7 Setup Communication (PDU negotiation)
  let spdu = @protocol.build_setup_pdu(1, 1, 1)
  try {
    sock.write(to_bytes(spdu))
  } catch {
    err => {
      sock.close()
      return Err(S7Error::transport("Setup PDU send failed: \{err.to_string()}"))
    }
  }
  let st_buf : FixedArray[Byte] = FixedArray::make(1024, 0x00)
  let st_n = try {
    sock.read(st_buf, max_len=1024)
  } catch {
    err => {
      sock.close()
      return Err(S7Error::transport("Setup resp recv failed: \{err.to_string()}"))
    }
  }
  if st_n < 4 {
    sock.close()
    return Err(S7Error::transport("Setup resp too short"))
  }
  let st_data : Array[Byte] = []
  for i in 0..<st_n {
    st_data.push(st_buf[i])
  }
  let pdu_size = match @protocol.parse_setup_resp(st_data) {
    Err(e) => {
      sock.close()
      return Err(e)
    }
    Ok(ps) => ps
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
      try {
        tcp.write(to_bytes(data))
      } catch {
        err => return Err(S7Error::transport("Send failed: \{err.to_string()}"))
      }
      let hb : FixedArray[Byte] = FixedArray::make(4, 0x00)
      let hn = try {
        tcp.read(hb, max_len=4)
      } catch {
        err => return Err(S7Error::transport("Response too short: \{err.to_string()}"))
      }
      if hn < 4 {
        return Err(S7Error::transport("Response too short"))
      }
      let rl = (hb[2].to_int() << 8) | hb[3].to_int()
      if rl < 4 {
        return Err(S7Error::invalid_pdu("Invalid TPKT"))
      }
      let bb : FixedArray[Byte] = FixedArray::make(rl - 4, 0x00)
      let bn = try {
        tcp.read(bb, max_len=rl - 4)
      } catch {
        err => return Err(S7Error::transport("Response read failed: \{err.to_string()}"))
      }
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
      try {
        tcp.write(to_bytes(data))
        Ok(data.length())
      } catch {
        err => Err(S7Error::transport("Send failed: \{err.to_string()}"))
      }
    }
  }
}

///|
pub async fn TcpConnection::receive(self : Self, len : Int) -> S7Result[Array[Byte]] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  match self.tcp {
    None => Err(S7Error::not_connected())
    Some(tcp) => {
      let buf : FixedArray[Byte] = FixedArray::make(len, 0x00)
      let n = try {
        tcp.read(buf, max_len=len)
      } catch {
        err => return Err(S7Error::transport("Receive failed: \{err.to_string()}"))
      }
      let result : Array[Byte] = []
      let cnt = if n < 0 { 0 } else { n }
      for i in 0..<cnt {
        result.push(buf[i])
      }
      Ok(result)
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
