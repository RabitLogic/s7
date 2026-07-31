// Tests for helper functions

///|
test "err_to_string" {
  inspect(err_to_string(@core.S7Error::not_connected()), content="Not connected")
  inspect(err_to_string(@core.S7Error::already_connected()), content="Already connected")
  inspect(err_to_string(@core.S7Error::connection_failed("timeout")), content="Connection failed: timeout")
  inspect(err_to_string(@core.S7Error::invalid_pdu("bad data")), content="Invalid PDU: bad data")
  inspect(err_to_string(@core.S7Error::plc_error(10, "error")), content="PLC error (10): error")
  inspect(err_to_string(@core.S7Error::job_pending()), content="Job pending")
  inspect(err_to_string(@core.S7Error::connection_timeout()), content="Connection timeout")
  inspect(err_to_string(@core.S7Error::connection_closed()), content="Connection closed")
}

///|
test "cpu_status_to_string" {
  inspect(cpu_status_to_string(@protocol.CpuStatus::from_u8(0x08)), content="RUN")
  inspect(cpu_status_to_string(@protocol.CpuStatus::from_u8(0x04)), content="STOP")
  inspect(cpu_status_to_string(@protocol.CpuStatus::from_u8(0x00)), content="UNKNOWN")
}

///|
test "hex_dump" {
  inspect(hex_dump([]), content="")
  inspect(hex_dump([0x00]), content="00")
  inspect(hex_dump([0xFF]), content="FF")
  inspect(hex_dump([0xAB, 0xCD, 0xEF]), content="AB CD EF")
  inspect(hex_dump([0x12, 0x34, 0x56, 0x78]), content="12 34 56 78")
  inspect(hex_dump([0x00, 0x01, 0x0A, 0x0F]), content="00 01 0A 0F")
}

///|
test "hex_dump roundtrip" {
  let original : Array[Byte] = [0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE]
  let dump = hex_dump(original)
  inspect(dump, content="DE AD BE EF CA FE BA BE")
}
