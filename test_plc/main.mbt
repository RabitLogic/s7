///|
/// Run the PLC test - wrapped so main() can call it
async fn run_test() -> Unit {
  let cfg = @transport.TcpConfig::new(
    host="192.168.47.140",
    port=102,
    rack=0,
    slot=1,
  )
  let cl = @client.S7Client::new_with_config(cfg)
  println("🔌 Connecting to PLC at 192.168.47.140:102 ...")

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

  // === DB200 structured read (READ-ONLY) ===
  // DB layout: signal:Bool@0.0, status:Bool@0.1, index:Int@2, code:String@4
  println("\n📖 Reading DB200 structured fields ...")

  // bytes 0..1 -> signal (bit 0), status (bit 1)
  match conn.ag_read(200, 0, 2) {
    Err(e) => println("⚠️  DB200 bool read error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let signal = @protocol.BoolField::from_byte(200, 0, 0, b[0])
      let status = @protocol.BoolField::from_byte(200, 0, 1, b[0])
      println("✅ signal = \{signal.value()}")
      println("✅ status = \{status.value()}")
    }
  }

  // bytes 2..3 -> index (S7 Int, big-endian signed 16-bit)
  match conn.ag_read(200, 2, 2) {
    Err(e) => println("⚠️  DB200 index read error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let u = @protocol.WordField::new(200, 2, b).value()
      let idx = if u >= 32768 { u - 65536 } else { u }
      println("✅ index = \{idx}")
    }
  }

  // bytes 4.. -> code (S7 String: [max_len, cur_len, chars...])
  match conn.ag_read(200, 4, 32) {
    Err(e) => println("⚠️  DB200 code read error: \{@utils.err_to_string(e)}")
    Ok(b) => {
      let cur = b[1].to_int()
      let mut s = ""
      for i in 2..<b.length() {
        if i - 2 >= cur {
          break
        }
        s = s + b[i].to_string()
      }
      println("✅ code = '\{s}'")
    }
  }

  // Raw dump for reference
  match conn.ag_read(200, 0, 40) {
    Err(e) => println("⚠️  DB200 raw read error: \{@utils.err_to_string(e)}")
    Ok(data) => println("   raw[0..40]: \{@utils.hex_dump(data)}")
  }

  println("\n🎉 Test complete!")
}

///|
async fn main {
  run_test()
}
