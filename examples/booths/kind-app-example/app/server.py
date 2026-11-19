#!/usr/bin/env python3
"""Simple web service for testing K8s deployment."""

import json
import os
import socket
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
            return

        # Return JSON with info about the pod/container
        response = {
            "message": "Hello from Kubernetes!",
            "hostname": socket.gethostname(),
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "path": self.path,
            "pod_name": os.environ.get("POD_NAME", "unknown"),
            "pod_ip": os.environ.get("POD_IP", "unknown"),
            "node_name": os.environ.get("NODE_NAME", "unknown"),
        }

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(response, indent=2).encode())

    def log_message(self, format, *args):
        print(f"{datetime.now().isoformat()} - {args[0]}")

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"Server running on port {port}")
    server.serve_forever()
