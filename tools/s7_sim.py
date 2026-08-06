#!/usr/bin/env python3
"""
Minimal S7 PLC Simulator for testing MoonBit s7 library.
Listens on port 102 and responds to basic S7 protocol:
  - COTP CR → CC
  - S7 Setup → PDU size negotiation
  - S7 Read → dummy data
  - S7 Write → acknowledge
"""

import socket
import struct
import sys
import threading

# ─── Protocol Helpers ───────────────────────────────────────────────

def build_cotp_cc(src_ref: int = 0x0000, dst_ref: int = 0x0001) -> bytes:
    """Build COTP Connection Confirm (CC) response."""
    return bytes([
        0x03, 0x00, 0x00, 0x16,  # TPKT
        0x11, 0xD0,              # COTP len=17, CC
        (dst_ref >> 8) & 0xFF, dst_ref & 0xFF,  # DST-REF
        (src_ref >> 8) & 0xFF, src_ref & 0xFF,  # SRC-REF
        0x00,                    # flags
        0xC0, 0x01, 0x03,       # TPDU-size = 1024
        0xC1, 0x02, 0x01, 0x00, # Calling TSAP
        0xC2, 0x02, 0x01, 0x00, # Called TSAP
    ])

def build_setup_resp(refn: int = 1, pdu_size: int = 480) -> bytes:
    """Build a standard S7 Setup Communication response (Ack-Data).

    Layout (28 bytes):
      TPKT(4) COTP(3) S7hdr(10) params(2: error class/code) data(9)
      The negotiated PDU size is read by the client at index [25..26].
    """
    return bytes([
        0x03, 0x00, 0x00, 0x1C,  # TPKT len = 28
        0x02, 0xF0, 0x80,        # COTP DT
        0x32,                    # S7 PID
        0x03,                    # msg type = Ack-Data
        0x00, 0x00,              # reserved
        (refn >> 8) & 0xFF, refn & 0xFF,  # ref number
        0x00, 0x02,              # param len = 2 (error class/code)
        0x00, 0x09,              # data len = 9
        0x00, 0x00,              # error class / code = 0
        0xF0,                    # function = setup
        0x00, 0x00,              # reserved
        0x01, 0x00,              # max calling length = 0x0001
        0x01,                    # max called length hi
        (pdu_size >> 8) & 0xFF, pdu_size & 0xFF,  # PDU size @ [25..26]
        0x00,                    # padding
    ])

def build_read_resp(data: bytes, refn: int = 1) -> bytes:
    """Build a standard S7 Read response (Ack-Data, single item).

    Real-PLC layout (matches Rust s7 / snap7):
      TPKT(4) COTP(3) S7hdr(10) params(4: error class/code + reserved)
      data(4: return code, transport size, length) + payload
      → return code at index 21, payload starting at index 25.
    """
    dlen = len(data)
    total_data_len = 4 + dlen            # 4-byte item header + payload
    total_pkt = 4 + 3 + 10 + 4 + total_data_len
    return bytes([
        0x03, 0x00, (total_pkt >> 8) & 0xFF, total_pkt & 0xFF,  # TPKT
        0x02, 0xF0, 0x80,               # COTP DT
        0x32,                            # s7+0: PID
        0x03,                            # s7+1: msg type = Ack-Data
        0x00, 0x00,                      # s7+2/3: reserved
        (refn >> 8) & 0xFF, refn & 0xFF, # s7+4/5: PDU ref
        0x00, 0x04,                      # s7+6/7: param length = 4
        (total_data_len >> 8) & 0xFF, total_data_len & 0xFF,  # s7+8/9: data length = 4 + dlen
        0x00, 0x00,                      # error class / code = 0
        0x00, 0x00,                      # reserved (params)
        0xFF,                            # return code = OK
        0x04,                            # transport size = byte
        (dlen >> 8) & 0xFF, dlen & 0xFF, # data length
    ]) + data

def build_write_resp(refn: int = 1) -> bytes:
    """Build an S7 Write response (Ack-Data, 22 bytes) matching real PLCs.

    Byte-for-byte the response S7-PLCSIM Advanced returns for a successful
    write: item return code 0xFF at index 21 (snap7 / Rust s7 check this).
    """
    return bytes([
        0x03, 0x00, 0x00, 0x16,  # TPKT len = 22
        0x02, 0xF0, 0x80,        # COTP DT
        0x32, 0x03, 0x00, 0x00,  # PID, Ack-Data, reserved
        (refn >> 8) & 0xFF, refn & 0xFF,  # PDU ref
        0x00, 0x02,              # param len = 2
        0x00, 0x01,              # data len = 1
        0x00, 0x00,              # params: error class/code = 0
        0x05, 0x01, 0xFF,        # data + item return code at index 21
    ])


def build_plc_status_resp(refn: int, status: int = 0x08) -> bytes:
    """Build a standard S7 PLC status response (45 bytes).

    The status byte (0x08 = RUN, 0x04/0x07 = STOP) lives at index 44,
    which is where the client's parse_plc_status reads it.
    """
    resp = bytearray(45)
    resp[0:4] = bytes([0x03, 0x00, 0x00, 45])
    resp[4:7] = bytes([0x02, 0xF0, 0x80])
    resp[7] = 0x32
    resp[8] = 0x07  # userdata
    resp[11:13] = bytes([(refn >> 8) & 0xFF, refn & 0xFF])
    resp[13:15] = bytes([0x00, 0x08])  # param len = 8
    resp[15:17] = bytes([0x00, 0x08])  # data len = 8
    resp[18] = 0x01
    resp[19] = 0x12
    resp[20] = 0x04
    resp[21] = 0x11
    resp[22] = 0x44
    resp[23] = 0x01
    resp[25] = 0xFF
    resp[26] = 0x09
    resp[28] = 0x04
    resp[29] = 0x04
    resp[30] = 0x24
    resp[44] = status
    return bytes(resp)


def build_szl_resp(refn: int, szl_id: int) -> bytes:
    """Build a standard S7 SZL first response with a 205-byte CPU-info payload.

    The SZL payload starts at index 41 (matches the client's parse_szl_first)
    and the CPU-info fields are placed at the offsets used by parse_cpu_info
    (as_name@2, module_name@36, copyright@104, serial@138, module_type@172).
    """
    payload = bytearray(205)
    asn = b"MOONBIT-AS"
    payload[2:2 + len(asn)] = asn
    mn = b"CPU1214C-DEMO"
    payload[36:36 + len(mn)] = mn
    cp = b"Copyright MoonBit 2026"
    payload[104:104 + len(cp)] = cp
    sn = b"SZ-00000001"
    payload[138:138 + len(sn)] = sn
    mt = b"CPU 1214C"
    payload[172:172 + len(mt)] = mt

    szl_data_size = len(payload)        # 205
    total_len = 41 + szl_data_size      # 246
    data_szl_field = szl_data_size + 8  # 213 (client/Rust: read_u16 - 8)

    resp = bytearray(total_len)
    resp[0:4] = bytes([0x03, 0x00, (total_len >> 8) & 0xFF, total_len & 0xFF])
    resp[4:7] = bytes([0x02, 0xF0, 0x80])
    resp[7] = 0x32
    resp[8] = 0x07  # userdata
    resp[11:13] = bytes([(refn >> 8) & 0xFF, refn & 0xFF])
    resp[13:15] = bytes([0x00, 0x08])  # param len = 8
    resp[15:17] = bytes([0x00, 4 + szl_data_size])
    resp[18] = 0x01
    resp[19] = 0x12
    resp[20] = 0x08
    resp[21] = 0x12  # function = read SZL
    resp[22] = 0x44  # sub
    resp[23] = 0x01
    resp[25] = 0xFF
    resp[26] = 0x00  # done flag
    resp[27:29] = bytes([0x00, 4 + szl_data_size])
    resp[29] = 0xFF
    resp[31:33] = bytes([(data_szl_field >> 8) & 0xFF, data_szl_field & 0xFF])
    resp[37:39] = bytes([0x00, 0x02])  # header length (x2 => 4)
    resp[39:41] = bytes([0x00, 0x01])  # record count
    resp[41:] = payload
    return bytes(resp)

def find_s7_header(data: bytes) -> int:
    """Find S7 protocol header (PID 0x32 followed by valid msg type)."""
    for i in range(len(data) - 1):
        if data[i] == 0x32 and data[i+1] in (0x01, 0x03, 0x07):
            return i
    return -1

def parse_s7_request(data: bytes):
    """Parse S7 request and return (msg_type, ref, params)."""
    s7 = find_s7_header(data)
    if s7 < 0:
        return None
    msg_type = data[s7 + 1]
    refn = (data[s7 + 4] << 8) | data[s7 + 5]
    plen = (data[s7 + 6] << 8) | data[s7 + 7]
    dlen = (data[s7 + 8] << 8) | data[s7 + 9]
    params = data[s7 + 10:s7 + 10 + plen]
    data_section = data[s7 + 10 + plen:s7 + 10 + plen + dlen]
    print(f"    [debug] s7_off={s7}, msg_type={msg_type:#x}, refn={refn}, plen={plen}, dlen={dlen}")
    print(f"    [debug] params ({len(params)}b): {params.hex()}")
    print(f"    [debug] data ({len(data_section)}b): {data_section.hex()}")
    return {
        'msg_type': msg_type,
        'refn': refn,
        'plen': plen,
        'dlen': dlen,
        'params': params,
        'data': data_section,
    }

# ─── Simulated Memory ───────────────────────────────────────────────

db_memory: dict[int, bytearray] = {}

def ensure_db(db_num: int, size: int = 256):
    if db_num not in db_memory:
        db_memory[db_num] = bytearray(size)

def handle_s7_request(req: dict) -> bytes | None:
    """Handle parsed S7 request and return response PDU."""
    params = req['params']
    if len(params) < 2:
        print(f"    [debug] params too short: {len(params)}")
        return None

    func = params[0]
    item_count = params[1]
    print(f"    [debug] func={func:#x}, item_count={item_count}")

    # Userdata requests (S7 msg type 0x07): SZL reads (cpu_info / cp_info)
    # and PLC status. Detected via function 0x11 sub 0x44.
    if func == 0x00 and len(params) >= 6 and params[1] == 0x01 and \
       params[2] == 0x12 and params[4] == 0x11 and params[5] == 0x44:
        wd = req['data']
        if len(wd) >= 6 and wd[4] == 0x04 and wd[5] == 0x24:
            print(f"    [debug] PLC status request")
            return build_plc_status_resp(req['refn'])
        szl_id = (wd[4] << 8) | wd[5] if len(wd) >= 6 else 0
        print(f"    [debug] SZL request id=0x{szl_id:04x}")
        return build_szl_resp(req['refn'], szl_id)

    if func == 0x04:  # Read
        results = []
        for i in range(item_count):
            off = 2 + i * 12
            if off + 12 > len(params):
                break
            # S7-1500 / PLCSIM item format:
            #   12 0A 10 <WL> <count_hi> <count_lo> <db_hi> <db_lo> <area> <addr2> <addr1> <addr0>
            wl = params[off + 3]
            count = (params[off + 4] << 8) | params[off + 5]
            db_num = (params[off + 6] << 8) | params[off + 7]
            area = params[off + 8]
            addr = (params[off + 9] << 16) | (params[off + 10] << 8) | params[off + 11]
            byte_off = addr >> 3
            bit_off = addr & 0x07
            word_size = 1 if wl in (0x01, 0x02, 0x03) else (2 if wl in (0x04, 0x05, 0x1C, 0x1D) else 4)
            data_len = count * word_size

            if area == 0x84:  # DataBlock
                ensure_db(db_num)
                mem = db_memory[db_num]
                data = bytes(mem[byte_off:byte_off + data_len])
                results.append(data)
            else:
                # Other areas: return zeros
                results.append(bytes(data_len))

        return build_read_resp(b''.join(results), req['refn'])

    elif func == 0x05:  # Write
        data_offset = 0
        for i in range(item_count):
            off = 2 + i * 12
            if off + 12 > len(params):
                break
            # S7-1500 / PLCSIM item format:
            #   12 0A 10 <WL> <count_hi> <count_lo> <db_hi> <db_lo> <area> <addr2> <addr1> <addr0>
            wl = params[off + 3]
            count = (params[off + 4] << 8) | params[off + 5]
            db_num = (params[off + 6] << 8) | params[off + 7]
            area = params[off + 8]
            addr = (params[off + 9] << 16) | (params[off + 10] << 8) | params[off + 11]
            byte_off = addr >> 3
            bit_off = addr & 0x07
            word_size = 1 if wl in (0x01, 0x02, 0x03) else (2 if wl in (0x04, 0x05, 0x1C, 0x1D) else 4)
            data_len = count * word_size

            # Write data follows after params in the data section.
            # Each write item: 0x00, transport_size, len_hi, len_lo, data...
            # (the len field is in bits for byte/word/dword, so use data_len.)
            wd = req['data']
            if data_offset + 4 <= len(wd):
                wdata = wd[data_offset + 4:data_offset + 4 + data_len]
                data_offset += 4 + data_len

                if area == 0x84:  # DataBlock
                    ensure_db(db_num)
                    mem = db_memory[db_num]
                    for j in range(min(len(wdata), len(mem) - byte_off)):
                        mem[byte_off + j] = wdata[j]

        return build_write_resp(req['refn'])

    return None

# ─── Connection Handler ─────────────────────────────────────────────

def handle_client(conn: socket.socket, addr):
    print(f"[+] Connection from {addr}")
    state = "COTP"
    try:
        while True:
            data = conn.recv(4096)
            if not data:
                break

            if state == "COTP":
                # Expect COTP CR
                if len(data) >= 7 and data[4] == 0x11 and data[5] == 0xE0:
                    # Parse calling/called TSAP from CR
                    resp = build_cotp_cc()
                    conn.send(resp)
                    print(f"    → COTP CC sent")
                    state = "SETUP"
                else:
                    print(f"    Unknown data (state=COTP): {data.hex()[:40]}")
                    break

            elif state == "SETUP":
                # Expect S7 Setup Communication
                req = parse_s7_request(data)
                if req and req['msg_type'] == 0x01:
                    resp = build_setup_resp(req['refn'])
                    conn.send(resp)
                    print(f"    → Setup resp sent (PDU=480)")
                    state = "READY"
                else:
                    print(f"    Unknown data (state=SETUP): {data.hex()[:40]}")
                    break

            elif state == "READY":
                req = parse_s7_request(data)
                if req is None:
                    print(f"    Cannot parse S7 request, sending dummy response")
                    conn.send(build_read_resp(bytes(10), req.get('refn', 1) if req else 1))
                    continue
                resp = handle_s7_request(req)
                func_name = "Read" if len(req['params']) > 0 and req['params'][0] == 0x04 else "Write" if len(req['params']) > 0 and req['params'][0] == 0x05 else f"Func={req['params'][0] if len(req['params']) > 0 else '?'}"
                if resp:
                    conn.send(resp)
                    print(f"    → {func_name} resp sent ({len(resp)}b)")
                else:
                    # Send dummy read response for unhandled requests
                    print(f"    → {func_name} unhandled, sending dummy response")
                    conn.send(build_read_resp(bytes(10), req['refn']))

    except ConnectionResetError:
        pass
    except Exception as e:
        print(f"    Error: {e}")
    finally:
        conn.close()
        print(f"[-] Disconnected {addr}")

# ─── Main ───────────────────────────────────────────────────────────

def main():
    host = sys.argv[1] if len(sys.argv) > 1 else "0.0.0.0"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 102

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((host, port))
    server.listen(5)
    print(f"[*] S7 PLC Simulator listening on {host}:{port}")
    print(f"    Simulated DBs: DB200 (1796 bytes, matching the real PLC layout)")
    ensure_db(200, 1796)
    # Put some recognizable data in DB200 (pattern 0x00, 0x11, 0x22, ...)
    for i in range(min(16, 1796)):
        db_memory[200][i] = i * 16 + i

    try:
        while True:
            conn, addr = server.accept()
            threading.Thread(target=handle_client, args=(conn, addr), daemon=True).start()
    except KeyboardInterrupt:
        print("\n[*] Shutting down...")
    finally:
        server.close()

if __name__ == "__main__":
    main()
