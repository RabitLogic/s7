// Tests for field types

///|
test "BoolField" {
  let bf = BoolField::new(1, 0, 0)
  inspect(bf.db_number(), content="1")
  inspect(bf.offset(), content="0")
  inspect(bf.value(), content="false")
  inspect(BoolField::size(), content="1")
  // Toggle on
  let on = bf.set_value(true)
  inspect(on.value(), content="true")
  // Toggle off
  let off = on.set_value(false)
  inspect(off.value(), content="false")
}

///|
test "BoolField from_byte" {
  // byte 0b00100100, bit 2 -> true
  let bf = BoolField::from_byte(1, 0, 2, 0x24)
  inspect(bf.db_number(), content="1")
  inspect(bf.offset(), content="0")
  inspect(bf.value(), content="true")
  // bit 5 -> true
  let bf2 = BoolField::from_byte(1, 0, 5, 0x24)
  inspect(bf2.value(), content="true")
  // bit 0 -> false
  let bf3 = BoolField::from_byte(1, 0, 0, 0x24)
  inspect(bf3.value(), content="false")
}

///|
test "WordField" {
  let wf = WordField::new(1, 0, [0xAB, 0xCD])
  inspect(wf.db_number(), content="1")
  inspect(wf.value(), content="43981")
  inspect(WordField::size(), content="2")
  inspect(wf.offset(), content="0")
  // Round-trip: to_bytes from value
  let wf2 = WordField::new(1, 0, wf.to_bytes())
  inspect(wf2.value(), content="43981")
}

///|
test "WordField edge cases" {
  // Zero
  let wz = WordField::new(1, 0, [0x00, 0x00])
  inspect(wz.value(), content="0")
  // Max
  let wm = WordField::new(1, 0, [0xFF, 0xFF])
  inspect(wm.value(), content="65535")
  // Short array
  let ws = WordField::new(1, 0, [0xAB])
  inspect(ws.value(), content="0")
}

///|
test "DIntField" {
  // -100000 = 0xFFFE7960
  let df = DIntField::new(1, 0, [0xFF, 0xFE, 0x79, 0x60])
  inspect(df.value(), content="-100000")
  inspect(DIntField::size(), content="4")
  inspect(df.db_number(), content="1")
  inspect(df.offset(), content="0")
  // Round-trip
  let df2 = DIntField::new(1, 0, df.to_bytes())
  inspect(df2.value(), content="-100000")
  // Max / min
  let dmax = DIntField::new(1, 0, [0x7F, 0xFF, 0xFF, 0xFF])
  inspect(dmax.value(), content="2147483647")
  let dmin = DIntField::new(1, 0, [0x80, 0x00, 0x00, 0x00])
  inspect(dmin.value(), content="-2147483648")
}

///|
test "DWordField" {
  // 4000000000 = 0xEE6B2800 (unsigned, fits in Int64 but not signed Int32)
  let dw = DWordField::new(1, 0, [0xEE, 0x6B, 0x28, 0x00])
  inspect(dw.value(), content="4000000000")
  inspect(DWordField::size(), content="4")
  inspect(dw.db_number(), content="1")
  // Round-trip
  let dw2 = DWordField::new(1, 0, dw.to_bytes())
  inspect(dw2.value(), content="4000000000")
  // Max unsigned
  let dwm = DWordField::new(1, 0, [0xFF, 0xFF, 0xFF, 0xFF])
  inspect(dwm.value(), content="4294967295")
  // dword_to_bytes / dint_to_bytes encode correctly
  let dwb = dword_to_bytes(4000000000L)
  inspect(dwb[0].to_int(), content="238")
  inspect(dwb[1].to_int(), content="107")
  inspect(dwb[2].to_int(), content="40")
  inspect(dwb[3].to_int(), content="0")
  let dib = dint_to_bytes(-100000)
  inspect(dib[0].to_int(), content="255")
  inspect(dib[1].to_int(), content="254")
  inspect(dib[2].to_int(), content="121")
  inspect(dib[3].to_int(), content="96")
}

///|
test "FloatField" {
  let ff = FloatField::new(1, 0, [0x42, 0x68, 0x00, 0x00])
  inspect(ff.value(), content="58")
  inspect(FloatField::size(), content="4")
  inspect(ff.db_number(), content="1")
}

///|
test "FloatField roundtrip" {
  let vals : Array[Double] = [0.0, 1.0, -1.0, 3.14159, 58.0, 100.5, -0.5]
  for v in vals {
    let bytes = f32_to_bytes(v)
    let ff = FloatField::new(1, 0, bytes)
    let diff = ff.value() - v
    let abs = if diff < 0.0 { -diff } else { diff }
    let ok = abs < 0.001
    inspect(ok, content="true")
  }
}

///|
test "DoubleField" {
  let df = DoubleField::new(1, 0, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
  inspect(df.db_number(), content="1")
  inspect(DoubleField::size(), content="8")
  inspect(df.value(), content="0")
}

///|
test "DoubleField roundtrip" {
  let vals : Array[Double] = [0.0, 1.0, -1.0, 3.14159, 100.0, -0.5]
  for v in vals {
    let bytes = f64_to_bytes(v)
    let df = DoubleField::new(1, 0, bytes)
    let diff = df.value() - v
    let abs = if diff < 0.0 { -diff } else { diff }
    inspect(abs < 0.001, content="true")
  }
}

///|
test "FieldValue enum" {
  let bf = BoolField::new(1, 0, 0)
  let fv_bool = FieldValue::from_bool(bf)
  inspect(fv_bool.data_block(), content="1")
  inspect(fv_bool.size(), content="1")
  inspect(fv_bool.value_bool(), content="Some(false)")
  inspect(fv_bool.value_int(), content="None")
  inspect(fv_bool.value_double(), content="None")

  let wf = WordField::new(1, 0, [0x12, 0x34])
  let fv_word = FieldValue::from_word(wf)
  inspect(fv_word.data_block(), content="1")
  inspect(fv_word.size(), content="2")
  inspect(fv_word.value_int(), content="Some(4660)")

  let ff = FloatField::new(1, 0, [0x3F, 0x80, 0x00, 0x00])
  let fv_float = FieldValue::from_float(ff)
  inspect(fv_float.size(), content="4")
  inspect(fv_float.value_double(), content="Some(1)")

  let df = DoubleField::new(1, 0, [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
  let fv_double = FieldValue::from_double(df)
  inspect(fv_double.size(), content="8")
  inspect(fv_double.value_double(), content="Some(0)")
}

///|
test "Field trait impl" {
  let bf = BoolField::new(2, 10, 3)
  inspect(bf.db_number(), content="2")
  inspect(bf.offset(), content="10")

  let wf = WordField::new(3, 20, [0xAB, 0xCD])
  inspect(wf.db_number(), content="3")
  inspect(wf.offset(), content="20")

  let ff = FloatField::new(4, 30, [0x42, 0x68, 0x00, 0x00])
  inspect(ff.db_number(), content="4")
  inspect(ff.offset(), content="30")
}
