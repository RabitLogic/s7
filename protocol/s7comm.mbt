///|
pub type S7Result[T] = @core.S7Result[T]

///|
pub type S7Error = @core.S7Error

///|
const PID : Byte = 0x32

///|
const MAX_PDU : Int = 480

///|
const PR : Byte = 0x04

///|
const PW : Byte = 0x05

///|
fn hi8(v : Int) -> Byte {
  ((v >> 8) & 0xFF).to_byte()
}

///|
fn lo8(v : Int) -> Byte {
  (v & 0xFF).to_byte()
}

///|
fn tb(v : Int) -> Byte {
  v.to_byte()
}

///|
fn cotp_dt() -> Array[Byte] {
  [0x02, 0xF0, 0x80]
}

///|
fn acode(a : Area) -> Byte {
  match a {
    ProcessInputs => tb(0x81)
    ProcessOutputs => tb(0x82)
    Flags => tb(0x83)
    DataBlock(_) => tb(0x84)
    SystemInfo => tb(0x85)
    Timer => tb(0x86)
    Counter => tb(0x87)
    Vendor(v) => tb(v)
  }
}

///|
fn adb(a : Area) -> Int {
  match a {
    DataBlock(v) => v
    _ => 0
  }
}

///|
fn _tscode(dt : DataType) -> Byte {
  match dt {
    Bool => 0x01
    Byte => 0x02
    Char => 0x02
    String => 0x02
    ByteArray(_) => 0x02
    Word => 0x03
    Int => 0x03
    Counter => 0x03
    Timer => 0x03
    S5Time => 0x03
    DWord => 0x04
    DInt => 0x04
    Real => 0x04
    Time => 0x04
    TimeOfDay => 0x04
    Date => 0x09
    DateAndTime => 0x0B
    IecTimer => 0x0B
  }
}

///|
/// Map word_len to transport size byte (TS_RES_*)
fn ts_from_wl(wl : Int) -> Byte {
  match wl {
    WL_BIT => tb(TS_RES_BIT)
    WL_BYTE | WL_CHAR => tb(TS_RES_BYTE)
    WL_WORD | WL_INT | WL_COUNTER | WL_TIMER => tb(TS_RES_OCTET)
    WL_DWORD | WL_DINT => tb(TS_RES_BYTE)
    WL_REAL => tb(TS_RES_REAL)
    _ => tb(TS_RES_BYTE)
  }
}

///|
fn mk_hdr(mt : Byte, refn : Int, plen : Int, dlen : Int) -> Array[Byte] {
  let b : Array[Byte] = Array::make(10, 0x00)
  b[0] = PID
  b[1] = mt
  b[2] = 0x00
  b[3] = 0x00
  b[4] = hi8(refn)
  b[5] = lo8(refn)
  b[6] = hi8(plen)
  b[7] = lo8(plen)
  b[8] = hi8(dlen)
  b[9] = lo8(dlen)
  b
}

///|
fn find_s7(data : Array[Byte]) -> Int {
  for i in 0..<data.length() {
    if i + 1 < data.length() &&
      data[i] == PID &&
      (data[i + 1] == 0x01 || data[i + 1] == 0x03 || data[i + 1] == 0x07) {
      return i
    }
  }
  -1
}

// ========== Read ==========

///|
pub fn build_read_pdu(
  items : Array[ReadItem],
  refn : Int,
) -> S7Result[Array[Byte]] {
  let n = items.length()
  let params : Array[Byte] = Array::make(2 + n * 12, 0x00)
  params[0] = PR
  params[1] = n.to_byte()
  for i in 0..<n {
    let b = 2 + i * 12
    let it = items[i]
    params[b] = 0x12
    params[b + 1] = 0x0A
    // Use word_len for transport size, fallback to tscode
    params[b + 2] = ts_from_wl(it.word_len)
    let db = adb(it.area)
    params[b + 3] = hi8(db)
    params[b + 4] = lo8(db)
    params[b + 5] = acode(it.area)
    let a = it.byte_offset
    params[b + 6] = lo8(a)
    params[b + 7] = it.bit_offset.to_byte()
    params[b + 8] = 0x00
    params[b + 9] = 0x00
    params[b + 10] = 0x00
    params[b + 11] = it.count.to_byte()
  }
  let hdr = mk_hdr(0x01, refn, params.length(), 0)
  let cd = cotp_dt()
  let total = cd.length() + hdr.length() + params.length()
  if total > MAX_PDU {
    return Err(S7Error::invalid_pdu("PDU too big"))
  }
  let tlen = total + 4
  let pkt : Array[Byte] = Array::make(tlen, 0x00)
  pkt[0] = 0x03
  pkt[1] = 0x00
  pkt[2] = hi8(tlen >> 8)
  pkt[3] = lo8(tlen)
  let mut off = 4
  for i in 0..<cd.length() {
    pkt[off + i] = cd[i]
  }
  off += cd.length()
  for i in 0..<hdr.length() {
    pkt[off + i] = hdr[i]
  }
  off += hdr.length()
  for i in 0..<params.length() {
    pkt[off + i] = params[i]
  }
  Ok(pkt)
}

// ========== Write ==========

///|
pub fn build_write_pdu(
  items : Array[WriteItem],
  refn : Int,
) -> S7Result[Array[Byte]] {
  let n = items.length()
  let params : Array[Byte] = Array::make(2 + n * 12, 0x00)
  let wdata : Array[Byte] = []
  params[0] = PW
  params[1] = n.to_byte()
  for i in 0..<n {
    let b = 2 + i * 12
    let it = items[i]
    let id = it.data
    params[b] = 0x12
    params[b + 1] = 0x0A
    params[b + 2] = ts_from_wl(it.word_len)
    let db = adb(it.area)
    params[b + 3] = hi8(db)
    params[b + 4] = lo8(db)
    params[b + 5] = acode(it.area)
    let a = it.byte_offset
    params[b + 6] = lo8(a)
    params[b + 7] = it.bit_offset.to_byte()
    params[b + 8] = 0x00
    params[b + 9] = 0x00
    params[b + 10] = 0x00
    params[b + 11] = id.length().to_byte()
    wdata.push(0xFF)
    wdata.push(ts_from_wl(it.word_len))
    let dl = id.length()
    wdata.push(hi8(dl))
    wdata.push(lo8(dl))
    for bv in id {
      wdata.push(bv)
    }
  }
  let hdr = mk_hdr(0x01, refn, params.length(), wdata.length())
  let cd = cotp_dt()
  let total = cd.length() + hdr.length() + params.length() + wdata.length()
  if total > MAX_PDU {
    return Err(S7Error::invalid_pdu("PDU too big"))
  }
  let tlen = total + 4
  let pkt : Array[Byte] = Array::make(tlen, 0x00)
  pkt[0] = 0x03
  pkt[1] = 0x00
  pkt[2] = hi8(tlen >> 8)
  pkt[3] = lo8(tlen)
  let mut off = 4
  for i in 0..<cd.length() {
    pkt[off + i] = cd[i]
  }
  off += cd.length()
  for i in 0..<hdr.length() {
    pkt[off + i] = hdr[i]
  }
  off += hdr.length()
  for i in 0..<params.length() {
    pkt[off + i] = params[i]
  }
  off += params.length()
  for i in 0..<wdata.length() {
    pkt[off + i] = wdata[i]
  }
  Ok(pkt)
}

// ========== Parse Response ==========

///|
pub fn parse_response(data : Array[Byte]) -> S7Result[Array[Array[Byte]]] {
  let n = data.length()
  if n < 20 {
    return Err(S7Error::invalid_pdu("Too short"))
  }
  if data[0] != 0x03 {
    return Err(S7Error::invalid_pdu("Bad TPKT"))
  }
  let s7 = find_s7(data)
  if s7 < 0 {
    return Err(S7Error::invalid_pdu("No S7 header"))
  }
  if data[s7 + 1] == 0x03 {
    return Err(S7Error::plc_error(data[s7 + 4].to_int(), "PLC error"))
  }
  let plen = (data[s7 + 5].to_int() << 8) | data[s7 + 6].to_int()
  let dlen = (data[s7 + 7].to_int() << 8) | data[s7 + 8].to_int()
  let ds = s7 + 10 + plen
  if ds + dlen > n {
    return Err(S7Error::invalid_pdu("Data overflow"))
  }
  let items : Array[Array[Byte]] = []
  let mut pos = ds
  while pos < ds + dlen {
    if pos + 4 > n {
      break
    }
    let ilen = (data[pos + 2].to_int() << 8) | data[pos + 3].to_int()
    pos += 4
    if pos + ilen > n {
      break
    }
    let idata : Array[Byte] = Array::make(ilen, 0x00)
    for i in 0..<ilen {
      idata[i] = data[pos + i]
    }
    items.push(idata)
    pos += ilen
  }
  Ok(items)
}

// ========== Setup ==========

///|
pub fn build_setup_pdu(refn : Int, call : Int, called : Int) -> Array[Byte] {
  let pkt : Array[Byte] = Array::make(22, 0x00)
  pkt[0] = 0x03
  pkt[1] = 0x00
  pkt[2] = 0x00
  pkt[3] = 0x16
  pkt[4] = 0x02
  pkt[5] = 0xF0
  pkt[6] = 0x80
  pkt[7] = PID
  pkt[8] = 0x01
  pkt[9] = 0x00
  pkt[10] = hi8(refn)
  pkt[11] = lo8(refn)
  pkt[12] = 0x00
  pkt[13] = 0x00
  pkt[14] = 0x07
  pkt[15] = 0x00
  pkt[16] = 0x00
  pkt[17] = 0xF0
  pkt[18] = 0x00
  pkt[19] = 0x00
  pkt[20] = call.to_byte()
  pkt[21] = called.to_byte()
  pkt
}

///|
pub fn parse_setup_resp(data : Array[Byte]) -> S7Result[Int] {
  if data.length() < 22 {
    return Err(S7Error::invalid_pdu("Too short"))
  }
  if find_s7(data) < 0 {
    return Err(S7Error::invalid_pdu("No S7 header"))
  }
  if data.length() >= 28 {
    Ok((data[25].to_int() << 8) | data[26].to_int())
  } else {
    Ok(480)
  }
}

// ========== COTP ==========

///|
pub fn build_cotp_cr(lsap : Array[Byte], rsap : Array[Byte]) -> Array[Byte] {
  let sl = lsap.length()
  let rl = rsap.length()
  let total = 4 + 7 + 2 + sl + 2 + rl + 3
  let pkt : Array[Byte] = Array::make(total, 0x00)
  pkt[0] = 0x03
  pkt[1] = 0x00
  pkt[2] = hi8(total >> 8)
  pkt[3] = lo8(total)
  pkt[4] = 0x11
  pkt[5] = 0xE0
  pkt[6] = 0x00
  pkt[7] = 0x00
  pkt[8] = 0x00
  pkt[9] = 0x01
  pkt[10] = 0x00
  let mut pos = 11
  pkt[pos] = 0xC1
  pkt[pos + 1] = sl.to_byte()
  pos += 2
  for i in 0..<sl {
    pkt[pos + i] = lsap[i]
  }
  pos += sl
  pkt[pos] = 0xC2
  pkt[pos + 1] = rl.to_byte()
  pos += 2
  for i in 0..<rl {
    pkt[pos + i] = rsap[i]
  }
  pos += rl
  pkt[pos] = 0xC0
  pkt[pos + 1] = 0x01
  pkt[pos + 2] = 0x03
  pkt
}

///|
pub fn parse_cotp_cc(data : Array[Byte]) -> S7Result[Int] {
  if data.length() < 7 {
    return Err(S7Error::invalid_pdu("Too short"))
  }
  if data[0] != 0x03 {
    return Err(S7Error::invalid_pdu("Bad TPKT"))
  }
  if data[4] != 0x11 || data[5] != 0xD0 {
    return Err(S7Error::invalid_pdu("Not CC"))
  }
  Ok(1024)
}

// ========== PLC Control ==========

///|
pub fn build_plc_start_pdu(refn : Int) -> Array[Byte] {
  let pkt : Array[Byte] = Array::make(33, 0x00)
  pkt[0] = 0x03
  pkt[1] = 0x00
  pkt[2] = 0x00
  pkt[3] = 0x21
  pkt[4] = 0x02
  pkt[5] = 0xF0
  pkt[6] = 0x80
  pkt[7] = PID
  pkt[8] = 0x01
  pkt[9] = 0x00
  pkt[10] = hi8(refn)
  pkt[11] = lo8(refn)
  pkt[12] = 0x00
  pkt[13] = 0x00
  pkt[14] = 0x10
  pkt[15] = 0x00
  pkt[16] = 0x00
  pkt[17] = 0x00
  pkt[18] = 0x00
  pkt[19] = 0x04
  pkt[20] = 0x01
  pkt[21] = 0x12
  pkt[22] = 0x08
  pkt[23] = 0x02
  pkt[24] = 0x10
  pkt[25] = 0x00
  pkt
}

///|
pub fn build_plc_stop_pdu(refn : Int) -> Array[Byte] {
  let pkt : Array[Byte] = Array::make(33, 0x00)
  pkt[0] = 0x03
  pkt[1] = 0x00
  pkt[2] = 0x00
  pkt[3] = 0x21
  pkt[4] = 0x02
  pkt[5] = 0xF0
  pkt[6] = 0x80
  pkt[7] = PID
  pkt[8] = 0x01
  pkt[9] = 0x00
  pkt[10] = hi8(refn)
  pkt[11] = lo8(refn)
  pkt[12] = 0x00
  pkt[13] = 0x00
  pkt[14] = 0x10
  pkt[15] = 0x00
  pkt[16] = 0x00
  pkt[17] = 0x29
  pkt[18] = 0x00
  pkt[19] = 0x04
  pkt[20] = 0x01
  pkt[21] = 0x13
  pkt[22] = 0x08
  pkt[23] = 0x02
  pkt[24] = 0x10
  pkt[25] = 0x01
  pkt
}

///|
pub fn build_plc_restart_pdu(refn : Int) -> Array[Byte] {
  let pkt : Array[Byte] = Array::make(33, 0x00)
  pkt[0] = 0x03
  pkt[1] = 0x00
  pkt[2] = 0x00
  pkt[3] = 0x21
  pkt[4] = 0x02
  pkt[5] = 0xF0
  pkt[6] = 0x80
  pkt[7] = PID
  pkt[8] = 0x01
  pkt[9] = 0x00
  pkt[10] = hi8(refn)
  pkt[11] = lo8(refn)
  pkt[12] = 0x00
  pkt[13] = 0x00
  pkt[14] = 0x10
  pkt[15] = 0x00
  pkt[16] = 0x00
  pkt[17] = 0x00
  pkt[18] = 0x00
  pkt[19] = 0x04
  pkt[20] = 0x01
  pkt[21] = 0x12
  pkt[22] = 0x08
  pkt[23] = 0x02
  pkt[24] = 0x10
  pkt[25] = 0x00
  pkt
}

///|
pub fn parse_plc_ctrl_resp(data : Array[Byte]) -> S7Result[Unit] {
  if data.length() < 19 {
    return Err(S7Error::invalid_pdu("Resp too short"))
  }
  if data[17] != 0x12 && data[17] != 0x13 {
    return Err(S7Error::plc_error(data[17].to_int(), "PLC ctrl error"))
  }
  if data[18] == 0x02 {
    return Err(S7Error::job_pending())
  }
  Ok(())
}

// ========== PLC Status ==========

///|
pub fn build_plc_status_pdu(refn : Int) -> Array[Byte] {
  let pkt : Array[Byte] = Array::make(33, 0x00)
  pkt[0] = 0x03
  pkt[1] = 0x00
  pkt[2] = 0x00
  pkt[3] = 0x21
  pkt[4] = 0x02
  pkt[5] = 0xF0
  pkt[6] = 0x80
  pkt[7] = PID
  pkt[8] = 0x07
  pkt[9] = 0x00
  pkt[10] = hi8(refn)
  pkt[11] = lo8(refn)
  pkt[12] = 0x00
  pkt[13] = 0x00
  pkt[14] = 0x08
  pkt[15] = 0x00
  pkt[16] = 0x00
  pkt[17] = 0x00
  pkt[18] = 0x00
  pkt[19] = 0x04
  pkt[20] = 0x01
  pkt[21] = 0x12
  pkt[22] = 0x08
  pkt[23] = 0x02
  pkt[24] = 0x10
  pkt[25] = 0x00
  pkt
}

///|
pub fn parse_plc_status(data : Array[Byte]) -> S7Result[CpuStatus] {
  if data.length() < 45 {
    return Err(S7Error::invalid_pdu("Status too short"))
  }
  let st = data[44]
  if st == 0x08 {
    Ok(Run)
  } else if st == 0x07 {
    Ok(Stop)
  } else {
    Ok(Unknown)
  }
}

// ========== SZL ==========

///|
pub fn build_szl_first_pdu(refn : Int, id : Int, index : Int) -> Array[Byte] {
  let pkt : Array[Byte] = Array::make(33, 0x00)
  pkt[0] = 0x03
  pkt[1] = 0x00
  pkt[2] = 0x00
  pkt[3] = 0x21
  pkt[4] = 0x02
  pkt[5] = 0xF0
  pkt[6] = 0x80
  pkt[7] = PID
  pkt[8] = 0x07
  pkt[9] = 0x00
  pkt[10] = hi8((refn + 1) & 0xFFFF)
  pkt[11] = lo8((refn + 1) & 0xFFFF)
  pkt[12] = 0x00
  pkt[13] = 0x00
  pkt[14] = 0x0C
  pkt[15] = 0x00
  pkt[16] = 0x00
  pkt[17] = 0x12
  pkt[18] = 0x08
  pkt[19] = 0x12
  pkt[20] = 0x44
  pkt[21] = 0x01
  pkt[22] = 0x00
  pkt[23] = 0x01
  pkt[24] = 0x00
  pkt[25] = 0x00
  pkt[26] = hi8(id)
  pkt[27] = lo8(id)
  pkt[28] = hi8(index)
  pkt[29] = lo8(index)
  pkt
}

///|
pub fn build_szl_next_pdu(refn : Int, seq : Int) -> Array[Byte] {
  let pkt : Array[Byte] = Array::make(33, 0x00)
  pkt[0] = 0x03
  pkt[1] = 0x00
  pkt[2] = 0x00
  pkt[3] = 0x21
  pkt[4] = 0x02
  pkt[5] = 0xF0
  pkt[6] = 0x80
  pkt[7] = PID
  pkt[8] = 0x07
  pkt[9] = 0x00
  pkt[10] = hi8((refn + 1) & 0xFFFF)
  pkt[11] = lo8((refn + 1) & 0xFFFF)
  pkt[12] = 0x00
  pkt[13] = 0x00
  pkt[14] = 0x0C
  pkt[15] = 0x00
  pkt[16] = 0x00
  pkt[17] = 0x12
  pkt[18] = 0x08
  pkt[19] = 0x12
  pkt[20] = 0x44
  pkt[21] = 0x01
  pkt[22] = hi8(seq)
  pkt[23] = lo8(seq)
  pkt[24] = 0x00
  pkt[25] = 0x00
  pkt[26] = 0x00
  pkt[27] = 0x00
  pkt[28] = 0x00
  pkt[29] = 0x00
  pkt
}

///|
pub fn parse_szl_first(data : Array[Byte]) -> S7Result[SZLData] {
  if data.length() < 42 {
    return Err(S7Error::invalid_pdu("SZL too short"))
  }
  let hlen = (data[31].to_int() << 8) | data[32].to_int()
  let dcount = (data[33].to_int() << 8) | data[34].to_int()
  let sdata : Array[Byte] = []
  for i in 35..<data.length() {
    sdata.push(data[i])
  }
  Ok({ header_len: hlen, data_count: dcount, data: sdata })
}

///|
pub fn parse_cpu_info(data : Array[Byte]) -> S7Result[CpuInfo] {
  if data.length() < 205 {
    return Err(S7Error::invalid_pdu("CPU info too short"))
  }
  Ok({
    module_type_name: str_slice(data, 172, 32),
    serial_number: str_slice(data, 138, 24),
    as_name: str_slice(data, 2, 24),
    copyright: str_slice(data, 104, 26),
    module_name: str_slice(data, 36, 24),
  })
}

///|
pub fn parse_cp_info(data : Array[Byte]) -> S7Result[CPInfo] {
  if data.length() < 14 {
    return Err(S7Error::invalid_pdu("CP info too short"))
  }
  Ok({
    max_pdu_length: (data[2].to_int() << 8) | data[3].to_int(),
    max_connections: (data[4].to_int() << 8) | data[5].to_int(),
    max_mpi_rate: (data[6].to_int() << 8) | data[7].to_int(),
    max_bus_rate: (data[10].to_int() << 8) | data[11].to_int(),
  })
}

///|
fn str_slice(data : Array[Byte], start : Int, maxlen : Int) -> String {
  let sb = StringBuilder::new()
  let end = if start + maxlen < data.length() {
    start + maxlen
  } else {
    data.length()
  }
  for i in start..<end {
    let b = data[i]
    if b == 0x00 {
      break
    }
    sb.write_char(b.to_int().unsafe_to_char())
  }
  sb.to_string()
}
