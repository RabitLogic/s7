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
    """Build S7 Setup Communication response."""
    return bytes([
        0x03, 0x00, 0x00, 0x1C,  # TPKT len=28
        0x02, 0xF0, 0x80,        # COTP DT
        0x32,                    # S7 PID
        0x01,                    # msg type = ack
        0x00, 0x00,              # reserved
        (refn >> 8) & 0xFF, refn & 0xFF,  # ref number
        0x00, 0x00,              # param len
        0x00, 0x07,              # data len = 7
        0x00, 0x0F, 0x00, 0x00, # data
        0x01, 0x00, 0x01, 0x00,
        0x01, (pdu_size >> 8) & 0xFF, pdu_size & 0xFF,  # PDU size
        0x00, 0x0A,
    ])

def build_read_resp(data: bytes, refn: int = 1) -> bytes:
    """Build S7 Read response matching MoonBit's parse_response().
    
    CRITICAL: parse_response reads param_len from s7+5/6 (off-by-one!)
    and data_len from s7+7/8. So the S7 header bytes are shifted."""
    dlen = len(data)
    total_data_len = 4 + dlen  # 4-byte data header + actual data
    
    # TPKT(4) + COTP_DT(3) + S7_HDR(10) + data_hdr(4) + data(dlen)
    total_pkt = 4 + 3 + 10 + 4 + dlen
    tpkt_hi = (total_pkt >> 8) & 0xFF
    tpkt_lo = total_pkt & 0xFF
    
    total_data_hi = (total_data_len >> 8) & 0xFF
    total_data_lo = total_data_len & 0xFF
    
    # S7 header at offset 7:
    # [0]=PID, [1]=msg_type, [2-3]=reserved
    # [4]=ref_hi, [5]=ref_lo(->plen_hi), [6]=plen_hi(->plen_lo)
    # [7]=plen_lo(->dlen_hi), [8]=dlen_hi(->dlen_lo), [9]=dlen_lo
    resp = bytearray([
        0x03, 0x00, tpkt_hi, tpkt_lo,  # TPKT
        0x02, 0xF0, 0x80,               # COTP DT
        0x32,                            # s7+0: PID
        0x07,                            # s7+1: msg_type = user data (avoids parse_response bug treating 0x03 as error)
        0x00, 0x00,                      # s7+2/3: reserved
        (refn >> 8) & 0xFF,             # s7+4: ref_hi
        0x00,                            # s7+5: ref_lo → parse reads as plen_hi
        0x00,                            # s7+6: plen_hi → parse reads as plen_lo
        total_data_hi,                   # s7+7: plen_lo → parse reads as dlen_hi
        total_data_lo,                   # s7+8: dlen_hi → parse reads as dlen_lo
        0x00,                            # s7+9: dlen_lo (unused)
        0xFF,                            # return code = OK
        0x04,                            # transport size = byte
        (dlen >> 8) & 0xFF, dlen & 0xFF, # data length
    ])
    resp.extend(data)
    return bytes(resp)

def build_write_resp(refn: int = 1) -> bytes:
    """Build S7 Write response (acknowledgement)."""
    return bytes([
        0x03, 0x00, 0x00, 0x1C,  # TPKT len=28
        0x02, 0xF0, 0x80,        # COTP DT
        0x32, 0x03, 0x00, 0x00,
        (refn >> 8) & 0xFF, refn & 0xFF,
        0x00, 0x00, 0x00, 0x06,
        0xFF, 0x04, 0x00, 0x01,  # data header
        0x00,                    # return code = OK
        0x00, 0x00, 0x00,        # padding
    ])

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

    if func == 0x04:  # Read
        results = []
        for i in range(item_count):
            off = 2 + i * 12
            if off + 12 > len(params):
                break
            # Parse read item
            transport = params[off + 2]
            db_hi = params[off + 3]
            db_lo = params[off + 4]
            area = params[off + 5]
            byte_off = (params[off + 6] << 8) | params[off + 7]
            bit_off = params[off + 8]
            count = params[off + 11]

            db_num = (db_hi << 8) | db_lo
            if area == 0x84:  # DataBlock
                ensure_db(db_num)
                mem = db_memory[db_num]
                data = bytes(mem[byte_off:byte_off + count])
                results.append(data)
            else:
                # Other areas: return zeros
                results.append(bytes(count))

        return build_read_resp(b''.join(results), req['refn'])

    elif func == 0x05:  # Write
        data_offset = 0
        for i in range(item_count):
            off = 2 + i * 12
            if off + 12 > len(params):
                break
            transport = params[off + 2]
            db_hi = params[off + 3]
            db_lo = params[off + 4]
            area = params[off + 5]
            byte_off = (params[off + 6] << 8) | params[off + 7]
            bit_off = params[off + 8]
            count = params[off + 11]

            # Write data follows after params in the data section
            # Each write item has: 0xFF, transport_size, len_hi, len_lo, data...
            wd = req['data']
            if data_offset + 4 <= len(wd):
                wlen = (wd[data_offset + 2] << 8) | wd[data_offset + 3]
                wdata = wd[data_offset + 4:data_offset + 4 + wlen]
                data_offset += 4 + wlen

                db_num = (db_hi << 8) | db_lo
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
    print(f"    Simulated DBs: DB200 (256 bytes initialized)")
    ensure_db(200, 256)
    # Put some recognizable data in DB200
    for i in range(min(16, 256)):
        db_memory[200][i] = i * 16 + i  # 0x00, 0x11, 0x22, ...

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
