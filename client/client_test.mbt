// Tests for S7Client

///|
test "new client" {
  let cl = S7Client::new()
  inspect(cl.is_connected(), content="false")
}

///|
test "client with config" {
  let cfg = @transport.TcpConfig::new(host="10.0.0.1", port=1050)
  let cl = S7Client::new_with_config(cfg)
  inspect(cl.is_connected(), content="false")
}
