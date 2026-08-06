// Tests for S7 PDU building

///|
test "build_setup_pdu" {
  let pdu = build_setup_pdu(1, 1, 1)
  inspect(pdu.length(), content="25")
  // Verify TPKT header
  inspect(pdu[0].to_int(), content="3")
  inspect(pdu[1].to_int(), content="0")
  // TPKT length field must equal the packet size
  inspect(((pdu[2].to_int() << 8) | pdu[3].to_int()), content="25")
  // Param length = 8, function = 0xF0, requested PDU = 960 (PLCSIM-compatible)
  inspect(((pdu[13].to_int() << 8) | pdu[14].to_int()), content="8")
  inspect(pdu[17].to_int(), content="240")
  inspect(((pdu[23].to_int() << 8) | pdu[24].to_int()), content="960")
}

///|
test "build_cotp_cr" {
  let cr = build_cotp_cr([0x01, 0x00], [0x01, 0x01])
  inspect(cr.length(), content="22")
  // Verify COTP CR header
  inspect(cr[4].to_int(), content="17") // 0x11 = CR
  inspect(cr[5].to_int(), content="224") // 0xE0 = DST ref
}

///|
test "build_cotp_cr custom_tsap" {
  let cr = build_cotp_cr([0x01, 0x02], [0x03, 0x04])
  inspect(cr.length(), content="22")
}

///|
test "build_read_write_pdu" {
  let items = [ReadItem::db(1, 0, DataType::byte())]
  let r = build_read_pdu(items, 1)
  inspect(r is Ok(_), content="true")
  match r {
    Ok(pdu) => {
      // S7 header starts at offset 7 (4 TPKT + 3 COTP DT)
      // PID=0x32 at [7], func=0x01 at [8]
      inspect(pdu[7].to_int(), content="50") // 0x32 = PID
      inspect(pdu[8].to_int(), content="1") // 0x01 = read function
    }
    _ => ()
  }

  let witems = [WriteItem::db(1, 0, DataType::byte(), [0x42])]
  let w = build_write_pdu(witems, 1)
  inspect(w is Ok(_), content="true")
  match w {
    Ok(pdu) => {
      inspect(pdu[7].to_int(), content="50") // 0x32 = PID
      inspect(pdu[8].to_int(), content="1") // 0x01 = write function
    }
    _ => ()
  }
}

///|
test "build_read_multiple_items" {
  let items = [
    ReadItem::db(1, 0, DataType::byte()),
    ReadItem::db(1, 4, DataType::word()),
    ReadItem::flag(0, DataType::dword()),
  ]
  let r = build_read_pdu(items, 1)
  inspect(r is Ok(_), content="true")
}

///|
test "PLC control PDUs" {
  inspect(build_plc_start_pdu(1).length(), content="39")
  inspect(build_plc_stop_pdu(2).length(), content="33")
  inspect(build_plc_restart_pdu(1).length(), content="37")
  inspect(build_plc_status_pdu(1).length(), content="33")
  // Verify function codes
  let start = build_plc_start_pdu(1)
  inspect(start[7].to_int(), content="50") // 0x32 = PID
  inspect(start[8].to_int(), content="1") // 0x01 = request
  inspect(start[17].to_int(), content="40") // 0x28 = PDU_START
  inspect(start[14].to_int(), content="22") // param length = 22
  let stop = build_plc_stop_pdu(1)
  inspect(stop[17].to_int(), content="41") // 0x29 = PDU_STOP
  let status = build_plc_status_pdu(1)
  inspect(status[8].to_int(), content="7") // 0x07 = userdata
}

///|
test "SZL PDUs" {
  let szl = build_szl_first_pdu(1, 0x001C, 0x000)
  inspect(szl.length(), content="33")
  // Check SZL ID in PDU (at [29..30])
  inspect(szl[29].to_int(), content="0") // high byte of 0x001C
  inspect(szl[30].to_int(), content="28") // low byte of 0x001C
  // Param length must be 8 (userdata header)
  inspect(szl[14].to_int(), content="8")

  let next = build_szl_next_pdu(2, 1)
  inspect(next.length(), content="33")
  inspect(next[24].to_int(), content="1") // sequence in
}

///|
test "parse_szl_first" {
  // Minimal valid SZL response: header + 2-byte payload starting at [41]
  let resp : Array[Byte] = Array::make(43, 0x00)
  resp[0] = 0x03
  resp[37] = 0x00
  resp[38] = 0x02 // header length field
  resp[39] = 0x00
  resp[40] = 0x01 // record count
  resp[41] = 0xAB // payload[0]
  resp[42] = 0xCD // payload[1]
  match parse_szl_first(resp) {
    Err(e) => fail("parse_szl_first error: \{e}")
    Ok(s) => {
      inspect(s.data.length(), content="2")
      inspect(s.data[0].to_int(), content="171")
      inspect(s.data[1].to_int(), content="205")
      inspect(s.data_count, content="1")
    }
  }
}

///|
/// A standard S7 Ack-Data read response (single item, param length 4,
/// return code 0xFF at index 21, payload starting at index 25) is what a
/// real PLC sends. It must parse to the payload bytes.
///
/// Bytes:
///  03 00 00 1F 02 F0 80 32 03 00 00 00 00 00 04 00 06
///  00 00 00 00 FF 04 00 02 41 42
///  → payload = [0x41, 0x42] ("AB")
test "parse_response standard ack-data" {
  let resp : Array[Byte] = [
    0x03, 0x00, 0x00, 0x1F,
    0x02, 0xF0, 0x80,
    0x32, 0x03, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x04, 0x00, 0x06,
    0x00, 0x00, 0x00, 0x00,
    0xFF, 0x04, 0x00, 0x02,
    0x41, 0x42,
  ]
  match parse_response(resp) {
    Err(e) => fail("parse_response returned error: \{e}")
    Ok(items) => {
      inspect(items.length(), content="1")
      inspect(items[0].length(), content="2")
      inspect(items[0][0].to_int(), content="65")
      inspect(items[0][1].to_int(), content="66")
    }
  }
}

///|
/// An error response (message type 0x83 = Ack-Data with the error flag set)
/// must surface as a PlcError instead of being accepted.
test "parse_response error flag" {
  let resp : Array[Byte] = [
    0x03, 0x00, 0x00, 0x17,
    0x02, 0xF0, 0x80,
    0x32, 0x83, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x03, 0x0A, 0x00, 0x00, 0x00, 0x00,
  ]
  match parse_response(resp) {
    Err(S7Error::PlcError(_, _)) => ()
    Err(other) => fail("expected PlcError, got \{other}")
    Ok(_) => fail("error response should not parse as OK")
  }
}

///|
/// A read item for a non-zero byte offset must encode the address as
/// (offset << 3) | bit as a little-endian 3-byte field. For DB 1, byte 1
/// → addr = 8 → [0x08, 0x00, 0x00].
test "read item address encoding" {
  let items = [ReadItem::db(1, 1, DataType::byte_array(1))]
  match build_read_pdu(items, 1) {
    Err(e) => fail("build failed: \{e}")
    Ok(pdu) => {
      // Item starts at offset 7 (S7) + 10 (header) + 2 (func/count) = 19
      inspect(pdu[19].to_int(), content="18") // var spec 0x12
      inspect(pdu[25].to_int(), content="8") // addr low = 0x08
      inspect(pdu[26].to_int(), content="0") // addr mid
      inspect(pdu[27].to_int(), content="0") // addr high
    }
  }
}

///|
test "parse_cotp_cc" {
  // Valid CC response
  let cc : Array[Byte] = [
    0x03, 0x00, 0x00, 0x16,
    0x11, 0xD0, 0x00, 0x00, 0x00, 0x01, 0x00,
    0xC1, 0x02, 0x01, 0x00,
    0xC2, 0x02, 0x01, 0x01,
    0xC0, 0x01, 0x03,
  ]
  let r = parse_cotp_cc(cc)
  inspect(r is Ok(_), content="true")

  // Too short
  let short = parse_cotp_cc([0x03, 0x00])
  inspect(short is Err(_), content="true")

  // Bad TPKT
  let bad = parse_cotp_cc([0x04, 0x00, 0x00, 0x10, 0x11, 0xD0, 0x00])
  inspect(bad is Err(_), content="true")

  // Not CC
  let notcc = parse_cotp_cc([0x03, 0x00, 0x00, 0x10, 0x11, 0xE0, 0x00])
  inspect(notcc is Err(_), content="true")
}

///|
test "parse_setup_resp" {
  // Valid setup response with PDU size
  let resp : Array[Byte] = [
    0x03, 0x00, 0x00, 0x1C,
    0x02, 0xF0, 0x80,
    0x32, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x00, 0x00, 0x07, 0x00,
    0x00, 0x0F, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
    0x01, 0xE0, // PDU size = 480
    0x00, 0x0A,
  ]
  let r = parse_setup_resp(resp)
  inspect(r, content="Ok(480)")

  // Too short
  let short = parse_setup_resp([0x03, 0x00])
  inspect(short is Err(_), content="true")
}

///|
test "parse_plc_status" {
  // Status = RUN (0x08) at offset 44
  let run : Array[Byte] = Array::make(50, 0x00)
  run[44] = 0x08
  let r = parse_plc_status(run)
  inspect(r, content="Ok(Run)")

  // Status = STOP (0x07)
  let stop : Array[Byte] = Array::make(50, 0x00)
  stop[44] = 0x07
  let s = parse_plc_status(stop)
  inspect(s, content="Ok(Stop)")

  // Unknown
  let unk : Array[Byte] = Array::make(50, 0x00)
  unk[44] = 0x00
  let u = parse_plc_status(unk)
  inspect(u, content="Ok(Unknown)")

  // Too short
  let short = parse_plc_status(Array::make(10, 0x00))
  inspect(short is Err(_), content="true")
}

///|
test "parse_plc_ctrl_resp" {
  // Success response echoes PDU_START (0x28)
  let ok : Array[Byte] = Array::make(20, 0x00)
  ok[17] = 0x28
  ok[18] = 0x00
  let r = parse_plc_ctrl_resp(ok, 0x28, 0x02)
  inspect(r, content="Ok(())")

  // Already in state (sub-code 0x02 = already running)
  let jp : Array[Byte] = Array::make(20, 0x00)
  jp[17] = 0x28
  jp[18] = 0x02
  let j = parse_plc_ctrl_resp(jp, 0x28, 0x02)
  inspect(j, content="Err(JobPending)")

  // Wrong function code
  let bad : Array[Byte] = Array::make(20, 0x00)
  bad[17] = 0x12
  let b = parse_plc_ctrl_resp(bad, 0x28, 0x02)
  inspect(b is Err(_), content="true")

  // Too short
  let short = parse_plc_ctrl_resp(Array::make(10, 0x00), 0x28, 0x02)
  inspect(short is Err(_), content="true")
}

///|
test "parse_response" {
  // Standard S7 Ack-Data read response (single item): param length 4,
  // return code 0xFF at index 21, payload starting at index 25.
  let resp : Array[Byte] = [
    0x03, 0x00, 0x00, 0x1F, // TPKT (len=31)
    0x02, 0xF0, 0x80,       // COTP DT
    0x32, 0x03,             // S7 PID + msg type Ack-Data
    0x00, 0x00,             // reserved
    0x00, 0x01,             // PDU ref
    0x00, 0x04,             // param length = 4
    0x00, 0x08,             // data length = 8
    0x00, 0x00, 0x00, 0x00, // error class/code + reserved (params)
    0xFF, 0x04, 0x00, 0x04, // data header: return code, transport, len
    0xDE, 0xAD, 0xBE, 0xEF, // actual data
  ]
  let r = parse_response(resp)
  inspect(r is Ok(_), content="true")
  match r {
    Ok(items) => {
      inspect(items.length(), content="1")
      inspect(items[0].length(), content="4")
      inspect(items[0][0].to_int(), content="222") // 0xDE
    }
    _ => ()
  }

  // Too short
  let short = parse_response([0x03, 0x00])
  inspect(short is Err(_), content="true")

  // Bad TPKT
  let bad = parse_response([0x04, 0x00, 0x00, 0x10, 0x00])
  inspect(bad is Err(_), content="true")
}

///|
test "parse_cpu_info" {
  // Build a 205-byte CPU info response
  let data : Array[Byte] = Array::make(205, 0x00)
  // Module type name at offset 172
  let mtn = "S7-1200"
  for i in 0..<mtn.length() {
    data[172 + i] = mtn[i].to_int().to_byte()
  }
  // Serial at offset 138
  let sn = "SCE1234567"
  for i in 0..<sn.length() {
    data[138 + i] = sn[i].to_int().to_byte()
  }
  // AS name at offset 2
  let asn = "S7-1200 Station"
  for i in 0..<asn.length() {
    data[2 + i] = asn[i].to_int().to_byte()
  }
  // Copyright at offset 104
  let cp = "Siemens AG 2024"
  for i in 0..<cp.length() {
    data[104 + i] = cp[i].to_int().to_byte()
  }
  // Module name at offset 36
  let mn = "CPU 1214C"
  for i in 0..<mn.length() {
    data[36 + i] = mn[i].to_int().to_byte()
  }

  let r = parse_cpu_info(data)
  inspect(r is Ok(_), content="true")
  // Validate module_type_name starts with 'S' (ASCII 83 = 0x53)
  match r {
    Ok(info) => {
      // Check module_type_name first byte matches 'S'
      let first = if info.module_type_name.length() > 0 {
        info.module_type_name[0].to_int()
      } else {
        0
      }
      inspect(first, content="83") // 'S' is ASCII 83
    }
    _ => ()
  }

  // Too short
  let short = parse_cpu_info(Array::make(100, 0x00))
  inspect(short is Err(_), content="true")
}

///|
test "parse_cp_info" {
  let data : Array[Byte] = Array::make(14, 0x00)
  data[2] = 0x04 // max PDU high
  data[3] = 0xB0 // max PDU low = 1200
  data[4] = 0x00 // max connections high
  data[5] = 0x10 // max connections low = 16
  data[6] = 0x00 // max MPI high
  data[7] = 0x2C // max MPI low = 44
  data[10] = 0x00 // max bus high
  data[11] = 0x64 // max bus low = 100
  let r = parse_cp_info(data)
  inspect(r is Ok(_), content="true")
  match r {
    Ok(info) => {
      inspect(info.max_pdu_length, content="1200")
      inspect(info.max_connections, content="16")
    }
    _ => ()
  }

  // Too short
  let short = parse_cp_info(Array::make(10, 0x00))
  inspect(short is Err(_), content="true")
}
