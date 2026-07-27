// Tests for S7 PDU building

///|
test "build_setup_pdu" {
  let pdu = build_setup_pdu(1, 1, 1)
  inspect(pdu.length(), content="22")
}

///|
test "build_cotp_cr" {
  let cr = build_cotp_cr([0x01, 0x00], [0x01, 0x01])
  inspect(cr.length(), content="22")
}

///|
test "build_read_write_pdu" {
  let items = [ReadItem::db(1, 0, DataType::byte())]
  inspect(build_read_pdu(items, 1) is Ok(_), content="true")
  let witems = [WriteItem::db(1, 0, DataType::byte(), [0x42])]
  inspect(build_write_pdu(witems, 1) is Ok(_), content="true")
}

///|
test "PLC control PDUs" {
  inspect(build_plc_start_pdu(1).length(), content="33")
  inspect(build_plc_stop_pdu(2).length(), content="33")
  inspect(build_plc_restart_pdu(1).length(), content="33")
  inspect(build_plc_status_pdu(1).length(), content="33")
}

///|
test "SZL PDUs" {
  let szl = build_szl_first_pdu(1, 0x001C, 0x000)
  inspect(szl.length(), content="33")
  let next = build_szl_next_pdu(2, 1)
  inspect(next.length(), content="33")
}
