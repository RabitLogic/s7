///|
pub struct ReadItem {
  area : Area
  byte_offset : Int
  bit_offset : Int
  count : Int
  data_type : DataType
  word_len : Int
}

///|
pub struct WriteItem {
  area : Area
  byte_offset : Int
  bit_offset : Int
  data_type : DataType
  data : Array[Byte]
  word_len : Int
}

///|
pub fn ReadItem::new(area : Area, off : Int, dt : DataType) -> ReadItem {
  {
    area,
    byte_offset: off,
    bit_offset: 0,
    count: 1,
    data_type: dt,
    word_len: dt_to_word_len(dt),
  }
}

///|
pub fn ReadItem::with_word_len(
  area : Area,
  off : Int,
  dt : DataType,
  wl : Int,
) -> ReadItem {
  {
    area,
    byte_offset: off,
    bit_offset: 0,
    count: 1,
    data_type: dt,
    word_len: wl,
  }
}

///|
pub fn WriteItem::new(
  area : Area,
  off : Int,
  dt : DataType,
  d : Array[Byte],
) -> WriteItem {
  {
    area,
    byte_offset: off,
    bit_offset: 0,
    data_type: dt,
    data: d,
    word_len: dt_to_word_len(dt),
  }
}

///|
pub fn WriteItem::with_word_len(
  area : Area,
  off : Int,
  dt : DataType,
  d : Array[Byte],
  wl : Int,
) -> WriteItem {
  {
    area,
    byte_offset: off,
    bit_offset: 0,
    data_type: dt,
    data: d,
    word_len: wl,
  }
}

///|
pub fn ReadItem::db(n : Int, off : Int, dt : DataType) -> ReadItem {
  ReadItem::new(DataBlock(n), off, dt)
}

///|
pub fn ReadItem::db_wl(n : Int, off : Int, dt : DataType, wl : Int) -> ReadItem {
  ReadItem::with_word_len(DataBlock(n), off, dt, wl)
}

///|
pub fn ReadItem::flag(off : Int, dt : DataType) -> ReadItem {
  ReadItem::new(Flags, off, dt)
}

///|
pub fn ReadItem::input(off : Int, dt : DataType) -> ReadItem {
  ReadItem::new(ProcessInputs, off, dt)
}

///|
pub fn ReadItem::output(off : Int, dt : DataType) -> ReadItem {
  ReadItem::new(ProcessOutputs, off, dt)
}

///|
pub fn WriteItem::db(
  n : Int,
  off : Int,
  dt : DataType,
  d : Array[Byte],
) -> WriteItem {
  WriteItem::new(DataBlock(n), off, dt, d)
}

///|
pub fn WriteItem::flag(off : Int, dt : DataType, d : Array[Byte]) -> WriteItem {
  WriteItem::new(Flags, off, dt, d)
}
