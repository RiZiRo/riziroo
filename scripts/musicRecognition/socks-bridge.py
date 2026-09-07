#!/usr/bin/env python3
"""Minimal HTTP CONNECT -> SOCKS5 gateway.

Lets HTTP-proxy clients (e.g. songrec's reqwest, which has no SOCKS support)
use a local SOCKS5 proxy such as v2rayN's 127.0.0.1:10808.

Usage: socks-bridge.py <listen_port> <socks_host> <socks_port>
Only CONNECT (HTTPS tunneling) is supported.
"""
import socket
import select
import threading
import sys


def pump(a, b):
    try:
        while True:
            data = a.recv(65536)
            if not data:
                break
            b.sendall(data)
    except OSError:
        pass
    finally:
        try:
            a.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            b.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass


def socks5_connect(socks_host, socks_port, target_host, target_port):
    s = socket.create_connection((socks_host, socks_port), timeout=15)
    s.settimeout(15)
    # greeting: no auth
    s.sendall(b"\x05\x01\x00")
    resp = s.recv(2)
    if len(resp) < 2 or resp[0] != 5 or resp[1] != 0:
        raise OSError("SOCKS5 server refused no-auth handshake")
    # CONNECT request with domain name
    host_bytes = target_host.encode("idna") if not target_host.replace(".", "").isdigit() else b""
    if host_bytes:
        req = b"\x05\x01\x00\x03" + bytes([len(host_bytes)]) + host_bytes
    else:
        req = b"\x05\x01\x00\x01" + socket.inet_aton(target_host)
    req += target_port.to_bytes(2, "big")
    s.sendall(req)
    resp = s.recv(10)
    if len(resp) < 2 or resp[1] != 0:
        raise OSError(f"SOCKS5 CONNECT failed: reply code {resp[1] if len(resp) > 1 else '?'}")
    return s


def handle(client, socks_host, socks_port):
    try:
        client.settimeout(15)
        req = b""
        while b"\r\n\r\n" not in req:
            chunk = client.recv(4096)
            if not chunk:
                return
            req += chunk
            if len(req) > 8192:
                return
        line = req.split(b"\r\n", 1)[0].decode("latin-1")
        parts = line.split()
        if len(parts) < 2 or parts[0].upper() != "CONNECT":
            client.sendall(b"HTTP/1.1 405 Method Not Allowed\r\n\r\n")
            return
        host, _, port = parts[1].rpartition(":")
        if not host:
            return
        upstream = socks5_connect(socks_host, socks_port, host, int(port))
    except OSError:
        try:
            client.sendall(b"HTTP/1.1 502 Bad Gateway\r\n\r\n")
        except OSError:
            pass
        return
    client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
    client.settimeout(None)
    t = threading.Thread(target=pump, args=(client, upstream), daemon=True)
    t.start()
    pump(upstream, client)


def main():
    listen_port = int(sys.argv[1])
    socks_host = sys.argv[2]
    socks_port = int(sys.argv[3])
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", listen_port))
    srv.listen(8)
    print(f"READY {listen_port}", flush=True)
    while True:
        client, _ = srv.accept()
        threading.Thread(target=handle, args=(client, socks_host, socks_port), daemon=True).start()


if __name__ == "__main__":
    main()
