// Tests for error types

///|
test "S7Error variants" {
  match S7Error::connection_failed("err") { ConnectionFailed(m) => inspect(m, content="err"); _ => () }
  match S7Error::invalid_pdu("bad") { InvalidPDU(m) => inspect(m, content="bad"); _ => () }
  match S7Error::not_connected() { NotConnected => inspect(true, content="true"); _ => () }
  match S7Error::already_connected() { AlreadyConnected => inspect(true, content="true"); _ => () }
  match S7Error::job_pending() { JobPending => inspect(true, content="true"); _ => () }
}

///|
test "S7Result type" {
  let ok : S7Result[Int] = Ok(42)
  inspect(ok is Ok(_), content="true")
  let err : S7Result[Int] = Err(S7Error::not_connected())
  inspect(err is Err(_), content="true")
}
