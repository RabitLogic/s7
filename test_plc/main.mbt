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
  conn.disconnect()
}

///|
async fn main {
  println("DB200 structured read against real PLCSIM")
  diag("192.168.1.40")
  println("\n🎉 Done")
}






