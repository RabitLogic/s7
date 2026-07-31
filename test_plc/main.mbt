///|
/// Run the PLC test - wrapped so main() can call it
async fn run_test() -> Unit {
  let cfg = @transport.TcpConfig::new(
    host="172.16.152.131",
    port=102,
    rack=0,
    slot=1,
  )
  let cl = @client.S7Client::new_with_config(cfg)
  println("🔌 Connecting to PLC at 172.16.152.131:102 ...")

  // Connect
  let conn = match cl.connect() {
    Err(e) => {
      println("❌ Connection failed: \{@utils.err_to_string(e)}")
      return
    }
    Ok(c) => c
  }
  defer conn.disconnect()
  println("✅ Connected!")

  // Read CPU status
  println("\n📊 Reading PLC status ...")
  match conn.plc_status() {
    Err(e) => println("⚠️  Status error: \{@utils.err_to_string(e)}")
    Ok(s) => println("✅ CPU status: \{@utils.cpu_status_to_string(s)}")
  }

  // Read CPU info
  println("\n🔍 Reading CPU info ...")
  match conn.cpu_info() {
    Err(e) => println("⚠️  CPU info error: \{@utils.err_to_string(e)}")
    Ok(info) => {
      println("✅ Module type:  \{info.module_type_name}")
      println("   Module name:  \{info.module_name}")
      println("   Serial:       \{info.serial_number}")
      println("   AS Name:      \{info.as_name}")
      println("   Copyright:    \{info.copyright}")
    }
  }

  // Test DB200 read
  println("\n📖 Reading DB200 (10 bytes) ...")
  match conn.ag_read(200, 0, 10) {
    Err(e) => println("⚠️  DB200 read error: \{@utils.err_to_string(e)}")
    Ok(data) => {
      println("✅ Read \{data.length().to_string()} bytes from DB200:")
      println("   Hex: \{@utils.hex_dump(data)}")
    }
  }

  // Test DB200 write
  println("\n✏️  Writing 2 bytes to DB200 (offset 0) ...")
  match conn.ag_write(200, 0, [0xAA, 0xBB]) {
    Err(e) => println("⚠️  DB200 write error: \{@utils.err_to_string(e)}")
    Ok(_) => println("✅ Write successful!")
  }

  // Read back to verify
  println("\n📖 Verifying DB200 after write ...")
  match conn.ag_read(200, 0, 10) {
    Err(e) => println("⚠️  DB200 verify read error: \{@utils.err_to_string(e)}")
    Ok(data) => {
      println("✅ Verified: \{data.length().to_string()} bytes from DB200:")
      println("   Hex: \{@utils.hex_dump(data)}")
    }
  }

  println("\n🎉 Test complete!")
}

///|
async fn main {
  run_test()
}
