///|
pub enum S7Error {
  ConnectionFailed(String)
  ConnectionTimeout
  ConnectionClosed
  InvalidPDU(String)
  InvalidParameter(String)
  PlcError(Int, String)
  Timeout(String)
  TransportError(String)
  TlsError(String)
  VersionMismatch(Int, Int)
  BufferOverflow
  ItemNotFound(String)
  NotConnected
  AlreadyConnected
  DataConversionError(String)
  Unsupported(String)
  ResourceExhausted(String)
  JobPending
  InvalidDataSize
  InvalidPassword
  NeedPassword
  FunNotAvailable
  DataOverPdu
  CpuError(Int)
  InvalidResponse(String)
} derive(Show)

///|
pub type S7Result[T] = Result[T, S7Error]

///|
pub fn S7Error::connection_failed(m : String) -> S7Error {
  ConnectionFailed(m)
}

///|
pub fn S7Error::invalid_pdu(m : String) -> S7Error {
  InvalidPDU(m)
}

///|
pub fn S7Error::plc_error(c : Int, m : String) -> S7Error {
  PlcError(c, m)
}

///|
pub fn S7Error::transport(m : String) -> S7Error {
  TransportError(m)
}

///|
pub fn S7Error::not_connected() -> S7Error {
  NotConnected
}

///|
pub fn S7Error::already_connected() -> S7Error {
  AlreadyConnected
}

///|
pub fn S7Error::item_not_found(m : String) -> S7Error {
  ItemNotFound(m)
}

///|
pub fn S7Error::invalid_data_size() -> S7Error {
  InvalidDataSize
}

///|
pub fn S7Error::invalid_response(m : String) -> S7Error {
  InvalidResponse(m)
}

///|
pub fn S7Error::job_pending() -> S7Error {
  JobPending
}

///|
pub fn S7Error::connection_timeout() -> S7Error {
  ConnectionTimeout
}

///|
pub fn S7Error::connection_closed() -> S7Error {
  ConnectionClosed
}

///|
pub fn S7Error::invalid_parameter(m : String) -> S7Error {
  InvalidParameter(m)
}

///|
pub fn S7Error::timeout(m : String) -> S7Error {
  Timeout(m)
}

///|
pub fn S7Error::tls_error(m : String) -> S7Error {
  TlsError(m)
}

///|
pub fn S7Error::version_mismatch(v1 : Int, v2 : Int) -> S7Error {
  VersionMismatch(v1, v2)
}

///|
pub fn S7Error::buffer_overflow() -> S7Error {
  BufferOverflow
}

///|
pub fn S7Error::data_conversion(m : String) -> S7Error {
  DataConversionError(m)
}

///|
pub fn S7Error::unsupported(m : String) -> S7Error {
  Unsupported(m)
}

///|
pub fn S7Error::resource_exhausted(m : String) -> S7Error {
  ResourceExhausted(m)
}

///|
pub fn S7Error::invalid_password() -> S7Error {
  InvalidPassword
}

///|
pub fn S7Error::need_password() -> S7Error {
  NeedPassword
}

///|
pub fn S7Error::fun_not_available() -> S7Error {
  FunNotAvailable
}

///|
pub fn S7Error::data_over_pdu() -> S7Error {
  DataOverPdu
}

///|
pub fn S7Error::cpu_error(c : Int) -> S7Error {
  CpuError(c)
}
