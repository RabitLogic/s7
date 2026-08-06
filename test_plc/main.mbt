///|
fn make_s7_str_field(s : String) -> Array[Byte] {
  // Build a full 256-byte S7 String field: [max_len, cur_len, chars..., zeros]
  let b = @protocol.encode_s7_string(254, s)
  while b.length() < 256 {
    b.push(0x00)
  }
  b
}

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

  // === DB200 size probe (confirm new test[] structure is live) ===
  println("\n--- DB200 size probe ---")
  let offs = [256, 512, 768, 1024, 1280, 1536, 1792]
  for off in offs {
    match conn.ag_read(200, off, 8) {
      Err(e) => println("   @\{off}: FAIL (\{@utils.err_to_string(e)})")
      Ok(b) => println("   @\{off}: \{@utils.hex_dump(b)}")
    }
  }

  // === DB200 test[] string-array write (persistent) ===
  // test[i] starts at 260 + i*256 (each String = 256 bytes, max 254).
  println("\n--- test[] string-array write ---")
  for i in 0..<6 {
    let off = 260 + i * 256
    match conn.ag_write(200, off, make_s7_str_field("T\{i}")) {
      Err(e) => println("   write test[\{i}]@\{off} error: \{@utils.err_to_string(e)}")
      Ok(_) => println("   ✅ test[\{i}]@\{off} = \"T\{i}\"")
    }
  }
  // Read back the test[] headers and verify each string
  for i in 0..<6 {
    let off = 260 + i * 256
    match conn.ag_read(200, off, 4) {
      Err(e) => println("   read test[\{i}] error: \{@utils.err_to_string(e)}")
      Ok(b) => {
        let cur = b[1].to_int()
        // expect "T\{i}" → chars 'T'(0x54) + digit (0x30+i)
        let ok = b[0].to_int() == 254 && cur == 2 && b[2].to_int() == 84 && b[3].to_int() == 0x30 + i
        println("   test[\{i}]@\{off}: \{@utils.hex_dump(b)}  verify: \{ok}")
      }
    }
  }

  // === Large read test (PDU chunking) ===
  println("\n--- large read test ---")
  for sz in [900, 940, 1000, 1500] {
    match conn.ag_read(200, 0, sz) {
      Err(e) => println("   read \{sz}B error: \{@utils.err_to_string(e)}")
      Ok(b) => println("   read \{sz}B -> got \{b.length()} bytes")
    }
  }

  // === Large write test (> 1 PDU, requires chunking) ===
  println("\n--- large write test (1200B @500, 2 chunks) ---")
  let big2 : Array[Byte] = Array::make(1200, 0x00)
  for i in 0..<1200 {
    big2[i] = (i & 0xFF).to_byte()
  }
  match conn.ag_write(200, 500, big2) {
    Err(e) => println("   large write error: \{@utils.err_to_string(e)}")
    Ok(_) => println("   ✅ large write OK (1200B @500)")
  }
  match conn.ag_read(200, 500, 1200) {
    Err(e) => println("   large read-back error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let mut same = b.length() == 1200
      if same {
        for i in 0..<1200 {
          if b[i] != big2[i] {
            same = false
          }
        }
      }
      println("   large write verified: \{same} (\{b.length()} bytes read back)")
    }
  }
  conn.disconnect()
}

///|
async fn main {
  println("DB200 comprehensive test against real PLCSIM")
  diag("192.168.1.40")
  println("\n🎉 Done")
}






