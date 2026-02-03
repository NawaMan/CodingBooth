#!/bin/bash
# Test: nginx

echo "=== Testing nginx ==="

NGINXDIR="/tmp/test-nginx-$$"
mkdir -p "$NGINXDIR"

# Use a random port to avoid conflicts
PORT=$((8080 + $$))

cleanup() {
    nginx -c "$NGINXDIR/nginx.conf" -s stop 2>/dev/null || true
    rm -rf "$NGINXDIR"
}
trap cleanup EXIT

cat > "$NGINXDIR/nginx.conf" << EOF
worker_processes 1;
error_log $NGINXDIR/error.log;
pid $NGINXDIR/nginx.pid;
events { worker_connections 128; }
http {
    access_log $NGINXDIR/access.log;
    server {
        listen $PORT;
        location / { return 200 'nginx works!\n'; }
    }
}
EOF

nginx -c "$NGINXDIR/nginx.conf"
sleep 1
curl -s "http://localhost:$PORT"
