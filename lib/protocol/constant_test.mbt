// Tests for constants

///|
test "WL constants" {
  inspect(WL_BIT, content="1"); inspect(WL_BYTE, content="2")
  inspect(WL_WORD, content="4"); inspect(WL_DWORD, content="6")
  inspect(WL_REAL, content="8"); inspect(WL_COUNTER, content="28")
}

///|
test "data_size_byte" {
  inspect(data_size_byte(WL_BYTE), content="1")
  inspect(data_size_byte(WL_WORD), content="2")
  inspect(data_size_byte(WL_DWORD), content="4")
  inspect(data_size_byte(999), content="0")
}

///|
test "dt_to_word_len" {
  inspect(dt_to_word_len(DataType::bool_dt()), content="1")
  inspect(dt_to_word_len(DataType::byte()), content="2")
  inspect(dt_to_word_len(DataType::word()), content="4")
}
