// Tests for TCP config and transport types

///|
test "TcpConfig" {
  let cfg = TcpConfig::new(host="10.0.0.1", port=1050, rack=1, slot=3)
  inspect(cfg.host, content="10.0.0.1")
  inspect(cfg.port, content="1050")
  inspect(cfg.rack, content="1")
  inspect(cfg.slot, content="3")
}

///|
test "TcpConnection" {
  let conn = TcpConnection::new(TcpConfig::new())
  inspect(conn.is_connected(), content="false")
  inspect(conn.pdu_length(), content="480")
}

///|
test "CotpConnection" {
  let cotp = CotpConnection::new()
  let cr = cotp.build_cr()
  inspect(cr.length(), content="22")
}
