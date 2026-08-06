///|
async fn diag(host : String) -> Unit {
  let cfg = @transport.TcpConfig::new(
    host=host,
    port=102,
    rack=0,
    slot=1,
  )
  let cl = @client.S7Client::new_with_config(cfg)
  println("\n=== Diag \{host} (Basic TSAP) ===")
  let conn = match cl.connect() {
    Err(e) => {
      println("❌ Connect failed: \{@utils.err_to_string(e)}")
      return
    }
    Ok(c) => c
  }
  match conn.plc_status() {
    Err(e) => println("   status error: \{@utils.err_to_string(e)}")
    Ok(s) => println("   CPU status: \{@utils.cpu_status_to_string(s)}")
  }
  // DB200 structured read (READ-ONLY):
  //   signal Bool @ 0.0, status Bool @ 0.1, index Int @ 2, code String @ 4
  match conn.ag_read(200, 0, 2) {
    Err(e) => println("   DB200 bool read error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let signal = @protocol.BoolField::from_byte(200, 0, 0, b[0])
      let status = @protocol.BoolField::from_byte(200, 0, 1, b[0])
      println("   signal = \{signal.value()}, status = \{status.value()}")
    }
  }
  match conn.ag_read(200, 2, 2) {
    Err(e) => println("   DB200 index read error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let u = @protocol.WordField::new(200, 2, b).value()
      let idx = if u >= 32768 { u - 65536 } else { u }
      println("   index = \{idx}")
    }
  }
  match conn.ag_read(200, 4, 32) {
    Err(e) => println("   DB200 code read error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let cur = b[1].to_int()
      let mut s = ""
      for i in 2..<b.length() {
        if i - 2 >= cur {
          break
        }
        s = s + b[i].to_string()
      }
      println("   code = '\{s}'")
    }
  }

  // === DB200 write test (persistent — values are NOT restored) ===
  println("\n--- DB200 write test (persistent) ---")
  // Offset 0: structured fields — signal=true, status=false, index=5, code="ABC"
  let data0 : Array[Byte] = [
    0x01, 0x00, 0x00, 0x05, // signal(bit0)=1, status(bit1)=0, index=5
    0xFE, 0x03, 0x41, 0x42, 0x43, // code: max=254, len=3, "ABC"
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]
  match conn.ag_write(200, 0, data0) {
    Err(e) => println("   write@0 error: \{@utils.err_to_string(e)}")
    Ok(_) => println("   ✅ write@0 (16B): signal=true, index=5, code=ABC")
  }
  // Offset 16: 16-byte ascending pattern
  let data16 : Array[Byte] = [
    0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,
    0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
  ]
  match conn.ag_write(200, 16, data16) {
    Err(e) => println("   write@16 error: \{@utils.err_to_string(e)}")
    Ok(_) => println("   ✅ write@16 (16B): 10 11 12 ... 1F")
  }
  // Offset 40: 8-byte pattern
  let data40 : Array[Byte] = [
    0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04,
  ]
  match conn.ag_write(200, 40, data40) {
    Err(e) => println("   write@40 error: \{@utils.err_to_string(e)}")
    Ok(_) => println("   ✅ write@40 (8B): DE AD BE EF 01 02 03 04")
  }
  // Read back 48 bytes and verify all three regions
  match conn.ag_read(200, 0, 48) {
    Err(e) => println("   read-back error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      println("   read-back[0..48]: \{@utils.hex_dump(b)}")
      let mut same0 = true
      for i in 0..<data0.length() {
        if b[i] != data0[i] {
          same0 = false
        }
      }
      println("   verify @0  : \{same0}")
      let mut same16 = true
      for i in 0..<data16.length() {
        if b[16 + i] != data16[i] {
          same16 = false
        }
      }
      println("   verify @16 : \{same16}")
      let mut same40 = true
      for i in 0..<data40.length() {
        if b[40 + i] != data40[i] {
          same40 = false
        }
      }
      println("   verify @40 : \{same40}")
    }
  }
  conn.disconnect()
}

///|
async fn main {
  println("DB200 persistent write test against real PLCSIM")
  diag("192.168.1.40")
  println("\n🎉 Done")
}






