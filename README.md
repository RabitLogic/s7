# MoonBit S7

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-0.10%2B-blue)](https://moonbitlang.com)

A pure MoonBit implementation of the Siemens S7 communication protocol for PLC devices.

> Fully compatible with [Rust s7 library](https://github.com/petar-dambovaliev/s7) API.

## Features

- ✅ **S7 Client API** — `ag_read/write`, `eb_read/write`, `ab_read/write`, `mb_read/write` (15 methods)
- ✅ **PLC Control** — `plc_start/stop/restart`, `plc_status`
- ✅ **SZL Diagnostics** — `cpu_info`, `cp_info`
- ✅ **COTP** — ISO Connection Request/Confirm (independent layer)
- ✅ **PDU Chunking** — Automatic large read/write splitting
- ✅ **Field Types** — `BoolField`, `WordField`, `FloatField`, `DoubleField` with `Field` trait
- ✅ **Field Collections** — `FieldValue` enum for heterogeneous field arrays
- ✅ **Async I/O** — Powered by `moonbitlang/async` official library
- ✅ **Cross-platform** — Linux, macOS, Windows (via async), WASM/JS (stub)

## Quick Start

### Add dependency

```toml
# moon.mod
import {
  "RabitLogic/s7",
}
```

### Basic usage

```moonbit
fn main {
  // Create client with default config (192.168.0.1:102)
  let cl = S7Client::new()

  // Connect to PLC
  cl.connect() as? conn
  defer conn.disconnect() // auto-disconnect on scope exit

  // Read 10 bytes from DB 1, starting at offset 0
  let data = conn.ag_read(1, 0, 10) as?
  println("Read \{data.length()} bytes")

  // Write data to DB 1
  conn.ag_write(1, 0, b"\x01\x02\x03") as?

  // PLC control
  conn.plc_start() as?
  let status = conn.plc_status() as?
  println("CPU status: \{status}")

  // Diagnostics
  let info = conn.cpu_info() as?
  println("Module: \{info.module_type_name}")
}
```

## API Reference

### S7Client

| Method | Description |
|--------|-------------|
| `new()` / `new_with_config(c)` | Create client |
| `async connect()` | Connect to PLC (TCP + COTP + PDU negotiation) |
| `async disconnect()` | Disconnect |
| `async ag_read(db, start, size)` | Read from data block (DB) |
| `async ag_write(db, start, data)` | Write to data block |
| `async eb_read/eb_write` | Read/write process inputs (E/A) |
| `async ab_read/ab_write` | Read/write process outputs (A/A) |
| `async mb_read/mb_write` | Read/write flags/markers (M) |
| `async plc_start/stop/restart` | PLC operating mode control |
| `async plc_status` | Get CPU status (Unknown/Stop/Run) |
| `async cpu_info` | Get CPU module info (SZL 0x001C) |
| `async cp_info` | Get CP/network info (SZL 0x0131) |
| `is_connected` | Check connection status |

### TcpConfig

| Field | Default | Description |
|-------|---------|-------------|
| `host` | `"192.168.0.1"` | PLC IP address |
| `port` | `102` | PLC port (ISO TCP) |
| `rack` | `0` | Rack number |
| `slot` | `1` | Slot number |
| `conn_type` | `1` | Connection type (PG/OP/Basic) |
| `connect_timeout` | `5000` | Connection timeout (ms) |
| `read_timeout` | `5000` | Read timeout (ms) |
| `write_timeout` | `5000` | Write timeout (ms) |
| `local_tsap` | `[0x01, 0x00]` | Local TSAP |
| `remote_tsap` | `[0x01, 0x01]` | Remote TSAP |

### Field Types

```moonbit
// Bit field
let bf = BoolField::new(1, 0, 0)           // DB1, byte 0, bit 0
let val = bf.value()                        // get bit value
let toggled = bf.set_value(true)            // set bit (returns new field)

// Word (u16)
let wf = WordField::new(1, 2, bytes)         // DB1, offset 2
let wval = wf.value()                        // 16-bit unsigned value

// Float (IEEE 754 f32)
let ff = FloatField::new(1, 4, bytes)        // DB1, offset 4
let fval = ff.value()                        // 32-bit float (as Double)

// Double (IEEE 754 f64)
let df = DoubleField::new(1, 8, bytes)       // DB1, offset 8
let dval = df.value()                        // 64-bit float

// FieldValue — heterogeneous collection
let fields : Array[FieldValue] = [
  FBool(BoolField::new(1, 0, 0)),
  FFloat(FloatField::new(1, 4, bytes)),
]
for f in fields {
  println("DB\{f.data_block()} @ \{f.offset()}")
}
```

## Architecture

```
┌─────────────────────────────────────┐
│            S7Client                 │
│  ┌───────────────────────────────┐  │
│  │      TcpConnection            │  │
│  │  ┌─────────────────────────┐  │  │
│  │  │  @socket.Tcp (async)    │  │  │
│  │  │  + FD-based FFI I/O    │  │  │
│  │  └─────────────────────────┘  │  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │      CotpConnection           │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
         ↕
┌─────────────────────────────────────┐
│         S7 Protocol Layer           │
│  build_read_pdu / parse_response    │
│  build_write_pdu / build_setup_pdu  │
│  SZL, PLC control, COTP            │
└─────────────────────────────────────┘
```

## Project Structure

```
s7/
├── moon.mod                # Module configuration
├── src/
│   ├── lib.mbt             # Version info
│   ├── error.mbt           # S7Error + S7Result
│   ├── client/
│   │   └── client.mbt      # S7Client (15 async methods)
│   ├── transport/
│   │   ├── transport.mbt   # Transport trait + ConnType
│   │   ├── tcp.mbt         # TcpConnection (native: FFI + async)
│   │   ├── tcp_stub.mbt    # Stub (WASM/JS)
│   │   └── cotp.mbt        # CotpConnection
│   └── protocol/
│       ├── types.mbt       # DataType, Area, CpuStatus, CpuInfo, CPInfo
│       ├── items.mbt       # ReadItem, WriteItem
│       ├── s7comm.mbt      # PDU encode/decode, SZL, PLC control
│       ├── field.mbt       # BoolField, WordField, FloatField, DoubleField
│       └── constant.mbt    # WL_*, TS_*, Area hex, data_size_byte
└── examples/
    └── main.mbt            # Demo program
```

## Platform Support

| Target | Status | Backend |
|--------|--------|---------|
| Linux | ✅ | native (async TCP + FFI I/O) |
| macOS | ✅ | native (async TCP + FFI I/O) |
| Windows | ✅ | native (async TCP + FFI I/O, MinGW) |
| WASM/JS | ✅ | stub (compile-only placeholder) |

## Comparison with Rust s7

The MoonBit S7 library is fully feature-aligned with the [Rust s7](https://github.com/petar-dambovaliev/s7) library:

| Feature | Rust s7 | MoonBit S7 |
|---------|---------|------------|
| Client API | 15 methods | 15 async methods |
| Transport trait | send + pdu_length + negotiate + connection_type | send + pdu_length + is_connected + disconnect + connection_type |
| Field types | Bool + Float + Double + Word | BoolField + FloatField + DoubleField + WordField |
| Field trait | `trait Field` | ✅ `trait Field` + `FieldValue` enum |
| PLC Control | start/stop/restart/plc_status | ✅ plc_start/stop/restart/plc_status |
| SZL | cpu_info/cp_info | ✅ cpu_info/cp_info |
| COTP | embedded in TCP | ✅ independent `CotpConnection` |
| I/O model | sync blocking | ⚡ async |
| Cross-platform | std library | async + FFI |

## License

MIT License — see [LICENSE](LICENSE)
