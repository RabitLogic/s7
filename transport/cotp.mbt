///|
pub struct CotpConnection {
  local_tsap : Array[Byte]
  remote_tsap : Array[Byte]
  tpdu_size : Int
  connected : Bool
}

///|
pub fn CotpConnection::new() -> CotpConnection {
  {
    local_tsap: [0x01, 0x00],
    remote_tsap: [0x01, 0x01],
    tpdu_size: 1024,
    connected: false,
  }
}

///|
pub fn CotpConnection::build_cr(self : Self) -> Array[Byte] {
  @protocol.build_cotp_cr(self.local_tsap, self.remote_tsap)
}

///|
pub fn CotpConnection::parse_cc(
  self : Self,
  data : Array[Byte],
) -> S7Result[CotpConnection] {
  match @protocol.parse_cotp_cc(data) {
    Err(e) => Err(e)
    Ok(tpdu) =>
      Ok({
        local_tsap: self.local_tsap,
        remote_tsap: self.remote_tsap,
        tpdu_size: tpdu,
        connected: true,
      })
  }
}
