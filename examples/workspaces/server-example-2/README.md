# Server Example

This example is the same minimal HTTP server as `server-example`, showing port exposure that avoids host-port collisions. A Python 3 `http.server` serves `www/` on container port 8080, while the booth is configured with `port = "NEXT:10000"`. Instead of hard-coding a host port, the booth is told to claim the next free one starting at 10000 — so you can launch this same server in three or four booths at once and every one lands on its own reachable port automatically. No more `address already in use`, no hunting for a spare port, no editing config each time you spin up another copy. It's the difference between juggling ports by hand and just launching booths and letting them sort it out.

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
