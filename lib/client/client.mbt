///|
/// S7 Client - async, uses pre-negotiated TcpConnection
pub type S7Result[T] = @lib.S7Result[T]

///|
pub type S7Error = @lib.S7Error

///|
pub struct S7Client {
  tcp : @transport.TcpConnection
  connected : Bool
  pdu_ref : Int
  pdu_size : Int
}

///|
pub fn S7Client::new() -> S7Client {
  {
    tcp: @transport.TcpConnection::new(@transport.TcpConfig::new()),
    connected: false,
    pdu_ref: 1,
    pdu_size: 480,
  }
}

///|
pub fn S7Client::new_with_config(c : @transport.TcpConfig) -> S7Client {
  {
    tcp: @transport.TcpConnection::new(c),
    connected: false,
    pdu_ref: 1,
    pdu_size: 480,
  }
}

///|
/// Connect to PLC — TcpConnection::connect() handles TCP + COTP + PDU negotiation
pub async fn S7Client::connect(self : Self) -> S7Result[S7Client] {
  if self.connected {
    return Err(S7Error::already_connected())
  }
  let tc = match self.tcp.connect() {
    Err(e) => return Err(e)
    Ok(c) => c
  }
  Ok({
    tcp: tc,
    connected: true,
    pdu_ref: tc.pdu_ref + 1,
    pdu_size: tc.pdu_length(),
  })
}

///|
pub fn S7Client::disconnect(self : Self) -> Unit {
  if self.connected {
    self.tcp.disconnect()
  }
}

///|
pub fn S7Client::is_connected(self : Self) -> Bool {
  self.connected
}

// ===== DB Read/Write =====

///|
pub async fn S7Client::ag_read(
  self : Self,
  db : Int,
  start : Int,
  size : Int,
) -> S7Result[Array[Byte]] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  chunked_read(self, @protocol.Area::db(db), start, size)
}

///|
pub async fn S7Client::ag_write(
  self : Self,
  db : Int,
  start : Int,
  data : Array[Byte],
) -> S7Result[Unit] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  let item = @protocol.WriteItem::db(
    db,
    start,
    @protocol.DataType::byte(),
    data,
  )
  exec_write(self, [item])
}

// ===== Process Inputs =====

///|
pub async fn S7Client::eb_read(
  self : Self,
  start : Int,
  size : Int,
) -> S7Result[Array[Byte]] {
  chunked_read(self, @protocol.Area::inputs(), start, size)
}

///|
pub async fn S7Client::eb_write(
  self : Self,
  start : Int,
  data : Array[Byte],
) -> S7Result[Unit] {
  let item = @protocol.WriteItem::new(
    @protocol.Area::inputs(),
    start,
    @protocol.DataType::byte(),
    data,
  )
  exec_write(self, [item])
}

// ===== Process Outputs =====

///|
pub async fn S7Client::ab_read(
  self : Self,
  start : Int,
  size : Int,
) -> S7Result[Array[Byte]] {
  chunked_read(self, @protocol.Area::outputs(), start, size)
}

///|
pub async fn S7Client::ab_write(
  self : Self,
  start : Int,
  data : Array[Byte],
) -> S7Result[Unit] {
  let item = @protocol.WriteItem::new(
    @protocol.Area::outputs(),
    start,
    @protocol.DataType::byte(),
    data,
  )
  exec_write(self, [item])
}

// ===== Flags =====

///|
pub async fn S7Client::mb_read(
  self : Self,
  start : Int,
  size : Int,
) -> S7Result[Array[Byte]] {
  chunked_read(self, @protocol.Area::flags(), start, size)
}

///|
pub async fn S7Client::mb_write(
  self : Self,
  start : Int,
  data : Array[Byte],
) -> S7Result[Unit] {
  let item = @protocol.WriteItem::flag(start, @protocol.DataType::byte(), data)
  exec_write(self, [item])
}

// ===== PLC Control =====

///|
pub async fn S7Client::plc_start(self : Self) -> S7Result[Unit] {
  do_ctrl(self, @protocol.build_plc_start_pdu(self.pdu_ref))
}

///|
pub async fn S7Client::plc_stop(self : Self) -> S7Result[Unit] {
  do_ctrl(self, @protocol.build_plc_stop_pdu(self.pdu_ref))
}

///|
pub async fn S7Client::plc_restart(self : Self) -> S7Result[Unit] {
  do_ctrl(self, @protocol.build_plc_restart_pdu(self.pdu_ref))
}

///|
pub fn S7Client::plc_status(self : Self) -> S7Result[@protocol.CpuStatus] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  match self.tcp.send_raw(@protocol.build_plc_status_pdu(self.pdu_ref)) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let resp = match self.tcp.receive(self.pdu_size) {
    Err(e) => return Err(e)
    Ok(d) => d
  }
  @protocol.parse_plc_status(resp)
}

///|
pub async fn S7Client::cpu_info(self : Self) -> S7Result[@protocol.CpuInfo] {
  szl_read(self, 0x001C, 0x000, 205)
}

///|
pub async fn S7Client::cp_info(self : Self) -> S7Result[@protocol.CPInfo] {
  szl_read_cp(self, 0x0131, 0x000)
}

// ===== Internal: PDU Chunking =====

///|
fn chunked_read(
  cl : S7Client,
  area : @protocol.Area,
  start : Int,
  size : Int,
) -> S7Result[Array[Byte]] {
  if !cl.connected {
    return Err(S7Error::not_connected())
  }
  let pdu = cl.pdu_size
  let overhead = 18
  let max_chunk = if pdu > overhead { pdu - overhead } else { 240 }
  let mut remaining = size
  let result : Array[Byte] = []
  let mut off = 0
  while remaining > 0 {
    let cs = if remaining > max_chunk { max_chunk } else { remaining }
    let item = @protocol.ReadItem::new(
      area,
      start + off,
      @protocol.DataType::byte_array(cs),
    )
    let req = match @protocol.build_read_pdu([item], cl.pdu_ref) {
      Err(e) => return Err(e)
      Ok(p) => p
    }
    match cl.tcp.send_raw(req) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let resp = match cl.tcp.receive(cl.pdu_size) {
      Err(e) => return Err(e)
      Ok(d) => d
    }
    let results = match @protocol.parse_response(resp) {
      Err(e) => return Err(e)
      Ok(r) => r
    }
    if results.length() > 0 {
      for b in results[0] {
        result.push(b)
      }
    }
    remaining -= cs
    off += cs
  }
  if result.length() == 0 {
    return Err(S7Error::item_not_found("No data"))
  }
  Ok(result)
}

///|
fn exec_write(
  cl : S7Client,
  items : Array[@protocol.WriteItem],
) -> S7Result[Unit] {
  let req = match @protocol.build_write_pdu(items, cl.pdu_ref) {
    Err(e) => return Err(e)
    Ok(p) => p
  }
  match cl.tcp.send_raw(req) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match cl.tcp.receive(cl.pdu_size) {
    Err(e) => return Err(e)
    Ok(_) => Ok(())
  }
}

///|
fn do_ctrl(cl : S7Client, pdu : Array[Byte]) -> S7Result[Unit] {
  if !cl.connected {
    return Err(S7Error::not_connected())
  }
  match cl.tcp.send_raw(pdu) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let resp = match cl.tcp.receive(cl.pdu_size) {
    Err(e) => return Err(e)
    Ok(d) => d
  }
  @protocol.parse_plc_ctrl_resp(resp)
}

///|
fn szl_read(
  cl : S7Client,
  id : Int,
  index : Int,
  _min : Int,
) -> S7Result[@protocol.CpuInfo] {
  if !cl.connected {
    return Err(S7Error::not_connected())
  }
  let req = @protocol.build_szl_first_pdu(cl.pdu_ref, id, index)
  match cl.tcp.send_raw(req) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let resp = match cl.tcp.receive(cl.pdu_size) {
    Err(e) => return Err(e)
    Ok(d) => d
  }
  let szl = match @protocol.parse_szl_first(resp) {
    Err(e) => return Err(e)
    Ok(s) => s
  }
  if szl.data.length() < _min {
    let req2 = @protocol.build_szl_next_pdu(cl.pdu_ref, cl.pdu_ref)
    match cl.tcp.send_raw(req2) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    let resp2 = match cl.tcp.receive(cl.pdu_size) {
      Err(e) => return Err(e)
      Ok(d) => d
    }
    let szl2 = match @protocol.parse_szl_first(resp2) {
      Err(e) => return Err(e)
      Ok(s) => s
    }
    let combined = szl.data
    for b in szl2.data {
      combined.push(b)
    }
    @protocol.parse_cpu_info(combined)
  } else {
    @protocol.parse_cpu_info(szl.data)
  }
}

///|
fn szl_read_cp(
  cl : S7Client,
  id : Int,
  index : Int,
) -> S7Result[@protocol.CPInfo] {
  if !cl.connected {
    return Err(S7Error::not_connected())
  }
  let req = @protocol.build_szl_first_pdu(cl.pdu_ref, id, index)
  match cl.tcp.send_raw(req) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let resp = match cl.tcp.receive(cl.pdu_size) {
    Err(e) => return Err(e)
    Ok(d) => d
  }
  let szl = match @protocol.parse_szl_first(resp) {
    Err(e) => return Err(e)
    Ok(s) => s
  }
  @protocol.parse_cp_info(szl.data)
}
