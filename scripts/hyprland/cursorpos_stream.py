#!/usr/bin/env python3
"""Stream the Hyprland pointer position to stdout as "X Y" lines.

services/AppLaunchFeedback.qml parks the launch bubble on the pointer, which means
sampling the cursor ~11 times a second while an app is starting. Forking `hyprctl`
that often is wasteful, so this talks to Hyprland's request socket directly: one
long-lived process, ~0.3 ms per sample.

Exits quietly once the compositor's socket goes away, so the shell's Process can
treat "it stopped" as "there is nothing left to follow".

Usage: cursorpos_stream.py [INTERVAL_SECONDS]
"""

import os
import socket
import sys
import time

DEFAULT_INTERVAL = 0.09
MAX_CONSECUTIVE_FAILURES = 8


def find_socket():
    signature = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not signature:
        return None
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    candidates = (
        f"{runtime}/hypr/{signature}/.socket.sock",
        f"/tmp/hypr/{signature}/.socket.sock",
    )
    return next((path for path in candidates if os.path.exists(path)), None)


def sample(path):
    with socket.socket(socket.AF_UNIX) as sock:
        sock.settimeout(1.0)
        sock.connect(path)
        sock.sendall(b"cursorpos")
        return sock.recv(64).decode("utf-8", "replace")


def main():
    try:
        interval = float(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_INTERVAL
    except ValueError:
        interval = DEFAULT_INTERVAL
    interval = min(max(interval, 0.016), 1.0)

    path = find_socket()
    if path is None:
        return 1

    failures = 0
    while True:
        try:
            reply = sample(path)
        except OSError:
            failures += 1
            if failures >= MAX_CONSECUTIVE_FAILURES:
                return 1
            time.sleep(0.2)
            continue

        failures = 0
        raw_x, _, raw_y = reply.strip().partition(",")
        try:
            print(f"{int(raw_x.strip())} {int(raw_y.strip())}", flush=True)
        except ValueError:
            pass
        except (BrokenPipeError, OSError):
            return 0

        time.sleep(interval)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
