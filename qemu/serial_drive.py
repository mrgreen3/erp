#!/usr/bin/env python3
import socket, sys, time, re

sock_path = sys.argv[1]
script = sys.argv[2:]  # list of "expect|send" pairs as args, expect can be empty

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
for _ in range(50):
    try:
        s.connect(sock_path)
        break
    except FileNotFoundError:
        time.sleep(0.2)
else:
    print("could not connect to socket", file=sys.stderr)
    sys.exit(1)

s.settimeout(60)
buf = b""

def read_until(pattern, timeout=60):
    global buf
    end = time.time() + timeout
    rx = re.compile(pattern.encode())
    while time.time() < end:
        try:
            s.settimeout(max(0.5, end - time.time()))
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
            if rx.search(buf):
                out = buf
                buf = b""
                return out.decode(errors="replace")
        except socket.timeout:
            break
    out = buf
    buf = b""
    return out.decode(errors="replace")

for i in range(0, len(script), 2):
    expect_pat = script[i]
    send_str = script[i+1] if i+1 < len(script) else None
    if expect_pat:
        out = read_until(expect_pat)
        print(out, end="")
    if send_str is not None:
        s.sendall((send_str + "\n").encode())
        time.sleep(0.3)

# drain remaining
try:
    s.settimeout(3)
    while True:
        chunk = s.recv(4096)
        if not chunk:
            break
        print(chunk.decode(errors="replace"), end="")
except socket.timeout:
    pass
s.close()
