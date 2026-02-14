# Server Example

Minimal HTTP server demonstrating port exposure from a CodingBooth.

**Stack:** Python 3.12 (`http.server`)

## Quick start

```bash
# 1. Launch the booth
cd examples/server-example
../../codingbooth

# 2. Inside the booth — start the server
./start-server.sh          # serves www/ on port 8080

# 3. Verify from inside the booth
curl http://localhost:8080

# 4. Open in your host browser
#    http://localhost:8080   — you should see the page from www/

# 5. Stop the server
./stop-server.sh
```

## How it works

`start-server.sh` runs `python -m http.server 8080` serving static files from the `www/` directory.
The port is forwarded to your host so you can access it from your browser.

## Scripts

| Script             | Description                         |
|--------------------|-------------------------------------|
| `start-server.sh` | Starts the HTTP server on port 8080 |
| `stop-server.sh`  | Stops the server                    |
