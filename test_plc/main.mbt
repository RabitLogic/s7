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
  // Elegant string read
  match conn.ag_read_string(200, 4, 254) {
    Err(e) => println("   code read error: \{@utils.err_to_string(e)}")
    Ok(s) => println("   code = '\{s}'")
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

  // === DB200 test[] string-array write (elegant String API) ===
  // test[i] starts at 260 + i*256 (each String = 256 bytes, max 254).
  println("\n--- test[] string-array (ag_write_string / ag_read_string) ---")
  for i in 0..<6 {
    let off = 260 + i * 256
    match conn.ag_write_string(200, off, 254, "T\{i}") {
      Err(e) => println("   write test[\{i}] error: \{@utils.err_to_string(e)}")
      Ok(_) => println("   ✅ test[\{i}]@\{off} = \"T\{i}\"")
    }
  }
  for i in 0..<6 {
    let off = 260 + i * 256
    match conn.ag_read_string(200, off, 254) {
      Err(e) => println("   read test[\{i}] error: \{@utils.err_to_string(e)}")
      Ok(s) => println("   test[\{i}]@\{off} = '\{s}'  (expect \"T\{i}\" → \{s == "T\{i}"})")
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

  // === Typed data types test (scratch area @100, inside code padding) ===
  println("\n--- typed data types (Int16/Word/DInt/DWord/Real/Real64/bits) ---")
  let typed : Array[Byte] = []
  typed.append([0x30, 0x39]) // Int16 @100 = 12345
  typed.append([0xD4, 0x31]) // Word  @102 = 54321
  typed.append([0xFF, 0xFE, 0x79, 0x60]) // DInt @104 = -100000
  typed.append([0xEE, 0x6B, 0x28, 0x00]) // DWord @108 = 4000000000
  typed.append(@protocol.f32_to_bytes(3.14)) // Real @112 = 3.14
  typed.append(@protocol.f64_to_bytes(-2.5)) // Real64 @116 = -2.5
  typed.append([0x05]) // bits @124: bit0=1, bit1=0, bit2=1
  match conn.ag_write(200, 100, typed) {
    Err(e) => println("   typed write error: \{@utils.err_to_string(e)}")
    Ok(_) => println("   ✅ typed write OK (25B @100)")
  }
  // Int16 @100
  match conn.ag_read_int(200, 100) {
    Err(e) => println("   Int16 read error: \{@utils.err_to_string(e)}")
    Ok(v) => println("   Int16 @100 = \{v} (expect 12345) → \{v == 12345}")
  }
  // Word @102
  match conn.ag_read_word(200, 102) {
    Err(e) => println("   Word read error: \{@utils.err_to_string(e)}")
    Ok(v) => println("   Word  @102 = \{v} (expect 54321) → \{v == 54321}")
  }
  // DInt @104
  match conn.ag_read_dint(200, 104) {
    Err(e) => println("   DInt read error: \{@utils.err_to_string(e)}")
    Ok(v) => println("   DInt  @104 = \{v} (expect -100000) → \{v == -100000}")
  }
  // DWord @108 — unsigned, now correctly 4000000000 via Int64
  match conn.ag_read_dword(200, 108) {
    Err(e) => println("   DWord read error: \{@utils.err_to_string(e)}")
    Ok(v) => println("   DWord @108 = \{v} (expect 4000000000) → \{v == 4000000000L}")
  }
  // Real @112
  match conn.ag_read(200, 112, 4) {
    Err(e) => println("   Real read error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let ff = @protocol.FloatField::new(200, 112, b)
      let ok = (ff.value() - 3.14).abs() < 0.001
      println("   Real  @112 = \{ff.value()} (expect ~3.14) → \{ok}")
    }
  }
  // Real64 @116
  match conn.ag_read(200, 116, 8) {
    Err(e) => println("   Real64 read error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let df = @protocol.DoubleField::new(200, 116, b)
      let ok = (df.value() - -2.5).abs() < 0.001
      println("   Real64@116 = \{df.value()} (expect -2.5) → \{ok}")
    }
  }
  // bits @124
  match conn.ag_read(200, 124, 1) {
    Err(e) => println("   bits read error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let b0 = @protocol.BoolField::from_byte(200, 124, 0, b[0])
      let b1 = @protocol.BoolField::from_byte(200, 124, 1, b[0])
      let b2 = @protocol.BoolField::from_byte(200, 124, 2, b[0])
      let okbits = b0.value() && (b1.value() == false) && b2.value()
      println("   bits @124: bit0=\{b0.value()} (T), bit1=\{b1.value()} (F), bit2=\{b2.value()} (T) → \{okbits}")
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






