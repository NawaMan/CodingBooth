#!/usr/bin/env python3
"""Two independent servers exercising preview assets, redirects and WebSockets."""
import base64
import hashlib
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        port = self.server.server_port
        if path == "/ws":
            key = self.headers.get("Sec-WebSocket-Key", "")
            accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
            self.send_response(101)
            self.send_header("Upgrade", "websocket")
            self.send_header("Connection", "Upgrade")
            self.send_header("Sec-WebSocket-Accept", accept)
            self.end_headers()
            message = f"socket-{port}".encode()
            self.wfile.write(bytes([0x81, len(message)]) + message)
            self.wfile.flush()
            return
        if path in ("/redirect", "/absolute-redirect"):
            self.send_response(302)
            self.send_header("Location", (f"http://localhost:{port}" if path == "/absolute-redirect" else "") + "/next")
            self.end_headers()
            return
        if path.startswith("/api/"):
            body = json.dumps({"port": port, "cookie": self.headers.get("Cookie", "")})
            content_type = "application/json"
        elif path == "/assets/app.js":
            body = '''fetch("/api/id").then(r => r.json()).then(data => {
              document.getElementById("api").textContent = "api-" + data.port;
            });
            const prefix = location.pathname.match(/^(.*\\/proxy\\/[0-9]+)\\//);
            const socket = new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + (prefix ? prefix[1] : "") + "/ws");
            socket.onmessage = e => { document.getElementById("socket").textContent = e.data; };
            document.getElementById("spa").onclick = () => history.pushState({}, "", "./spa?ok=1#section");
            '''
            content_type = "application/javascript"
        elif path == "/assets/app.css":
            body = "body { font: 18px system-ui; padding: 24px; background: rgb(232, 245, 233); } a,button { margin-right: 16px; }"
            content_type = "text/css"
        else:
            body = f'''<!doctype html><html><head><title>Server {port}</title>
              <link rel="stylesheet" href="/assets/app.css"></head><body>
              <h1>Server {port}</h1><p id="path">{path}</p>
              <p id="api">Loading API…</p><p id="socket">Connecting…</p>
              <a href="/next">Next page</a><a href="/redirect">Redirect</a>
              <a href="/absolute-redirect">Absolute redirect</a><button id="spa">SPA navigation</button>
              <script src="/assets/app.js"></script></body></html>'''
            content_type = "text/html"
        data = body.encode()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        # The preview should remove frame-blocking response headers.
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Content-Security-Policy", "frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    servers = [ThreadingHTTPServer(("127.0.0.1", port), Handler) for port in (8080, 8081)]
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    threading.Event().wait()
