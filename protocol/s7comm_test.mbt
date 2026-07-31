// Tests for S7 PDU building

///|
test "build_setup_pdu" {
  let pdu = build_setup_pdu(1, 1, 1)
  inspect(pdu.length(), content="22")
  // Verify TPKT header
  inspect(pdu[0].to_int(), content="3")
  inspect(pdu[1].to_int(), content="0")
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
  inspect(build_plc_start_pdu(1).length(), content="33")
  inspect(build_plc_stop_pdu(2).length(), content="33")
  inspect(build_plc_restart_pdu(1).length(), content="33")
  inspect(build_plc_status_pdu(1).length(), content="33")
  // Verify function codes
  let start = build_plc_start_pdu(1)
  inspect(start[7].to_int(), content="50") // 0x32 = PID
  inspect(start[8].to_int(), content="1") // 0x01 = request
  let status = build_plc_status_pdu(1)
  inspect(status[8].to_int(), content="7") // 0x07 = read SZL
}

///|
test "SZL PDUs" {
  let szl = build_szl_first_pdu(1, 0x001C, 0x000)
  inspect(szl.length(), content="33")
  // Check SZL ID in PDU
  inspect(szl[26].to_int(), content="0") // high byte of 0x001C
  inspect(szl[27].to_int(), content="28") // low byte of 0x001C

  let next = build_szl_next_pdu(2, 1)
  inspect(next.length(), content="33")
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
  // Success response
  let ok : Array[Byte] = Array::make(20, 0x00)
  ok[17] = 0x12
  ok[18] = 0x00
  let r = parse_plc_ctrl_resp(ok)
  inspect(r, content="Ok(())")

  // Job pending
  let jp : Array[Byte] = Array::make(20, 0x00)
  jp[17] = 0x12
  jp[18] = 0x02
  let j = parse_plc_ctrl_resp(jp)
  inspect(j, content="Err(JobPending)")

  // Too short
  let short = parse_plc_ctrl_resp(Array::make(10, 0x00))
  inspect(short is Err(_), content="true")
}

///|
test "parse_response" {
  // Build a minimal valid read response with S7 data
  // S7 header layout (as parsed by parse_response):
  //   s7+0: PID (0x32), s7+1: func, s7+2-3: reserved
  //   s7+4: ref hi, s7+5: ref/plen_hi, s7+6: plen_lo,
  //   s7+7: dlen_hi, s7+8: dlen_lo, s7+9: reserved
  let resp : Array[Byte] = [
    0x03, 0x00, 0x00, 0x1F, // TPKT (len=31)
    0x02, 0xF0, 0x80,       // COTP DT
    0x32, 0x01,             // S7 PID + func (find_s7 matches here)
    0x00, 0x00,             // reserved
    0x00, 0x00,             // ref (s7+4/5) - low byte used as plen_hi by parse
    0x00,                   // s7+6: plen_lo = 0
    0x00,                   // s7+7: dlen_hi = 0
    0x04,                   // s7+8: dlen_lo = 4
    0x00,                   // s7+9
    0xFF, 0x04, 0x00, 0x04, // data header: return code, transport, len
    0xDE, 0xAD, 0xBE, 0xEF, // actual data
  ]
  let r = parse_response(resp)
  inspect(r is Ok(_), content="true")
  match r {
    Ok(items) => inspect(items.length(), content="1")
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
test "parse_szl_first" {
  let data : Array[Byte] = Array::make(50, 0x00)
  data[31] = 0x00 // header len high
  data[32] = 0x10 // header len low = 16
  data[33] = 0x00 // data count high
  data[34] = 0x05 // data count low = 5
  data[35] = 0x41 // some data
  data[36] = 0x42
  let r = parse_szl_first(data)
  inspect(r is Ok(_), content="true")
  match r {
    Ok(szl) => {
      inspect(szl.header_len, content="16")
      inspect(szl.data_count, content="5")
      inspect(szl.data.length(), content="15")
    }
    _ => ()
  }

  // Too short
  let short = parse_szl_first(Array::make(30, 0x00))
  inspect(short is Err(_), content="true")
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
