# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0

"""Simple Flask application demonstrating Boothfile environment."""

from flask import Flask, jsonify

app = Flask(__name__)


@app.route("/")
def home():
    return jsonify({
        "message": "Hello from Boothfile example!",
        "description": "This app runs in a CodingBooth environment configured with Boothfile"
    })


@app.route("/health")
def health():
    return jsonify({"status": "healthy"})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
