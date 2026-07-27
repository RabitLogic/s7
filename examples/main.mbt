///|
fn main {
  println("=== S7 Library v\{@src.version()} ===")
  let cfg = @transport.TcpConfig::new(
    host="192.168.0.1",
    port=102,
    rack=0,
    slot=1,
  )
  println("Config: \{cfg.host}:\{cfg.port}")
  let cl = @client.S7Client::new_with_config(cfg)
  println("Client ready. Connected: \{cl.is_connected()}")

  // Show all available APIs
  println("")
  println("API Reference:")
  println("  connect/disconnect")
  println("  ag_read/ag_write(db, start, size|data)")
  println("  eb_read/eb_write(start, size|data)  - Process Inputs")
  println("  ab_read/ab_write(start, size|data)  - Process Outputs")
  println("  mb_read/mb_write(start, size|data)  - Flags")
  println("  plc_start/plc_stop/plc_restart")
  println("  plc_status -> CpuStatus")
  println("  cpu_info -> CpuInfo")
  println("  cp_info -> CPInfo")
  println("")
  println("=== Done ===")
}
