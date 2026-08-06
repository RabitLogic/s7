///|
/// S7 Client - async, uses pre-negotiated TcpConnection
pub type S7Result[T] = @core.S7Result[T]

///|
pub type S7Error = @core.S7Error

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
  chunked_write(self, @protocol.Area::db(db), start, data)
}

// ===== DB String convenience =====

///|
/// Read an S7 STRING field and decode it to a MoonBit String.
/// `max_len` is the declared max length of the field (e.g. 254 for `String`).
pub async fn S7Client::ag_read_string(
  self : Self,
  db : Int,
  start : Int,
  max_len : Int,
) -> S7Result[String] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  let size = max_len + 2
  match chunked_read(self, @protocol.Area::db(db), start, size) {
    Err(e) => Err(e)
    Ok(data) => Ok(@protocol.decode_s7_string(data))
  }
}

///|
/// Write a MoonBit String into an S7 STRING field (UTF-8 encoded, truncated
/// to `max_len`). Returns the field bytes written.
pub async fn S7Client::ag_write_string(
  self : Self,
  db : Int,
  start : Int,
  max_len : Int,
  value : String,
) -> S7Result[Array[Byte]] {
  if !self.connected {
    return Err(S7Error::not_connected())
  }
  let field = @protocol.StringField::new(db, start, max_len, value)
  let bytes = field.to_bytes()
  match chunked_write(self, @protocol.Area::db(db), start, bytes) {
    Err(e) => Err(e)
    Ok(_) => Ok(bytes)
  }
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
  chunked_write(self, @protocol.Area::inputs(), start, data)
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
  chunked_write(self, @protocol.Area::outputs(), start, data)
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
  chunked_write(self, @protocol.Area::flags(), start, data)
}

// ===== PLC Control =====

///|
pub async fn S7Client::plc_start(self : Self) -> S7Result[Unit] {
  // cold start: expect PDU_START (0x28), already-running = 0x02
  do_ctrl(self, @protocol.build_plc_start_pdu(self.pdu_ref), 0x28, 0x02)
}

///|
pub async fn S7Client::plc_stop(self : Self) -> S7Result[Unit] {
  // stop: expect PDU_STOP (0x29), already-stopped = 0x07
  do_ctrl(self, @protocol.build_plc_stop_pdu(self.pdu_ref), 0x29, 0x07)
}

///|
pub async fn S7Client::plc_restart(self : Self) -> S7Result[Unit] {
  // warm start: expect PDU_START (0x28), already-running = 0x02
  do_ctrl(self, @protocol.build_plc_restart_pdu(self.pdu_ref), 0x28, 0x02)
}

///|
pub async fn S7Client::plc_status(self : Self) -> S7Result[@protocol.CpuStatus] {
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
async fn chunked_read(
  cl : S7Client,
  area : @protocol.Area,
  start : Int,
  size : Int,
) -> S7Result[Array[Byte]] {
  if !cl.connected {
    return Err(S7Error::not_connected())
  }
  let pdu = cl.pdu_size
  // Read response overhead = TPKT(4) + COTP(3) + S7 hdr(10) + params(2) +
  // data item header(4) = 23. Keeping response <= pdu ensures the chunk fits
  // the negotiated PDU on real PLCs (not just PLCSIM Advanced).
  let overhead = 23
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
async fn exec_write(
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
  let resp = match cl.tcp.receive(cl.pdu_size) {
    Err(e) => return Err(e)
    Ok(d) => d
  }
  // Verify the write response return code (0xFF = OK) at full-frame byte 21.
  let s7 = @protocol.find_s7(resp)
  if s7 < 0 || resp.length() <= s7 + 14 {
    return Err(S7Error::invalid_pdu("Bad write response"))
  }
  let rc = resp[s7 + 14].to_int()
  if rc != 0xFF {
    return Err(S7Error::plc_error(rc, "PLC write item error"))
  }
  Ok(())
}

///|
async fn chunked_write(
  cl : S7Client,
  area : @protocol.Area,
  start : Int,
  data : Array[Byte],
) -> S7Result[Unit] {
  if !cl.connected {
    return Err(S7Error::not_connected())
  }
  let pdu = cl.pdu_size
  let overhead = 35
  let max_chunk = if pdu > overhead { pdu - overhead } else { 240 }
  let mut off = 0
  while off < data.length() {
    let cs = if data.length() - off > max_chunk { max_chunk } else { data.length() - off }
    let chunk : Array[Byte] = Array::make(cs, 0x00)
    for i in 0..<cs {
      chunk[i] = data[off + i]
    }
    let item = @protocol.WriteItem::new(
      area,
      start + off,
      @protocol.DataType::byte_array(cs),
      chunk,
    )
    match exec_write(cl, [item]) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    off += cs
  }
  Ok(())
}

///|
async fn do_ctrl(
  cl : S7Client,
  pdu : Array[Byte],
  start_cmp : Byte,
  already_cmp : Byte,
) -> S7Result[Unit] {
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
  @protocol.parse_plc_ctrl_resp(resp, start_cmp, already_cmp)
}

///|
async fn szl_read(
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
async fn szl_read_cp(
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
