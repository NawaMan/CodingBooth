import os
from http.server import SimpleHTTPRequestHandler, HTTPServer

os.chdir("www")  # ✅ Serve files from the www folder

class MyHandler(SimpleHTTPRequestHandler):
    def list_directory(self, path):
        self.send_error(403, "Directory listing not allowed")

    def do_GET(self):
        if self.path == "/":
            self.path = "/index.html"
        return super().do_GET()

HOST = "0.0.0.0"
PORT = 8080

server = HTTPServer((HOST, PORT), MyHandler)
print(f"Serving HTTP on {HOST}:{PORT} — press Ctrl+C to stop")
server.serve_forever()
