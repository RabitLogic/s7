// TCP Transport stub for WASM/JS targets (compile-only, limited functionality)

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
    remote_tsap: [0x01, 0x00],
    rack,
    slot,
    conn_type,
  }
}

///|
pub struct TcpConnection {
  config : TcpConfig
  connected : Bool
  pdu_ref : Int
  pdu_size : Int
}

///|
pub fn TcpConnection::new(c : TcpConfig) -> TcpConnection {
  { config: c, connected: false, pdu_ref: 0, pdu_size: 480 }
}

///|
pub async fn TcpConnection::connect(
  self : Self,
) -> @lib.S7Result[TcpConnection] {
  if self.connected {
    return Err(@lib.S7Error::already_connected())
  }
  Ok({ config: self.config, connected: true, pdu_ref: 1, pdu_size: 480 })
}

///|
pub fn TcpConnection::disconnect(self : Self) -> Unit {

}

///|
pub async fn TcpConnection::send(
  self : Self,
  _data : Array[Byte],
) -> @lib.S7Result[Array[Byte]] {
  if !self.connected {
    return Err(@lib.S7Error::not_connected())
  }
  Ok(Array::make(1024, 0x00))
}

///|
pub fn TcpConnection::send_raw(
  self : Self,
  data : Array[Byte],
) -> @lib.S7Result[Int] {
  if !self.connected {
    return Err(@lib.S7Error::not_connected())
  }
  Ok(data.length())
}

///|
pub fn TcpConnection::receive(
  self : Self,
  len : Int,
) -> @lib.S7Result[Array[Byte]] {
  if !self.connected {
    return Err(@lib.S7Error::not_connected())
  }
  Ok(Array::make(len, 0x00))
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
