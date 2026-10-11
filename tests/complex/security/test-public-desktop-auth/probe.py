#!/usr/bin/env python3
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
"""Exercise the public entry point; a 200 HTML page alone cannot prove VNC works."""
import base64
import http.client
import json
import os
import socket
import ssl
import subprocess
import sys
import time

desktop = sys.argv[1]
context = ssl._create_unverified_context()  # The booth's default local CA.
inner_port, vnc_port = (16666, 5901) if desktop == "lxqt" else (17777, 5900)
log = open("/tmp/auth-desktop.log", "w")
process = None


def request(path, method="GET", body=None, cookie=None):
    headers = {"Cookie": cookie} if cookie else {}
    if body is not None:
        headers["Content-Type"] = "application/json"
    conn = http.client.HTTPSConnection("localhost", 10443, context=context, timeout=4)
    try:
        conn.request(method, path, body, headers)
        response = conn.getresponse()
        return response.status, dict(response.getheaders()), response.read()
    finally:
        conn.close()


def login(password, username="coder"):
    body = json.dumps({
        "username_b64": base64.b64encode(username.encode()).decode(),
        "password_b64": base64.b64encode(password.encode()).decode(),
    })
    return request("/booth-messages/api/login", "POST", body)


def stop():
    global process
    subprocess.run(["pkill", "-KILL", "-u", "cbauthtest"], check=False)
    if process is not None:
        process.wait(timeout=5)
        process = None


def start(password, public=True):
    global process
    env = dict(os.environ, BOOTH_PUBLIC=str(public).lower(), PASSWORD=password,
               BOOTH_CONTAINER_NAME="review-" + desktop, BOOTH_HOST_PORT="10443")
    process = subprocess.Popen(
        ["runuser", "-u", "cbauthtest", "--", "start-" + desktop + "-wrapped"],
        env=env, stdout=log, stderr=log, start_new_session=True)
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise AssertionError("desktop launcher exited before becoming ready")
        try:
            if request("/__booth/health")[0] == 200:
                return
        except (OSError, http.client.HTTPException):
            pass
        time.sleep(.2)
    raise AssertionError("desktop did not become ready")


def websocket(cookie=None):
    with socket.create_connection(("localhost", 10443), timeout=5) as raw:
        with context.wrap_socket(raw, server_hostname="localhost") as conn:
            headers = ("GET /websockify HTTP/1.1\r\nHost: localhost:10443\r\n"
                       "Connection: Upgrade\r\nUpgrade: websocket\r\n"
                       "Sec-WebSocket-Version: 13\r\n"
                       "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
                       "Sec-WebSocket-Protocol: binary\r\n")
            if cookie:
                headers += "Cookie: " + cookie + "\r\n"
            conn.sendall((headers + "\r\n").encode())
            stream = conn.makefile("rb")
            status = int(stream.readline().split()[1])
            while True:
                line = stream.readline()
                assert line, "WebSocket response ended before its headers"
                if line == b"\r\n":
                    break
            if status != 101:
                return status, b""
            # websockify sends the initial VNC banner as one binary frame.
            frame = stream.read(2)
            assert len(frame) == 2 and frame[0] & 15 == 2, frame
            length = frame[1] & 127
            assert length < 126, length
            return status, stream.read(length)


def check_backends():
    for port in (inner_port, vnc_port):
        listeners = []
        for path in ("/proc/net/tcp", "/proc/net/tcp6"):
            for line in open(path).readlines()[1:]:
                fields = line.split()
                address, number = fields[1].split(":")
                if int(number, 16) == port and fields[3] == "0A":
                    listeners.append(address)
        assert listeners and all(address == "0100007F" or
                                 address == "00000000000000000000000001000000"
                                 for address in listeners), (port, listeners)


try:
    # Public without a password must fail before a desktop is started.
    env = dict(os.environ, BOOTH_PUBLIC="true", PASSWORD="")
    refused = subprocess.run(
        ["runuser", "-u", "cbauthtest", "--", "start-" + desktop + "-wrapped"],
        env=env, capture_output=True, timeout=5)
    assert refused.returncode != 0 and b"requires PASSWORD" in refused.stderr
    print("PASS: missing public password refuses startup", flush=True)

    password = 'review password "\\ unicode-\u00e9'
    start(password)
    for path in ("/", "/booth", "/vnc.html", "/app/ui.js", "/__booth/info"):
        status, headers, _ = request(path)
        assert status == 302 and headers.get("Location") == "/login", (path, status)
    assert b'Sign in' in request("/login")[2]
    assert websocket()[0] == 401
    assert request("/booth-messages/api/idle/disable", "POST")[0] == 401
    assert not os.path.exists("/home/coder/code/.booth/.tmp/.idle-disabled")
    assert request("/booth", cookie="booth_auth=forged")[0] == 302
    assert websocket("booth_auth=forged")[0] == 401
    print("PASS: anonymous and forged sessions cannot reach desktop or controls", flush=True)

    for value, user in (("wrong", "coder"), (password + "wrong", "coder"), (password, "wrong")):
        status, headers, _ = login(value, user)
        assert status == 401 and "Set-Cookie" not in headers
    status, headers, _ = login(password)
    assert status == 200
    session = headers["Set-Cookie"]
    assert all(flag in session for flag in ("HttpOnly", "Secure", "SameSite=Strict"))
    cookie = session.split(";", 1)[0]
    assert request("/booth", cookie=cookie)[0] == 200
    assert request("/vnc.html", cookie=cookie)[0] == 200
    status, banner = websocket(cookie)
    assert status == 101 and banner.startswith(b"RFB "), (status, banner)
    check_backends()
    print("PASS: correct password opens live VNC over HTTPS; backends use loopback", flush=True)

    stop()
    # 'none' must be a real password here, not the VNC disable-auth sentinel.
    start("none")
    assert request("/booth", cookie=cookie)[0] == 302
    assert websocket(cookie)[0] == 401
    assert login(password)[0] == 401
    status, headers, _ = login("none")
    assert status == 200
    fresh_cookie = headers["Set-Cookie"].split(";", 1)[0]
    assert fresh_cookie != cookie and websocket(fresh_cookie)[0] == 101
    print("PASS: restart revokes old sessions and passwords, including literal 'none'", flush=True)

    stop()
    start("", public=False)
    assert request("/booth")[0] == 200 and websocket()[0] == 101
    print("PASS: private desktop remains accessible without a login", flush=True)
finally:
    stop()
    log.close()
    if sys.exc_info()[0] is not None:
        for path in ["/tmp/auth-desktop.log", "/tmp/nginx-booth-wrapper-error.log",
                     "/tmp/cb-wayvnc.log", "/tmp/caddy.log"]:
            if os.path.isfile(path):
                print(path + ":\n" + open(path).read()[-4000:], file=sys.stderr)
