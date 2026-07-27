// Tests for field types

///|
test "BoolField" {
  let bf = BoolField::new(1, 0, 0)
  inspect(bf.db_number(), content="1"); inspect(bf.offset(), content="0")
  inspect(bf.value(), content="false")
  inspect(BoolField::size(), content="1")
  let on = bf.set_value(true)
  inspect(on.value(), content="true")
}

///|
test "WordField" {
  let wf = WordField::new(1, 0, [0xAB, 0xCD])
  inspect(wf.db_number(), content="1")
  inspect(wf.value(), content="43981")
  inspect(WordField::size(), content="2")
}

///|
test "FloatField" {
  let ff = FloatField::new(1, 0, [0x42, 0x68, 0x00, 0x00])
  inspect(ff.value(), content="58")
  inspect(FloatField::size(), content="4")
}

///|
test "DoubleField" {
  let df = DoubleField::new(1, 0, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
  inspect(df.db_number(), content="1")
  inspect(DoubleField::size(), content="8")
}
