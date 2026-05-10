from flask import Flask, jsonify

app = Flask(__name__)


@app.get("/")
def index():
    return "<h1>Hello from Flask in CodingBooth!</h1><p>Try <a href='/api/ping'>/api/ping</a>.</p>"


@app.get("/api/ping")
def ping():
    return jsonify(status="ok", message="pong")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
