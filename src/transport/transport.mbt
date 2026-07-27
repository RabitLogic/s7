///|
pub type S7Result[T] = @src.S7Result[T]

///|
pub type S7Error = @src.S7Error

// Transport trait - pluggable async transport abstraction

///|
pub trait Transport {
  async fn send(Self, Array[Byte]) -> S7Result[Array[Byte]]
  fn pdu_length(Self) -> Int
  fn is_connected(Self) -> Bool
  async fn disconnect(Self) -> Unit
  fn connection_type(Self) -> ConnType
}

// Connection type enum

///|
pub enum ConnType {
  PG
  OP
  Basic
}

///|
pub fn ConnType::pg() -> ConnType {
  PG
}

///|
pub fn ConnType::op() -> ConnType {
  OP
}

///|
pub fn ConnType::basic() -> ConnType {
  Basic
}
