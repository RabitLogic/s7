// Tests for protocol items

///|
test "ReadItem" {
  let r = ReadItem::new(Area::db(1), 100, DataType::byte())
  inspect(r.byte_offset, content="100")
  inspect(r.count, content="1")
}

///|
test "WriteItem" {
  let w = WriteItem::new(Area::db(1), 100, DataType::byte(), [0x42])
  inspect(w.byte_offset, content="100")
  inspect(w.data.length(), content="1")
}
