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

  // === DB200 read/write test (non-destructive: restores original) ===
  println("\n--- DB200 read/write test ---")
  // Snapshot original bytes 0..16
  let orig = match conn.ag_read(200, 0, 16) {
    Err(e) => {
      println("   snapshot read error: \{@utils.err_to_string(e)}")
      return
    }
    Ok(b) => b
  }
  println("   original[0..16]: \{@utils.hex_dump(orig)}")

  // Test pattern: signal=true, status=false, index=5, code="ABC"
  //   byte0=0x01 (signal bit0), byte1=0x00 (status bit1),
  //   byte2-3=0x0005 (index=5), byte4-5=FE 03 + 'A''B''C' (code), rest 0
  let test_data : Array[Byte] = [
    0x01, 0x00, 0x00, 0x05,
    0xFE, 0x03, 0x41, 0x42, 0x43,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]
  match conn.ag_write(200, 0, test_data) {
    Err(e) => println("   write error: \{@utils.err_to_string(e)}")
    Ok(_) => println("   ✅ write OK")
  }
  match conn.ag_read(200, 0, 16) {
    Err(e) => println("   read-back error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let mut same = b.length() == test_data.length()
      if same {
        for i in 0..<b.length() {
          if b[i] != test_data[i] {
            same = false
          }
        }
      }
      println("   read-back[0..16]: \{@utils.hex_dump(b)}")
      println("   write verified: \{same}")
    }
  }

  // Restore original values
  match conn.ag_write(200, 0, orig) {
    Err(e) => println("   restore write error: \{@utils.err_to_string(e)}")
    Ok(_) => println("   ✅ restored original")
  }
  match conn.ag_read(200, 0, 16) {
    Err(e) => println("   restored read error: \{@utils.err_to_string(e)}")
    Ok(b) => println("   restored[0..16]: \{@utils.hex_dump(b)}")
  }
  conn.disconnect()
}

///|
async fn main {
  println("DB200 structured read against real PLCSIM")
  diag("192.168.1.40")
  println("\n🎉 Done")
}






